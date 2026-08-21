#!/usr/bin/env bash
# Stop — avisa si la sesion escribio codigo y termino sin ejecutar ningun oraculo.
#
# Por que existe: "verifica tu trabajo" era una regla advisoria de CLAUDE.md y el KPI decia
# 0 sesiones con oraculo. Esto la convierte en senal.
#
# POR QUE AVISA Y NO BLOQUEA (decision consciente, no descuido):
#   Un Stop hook que devuelve exit 2 impide terminar el turno. Con un falso positivo, deja
#   la sesion atrapada, y este usuario ya tiene un incidente documentado con un hook que
#   tumbo su flujo. El coste de un falso positivo bloqueante es mucho mayor que el de un
#   aviso ignorado. Si con el tiempo el aviso se ignora siempre, ENTONCES se endurece:
#   esa promocion se decide con datos en /retro, no de entrada.
#
# Contrato: exit 0 SIEMPRE. Sin red, sin procesos de fondo, < 100 ms.
set -uo pipefail

STATE_DIR="${MCHARNESS_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/mcharness}"
payload=$(cat 2>/dev/null) || exit 0

if command -v jq >/dev/null 2>&1; then
  sid=$(printf '%s' "$payload" | jq -r '.session_id // "unknown"' 2>/dev/null)
  cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
else
  sid="unknown"; cwd="$PWD"
fi
[ -n "$cwd" ] || cwd="$PWD"

# Ya hubo oraculo: nada que decir.
[ -f "$STATE_DIR/session-$sid.oracle" ] && exit 0

# Solo avisa si de verdad se toco codigo. Una sesion de lectura o de preguntas no necesita
# oraculo, y avisar ahi seria el ruido que hace que se ignore el aviso de verdad.
git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || exit 0
changed=$(git -C "$cwd" diff --name-only 2>/dev/null | grep -c . || true)
staged=$(git -C "$cwd" diff --cached --name-only 2>/dev/null | grep -c . || true)
[ "$((changed + staged))" -gt 0 ] || exit 0

oracle=""
# shellcheck disable=SC2016  # los backticks son literales de markdown, no expansion
[ -f "$cwd/knowledge/ORACLES.md" ] && oracle=$(grep -o '`make test`' "$cwd/knowledge/ORACLES.md" 2>/dev/null | head -1)
# shellcheck disable=SC2016
[ -n "$oracle" ] || { [ -f "$cwd/Makefile" ] && grep -q '^test:' "$cwd/Makefile" 2>/dev/null && oracle='`make test`'; }

{
  echo "── mcharness ──────────────────────────────────────────────"
  echo "  $((changed + staged)) fichero(s) modificado(s) y NINGÚN oráculo ejecutado."
  [ -n "$oracle" ] && echo "  Oráculo de este repo: $oracle"
  echo "  Evidencia antes que afirmaciones:  /verify"
  echo "───────────────────────────────────────────────────────────"
} >&2

exit 0
