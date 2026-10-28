#!/usr/bin/env bash
# PreToolUse (todas las herramientas) — compuerta de frescura del nucleo. Por qué: el aviso de nucleo-nudge.sh
# solo se cumple en el 47 % de los casos y dentro de un turno autónomo no hay Stop que lo fuerce. Tras el aviso
# de la banda 70 u 85 con el nucleo sin escribir, la 4.ª llamada del hilo principal se deniega UNA vez por banda
# y sesión, con el motivo accionable. Falla en abierto: cualquier duda → salida 0 sin nada. ADR 020.
# Estado en ~/.claude/session-logs: nudge-$SID (bandas avisadas) y nudge-$SID.nucleo (ruta del nucleo que miró el
# nudge; su mtime es la hora del aviso), ambos del nudge; gate-$SID-$B (una línea por llamada contada) y gate-$SID-$B.d (la denegación ya reclamada).
# Para medirla: gate-denegaciones.log, una línea por denegación (fecha, sesión, banda, herramienta, nucleo).
# Opt-in: solo actúa con env.CC_NUCLEO_GATE=1; sin la variable (o con otro valor) sale en silencio.
set -u
[ "${CC_NUCLEO_GATE:-0}" = 1 ] || exit 0
IN=$(cat)
{ read -r SID; read -r AID; read -r TOOL; read -r DEST; read -r CMD; } < <(jq -r '.session_id // "", .agent_id // "", .tool_name // "", (.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // ""), (.tool_input.command // "" | gsub("\n"; " "))' <<<"$IN" 2>/dev/null)
# Solo el hilo principal: agent_id (nunca agent_type, que con --agent lo trae también el hilo principal).
[ -z "${AID:-}" ] || exit 0
case "${SID:-}" in ''|*[!A-Za-z0-9_-]*) exit 0;; esac
LOG=$HOME/.claude/session-logs
[ -s "$LOG/nudge-$SID" ] || exit 0
if command grep -qx 85 "$LOG/nudge-$SID" 2>/dev/null; then B=85
elif command grep -qx 70 "$LOG/nudge-$SID" 2>/dev/null; then B=70
else exit 0; fi
AVISO=$LOG/nudge-$SID.nucleo
read -r NUC <"$AVISO" 2>/dev/null; [ -n "${NUC:-}" ] || exit 0
# Desarmada si el nucleo se escribió después del aviso.
[ ! "$NUC" -nt "$AVISO" ] || exit 0
# Quien obedece no queda bloqueado: estado/ (nucleo y borradores) y handoff pasan sin contar.
case "/$DEST" in */.claude/estado/*) exit 0;; esac
if [ "$TOOL" = Bash ] && [[ $CMD =~ (^|[^A-Za-z0-9_.-])handoff([^A-Za-z0-9_-]|$) ]]; then exit 0; fi
# Llamadas en paralelo: la cuenta es un append (una línea por llamada) y la denegación se reclama con un
# fichero que solo crea una (set -C), así que no hay lectura-suma-escritura que pisar.
G=$LOG/gate-$SID-$B
{ echo >>"$G"; } 2>/dev/null || exit 0
N=$({ wc -l <"$G"; } 2>/dev/null) || exit 0
[ $((N)) -ge 4 ] || exit 0   # wc -l: siempre un entero, aunque el fichero tenga basura
( set -C; : >"$G.d" ) 2>/dev/null || exit 0
{ printf '%s\t%s\t%s\t%s\t%s\n' "$(date +%FT%T%z)" "$SID" "$B" "$TOOL" "$NUC" >>"$LOG/gate-denegaciones.log"; } 2>/dev/null
HO=handoff; command -v handoff >/dev/null 2>&1 || HO=${CLAUDE_HOME:-$HOME/.claude}/bin/handoff
jq -cn --arg r "nucleo.md sin actualizar tras el aviso de contexto: actualiza $NUC o cierra la fase con \`$HO --desde <borrador> --sesion $SID\`, y después reintenta." \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
