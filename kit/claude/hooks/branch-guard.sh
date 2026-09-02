#!/bin/bash
# branch-guard.sh — Blocks git push to protected branches
# Source: yurukusa/claude-code-hooks (MIT)
# Protocol: exit 2 = block with stderr reason

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0

# Sin ancla de inicio y sin exigir `push` pegado a `git`: el ancla '^' dejaba pasar
# `cd /tmp && git push origin master` y exigir `git\s+push` dejaba pasar
# `git -C /ruta push origin main`. El corte por [;&|] mantiene el patron dentro de un
# solo comando, para que un "push" de otro segmento no active el guard.
echo "$COMMAND" | grep -qE '\bgit\b[^;&|]*\bpush\b' || exit 0

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
