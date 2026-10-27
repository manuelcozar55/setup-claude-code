#!/usr/bin/env bash
# PostCompact — ¿sobrevivieron al resumen las anclas del checkpoint? Deja una línea medible en el log.
# stdin: {"trigger":"manual|auto","compact_summary":"...","session_id":"...","cwd":"..."}
# Por qué: sin sensor, «el resumen conserva lo importante» es una creencia. Anclas = ficheros que el
# checkpoint de pre-compact.sh declara tocados (su sección «## git», el `git status --short`; un fichero
# que la persona solo nombra en un prompt no es ancla); los que el resumen no nombra se anotan en
# session-logs/compact-AAAA-MM.log (campo anclas_perdidas=, que lee scripts/compact-audit.py).
# Observacional y gratis: sin modelo, nunca bloquea (exit 0 siempre).
set -u
IN=$(cat)
TRIGGER=$(jq -r '.trigger // "unknown"' <<<"$IN" 2>/dev/null) || exit 0
S=$(jq -r '.compact_summary // ""' <<<"$IN" 2>/dev/null) || exit 0
SID=$(jq -r '.session_id // empty' <<<"$IN" 2>/dev/null)
CWD=$(jq -r '.cwd // empty' <<<"$IN" 2>/dev/null); CWD=${CWD:-$PWD}
# shellcheck source=SCRIPTDIR/lib/nucleo.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/nucleo.sh"
RAIZ=$(nucleo_raiz "$CWD" 2)
nucleo_enlazado "$RAIZ" && exit 0
# Mismo sitio y nombre que escribe pre-compact.sh. Desde ~ no hay anclas: su git status es el de toda la carpeta personal.
CPD="$RAIZ/.claude/estado/checkpoints"
CK="$CPD/checkpoint-compact.md"
[ -n "$SID" ] && CK="$CPD/checkpoint-compact-$(printf '%s' "$SID" | sha256sum | cut -d' ' -f1).md"
LOGD="${CLAUDE_HOME:-$HOME/.claude}/session-logs"; mkdir -p "$LOGD" 2>/dev/null || exit 0
MISS=""
if [ "$RAIZ" != "$HOME" ] && [ -f "$CK" ] && [ ! -L "$CK" ]; then
  # Se excluye el propio estado (.claude/estado/*): lo reinyecta session-start-compact.sh. Un «??» tampoco cuenta: el
  # git status lista todo lo no seguido, lo haya tocado la sesión o no (medido: 12 de 12 anclas falsas).
  while read -r f; do
    [ -n "$f" ] || continue
    grep -qF -- "$(basename "$f")" <<<"$S" || MISS="$MISS $f"
  done < <(awk '/^## /{g=($0=="## git");next} g && !/^rama: / && !/^\?\? /' "$CK" 2>/dev/null \
    | grep -oE '[A-Za-z0-9_./-]+\.(py|ts|tsx|js|md|sh|json|sql|toml|ya?ml)' | grep -v '/estado/' | sort -u | head -40)
fi
MISS=${MISS# }
# shellcheck disable=SC2086  # contar palabras
N_MISS=$(set -- $MISS; echo $#)
printf '%s\t%s\tresumen_chars=%s\tanclas_perdidas=%s\t%s\n' \
  "$(date -Is)" "$TRIGGER" "${#S}" "$N_MISS" "${MISS:0:300}" >>"$LOGD/compact-$(date +%Y-%m).log" 2>/dev/null
if [ "$N_MISS" -gt 0 ]; then
  jq -cn --arg m "${MISS:0:200}" --arg ck "$CK" \
    '{systemMessage:("Compactación: el resumen no menciona "+$m+". El checkpoint completo sigue en "+$ck)}' 2>/dev/null
fi
exit 0
