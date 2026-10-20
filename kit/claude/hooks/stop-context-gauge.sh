#!/usr/bin/env bash
# Stop — un sensor y un gate sobre el mismo transcript, en un solo proceso:
#   1) contexto real del último turno: avisa a la persona al cruzar la línea blanda (60 % del airbag);
#   2) gate: commit de esta sesión con .claude/estado/nucleo.md sin actualizar. La regla en prosa
#      («actualiza nucleo al cerrar cada fase») se incumplía sesión tras sesión.
# stdin: {"transcript_path":"...", "session_id":"...", "cwd":"...", "stop_hook_active":bool}
#
# Por qué (1): solo la persona puede lanzar /compact o /clear, y casi todas las compactaciones son
# el airbag automático (ventana − 33k). Este aviso convierte el airbag en una decisión planificada.
# Aviso a mitad de turno, para el modelo: nucleo-nudge.sh (PostToolUse).
set -u
IN=$(cat)
TP=$(jq -r '.transcript_path // empty' <<<"$IN" 2>/dev/null)
[ -n "$TP" ] && [ -f "$TP" ] || exit 0
# shellcheck source=SCRIPTDIR/lib/nucleo.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/nucleo.sh"
MSG=""

read -r CTX PCT <<<"$(nucleo_ctx "$TP")"
if [ -n "${PCT:-}" ] && [ "$PCT" -ge 60 ]; then
  HO=handoff; command -v handoff >/dev/null 2>&1 || HO=$HOME/.claude/bin/handoff
  MSG="Contexto $CTX tok ($PCT % del airbag). Fase cerrada: /handoff (cockpit: deja el estado en .claude/estado/nucleo.md y retoma limpio); sin cockpit, actualiza nucleo.md con \`$HO --desde <borrador>\` y /clear (el hook de arranque lo re-inyecta). Si no, delega el resto a subagentes."
fi

# 2) Gate: un `git commit` lanzado EN ESTE transcript es posterior a nucleo.md. No vale «HEAD es
# reciente»: commits ajenos, rebase y amend lo disparaban. Un disparo por (sesión, commit), así
# que no hay bucle aunque la persona decida no tocar nucleo. NUCLEO_GATE=observe (defecto) solo
# registra en el log; block devuelve decision. Ante cualquier dato que falte: no hace nada.
REASON=""
SID=$(jq -r '.session_id // empty' <<<"$IN" 2>/dev/null)
CWD=$(jq -r '.cwd // empty' <<<"$IN" 2>/dev/null); CWD=${CWD:-$PWD}
RAIZ=$(nucleo_raiz "$CWD")
NUC="$RAIZ/.claude/estado/nucleo.md"
# D1: desde ~ el nucleo compartido no es el de esta sesión: sin puerta (en block mandaría actualizar el de otra tarea).
if [ "$RAIZ" != "$HOME" ] && [ "$(jq -r '.stop_hook_active // false' <<<"$IN" 2>/dev/null)" != true ] && [ -f "$NUC" ] && ! nucleo_enlazado "$RAIZ"; then
  MT=$(stat -c %Y "$NUC" 2>/dev/null || stat -f %m "$NUC" 2>/dev/null)
  # shortcut: el commit puede ir a otro repo (`cd x && git commit`); el modo observe mide si pasa.
  COM=$(tail -n 3000 "$TP" | timeout 5 jq -rR 'fromjson? | select(.type=="assistant" and (.timestamp|type)=="string")
      | select(any(.message.content[]?; .type=="tool_use" and .name=="Bash"
          and ((.input.command // "") | test("\\bgit\\b[^;&|\\n]*\\bcommit\\b") and (test("--amend")|not))))
      | .timestamp | sub("\\.[0-9]+"; "") | fromdateiso8601' 2>/dev/null | tail -1)
  # shortcut: 300 s de margen porque lo normal es actualizar nucleo y luego commitear.
  case "$MT,$COM" in *[!0-9,]*|,*|*,) ;; *)
    if [ "$MT" -gt 0 ] && [ "$COM" -gt $((MT + 300)) ]; then
      MODO=${NUCLEO_GATE:-observe}; [ "$MODO" = block ] || MODO=observe
      LOG=$HOME/.claude/session-logs/gate-nucleo.log
      if ! command grep -qF "	$COM	$SID	$RAIZ	" "$LOG" 2>/dev/null; then
        mkdir -p "$(dirname "$LOG")"
        printf '%s\t%s\t%s\t%s\t%s\n' "$(date +%FT%T%z)" "$COM" "$SID" "$RAIZ" "$MODO" >>"$LOG"
        [ "$MODO" = block ] && REASON="Hubo un git commit en esta sesión y $NUC no se ha tocado desde antes. Marca en Plan lo hecho, actualiza Paso actual, Siguiente acción, Pendientes y Ficheros tocados (con el comando que lo verificó). Si de verdad no cambia nada, di por qué en una línea y termina."
      fi
    fi;;
  esac
fi

if [ -n "$MSG$REASON" ]; then
  jq -cn --arg m "$MSG" --arg r "$REASON" \
    '(if $m != "" then {systemMessage:$m} else {} end) + (if $r != "" then {decision:"block",reason:$r} else {} end)'
fi
exit 0
