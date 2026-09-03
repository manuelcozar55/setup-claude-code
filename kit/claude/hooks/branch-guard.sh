#!/bin/bash
# branch-guard.sh — Blocks git push to protected branches
# Source: yurukusa/claude-code-hooks (MIT)
# Protocol: exit 2 = block with stderr reason

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
  echo "branch-guard.sh will not allow a command it could not inspect. Install jq, or remove this hook deliberately." >&2
  exit 2
fi
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
