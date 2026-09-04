#!/bin/bash
# branch-guard.sh — Blocks git push to protected branches
# Source: yurukusa/claude-code-hooks (MIT)
# Protocol: exit 2 = block with stderr reason

INPUT=$(cat)

# Fail-closed: sin jq no hay decision posible, y permitir en silencio apagaba toda la
# Capa 1 sin un mensaje. Denegar puede frenar trabajo legitimo, y por eso install.sh
# exige jq en una puerta de dependencia: llegar aqui sin el es una instalacion incompleta.
if ! command -v jq >/dev/null 2>&1; then
  echo "BLOCKED (fail-closed): falta jq en el PATH, asi que branch-guard no puede leer el comando." >&2
  echo "Instala jq (apt install jq) y reintenta." >&2
  exit 2
fi
if ! COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); then
  echo "BLOCKED (fail-closed): el payload de PreToolUse no es JSON parseable; branch-guard no puede leer el comando." >&2
  exit 2
fi
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
