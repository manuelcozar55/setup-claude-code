#!/bin/bash
# branch-guard.sh — Blocks git push to protected branches
# Source: yurukusa/claude-code-hooks (MIT)
# Protocol: exit 2 = block with stderr reason

# >>> hk-json ─────────────────────────────────────────────────────────────────
# Leer JSON sin depender de jq. Cadena de tres eslabones, en este orden:
#   1. jq si esta         -> el camino de siempre, sin cambiar un byte
#   2. python3 si no      -> json de la stdlib, parseo de verdad
#   3. ninguno de los dos -> fallo cerrado; quien llama decide como bloquear
# python3 NO es una dependencia nueva: kit/install.sh aborta con exit 1 si no puede crear
# el venv con `python3 -m venv`, y el kit ya distribuye cuatro hooks .py. jq, en cambio,
# no esta declarado como requisito en ningun sitio.
# PROHIBIDO parsear esto con grep/sed/awk: el payload lleva llaves, comillas y saltos de
# linea DENTRO de los valores, y una igualdad por subcadena es exactamente el defecto que
# este repo lleva media rama persiguiendo.
# Este bloque esta DUPLICADO en los seis hooks que leen JSON, y kit/test/test_guards.sh
# comprueba que los seis son identicos byte a byte. Se duplica en vez de compartirse
# porque un hook es un ejecutable hoja que el runtime lanza por ruta absoluta: ninguno de
# los 14 del kit hace `source` de nada, los cuatro guards se instalan en ~/.claude/hooks/
# mientras que auto-spec y verify-gate viven en el repo (no hay ruta relativa comun), y
# una libreria compartida anadiria a un control de seguridad un modo de fallo nuevo --
# libreria ausente => bloquear TODO.
if command -v jq >/dev/null 2>&1; then HK_JSON=jq
elif command -v python3 >/dev/null 2>&1; then HK_JSON=py
else HK_JSON=no; fi

# hk_get <ruta.punteada> [defecto]  --  JSON por stdin, valor por stdout.
# El contrato es el que ya tenia jq a solas, y de el depende todo lo de abajo:
#   rc=0 con salida vacia -> el campo no esta (permitir es lo correcto)
#   rc!=0                 -> no se ha podido leer la entrada (ciego: no puede autorizar)
# El defecto viaja por --arg/argv, nunca interpolado dentro del programa.
hk_get() {
  case "$HK_JSON" in
    jq) if [ $# -ge 2 ]; then jq -r --arg d "$2" ".$1 // \$d" 2>/dev/null
        else jq -r ".$1 // empty" 2>/dev/null; fi ;;
    py) python3 -c 'import json,sys
try: d = json.load(sys.stdin)
except Exception: sys.exit(5)
for k in sys.argv[1].split("."):
    if d is None: break
    if not isinstance(d, dict): sys.exit(5)
    d = d.get(k)
if d is None or d is False: d = sys.argv[2] if len(sys.argv) > 2 else None
if d is not None: print(d if isinstance(d, str) else json.dumps(d))' "$1" ${2+"$2"} 2>/dev/null ;;
    *)  return 127 ;;
  esac
}
# <<< hk-json ─────────────────────────────────────────────────────────────────

# >>> hk-ciego ────────────────────────────────────────────────────────────────
# Un guard que no ha podido leer su entrada no puede autorizarla. El bloqueo va por
# exit 2 + motivo por stderr porque es el unico mecanismo que no depende de nada
# instalado, que es justo el punto cuando lo que falta es el parser. Identico en los
# cuatro guards salvo el nombre, que se pasa como argumento en vez de sacarlo de $0:
# el runtime no garantiza con que $0 los invoca, y el nombre es parte del mensaje.
# El texto del caso jq se conserva palabra por palabra desde J-1: con jq presente no
# cambia ni un byte, tampoco cuando lo que falla es que la entrada no sea JSON.
hk_ciego() { # $1 nombre del hook, $2 rc de la lectura
  case "$HK_JSON" in
    jq) echo "BLOCKED: cannot read the hook input with jq (rc=$2: jq missing from PATH, or input that is not readable JSON)." >&2
        echo "$1 will not allow a command it could not inspect. Install jq, or remove this hook deliberately." >&2 ;;
    py) echo "BLOCKED: cannot read the hook input with python3 (rc=$2: the input is not readable JSON)." >&2
        echo "$1 will not allow a command it could not inspect. Send it valid JSON, or remove this hook deliberately." >&2 ;;
    *)  echo "BLOCKED: cannot read the hook input: no JSON parser found (rc=$2: neither jq nor python3 in PATH)." >&2
        echo "$1 will not allow a command it could not inspect. Install jq or python3, or remove this hook deliberately." >&2 ;;
  esac
  exit 2
}
# <<< hk-ciego ────────────────────────────────────────────────────────────────

INPUT=$(cat)
# Lo que separa "no hay comando que revisar" de "no he podido leer el comando" NO es que
# la salida venga vacia: es el CODIGO DE SALIDA del lector. rc=0 con salida vacia
# permite (un evento que no es Bash no trae .tool_input.command, y ahi permitir es
# correcto); rc!=0 significa que el guard esta ciego, y un guard ciego no puede autorizar.
# Antes de J-1 los dos casos se confundian y este guard PERMITIA en silencio justo lo que
# con jq bloquea. Desde Track M la ausencia de jq ya no deja ciego a nadie: hk_get lee con
# python3 y este guard bloquea y permite exactamente lo mismo que con jq. El fallo cerrado
# de hk_ciego es el ULTIMO recurso -- solo cuando no hay ni jq ni python3.
COMMAND=$(echo "$INPUT" | hk_get tool_input.command); HK_RC=$?
if [[ "$HK_RC" -ne 0 ]]; then hk_ciego "branch-guard.sh" "$HK_RC"; fi
[[ -z "$COMMAND" ]] && exit 0

# Sin ancla de inicio y sin exigir `push` pegado a `git`: el ancla '^' dejaba pasar
# `cd /tmp && git push origin master` y exigir `git\s+push` dejaba pasar
# `git -C /ruta push origin main`. El corte por [;&|] mantiene el patron dentro de un
# solo comando, para que un "push" de otro segmento no active el guard.
# rc=1 es "no es un push" y se sale; rc>=2 es "la regex no compila", que con `|| exit 0` era un
# permiso silencioso. Se distinguen: si el filtro se rompe, el guard deniega en vez de callarse.
echo "$COMMAND" | grep -qE '\bgit\b[^;&|]*\bpush\b'
rc_filtro=$?
if [ "$rc_filtro" -ge 2 ]; then
  echo "BLOCKED: branch-guard no puede evaluar el comando (grep rc=$rc_filtro)." >&2
  exit 2
fi
[ "$rc_filtro" -eq 0 ] || exit 0

PROTECTED="${CC_PROTECT_BRANCHES:-main:master:production}"
IFS=':' read -ra BRANCHES <<< "$PROTECTED"
for branch in "${BRANCHES[@]}"; do
  if echo "$COMMAND" | grep -qwE "(origin\s+${branch}|${branch}\s|${branch}$)"; then
    echo "BLOCKED: Attempted push to protected branch '${branch}'." >&2
    echo "Command: $COMMAND" >&2
    echo "Push to a feature/staging branch first, then open a PR." >&2
    exit 2
  fi
done

exit 0
