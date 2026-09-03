#!/usr/bin/env bash
# test_verify_gate.sh — el Stop hook contra el contrato `mch task gate`.
#
# Lo que se mide es la asimetria, que es la leccion de 6edfd73: AUSENCIA de autoridad
# (no hay mch, o mch dice que no gobierna) => NO bloquear, porque el kit tiene que
# seguir siendo util en los cientos de repos que no usan mch. AUTORIDAD PRESENTE QUE
# NO RESPONDE (timeout, rc desconocido) => BLOQUEAR, porque ahi el silencio es el fallo.
# Un gate que confunda esos dos casos falla en abierto justo cuando importa.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; RAIZ="$(cd "$HERE/../.." && pwd)"
GATE="$RAIZ/.claude/hooks/verify-gate.sh"
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

if ! command -v jq >/dev/null 2>&1; then
  echo "ok - jq no disponible: suite omitida"; echo "== 1 passed, 0 failed =="; exit 0
fi

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/proj"

# En if/then, no 'A && B || C': ese patron ejecuta C tambien cuando A es cierto
# pero B falla, y es como se cuela un falso negativo (MISTAKES M-003).
decision(){ if [ -n "$1" ]; then printf '%s' "$1" | jq -r '.decision // "ninguna"' 2>/dev/null
            else echo "ninguna"; fi; }
pl(){ printf '{"session_id":"s1","cwd":"%s","stop_hook_active":%s}' "$T/proj" "${1:-false}"; }

# `mch` de mentira: $1 rc, $2 json en stdout (sin comillas simples), $3 retardo.
fabrica_mch(){
  { echo '#!/usr/bin/env bash'
    [ -n "${3:-}" ] && echo "sleep $3"
    [ -n "${2:-}" ] && printf "printf '%%s\\\\n' '%s'\n" "$2"
    echo "exit $1"
  } > "$T/bin/mch"
  chmod +x "$T/bin/mch"
}
corre(){ printf '%s' "$(pl "${1:-false}")" | env PATH="$T/bin:$PATH" bash "$GATE" 2>/dev/null; }

# Para el caso A6 no basta con borrar $T/bin/mch: en una maquina con mch instalado
# seguiria encontrandolo en el PATH del sistema y el test pasaria por la razon
# equivocada. Se construye un PATH del que se ha quitado todo directorio que
# contenga un mch ejecutable.
sin_mch_path(){
  printf '%s' "$PATH" | tr ':' '\n' | while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ -x "$d/mch" ] || printf '%s:' "$d"
  done
}
corre_sin_mch(){ printf '%s' "$(pl false)" | env PATH="$(sin_mch_path)" bash "$GATE" 2>/dev/null; }

ROJO='{"contrato":1,"gobierna":true,"veredicto":"rojo","motivo":"no hay ejecucion VERDE del oraculo registrada tras el ultimo start","tarea":"T-042","titulo":"x","clase":"sensor","oraculo_sellado":"pytest tests/ -q","intentos":7,"ultimo_run_rc":1,"alcance":"verificable","evidencia":"incompleta"}'
VERDE='{"contrato":1,"gobierna":true,"veredicto":"verde","motivo":"ok","tarea":"T-042","intentos":1}'
FUTURO='{"contrato":99,"gobierna":true,"veredicto":"rojo","motivo":"algo","tarea":"T-042","intentos":1}'
# rc=0 tiene DOS significados muy distintos y este es el segundo: mch no tiene ninguna
# tarea en curso de la que opinar. No dice que el turno este verificado.
SIN_TAREA='{"contrato":1,"gobierna":true,"veredicto":"verde","motivo":"no hay ninguna tarea en curso"}'

# --- A6: sin mch en PATH, NUNCA bloquea -----------------------------------
rm -f "$T/bin/mch"
ck "$(decision "$(corre_sin_mch)")" "ninguna" "A6: sin mch en PATH el hook no bloquea jamas"
# Falsabilidad del propio andamio: si sin_mch_path no quitara de verdad el mch del
# sistema, este test pasaria por la razon equivocada.
ck "$(env PATH="$(sin_mch_path)" command -v mch >/dev/null 2>&1 && echo encontrado || echo no)" "no" \
   "falsabilidad del andamio: el PATH recortado no tiene ningun mch"

# --- rc=3: mch no gobierna este proyecto -> no bloquea ---------------------
fabrica_mch 3 '{"contrato":1,"gobierna":false,"veredicto":"no-gobernado","motivo":"sin cola"}'
ck "$(decision "$(corre)")" "ninguna" "rc=3 (mch no gobierna aqui): no bloquea"

# --- rc=2: error de uso (version de mch sin el subcomando) -> no bloquea ---
fabrica_mch 2 ''
ck "$(decision "$(corre)")" "ninguna" "rc=2 (error de uso): se trata como 3, no bloquea"

# --- rc=0: mch no objeta -> este bloque no bloquea --------------------------
# Ojo: este caso pasa con las DOS implementaciones posibles del rc=0 (salir con exit 0,
# o seguir hacia abajo), porque el $T/proj temporal no es un repo git y el modo normal
# se calla igual. Por si solo no mide la diferencia; el ultimo caso de la suite si.
fabrica_mch 0 "$VERDE"
ck "$(decision "$(corre)")" "ninguna" "rc=0: mch no objeta y el hook no bloquea por su cuenta"

# --- A7: rc=1 -> BLOQUEA, y el motivo llega al modelo ----------------------
fabrica_mch 1 "$ROJO"
out="$(corre)"
ck "$(decision "$out")" "block" "A7: rc=1 (tarea en curso sin evidencia) bloquea"
razon="$(printf '%s' "$out" | jq -r '.reason // ""')"
ck "$(printf '%s' "$razon" | grep -q 'T-042' && echo y || echo n)" "y" "el bloqueo nombra la tarea"
ck "$(printf '%s' "$razon" | grep -q 'no hay ejecucion VERDE' && echo y || echo n)" "y" "el bloqueo lleva el motivo de mch"
ck "$(printf '%s' "$razon" | grep -qE '^Intentos registrados desde el ultimo start: 7$' && echo y || echo n)" "y" \
   "el bloqueo lleva los intentos derivados del journal"

# --- rc desconocido: autoridad presente que no responde -> BLOQUEA ---------
fabrica_mch 9 ''
ck "$(decision "$(corre)")" "block" "rc desconocido: fallo cerrado, bloquea"

# --- timeout: idem. El hook no puede esperar indefinidamente ni liberar ----
fabrica_mch 0 "$VERDE" 30
ck "$(decision "$(corre)")" "block" "timeout de mch: fallo cerrado, bloquea"

# --- contrato mas nuevo del que el hook entiende: bloquea Y lo advierte ----
fabrica_mch 1 "$FUTURO"
out2="$(corre)"
ck "$(decision "$out2")" "block" "contrato futuro: el rc sigue siendo el contrato estable"
ck "$(printf '%s' "$out2" | jq -r '.reason // ""' | grep -qi 'contrato' && echo y || echo n)" "y" \
   "contrato futuro: el hook advierte que puede no entender el detalle"

# --- el cap de Claude Code se respeta -------------------------------------
fabrica_mch 1 "$ROJO"
ck "$(decision "$(corre true)")" "ninguna" "stop_hook_active=true: el hook se aparta (cap de 8)"

# --- intentos altos: sigue bloqueando, y el modelo ve cuantos lleva --------
# Sustituye al caso "presupuesto agotado" del modo autonomo. La diferencia es que
# el presupuesto ya no se puede agotar borrando un fichero: 'intentos' se deriva
# de un journal append-only, y solo baja si alguien reescribe la historia.
AGOTADO='{"contrato":1,"gobierna":true,"veredicto":"rojo","motivo":"la ultima ejecucion registrada es ROJA (rc=1)","tarea":"T-042","clase":"sensor","oraculo_sellado":"make test","intentos":9,"ultimo_run_rc":1,"alcance":"verificable","evidencia":"incompleta"}'
fabrica_mch 1 "$AGOTADO"
out3="$(corre)"
ck "$(decision "$out3")" "block" "muchos intentos: sigue bloqueando (el presupuesto no se borra)"
ck "$(printf '%s' "$out3" | jq -r '.reason // ""' | grep -qE '^Intentos registrados desde el ultimo start: 9$' && echo y || echo n)" "y" \
   "el bloqueo dice cuantos intentos van"

# --- modo aviso: mch no gobierna y hay cambios sin verificar ---------------
# El kit tiene que seguir sirviendo en repos sin mch: avisa por stderr, no bloquea.
fabrica_mch 3 '{"contrato":1,"gobierna":false,"veredicto":"no-gobernado","motivo":"sin cola"}'
git -C "$T/proj" init -q 2>/dev/null
git -C "$T/proj" config user.email t@t; git -C "$T/proj" config user.name t
echo "base" > "$T/proj/f.txt"; git -C "$T/proj" add -A; git -C "$T/proj" commit -qm base
echo "cambio sin verificar" >> "$T/proj/f.txt"
err="$(printf '%s' "$(pl false)" | env PATH="$T/bin:$PATH" bash "$GATE" 2>&1 >/dev/null)"
ck "$(printf '%s' "$err" | grep -qi 'oraculo\|oráculo\|verific' && echo y || echo n)" "y" \
   "mch no gobierna + cambios sin verificar: avisa por stderr"
salida="$(printf '%s' "$(pl false)" | env PATH="$T/bin:$PATH" bash "$GATE" 2>/dev/null)"
ck "$(decision "$salida")" "ninguna" "mch no gobierna: avisa pero NO bloquea"

# --- rc=0 NO puede apagar lo que hay debajo (fallo en abierto) -------------
# La rama 0) del case cae hacia abajo a proposito: `gate` devuelve rc=0 tambien
# cuando no hay ninguna tarea en curso, y un `exit 0` ahi dejaria mudo el modo
# aviso en cualquier repo con TAREAS.md. Antes esto se medía contra el modo
# autonomo; retirado ese, se mide contra el aviso, que es lo que hay debajo ahora.
fabrica_mch 0 "$SIN_TAREA"
avisa="$(printf '%s' "$(pl false)" | env PATH="$T/bin:$PATH" bash "$GATE" 2>&1 >/dev/null)"
ck "$(printf '%s' "$avisa" | grep -qi 'oráculo' && echo y || echo n)" "y" \
   "rc=0 sin tarea en curso no apaga el modo aviso"
ck "$(decision "$(corre)")" "ninguna" "rc=0 avisa por stderr pero no bloquea"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
