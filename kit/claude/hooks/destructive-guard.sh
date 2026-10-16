#!/bin/bash
# destructive-guard.sh — Blocks rm-rf on sensitive paths, git reset --hard, git clean
# Source: yurukusa/claude-code-hooks (MIT)
# WSL2 note: rm -rf follows NTFS junctions — can delete far beyond target directory
# Protocol: exit 2 = block

INPUT=$(cat)
# El escape hatch declarado se atiende ANTES del fail-closed de abajo: quien pone
# CC_ALLOW_DESTRUCTIVE=1 ya ha apagado este guard a proposito, y no necesita jq para eso.
[[ "${CC_ALLOW_DESTRUCTIVE:-0}" == "1" ]] && exit 0

# Fail-closed: sin jq no hay decision posible, y permitir en silencio apagaba toda la
# Capa 1 sin un mensaje. Denegar puede frenar trabajo legitimo, y por eso install.sh
# exige jq en una puerta de dependencia: llegar aqui sin el es una instalacion incompleta.
if ! command -v jq >/dev/null 2>&1; then
  echo "BLOCKED (fail-closed): falta jq en el PATH, asi que destructive-guard no puede leer el comando." >&2
  echo "Instala jq (apt install jq) y reintenta." >&2
  exit 2
fi
if ! COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); then
  echo "BLOCKED (fail-closed): el payload de PreToolUse no es JSON parseable; destructive-guard no puede leer el comando." >&2
  exit 2
fi
[[ -z "$COMMAND" ]] && exit 0

log_block() {
  local logfile="${CC_BLOCK_LOG:-$HOME/.claude/audit-logs/blocked-commands.log}"
  mkdir -p "$(dirname "$logfile")" 2>/dev/null
  echo "[$(date -Iseconds)] BLOCKED: $1 | cmd: $COMMAND" >> "$logfile" 2>/dev/null
}

SAFE_DIRS="${CC_SAFE_DELETE_DIRS:-node_modules:dist:build:.cache:__pycache__:coverage:.next:.nuxt:tmp}"

# El texto se normaliza con la lib comun: continuaciones unidas y comentarios quitados SOLO fuera
# de comillas (el sed anterior cortaba en el `#` de `git commit -m "fix #12" && git reset --hard`).
# Un comentario de verdad sigue sin poder voltear la exencion de directorio seguro ni esconderse
# tras un ancla de final (un decoy `... # tmp` tras un rm sobre /etc).
# shellcheck source=SCRIPTDIR/lib/cmdnorm.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/cmdnorm.sh" || { echo "BLOCKED (fail-closed): falta lib/cmdnorm.sh; reinstala el kit." >&2; exit 2; }
if ! cmdn_parse "$COMMAND"; then
  echo "BLOCKED (fail-closed): awk no pudo normalizar el comando; destructive-guard no puede evaluarlo." >&2
  exit 2
fi
COMMAND_SCAN=$CMDN_TEXT

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

# Check 5: el mismo conjunto sobre cada comando simple ya normalizado (tokens descomillados, sin
# prefijos sudo/env/command/nice/timeout ni ruta de ejecutable, sin opciones globales de git).
# Los checks de arriba siguen mirando el texto porque su patron no esta anclado y por eso ven
# tambien lo que va dentro de un `bash -c "..."`; este cubre las grafias que sacaban el comando del
# patron: `git -C dir reset --hard`, `sudo git clean --force -d`, `rm -rv`, `rm -R`, `rm -rf --`.
# shellcheck disable=SC2088,SC2016  # `~` y `$HOME` son el TEXTO del operando, no se expanden.
sensitive_operand() {
  case $1 in
    /|/[!a-z]*|/home*|/etc*|/usr*|/var*|/root*|/boot*|'~'|'~/'*|..|../*|'$HOME'|'$HOME/'*|'${HOME}'|'${HOME}/'*) return 0 ;;
  esac
  return 1
}
safe_operand() {
  local d
  case $1 in /home*|/etc*|/usr*|/var*|/root*|/boot*|/lib*|/bin*|/sbin*) return 1 ;; esac
  for d in "${DIRS[@]}"; do [[ "/$1/" == *"/$d/"* ]] && return 0; done
  return 1
}
IFS=':' read -ra DIRS <<< "$SAFE_DIRS"
for seg in "${CMDN_SEGS[@]}"; do
  cmdn_fields "$seg"
  case ${T[1]:-} in
    rm)
      dd=0
      for a in "${T[@]:2}"; do
        if (( ! dd )) && [[ $a == -- ]]; then dd=1; continue; fi
        if (( ! dd )) && [[ $a == -* ]]; then continue; fi
        if sensitive_operand "$a" && ! safe_operand "$a"; then
          log_block "rm on sensitive path"
          echo "BLOCKED: rm on sensitive path (WSL2 risk: NTFS junctions can delete beyond target)." >&2
          echo "Command: $COMMAND" >&2
          exit 2
        fi
      done ;;
    git)
      case ${T[2]:-} in
        reset)
          for a in "${T[@]:3}"; do
            if [[ $a == --hard ]]; then
              log_block "git reset --hard"
              echo "BLOCKED: git reset --hard discards all uncommitted changes." >&2
              echo "Consider: git stash, or git reset --soft" >&2
              exit 2
            fi
          done ;;
        clean)
          force=0; dry=0
          for a in "${T[@]:3}"; do
            case $a in
              --force) force=1 ;;
              --dry-run) dry=1 ;;
              --*) ;;
              -*) [[ $a == -*[fd]* ]] && force=1; [[ $a == -*n* ]] && dry=1 ;;
            esac
          done
          if (( force && ! dry )); then
            log_block "git clean"
            echo "BLOCKED: git clean removes untracked files permanently." >&2
            echo "Run: git clean -n (dry run) first to verify what would be deleted." >&2
            exit 2
          fi ;;
      esac ;;
  esac
done

exit 0
