#!/usr/bin/env bash
# PostToolUse/Bash — registra que en esta sesion SI se ejecuto un oraculo.
#
# Por que existe: el KPI 5 del harness ("sesiones con oraculo ejecutado") valia 0 porque
# nadie lo medía. Una regla que dice "verifica tu trabajo" no produce datos; un hook si.
#
# Contrato: rapidisimo, sin red, sin procesos de fondo, exit 0 SIEMPRE. Este hook observa,
# no decide. Un sensor que puede tumbar la sesion deja de ser gratis.
set -uo pipefail

STATE_DIR="${MCHARNESS_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/mcharness}"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

payload=$(cat 2>/dev/null) || exit 0

if command -v jq >/dev/null 2>&1; then
  cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
  rc=$(printf '%s' "$payload" | jq -r '.tool_response.exit_code // .tool_response.exitCode // empty' 2>/dev/null)
  sid=$(printf '%s' "$payload" | jq -r '.session_id // "unknown"' 2>/dev/null)
else
  cmd=$(printf '%s' "$payload" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
  sid="unknown"
  rc=""
fi
[ -n "$cmd" ] || exit 0
cmd=$(printf '%s' "$cmd" | tr '\n\t' '  ')

# Heuristica deliberadamente estrecha. Falso negativo conocido y aceptado: un oraculo con
# otro nombre (un script propio, un binario a medida) no se detecta. Preferimos no contar
# de mas: un KPI inflado es peor que uno conservador.
case "$cmd" in
  *"make test"*|*pytest*|*shellcheck*|*gitleaks*|*"npm test"*|*"cargo test"*|*"go test"*)
    printf '%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" "${cmd:0:200}" "$rc" \
      >> "$STATE_DIR/oracle-runs.tsv" 2>/dev/null
    # Verde solo si el rc es fiable: con tuberia (sin '||') el rc del tool es el del ultimo
    # tramo (tail), no el del oraculo; y un rc declarado distinto de 0 no es verde.
    if [ "${rc:-0}" = "0" ] && { [ -n "$rc" ] || [[ "${cmd//||/}" != *"|"* ]]; }; then
      : > "$STATE_DIR/session-$sid.oracle" 2>/dev/null
    fi
    ;;
esac

exit 0
