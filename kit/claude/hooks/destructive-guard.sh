#!/bin/bash
# destructive-guard.sh — Blocks rm-rf on sensitive paths, git reset --hard, git clean
# Source: yurukusa/claude-code-hooks (MIT)
# WSL2 note: rm -rf follows NTFS junctions — can delete far beyond target directory
# Protocol: exit 2 = block

INPUT=$(cat)
# Lo que separa "no hay comando que revisar" de "no he podido leer el comando" NO es que
# la salida venga vacia: es el CODIGO DE SALIDA de jq. Sin jq (rc=127) la sustitucion
# dejaba COMMAND vacia, el `[[ -z ]]` de abajo lo confundia con el primer caso y este
# guard PERMITIA en silencio justo lo que con jq bloquea. rc=0 con salida vacia sigue
# permitiendo (un evento que no es Bash no trae .tool_input.command, y ahi permitir es
# correcto); rc!=0 significa que el guard esta ciego, y un guard ciego no puede autorizar.
# Se bloquea con exit 2 + stderr: el mismo protocolo que usan los checks de abajo, y el
# unico que no necesita jq para emitirse.
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); JQ_RC=$?
if [[ "$JQ_RC" -ne 0 ]]; then
  echo "BLOCKED: cannot read the hook input with jq (rc=$JQ_RC: jq missing from PATH, or input that is not readable JSON)." >&2
  echo "destructive-guard.sh will not allow a command it could not inspect. Install jq, or remove this hook deliberately." >&2
  exit 2
fi
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
  echo "BLOCKED: find -delete on broad path (WSL2 junction risk)." >&2
  exit 2
fi

exit 0
