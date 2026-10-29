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
ck "$?" "0" "acepta una ruta absoluta"
"$AUT" stop --session g0 >/dev/null 2>&1; "$AUT" stop --session g0b >/dev/null 2>&1

# --- 2. Presupuesto de intentos --------------------------------------------
"$AUT" start --session g1 --oracle "/bin/false" --goal "x" --max-repairs 2 >/dev/null
"$AUT" attempt --session g1 >/dev/null 2>&1; ck "$?" "0" "intento 1 dentro del presupuesto"
"$AUT" attempt --session g1 >/dev/null 2>&1; ck "$?" "0" "intento 2 dentro del presupuesto"
"$AUT" attempt --session g1 >/dev/null 2>&1; ck "$?" "1" "intento 3 agota el presupuesto de 2"
"$AUT" stop --session g1 >/dev/null

# --- 3. Gate con oraculo ROJO: bloquea -------------------------------------
runp start --oracle "/bin/false" --goal "que pase" --max-repairs 3 >/dev/null
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
runp start --oracle "/bin/true" --goal "trivial" >/dev/null
r=$(pl "$(uuid)" | "$GATE" 2>/dev/null)
ck "$(printf '%s' "$r" | grep -c . || true)" "0" "oraculo verde -> no bloquea"
runp status >/dev/null 2>&1
ck "$?" "1" "oraculo verde -> cierra el run automaticamente"

# --- 7. Sin run activo: modo normal, nunca bloquea -------------------------
r=$(pl "$(uuid)" | "$GATE" 2>/dev/null)
ck "$(printf '%s' "$r" | grep -c . || true)" "0" "sin run autonomo -> modo normal, no emite bloqueo"

# --- 8. Falsabilidad: el gate DISCRIMINA entre rojo y verde ----------------
# Sin esto, todo lo anterior podria estar pasando con un gate que nunca bloquea.
runp start --oracle "/bin/false" --goal "x" >/dev/null
rojo=$(decision "$(pl "$(uuid)" | "$GATE" 2>/dev/null)")
runp stop >/dev/null
runp start --oracle "/bin/true" --goal "x" >/dev/null
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
: > "$MCHARNESS_STATE/session-n2.oracle"; touch -d '1 hour from now' "$MCHARNESS_STATE/session-n2.oracle"
r=$(gp n2 | "$GATE" 2>&1 >/dev/null); rc=$?
ck "$(printf '%s' "$r" | grep -c . || true)" "0" "normal: marcador posterior a la edicion -> silencio"
ck "$rc" "0" "normal: silencio con exit 0"
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
echo 'test:' > "$S/Makefile"; echo ok > "$S/tests/t.sh"; echo ok > "$S/tests/dir sp/a b.sh"; echo v > "$S/src.txt"
git -C "$S" init -q && git -C "$S" add -A && git -C "$S" -c user.name=t -c user.email=t@t commit -q -m i
export MCHARNESS_STATE="$T/state10"
sp() { printf '{"session_id":"%s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":false}' "$1" "$S"; }
sruns() { (cd "$S" && ./scripts/autonomy.sh "$@"); }
sruns start --oracle "/bin/true" --goal "x" --max-repairs 2 >/dev/null
echo src2 > "$S/src.txt"; echo nuevo > "$S/tests/nuevo.sh"
r=$(sp "$(uuid)" | "$GATE" 2>/dev/null)
ck "$(printf '%s' "$r" | grep -c . || true)" "0" "sensor: solo codigo cambiado y fichero de test NUEVO -> libera (TDD legitimo)"
sruns start --oracle "/bin/true" --goal "x" --max-repairs 2 >/dev/null
echo flojo >> "$S/Makefile"
out=$(sp "$(uuid)" | "$GATE" 2>/dev/null)
ck "$(decision "$out")" "block" "sensor: oraculo verde pero Makefile modificado -> block"
ckhas "$(printf '%s' "$out" | jq -r '.reason // ""')" "Makefile" y "sensor: el motivo lista el fichero alterado"
sruns status >/dev/null 2>&1; ck "$?" "0" "sensor: el run sigue activo tras el bloqueo"
sp "$(uuid)" | "$GATE" >/dev/null 2>&1
r=$(sp "$(uuid)" | "$GATE" 2>&1 >/dev/null)
ckhas "$r" "SENSOR ALTERADO" y "sensor: agotado el presupuesto libera con SENSOR ALTERADO"
sruns status >/dev/null 2>&1; ck "$?" "1" "sensor: y cierra el run"
git -C "$S" checkout -q Makefile
sruns start --oracle "/bin/true" --goal "x" >/dev/null
rm "$S/tests/dir sp/a b.sh"
out=$(sp "$(uuid)" | "$GATE" 2>/dev/null)
ck "$(decision "$out")" "block" "sensor: fichero sensor borrado (con espacios en la ruta) -> block"
ckhas "$(printf '%s' "$out" | jq -r '.reason // ""')" "a b.sh" y "sensor: el motivo lista el borrado"
sruns stop >/dev/null; git -C "$S" checkout -q .
sruns start --oracle "/bin/true" --goal "x" >/dev/null
r=$(sp "$(uuid)" | "$GATE" 2>/dev/null)
ck "$(printf '%s' "$r" | grep -c . || true)" "0" "sensor: sin tocar el sensor, verde libera como siempre"
# Fichero sensor ya borrado al arrancar (ultimo en el orden) y start desde un subdirectorio:
# la linea base no puede quedar vacia (M4 quedaria anulada en silencio).
echo a > "$S/tests/a.py"; echo z > "$S/tests/zz.py"; mkdir -p "$S/sub"
git -C "$S" add -A && git -C "$S" -c user.name=t -c user.email=t@t commit -q -m j
rm "$S/tests/zz.py"
sruns start --oracle "/bin/true" --goal "x" >/dev/null
echo flojo >> "$S/tests/a.py"
out=$(sp "$(uuid)" | "$GATE" 2>/dev/null)
ck "$(decision "$out")" "block" "sensor: con un sensor ya borrado al arrancar, la linea base sigue viva -> block"
sruns stop >/dev/null; git -C "$S" checkout -q . ; rm -f "$S/tests/nuevo.sh"
(cd "$S/sub" && ../scripts/autonomy.sh start --oracle "/bin/true" --goal "x" >/dev/null)
echo flojo >> "$S/Makefile"
(cd "$S/sub" && ../scripts/autonomy.sh sensor-check >/dev/null 2>&1)
ck "$?" "1" "sensor: start desde un subdirectorio tambien guarda la linea base"
sruns stop >/dev/null 2>&1; (cd "$S/sub" && ../scripts/autonomy.sh stop >/dev/null 2>&1); git -C "$S" checkout -q .
export MCHARNESS_STATE="$T/state"

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ] || exit 1
