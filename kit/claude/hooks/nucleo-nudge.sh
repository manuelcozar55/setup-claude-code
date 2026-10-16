#!/usr/bin/env bash
# PostToolUse (todas las herramientas) — pide al MODELO que actualice nucleo.md antes de que el
# airbag compacte. Por qué: el aviso del Stop lo ve la persona y llega al final del turno, pero la
# mayoría de las compactaciones caen dentro de un turno autónomo; medido, 3 de cada 4 llegaban con
# el nucleo sin escribir en los 20 turnos previos. additionalContext llega junto al tool_result.
# Una vez por banda (50/70/85 % del airbag) y sesión, y solo si nucleo.md tiene más de 10 min o no
# existe; bajo el 50 % se rearman (compactar no cambia el session_id). Sin nada que decir, salida
# vacía. Camino caliente: corre tras cada herramienta.
set -u
IN=$(cat)
{ read -r SID; read -r TP; read -r CWD; } < <(jq -r '.session_id // "", .transcript_path // "", .cwd // ""' <<<"$IN" 2>/dev/null)
case "${SID:-}" in ''|*[!A-Za-z0-9_-]*) exit 0;; esac   # va a un nombre de fichero
[ -f "${TP:-}" ] || exit 0
# shellcheck source=SCRIPTDIR/lib/nucleo.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/nucleo.sh"
RAIZ=$(nucleo_raiz "${CWD:-$PWD}")
nucleo_enlazado "$RAIZ" && exit 0
NUC="$RAIZ/.claude/estado/nucleo.md"
MT=$(stat -c %Y "$NUC" 2>/dev/null || stat -f %m "$NUC" 2>/dev/null)
EDAD=$(( $(date +%s) - ${MT:-0} ))
[ -z "$MT" ] || [ "$EDAD" -gt 600 ] || exit 0
read -r _ PCT <<<"$(nucleo_ctx "$TP")"
[ -n "${PCT:-}" ] || exit 0
MARCA=$HOME/.claude/session-logs/nudge-$SID
if [ "$PCT" -ge 85 ]; then B=85; elif [ "$PCT" -ge 70 ]; then B=70; elif [ "$PCT" -ge 50 ]; then B=50
else [ -s "$MARCA" ] && : >"$MARCA"; exit 0; fi
command grep -qx "$B" "$MARCA" 2>/dev/null && exit 0
mkdir -p "$(dirname "$MARCA")" && echo "$B" >>"$MARCA"
if [ -n "$MT" ]; then
  M="CONTEXTO $PCT % del airbag. nucleo.md lleva $((EDAD / 60)) min sin actualizar: antes de la siguiente herramienta actualiza Paso actual / Siguiente acción / Pendientes en $NUC."
else
  M="CONTEXTO $PCT % del airbag y no hay nucleo.md: antes de la siguiente herramienta créalo en $NUC con la forma de \$HOME/.claude/templates/nucleo.md."
fi
[ "$B" = 70 ] && M="$M Fin de fase = parada válida: termina la fase, actualiza nucleo.md y cierra el turno."
[ "$B" = 85 ] && M="$M Cierra el turno ya: con cockpit en un proyecto, el handoff y /clear son automáticos al cerrar el turno; si no, la persona hará /handoff."
jq -cn --arg c "$M" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$c}}'
exit 0
