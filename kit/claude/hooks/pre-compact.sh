#!/usr/bin/env bash
# PreCompact — checkpoint determinista ANTES de que el resumen del modelo destruya el contexto, y
# una línea de KPI: ¿llega nucleo.md fresco a la compactación?
# stdin: {"trigger":"manual|auto","session_id":"...","transcript_path":"...","cwd":"..."}
# El campo es `trigger`; `triggerReason` no existe en el binario.
# El checkpoint lo re-inyecta session-start-compact.sh (recortado). Vive en <raíz>/.claude/estado/checkpoints/,
# que nucleo_estado_dir crea si falta junto con su .gitignore interno (trae los últimos prompts de la
# persona: nunca a git). Desde ~ no hay proyecto: solo se escribe donde ya hubiera un estado/ heredado.
# Observacional: nunca bloquea (exit 0 siempre).
set -u
IN=$(cat)
TRIGGER=$(jq -r '.trigger // "unknown"' <<<"$IN" 2>/dev/null || echo unknown)
TP=$(jq -r '.transcript_path // empty' <<<"$IN" 2>/dev/null)
SID=$(jq -r '.session_id // empty' <<<"$IN" 2>/dev/null)
CWD=$(jq -r '.cwd // empty' <<<"$IN" 2>/dev/null); CWD=${CWD:-$PWD}
# shellcheck source=SCRIPTDIR/lib/nucleo.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/nucleo.sh"
RAIZ=$(nucleo_raiz "$CWD" 2)
nucleo_enlazado "$RAIZ" && exit 0
if nucleo_modo_estado_md "$RAIZ"; then NUC=$RAIZ/ESTADO.md; else NUC=$(nucleo_ruta "$RAIZ") || exit 0; fi

# KPI: ts sesión ctx% edad_nucleo_s (-1 si no existe). Se mide con nucleo_audit o con awk.
MT=$(stat -c %Y "$NUC" 2>/dev/null || stat -f %m "$NUC" 2>/dev/null)
PCT=$( { [ -n "$TP" ] && nucleo_ctx "$TP"; } | cut -d' ' -f2)
mkdir -p "${CLAUDE_HOME:-$HOME/.claude}/session-logs" 2>/dev/null \
  && printf '%s %s %s %s\n' "$(date +%FT%T%z)" "${SID:--}" "${PCT:--}" "$([ -n "$MT" ] && echo $(( $(date +%s) - MT )) || echo -1)" \
     >>"${CLAUDE_HOME:-$HOME/.claude}/session-logs/nucleo-freshness.log"
# Una línea por compactación y nadie la leía entera: se acota a las últimas 1000 al pasar de 2000.
# Temporal único en el mismo directorio (mv atómico) con el modo del log, y borrado si algo falla
# o si una señal mata el hook a medias. Aceptado: con dos compactaciones a la vez se puede perder
# la línea que la otra añada entre el tail y el mv. chmod --reference es de GNU: sin él, el log
# rota igual con el 0600 de mktemp.
FLOG="${CLAUDE_HOME:-$HOME/.claude}/session-logs/nucleo-freshness.log"
FTMP=
trap '[ -z "$FTMP" ] || rm -f -- "$FTMP"' EXIT
trap 'exit 0' HUP INT TERM
if [ "$(wc -l <"$FLOG" 2>/dev/null || echo 0)" -gt 2000 ] && FTMP=$(mktemp "$FLOG.XXXXXX" 2>/dev/null); then
  { tail -n 1000 "$FLOG" >"$FTMP" && { chmod --reference="$FLOG" "$FTMP" || :; } \
      && mv -f -- "$FTMP" "$FLOG"; } 2>/dev/null || rm -f -- "$FTMP"
fi
FTMP=

if [ "$RAIZ" = "$HOME" ]; then
  ESTADO="$RAIZ/.claude/estado"; CPD=$ESTADO
  [ -d "$ESTADO" ] || exit 0
  GI=$ESTADO/.gitignore
  if [ ! -L "$GI" ] && ! command grep -qsx 'checkpoint-compact\*' "$GI"; then
    [ -s "$GI" ] && [ -n "$(tail -c1 "$GI")" ] && echo >>"$GI"
    echo 'checkpoint-compact*' >>"$GI"
  fi
else
  ESTADO=$(nucleo_estado_dir "$RAIZ") || exit 0
  CPD=$ESTADO/checkpoints
fi
OUT="$CPD/checkpoint-compact.md"
[ -n "$SID" ] && OUT="$CPD/checkpoint-compact-$(printf '%s' "$SID" | sha256sum | cut -d' ' -f1).md"
# El aviso de fallo no promete un checkpoint anterior si esta sesión aún no tiene ninguno.
PREVIO='anterior conservado'; [ -e "$OUT" ] || PREVIO='no había ninguno anterior'
TMP=$(mktemp "$CPD/.checkpoint-compact.XXXXXX") || exit 0
trap 'rm -f -- "$TMP"' EXIT
trap 'exit 0' HUP INT TERM
(
  set -e -o pipefail
  echo "# Checkpoint pre-compact ($TRIGGER) $(date -Is)"
  echo "cwd: $CWD"
  # Claude permite 10 s para el hook completo; Git deja margen para publicar el checkpoint.
  # core.fsmonitor=false: un .git/config ajeno no ejecuta su fsmonitor desde este hook.
  # shellcheck disable=SC2016  # $1 lo expande el bash hijo
  timeout -k 1 5 bash -c '
    if git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      echo; echo "## git"
      echo "rama: $(git -C "$1" branch --show-current)"
      git -c core.fsmonitor=false -C "$1" status --short | head -30
      git -c core.fsmonitor=false -C "$1" diff --stat | tail -1
    fi
  ' bash "$RAIZ" 2>/dev/null || true
  if [ -n "$TP" ]; then
    # Fichero ausente o ilegible, o jq que falla (también si ninguna línea es JSON): set -e -o pipefail
    # aborta y el checkpoint anterior se conserva. Una línea a medias (Claude Code sigue escribiendo
    # mientras corre el hook) se descarta sin más: fromjson? la salta. Un registro con otra forma (message,
    # payload o un elemento de content que no es objeto) también: objects lo salta, sin abortar todo.
    { [ -f "$TP" ] && [ -r "$TP" ]; } || exit 1
    echo; echo "## últimos mensajes humanos"
    # Claude Code: type=user. Codex: event_msg/user_message (response_item repetiría el mismo texto).
    tail -n 3000 "$TP" \
      | jq -Rr -n '[inputs | fromjson? | select(type == "object")] as $l
          | if ($l | length) == 0 then error("ninguna línea JSON") else $l[] end
          | if .type == "user" and ((.isMeta // false) | not) then
              (.message | objects | .content) | if type == "array" then map(objects | select(.type == "text") | .text) | join(" ") else . end
            elif .type == "event_msg" and (.payload | objects | .type) == "user_message" then .payload.message
            else empty end
          | select(type == "string") | gsub("\\s+"; " ")
          | select(startswith("<") | not) | select(test("[^[:space:]]"))' 2>/dev/null \
      | tail -3 | cut -c1-400 | sed 's/^/- /'
  fi
  echo; echo "## pendientes declarados"
  command grep -hE '^\s*- \[ \]' "$NUC" 2>/dev/null | head -15 || true
) > "$TMP" 2>/dev/null
# shellcheck disable=SC2181  # `if ! (…)` apagaría el set -e de dentro
[ "$?" -eq 0 ] || { echo "[PreCompact] fallo al generar checkpoint; $PREVIO" >&2; exit 0; }
mv -f -- "$TMP" "$OUT" 2>/dev/null || { echo "[PreCompact] fallo al publicar checkpoint; $PREVIO" >&2; exit 0; }
# Uno por sesión y con prompts de la persona: sin rotar se acumulan para siempre. Va después de
# publicar el nuevo, así un fallo de arriba no deja sin checkpoint viejo ni nuevo; $OUT no se toca.
# Por edad (14 días) y por número (NUCLEO_CHECKPOINT_KEEP, 5 por defecto, contando el nuevo): con muchas
# sesiones al día la edad sola dejaba decenas de ficheros con prompts.
find "$CPD" -maxdepth 1 -type f -name 'checkpoint-compact-*.md' ! -path "$OUT" -mtime +14 -delete 2>/dev/null
KEEP=${NUCLEO_CHECKPOINT_KEEP:-5}
case $KEEP in ''|*[!0-9]*|0) KEEP=5 ;; esac
find "$CPD" -maxdepth 1 -type f -name 'checkpoint-compact-*.md' ! -path "$OUT" -printf '%T@ %p\n' 2>/dev/null \
  | sort -rn | tail -n +"$KEEP" | cut -d' ' -f2- | while IFS= read -r f; do rm -f -- "$f"; done
echo "[PreCompact] ($TRIGGER) checkpoint en $OUT" >&2
exit 0
