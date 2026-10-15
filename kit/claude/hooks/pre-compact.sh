#!/usr/bin/env bash
# PreCompact — checkpoint determinista ANTES de que el resumen del modelo destruya el contexto, y
# una línea de KPI: ¿llega nucleo.md fresco a la compactación?
# stdin: {"trigger":"manual|auto","session_id":"...","transcript_path":"...","cwd":"..."}
# El campo es `trigger`; `triggerReason` no existe en el binario.
# El checkpoint lo re-inyecta session-start-compact.sh (recortado). Vive junto a nucleo.md, en
# <raíz>/.claude/estado/ (solo si ya existe: un repo sin nucleo no se ensucia), con una línea en su
# .gitignore para no colarse en un commit: trae los últimos prompts de la persona.
# Observacional: nunca bloquea (exit 0 siempre).
set -u
IN=$(cat)
TRIGGER=$(jq -r '.trigger // "unknown"' <<<"$IN" 2>/dev/null || echo unknown)
TP=$(jq -r '.transcript_path // empty' <<<"$IN" 2>/dev/null)
SID=$(jq -r '.session_id // empty' <<<"$IN" 2>/dev/null)
CWD=$(jq -r '.cwd // empty' <<<"$IN" 2>/dev/null); CWD=${CWD:-$PWD}
# shellcheck source=SCRIPTDIR/lib/nucleo.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/nucleo.sh"
RAIZ=$(nucleo_raiz "$CWD")
nucleo_enlazado "$RAIZ" && exit 0
ESTADO="$RAIZ/.claude/estado"

# KPI: ts sesión ctx% edad_nucleo_s (-1 si no existe). Se mide con nucleo_audit o con awk.
MT=$(stat -c %Y "$ESTADO/nucleo.md" 2>/dev/null || stat -f %m "$ESTADO/nucleo.md" 2>/dev/null)
PCT=$( { [ -n "$TP" ] && nucleo_ctx "$TP"; } | cut -d' ' -f2)
mkdir -p "$HOME/.claude/session-logs" 2>/dev/null \
  && printf '%s %s %s %s\n' "$(date +%FT%T%z)" "${SID:--}" "${PCT:--}" "$([ -n "$MT" ] && echo $(( $(date +%s) - MT )) || echo -1)" \
     >>"$HOME/.claude/session-logs/nucleo-freshness.log"
# Una línea por compactación y nadie la leía entera: se acota a las últimas 1000 al pasar de 2000.
# Temporal único en el mismo directorio (mv atómico) con el modo del log, y borrado si algo falla
# o si una señal mata el hook a medias. Aceptado: con dos compactaciones a la vez se puede perder
# la línea que la otra añada entre el tail y el mv. chmod --reference es de GNU: sin él, el log
# rota igual con el 0600 de mktemp.
FLOG="$HOME/.claude/session-logs/nucleo-freshness.log"
FTMP=
trap '[ -z "$FTMP" ] || rm -f -- "$FTMP"' EXIT
trap 'exit 0' HUP INT TERM
if [ "$(wc -l <"$FLOG" 2>/dev/null || echo 0)" -gt 2000 ] && FTMP=$(mktemp "$FLOG.XXXXXX" 2>/dev/null); then
  { tail -n 1000 "$FLOG" >"$FTMP" && { chmod --reference="$FLOG" "$FTMP" || :; } \
      && mv -f -- "$FTMP" "$FLOG"; } 2>/dev/null || rm -f -- "$FTMP"
fi
FTMP=

[ -d "$ESTADO" ] || exit 0
GI=$ESTADO/.gitignore
if [ ! -L "$GI" ] && ! command grep -qsx 'checkpoint-compact-\*' "$GI"; then
  [ -s "$GI" ] && [ -n "$(tail -c1 "$GI")" ] && echo >>"$GI"
  echo 'checkpoint-compact-*' >>"$GI"
fi
OUT="$ESTADO/checkpoint-compact.md"
[ -n "$SID" ] && OUT="$ESTADO/checkpoint-compact-$(printf '%s' "$SID" | sha256sum | cut -d' ' -f1).md"
TMP=$(mktemp "$ESTADO/.checkpoint-compact.XXXXXX") || exit 0
trap 'rm -f -- "$TMP"' EXIT
trap 'exit 0' HUP INT TERM
(
  set -e
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
  if [ -n "$TP" ] && [ -f "$TP" ]; then
    echo; echo "## últimos mensajes humanos"
    tail -n 3000 "$TP" \
      | jq -r 'select(.type == "user" and ((.isMeta // false) | not))
          | .message.content | if type == "array" then map(select(.type == "text") | .text) | join(" ") else . end
          | select(type == "string") | gsub("\\s+"; " ")' 2>/dev/null \
      | command grep -v -e '^<' -e '^\s*$' | tail -3 | cut -c1-400 | sed 's/^/- /' || true
  fi
  echo; echo "## pendientes declarados"
  command grep -hE '^\s*- \[ \]' "$ESTADO/nucleo.md" 2>/dev/null | head -15 || true
) > "$TMP" 2>/dev/null
# shellcheck disable=SC2181  # `if ! (…)` apagaría el set -e de dentro
[ "$?" -eq 0 ] || { echo '[PreCompact] fallo al generar checkpoint; anterior conservado' >&2; exit 0; }
mv -f -- "$TMP" "$OUT" 2>/dev/null || { echo '[PreCompact] fallo al publicar checkpoint; anterior conservado' >&2; exit 0; }
# Uno por sesión y con prompts de la persona: sin rotar se acumulan para siempre. Va después de
# publicar el nuevo, así un fallo de arriba no deja sin checkpoint viejo ni nuevo; $OUT no se toca.
find "$ESTADO" -maxdepth 1 -type f -name 'checkpoint-compact-*.md' ! -path "$OUT" -mtime +14 -delete 2>/dev/null
echo "[PreCompact] ($TRIGGER) checkpoint en $OUT" >&2
exit 0
