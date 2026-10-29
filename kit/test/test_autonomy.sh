#!/usr/bin/env bash
# Verifica el modo autonomo: scripts/autonomy.sh y el Stop hook verify-gate.sh.
#
# Lo que importa aqui no es que el gate "haga algo", sino que haga lo correcto en los
# cuatro estados que deciden si un run desatendido es seguro: rojo (bloquea), verde
# (libera), presupuesto agotado (libera y avisa), y cap de Claude Code (se aparta).
# Un gate que se equivoque en el tercero o el cuarto secuestra la sesion del usuario.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
AUT="$PWD/scripts/autonomy.sh"
GATE="$PWD/.claude/hooks/verify-gate.sh"
pass=0; fail=0

if ! command -v jq >/dev/null 2>&1; then
  echo "ok - jq no disponible: suite omitida"; echo "== 1 passed, 0 failed =="; exit 0
fi

ck() { if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1))
       else echo "NOT ok - $3 (obtenido '$1', esperado '$2')"; fail=$((fail+1)); fi; }
# ckhas <texto> <patron> <y|n> <desc>. En if/then, no 'A && B || C': ese patron no es
# if-then-else y ejecuta C tambien cuando A es cierto pero B falla (MISTAKES M-003).
ckhas() { local got=n; printf '%s' "$1" | grep -qi "$2" && got=y; ck "$got" "$3" "$4"; }
# decision <salida-del-gate>: "ninguna" si el gate no emitio nada. Sin este guardia, un
# jq sobre cadena vacia devuelve vacio y no el default, que es como se cuela un falso
# negativo justo en el check que debe demostrar que el gate discrimina.
decision() { [ -n "$1" ] && printf '%s' "$1" | jq -r '.decision // "ninguna"' 2>/dev/null || echo "ninguna"; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export MCHARNESS_STATE="$T/state"
mkdir -p "$T/proj/scripts"; cp "$AUT" "$T/proj/scripts/autonomy.sh"
P="$T/proj"
printf 'ok:\n\t@true\nko:\n\t@false\nflip:\n\t@test -f flag\n' > "$P/Makefile"
# El TSV de historial se escribe bajo el cwd: fuera del arbol del repo que se prueba.
cd "$T" || exit 1

pl() { printf '{"session_id":"%s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":%s}' \
       "$1" "$P" "${2:-false}"; }

# El run se arranca COMO LO ARRANCA EL MODELO: desde el directorio del proyecto y sin
# --session, porque el session_id solo existe dentro del payload del hook y quien lanza
# el run (Bash) no lo conoce. La clave del estado es por eso el directorio. Los payloads
# de abajo llevan a proposito un UUID distinto en cada llamada: si el gate volviera a
# leer el estado por session_id, no encontraria run, caeria a modo normal y dejaria
# cerrar el turno con el oraculo en ROJO -- en silencio, que es como se colo la primera vez.
runp() { (cd "$P" && ./scripts/autonomy.sh "$@"); }
uuid() { printf '%s-%s-4%s-a%s-%s' "$(openssl rand -hex 4 2>/dev/null || echo deadbeef)" \
         "$(openssl rand -hex 2 2>/dev/null || echo cafe)" "$(openssl rand -hex 1 2>/dev/null || echo 1f)ab" \
         "$(openssl rand -hex 1 2>/dev/null || echo 2c)3d" "$(openssl rand -hex 6 2>/dev/null || echo 0123456789ab)"; }

# --- 1. El oraculo debe ser inmune a la reescritura de comandos (M-001) -----
"$AUT" start --session g0 --oracle "pytest -q" --goal "x" >/dev/null 2>&1
ck "$?" "1" "rechaza un oraculo por nombre suelto (seria reescrito: MISTAKES M-001)"
"$AUT" start --session g0 --oracle "make test" --goal "x" >/dev/null 2>&1
ck "$?" "0" "acepta 'make ...'"
"$AUT" start --session g0b --oracle "/usr/bin/true" --goal "x" >/dev/null 2>&1
ck "$?" "1" "rechaza una ruta absoluta (el Stop hook la ejecutaria sin pasar por permisos)"
"$AUT" stop --session g0 >/dev/null 2>&1

# --- 2. Presupuesto de intentos --------------------------------------------
"$AUT" start --session g1 --oracle "make ko" --goal "x" --max-repairs 2 >/dev/null
"$AUT" attempt --session g1 >/dev/null 2>&1; ck "$?" "0" "intento 1 dentro del presupuesto"
"$AUT" attempt --session g1 >/dev/null 2>&1; ck "$?" "0" "intento 2 dentro del presupuesto"
"$AUT" attempt --session g1 >/dev/null 2>&1; ck "$?" "1" "intento 3 agota el presupuesto de 2"
"$AUT" stop --session g1 >/dev/null

# --- 3. Gate con oraculo ROJO: bloquea -------------------------------------
runp start --oracle "make ko" --goal "que pase" --max-repairs 3 >/dev/null
out=$(pl "$(uuid)" | "$GATE" 2>/dev/null)
ck "$(decision "$out")" "block" "oraculo rojo -> {\"decision\":\"block\"} (run arrancado sin --session)"
reason=$(printf '%s' "$out" | jq -r '.reason // ""' 2>/dev/null)
ckhas "$reason" "ROJO"   y "el motivo dice que el oraculo esta en rojo"
ckhas "$reason" "sensor" y "el motivo PROHIBE explicitamente aflojar el sensor"

# --- 4. Cap de Claude Code: el hook se aparta ------------------------------
# Si esto falla, el hook secuestra la sesion pese al mecanismo de seguridad del propio
# Claude Code. Es el fallo mas grave posible en un Stop hook.
r=$(pl "$(uuid)" true | "$GATE" 2>/dev/null)
ck "$(printf '%s' "$r" | grep -c . || true)" "0" "stop_hook_active=true -> NO bloquea (respeta el cap de 8)"

# --- 5. Presupuesto agotado: libera en vez de insistir ---------------------
for _ in 1 2 3 4 5; do pl "$(uuid)" | "$GATE" >/dev/null 2>&1; done
r=$(pl "$(uuid)" | "$GATE" 2>/dev/null)
ck "$(printf '%s' "$r" | grep -c . || true)" "0" "agotado el presupuesto -> deja terminar (no insiste indefinidamente)"
runp status >/dev/null 2>&1
ck "$?" "1" "y cierra el run autonomo al agotarlo"

# --- 6. Gate con oraculo VERDE: libera y cierra ----------------------------
runp start --oracle "make ok" --goal "trivial" >/dev/null
r=$(pl "$(uuid)" | "$GATE" 2>/dev/null)
ck "$(printf '%s' "$r" | grep -c . || true)" "0" "oraculo verde -> no bloquea"
runp status >/dev/null 2>&1
ck "$?" "1" "oraculo verde -> cierra el run automaticamente"

# --- 7. Sin run activo: modo normal, nunca bloquea -------------------------
r=$(pl "$(uuid)" | "$GATE" 2>/dev/null)
ck "$(printf '%s' "$r" | grep -c . || true)" "0" "sin run autonomo -> modo normal, no emite bloqueo"

# --- 8. Falsabilidad: el gate DISCRIMINA entre rojo y verde ----------------
# Sin esto, todo lo anterior podria estar pasando con un gate que nunca bloquea.
runp start --oracle "make ko" --goal "x" >/dev/null
rojo=$(decision "$(pl "$(uuid)" | "$GATE" 2>/dev/null)")
runp stop >/dev/null
runp start --oracle "make ok" --goal "x" >/dev/null
verde=$(decision "$(pl "$(uuid)" | "$GATE" 2>/dev/null)")
if [ "$rojo" = "block" ] && [ "$verde" = "ninguna" ]; then
  echo "ok - falsabilidad: rojo bloquea y verde no ('$rojo' vs '$verde')"; pass=$((pass+1))
else
  echo "NOT ok - el gate no discrimina rojo de verde ('$rojo' vs '$verde')"; fail=$((fail+1))
fi

# --- 9. Modo normal: el aviso mira la edicion y deja rastro (M3+M9) ---------
G="$T/g"; mkdir -p "$G"
git -C "$G" init -q && git -C "$G" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
echo a > "$G/f.txt"; git -C "$G" add f.txt
git -C "$G" -c user.name=t -c user.email=t@t commit -q -m f
export MCHARNESS_STATE="$T/state9"; mkdir -p "$MCHARNESS_STATE"
LOG9="$MCHARNESS_STATE/gate-avisos.log"
gp() { printf '{"session_id":"%s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":false}' "$1" "$G"; }
echo b > "$G/f.txt"
: > "$MCHARNESS_STATE/session-n1.oracle"; touch -d '2 hours ago' "$MCHARNESS_STATE/session-n1.oracle"
r=$(gp n1 | "$GATE" 2>&1 >/dev/null); rc=$?
ckhas "$r" "NINGÚN oráculo" y "normal: marcador anterior a la edicion -> avisa"
ck "$rc" "0" "normal: avisa con exit 0 (ADR 004)"
: > "$MCHARNESS_STATE/session-n2.oracle"; touch -d "@$(( $(date +%s) + 3600 ))" "$MCHARNESS_STATE/session-n2.oracle"
ck "$([ "$MCHARNESS_STATE/session-n2.oracle" -nt "$G/f.txt" ] && echo y || echo n)" "y" "normal: la marca futura es de verdad posterior a la edicion (touch no falla en silencio)"
r=$(gp n2 | "$GATE" 2>&1 >/dev/null); rc=$?
ck "$(printf '%s' "$r" | grep -c . || true)" "0" "normal: marcador posterior a la edicion -> silencio"
ck "$rc" "0" "normal: silencio con exit 0"
touch -d '2 hours ago' "$MCHARNESS_STATE/session-n2.oracle"
r=$(gp n2 | "$GATE" 2>&1 >/dev/null)
ckhas "$r" "NINGÚN oráculo" y "normal: la misma marca puesta en el pasado -> avisa (el check de silencio es falsable)"
r=$(gp n3 | "$GATE" 2>&1 >/dev/null); rc=$?
ckhas "$r" "NINGÚN oráculo" y "normal: sin marcador -> avisa"
ck "$rc" "0" "normal: sin marcador, exit 0"
ck "$(grep -c ' n3 1$' "$LOG9")" "1" "normal: el aviso deja una linea 'fecha sid n' en gate-avisos.log"
git -C "$G" checkout -q f.txt
r=$(gp n4 | "$GATE" 2>&1 >/dev/null)
ck "$(printf '%s' "$r" | grep -c . || true)" "0" "normal: sin cambios -> silencio como siempre"
printf '%s\n' $(seq 1 700) > "$T/big"; sed 's/^/2026-01-01T00:00:00Z x /' "$T/big" > "$LOG9"
echo b > "$G/f.txt"; gp n5 | "$GATE" >/dev/null 2>&1
ck "$([ "$(wc -l < "$LOG9")" -le 500 ] && echo y || echo n)" "y" "normal: gate-avisos.log tiene tope"
export MCHARNESS_STATE="$T/estado-nuevo/x"
gp n6 | "$GATE" >/dev/null 2>&1
ck "$(grep -c ' n6 1$' "$MCHARNESS_STATE/gate-avisos.log" 2>/dev/null || true)" "1" "normal: con el directorio de estado inexistente el aviso se registra"
git -C "$G" checkout -q f.txt
export MCHARNESS_STATE="$T/state"

# --- 10. Sensor alterado: oraculo verde no cierra si se toco el sensor (M4) ---
S="$T/s"; mkdir -p "$S/scripts" "$S/tests" "$S/tests/dir sp"
cp "$AUT" "$S/scripts/autonomy.sh"
printf 'ok:\n\t@true\n' > "$S/Makefile"; echo ok > "$S/tests/t.sh"; echo ok > "$S/tests/dir sp/a b.sh"; echo v > "$S/src.txt"
git -C "$S" init -q && git -C "$S" add -A && git -C "$S" -c user.name=t -c user.email=t@t commit -q -m i
export MCHARNESS_STATE="$T/state10"
sp() { printf '{"session_id":"%s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":false}' "$1" "$S"; }
sruns() { (cd "$S" && ./scripts/autonomy.sh "$@"); }
sruns start --oracle "make ok" --goal "x" --max-repairs 2 >/dev/null
echo src2 > "$S/src.txt"; echo nuevo > "$S/tests/nuevo.sh"
r=$(sp "$(uuid)" | "$GATE" 2>/dev/null)
ck "$(printf '%s' "$r" | grep -c . || true)" "0" "sensor: solo codigo cambiado y fichero de test NUEVO -> libera (TDD legitimo)"
sruns start --oracle "make ok" --goal "x" --max-repairs 2 >/dev/null
echo '# flojo' >> "$S/Makefile"
out=$(sp "$(uuid)" | "$GATE" 2>/dev/null)
ck "$(decision "$out")" "block" "sensor: oraculo verde pero Makefile modificado -> block"
ckhas "$(printf '%s' "$out" | jq -r '.reason // ""')" "Makefile" y "sensor: el motivo lista el fichero alterado"
ckhas "$(printf '%s' "$out" | jq -r '.reason // ""')" "Makefile (borrado)" n "sensor: un fichero modificado no se marca (borrado)"
sruns status >/dev/null 2>&1; ck "$?" "0" "sensor: el run sigue activo tras el bloqueo"
sp "$(uuid)" | "$GATE" >/dev/null 2>&1
r=$(sp "$(uuid)" | "$GATE" 2>&1 >/dev/null)
ckhas "$r" "SENSOR ALTERADO" y "sensor: agotado el presupuesto libera con SENSOR ALTERADO"
sruns status >/dev/null 2>&1; ck "$?" "1" "sensor: y cierra el run"
git -C "$S" checkout -q Makefile
sruns start --oracle "make ok" --goal "x" >/dev/null
rm "$S/tests/dir sp/a b.sh"
out=$(sp "$(uuid)" | "$GATE" 2>/dev/null)
ck "$(decision "$out")" "block" "sensor: fichero sensor borrado (con espacios en la ruta) -> block"
ckhas "$(printf '%s' "$out" | jq -r '.reason // ""')" "a b.sh (borrado)" y "sensor: el motivo marca el fichero como (borrado)"
sruns stop >/dev/null; git -C "$S" checkout -q .
sruns start --oracle "make ok" --goal "x" >/dev/null
r=$(sp "$(uuid)" | "$GATE" 2>/dev/null)
ck "$(printf '%s' "$r" | grep -c . || true)" "0" "sensor: sin tocar el sensor, verde libera como siempre"
# Fichero sensor ya borrado al arrancar (ultimo en el orden) y start desde un subdirectorio:
# la linea base no puede quedar vacia (M4 quedaria anulada en silencio).
echo a > "$S/tests/a.py"; echo z > "$S/tests/zz.py"; mkdir -p "$S/sub"
git -C "$S" add -A && git -C "$S" -c user.name=t -c user.email=t@t commit -q -m j
rm "$S/tests/zz.py"
sruns start --oracle "make ok" --goal "x" >/dev/null
echo flojo >> "$S/tests/a.py"
out=$(sp "$(uuid)" | "$GATE" 2>/dev/null)
ck "$(decision "$out")" "block" "sensor: con un sensor ya borrado al arrancar, la linea base sigue viva -> block"
sruns stop >/dev/null; git -C "$S" checkout -q . ; rm -f "$S/tests/nuevo.sh"
(cd "$S/sub" && ../scripts/autonomy.sh start --oracle "make ok" --goal "x" >/dev/null)
echo '# flojo' >> "$S/Makefile"
(cd "$S/sub" && ../scripts/autonomy.sh sensor-check >/dev/null 2>&1)
ck "$?" "1" "sensor: start desde un subdirectorio tambien guarda la linea base"
sruns stop >/dev/null 2>&1; (cd "$S/sub" && ../scripts/autonomy.sh stop >/dev/null 2>&1); git -C "$S" checkout -q .
export MCHARNESS_STATE="$T/state"

# Repo sin ficheros sensor: la linea base queda vacia, no con el hash de stdin vacio.
E="$T/e"; mkdir -p "$E/scripts"; cp "$AUT" "$E/scripts/autonomy.sh"; echo v > "$E/src.txt"
git -C "$E" init -q && git -C "$E" add -A && git -C "$E" -c user.name=t -c user.email=t@t commit -q -m i
export MCHARNESS_STATE="$T/state10e"
(cd "$E" && ./scripts/autonomy.sh start --session e1 --oracle "make ok" --goal "x" >/dev/null)
ck "$(wc -l < "$MCHARNESS_STATE/run-e1.sensor" | tr -d ' ')" "0" "sensor: repo sin ficheros sensor -> linea base de 0 lineas (xargs -r)"
export MCHARNESS_STATE="$T/state"

# --- 11. Caducidad e historial del run (M11) --------------------------------
export MCHARNESS_STATE="$T/state11"
rm -f "$P/flag"
TSV="$P/.claude/estado/autonomia.tsv"; rm -f "$TSV"
hace() { date -u -d "$1 ago" +%Y-%m-%dT%H:%M:%SZ; }
setstart() { sed -i "s/^STARTED=.*/STARTED=$1/" "$MCHARNESS_STATE"/run-*.env; }
runp start --oracle "make ko" --goal "x" >/dev/null
setstart "$(hace '25 hours')"
out=$(pl "$(uuid)" | "$GATE" 2>"$T/err"); r=$(cat "$T/err")
ck "$(decision "$out")" "ninguna" "ttl: run de 25 h con oraculo rojo -> el gate no bloquea"
ckhas "$r" "caducado" y "ttl: el gate avisa 'run caducado'"
runp status >/dev/null 2>&1; ck "$?" "1" "ttl: y borra el estado del run"
runp start --oracle "make ko" --goal "x" >/dev/null; setstart "$(hace '10 minutes')"
ck "$(decision "$(pl "$(uuid)" | "$GATE" 2>/dev/null)")" "block" "ttl: run de 10 min con el defecto de 240 -> sigue bloqueando"
runp stop >/dev/null
runp start --oracle "make ko" --goal "x" --max-minutes 5 >/dev/null; setstart "$(hace '10 minutes')"
ck "$(decision "$(pl "$(uuid)" | "$GATE" 2>/dev/null)")" "ninguna" "ttl: start --max-minutes 5 caduca a los 10 min (antes de 240)"
runp start --oracle "make ko" --goal "x" --max-minutes abc >/dev/null 2>&1; ck "$?" "1" "ttl: --max-minutes no numerico se rechaza"
rm -f "$TSV"
runp start --oracle "make flip" --goal "multi
linea	con tab" >/dev/null
pl "$(uuid)" | "$GATE" >/dev/null 2>&1; pl "$(uuid)" | "$GATE" >/dev/null 2>&1
: > "$P/flag"; pl "$(uuid)" | "$GATE" >/dev/null 2>&1; rm -f "$P/flag"
ck "$(wc -l < "$TSV" | tr -d ' ')" "4" "tsv: start + 2 intentos rojos + stop verde = 4 filas (con goal multilinea)"
ck "$(cut -f2 "$TSV" | paste -sd, -)" "start,intento,intento,stop" "tsv: eventos en orden"
ck "$(awk -F'\t' 'NF!=6' "$TSV" | wc -l | tr -d ' ')" "0" "tsv: todas las filas tienen 6 campos"
ck "$(awk -F'\t' '$2=="intento" && $4!=0' "$TSV" | wc -l | tr -d ' ')" "2" "tsv: los intentos llevan el rc rojo del oraculo"
ck "$(awk -F'\t' '$2=="stop"{print $4}' "$TSV")" "0" "tsv: el stop del verde lleva rc 0"
ck "$(cut -f3 "$TSV" | paste -sd, -)" "0,1,2,2" "tsv: columna intento"
ck "$(grep -c 'multi\|linea' "$TSV" || true)" "0" "tsv: ni goal ni oraculo se copian al historial"
ck "$(git -C "$T" status --porcelain 2>/dev/null | grep -c autonomia || true)" "0" "tsv: no hay autonomia.tsv versionado"
export MCHARNESS_STATE="$T/state"

# --- 12. El oraculo y la sesion no escalan: solo cosas del repo (revision T05) ---
oc() { "$AUT" start --session o1 --oracle "$1" --goal x >/dev/null 2>&1; local rc=$?; "$AUT" stop --session o1 >/dev/null 2>&1; echo "$rc"; }
ck "$(oc '/tmp/evil.sh')" "1" "oraculo: ruta absoluta rechazada"
ck "$(oc 'make ok; /tmp/evil.sh')" "1" "oraculo: 'make ...; /abs' rechazado (encadenado)"
ck "$(oc 'make ok /etc/x')" "1" "oraculo: argumento de ruta absoluta rechazado"
ck "$(oc 'make ok && echo hola')" "1" "oraculo: metacaracteres de shell rechazados"
ck "$(oc '../x.sh')" "1" "oraculo: ruta relativa con .. rechazada"
ck "$(oc 'bash kit/test/../../x.sh')" "1" "oraculo: bash kit/test con .. rechazado"
ck "$(oc 'rtk proxy /tmp/evil.sh')" "1" "oraculo: rtk proxy ya no abre una puerta a rutas absolutas"
ck "$(oc 'make test')" "0" "oraculo: make <target> aceptado"
ck "$(oc 'bash kit/test/test_autonomy.sh')" "0" "oraculo: bash kit/test/<x>.sh aceptado"
ck "$(oc 'oraculo -- pytest -q')" "0" "oraculo: oraculo -- ... aceptado"
ck "$(oc './scripts/check.sh')" "0" "oraculo: ruta relativa bajo la raiz aceptada"
ck "$(oc 'scripts/check.sh --fast')" "0" "oraculo: scripts/... aceptado"
for s in 'a/b' '../x' 'a..b' '/abs'; do
  "$AUT" start --session "$s" --oracle "make ok" --goal x >/dev/null 2>&1
  ck "$?" "1" "sesion '$s' rechazada"
done
"$AUT" start --session ok-1.2_x --oracle "make ok" --goal x >/dev/null 2>&1; ck "$?" "0" "sesion con letras, cifras y .-_ aceptada"
"$AUT" stop --session ok-1.2_x >/dev/null 2>&1

# --- 13. El estado en disco no es de fiar: el hook lo revalida y no lo ejecuta (revision T13) ---
export MCHARNESS_STATE="$T/state13"
envf() { ls "$MCHARNESS_STATE"/run-*.env; }
runp start --oracle "make ok" --goal "x" >/dev/null
sed -i 's|^ORACLE=.*|ORACLE=/bin/false|' "$(envf)"
out=$(pl "$(uuid)" | "$GATE" 2>"$T/err")
ck "$(decision "$out")" "ninguna" "estado: ORACLE absoluto editado en el env -> el hook no lo ejecuta"
ckhas "$(cat "$T/err")" "estado invalido" y "estado: el hook dice por que cae a modo normal"
runp status >/dev/null 2>&1; ck "$?" "0" "estado: y no borra el estado invalido"
runp stop >/dev/null 2>&1; rm -f "$MCHARNESS_STATE"/run-*.env
# Env de la version anterior (ORACLE con printf %q): no valida, cae a modo normal con aviso.
printf 'ORACLE=make\\ ok\nGOAL=x\nMAXREP=3\nATTEMPTS=0\nSTARTED=%s\n' "$(hace '1 minute')" > "$MCHARNESS_STATE/run-viejo.env"
out=$(pl "$(uuid)" | "$GATE" 2>"$T/err")
ck "$(decision "$out")-$(grep -c 'estado invalido' "$T/err")" "ninguna-1" "estado: env antiguo con %q cae a modo normal con aviso"
rm -f "$MCHARNESS_STATE/run-viejo.env"
runp start --oracle "make ko" --goal "x" >/dev/null
echo "touch $T/pwned" >> "$(envf)"
d=$(decision "$(pl "$(uuid)" | "$GATE" 2>/dev/null)")
ck "$d-$([ -e "$T/pwned" ] && echo ejecutada || echo ignorada)" "block-ignorada" "estado: una linea extra en el env se ignora y el oraculo valido sigue bloqueando"
runp stop >/dev/null 2>&1
runp start --oracle "make ko" --goal "x" --max-minutes 100000 >/dev/null
setstart ""
runp expired >/dev/null 2>&1; ck "$?" "0" "ttl: STARTED vacio cuenta como caducado (no como las 00:00 de hoy)"
setstart "$(date -u -d '1 day' +%Y-%m-%dT%H:%M:%SZ)"
runp expired >/dev/null 2>&1; ck "$?" "0" "ttl: STARTED en el futuro cuenta como ilegible -> caducado"
runp stop >/dev/null 2>&1
export MCHARNESS_STATE="$T/state"

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ] || exit 1
