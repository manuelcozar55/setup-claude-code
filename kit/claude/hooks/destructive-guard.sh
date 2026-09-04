#!/bin/bash
# destructive-guard.sh — Blocks rm-rf on sensitive paths, git reset --hard, git clean
# Source: yurukusa/claude-code-hooks (MIT)
# WSL2 note: rm -rf follows NTFS junctions — can delete far beyond target directory
# Protocol: exit 2 = block

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
if [[ "$HK_RC" -ne 0 ]]; then hk_ciego "destructive-guard.sh" "$HK_RC"; fi
[[ -z "$COMMAND" ]] && exit 0
[[ "${CC_ALLOW_DESTRUCTIVE:-0}" == "1" ]] && exit 0

log_block() {
  local logfile="${CC_BLOCK_LOG:-$HOME/.claude/audit-logs/blocked-commands.log}"
  mkdir -p "$(dirname "$logfile")" 2>/dev/null
  echo "[$(date -Iseconds)] BLOCKED: $1 | cmd: $COMMAND" >> "$logfile" 2>/dev/null
}

SAFE_DIRS="${CC_SAFE_DELETE_DIRS:-node_modules:dist:build:.cache:__pycache__:coverage:.next:.nuxt:tmp}"

# Strip a trailing shell comment before matching: a decoy like `rm -rf /etc # tmp`
# must not be able to flip the safe-dir exemption or hide behind an end-anchor.
COMMAND_SCAN=$(printf '%s' "$COMMAND" | sed 's/[[:space:]]#.*$//')

# Check 1: rm -rf on sensitive paths. ~ and .. are matched even when followed by
# more text (previously end-anchored, so a trailing token defeated detection).
# Las formas largas (--recursive/--force) van en la clase de opciones: solo se aceptaban
# grupos de flags cortos, asi que `rm --recursive --force /home/usuario/docs` no
# emparejaba la ruta sensible y salia limpio de los cinco guards.
if echo "$COMMAND_SCAN" | grep -qE 'rm\s+((-[rf]+|--recursive|--force)\s+)*(\/$|\/\s|\/[^a-z]|\/home|\/etc|\/usr|\/var|\/root|\/boot|~($|[/[:space:]])|\.\.($|[/[:space:]]))'; then
  SAFE=0
  IFS=':' read -ra DIRS <<< "$SAFE_DIRS"
  for dir in "${DIRS[@]}"; do
    # Exempt only when a safe dir is a real path token of the target AND the
    # command is not also touching an absolute sensitive path.
    if echo "$COMMAND_SCAN" | grep -qE "(^|[[:space:]/])${dir}(/|[[:space:]]|$)" \
       && ! echo "$COMMAND_SCAN" | grep -qE '(^|[[:space:]])(/home|/etc|/usr|/var|/root|/boot|/lib|/bin|/sbin)'; then
      SAFE=1; break
    fi
  done
  if (( SAFE == 0 )); then
    log_block "rm on sensitive path"
    echo "BLOCKED: rm on sensitive path (WSL2 risk: NTFS junctions can delete beyond target)." >&2
    echo "Command: $COMMAND" >&2
    exit 2
  fi
fi

# Check 2: git reset --hard
if echo "$COMMAND_SCAN" | grep -qE '^\s*git\s+reset\s+--hard|[;&|]\s*git\s+reset\s+--hard'; then
  log_block "git reset --hard"
  echo "BLOCKED: git reset --hard discards all uncommitted changes." >&2
  echo "Consider: git stash, or git reset --soft" >&2
  exit 2
fi

# Check 3: git clean -fd
if echo "$COMMAND_SCAN" | grep -qE '(^|[;&|])\s*git\s+clean\s+-[a-z]*[fd]'; then
  log_block "git clean"
  echo "BLOCKED: git clean removes untracked files permanently." >&2
  echo "Run: git clean -n (dry run) first to verify what would be deleted." >&2
  exit 2
fi

# Check 4: find -delete on broad paths (WSL2 junction risk). /home/... entra por su
# propia alternativa: el resto exige un separador justo tras / ~ .., asi que
# `find /home/usuario/docs -delete` no emparejaba ninguna.
if echo "$COMMAND_SCAN" | grep -qE 'find\s+((\/|~|\.\.)\s|\/home\/).*-delete'; then
  log_block "find -delete on broad path"
  echo "BLOCKED: find -delete on broad path (WSL2 junction risk)." >&2
  exit 2
fi

exit 0
