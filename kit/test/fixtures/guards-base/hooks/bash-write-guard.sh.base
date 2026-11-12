#!/bin/bash
# bash-write-guard.sh — PreToolUse Bash: secretos en el contenido que un comando ESCRIBE.
# write-guard.py escanea Write/Edit/MultiEdit/NotebookEdit, pero `Edit(...)` y ese guard no frenan a
# Bash: `cat > f <<EOF`, `echo ... >> f`, `tee f` y `sed -i` escriben igual y pasaban sin mirar. Aqui
# se escanea el comando con las filas `block` de lib/secret-patterns, la MISMA lista que write-guard.py
# (las `advise` y los patrones con lookahead los da solo write-guard.py).
# Protocolo: JSON deny + exit 0, o salida silenciosa para permitir.
#
# Camino caliente: corre en CADA llamada a Bash. Si el payload no tiene `>`, `<<`, `tee` ni `sed` (y
# ninguna escapada \u003 de `<`/`>`) se sale en bash puro, sin lanzar ni jq ni grep. Eso es lo comun.
set -uo pipefail

IFS= read -r -d '' INPUT || true

case $INPUT in
  *'>'*|*'<<'*|*tee*|*sed*|*'\u003'*) ;;
  *) exit 0 ;;
esac

# Fail-closed, como el resto de guards: sin jq no se puede leer el comando de una escritura.
if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED (fail-closed): falta jq en el PATH, asi que bash-write-guard no puede evaluar este comando que escribe. Instala jq (apt install jq) y reintenta."}}'
  exit 0
fi

deny() {
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) \
  || deny "BLOCKED (fail-closed): el payload de PreToolUse no es JSON parseable, asi que bash-write-guard no puede evaluar el comando."
[[ -z "$COMMAND" ]] && exit 0

# Mismo criterio que la salida temprana pero sobre el comando ya decodificado: `sed` solo cuenta con -i
# (o --in-place), y los demas necesitan ser escritura de verdad.
WRITES=0
[[ $COMMAND == *'>'* || $COMMAND == *'<<'* ]] && WRITES=1
[[ $COMMAND =~ (^|[^[:alnum:]_])tee([^[:alnum:]_]|$) ]] && WRITES=1
if [[ $COMMAND =~ (^|[^[:alnum:]_])sed[[:space:]] ]]; then
  # Dos pruebas separadas a proposito: un `;`, `|` o `&` dentro del script (o entre comillas) no deja
  # que una sola regex llegue al `-i` que va detras. Un falso positivo solo cuesta un grep.
  [[ $COMMAND =~ [[:space:]]-[a-zA-Z]*i || $COMMAND == *--in-place* ]] && WRITES=1
fi
(( WRITES )) || exit 0

PATTERNS="$(dirname "${BASH_SOURCE[0]}")/lib/secret-patterns"
[[ -r $PATTERNS ]] || deny "BLOCKED (fail-closed): falta lib/secret-patterns junto al guard; reinstala el kit."

LABELS=(); ERES=(); UNION=''
while IFS=$'\t' read -r label action ere; do
  [[ -z $label || $label == '#'* || $action != block ]] && continue
  LABELS+=("$label"); ERES+=("$ere"); UNION+="|$ere"
done < "$PATTERNS"
[[ -n $UNION ]] || deny "BLOCKED (fail-closed): lib/secret-patterns no tiene ninguna fila block; reinstala el kit."

printf '%s' "$COMMAND" | grep -qE -e "${UNION#|}"
rc=$?
[[ $rc -eq 1 ]] && exit 0
[[ $rc -eq 0 ]] || deny "BLOCKED (fail-closed): lib/secret-patterns no compila (grep rc=$rc); se deniega por seguridad."

HITS=()
for i in "${!ERES[@]}"; do
  printf '%s' "$COMMAND" | grep -qE -e "${ERES[i]}" && HITS+=("${LABELS[i]}")
done
deny "BASH-WRITE-GUARD BLOCKED: el comando escribe contenido que parece un secreto ($(IFS=,; echo "${HITS[*]}")). Usa variables de entorno o un gestor de secretos."
