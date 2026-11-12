#!/usr/bin/env bash
# cambiar-origen.sh nuevo-owner/nuevo-repo
# Para un fork: reescribe el repo de origen (owner/repo de GitHub) en kit/ORIGEN y en todas las apariciones
# versionadas (settings.json, docs, README, ENTREGA, CONTRIBUTING, SECURITY...). No toca CHANGELOG.md ni knowledge/
# (historia) ni kit/test (los tests leen kit/ORIGEN). Lo que NO cambia (nombre y correo del autor en README,
# SECURITY y kit/README) se lista al final: son datos de autoria, no de origen; cambialos a mano.
# POSIX: sed y git grep.
set -euo pipefail
usage() { echo "Uso: bash scripts/cambiar-origen.sh nuevo-owner/nuevo-repo" >&2; exit 64; }
[ $# -eq 1 ] || usage
NEW=$1
[[ $NEW =~ ^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9._-]+$ ]] || { echo "cambiar-origen: '$NEW' no es owner/repo" >&2; usage; }

cd "$(dirname "${BASH_SOURCE[0]}")/.."
[ -f kit/ORIGEN ] || { echo "cambiar-origen: no encuentro kit/ORIGEN" >&2; exit 1; }
read -r OLD < kit/ORIGEN
[ "$OLD" != "$NEW" ] || { echo "cambiar-origen: el origen ya es $NEW" >&2; exit 1; }
old_re="$(printf '%s' "$OLD" | sed 's/[.[\*^$/|]/\\&/g')"
new_rep="$(printf '%s' "$NEW" | sed 's/[&|\\]/\\&/g')"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  lista() { git grep -lF -e "$OLD" -- . ':!CHANGELOG.md' ':!knowledge' ':!kit/test' || true; }
else
  lista() { grep -rlF -e "$OLD" . --exclude-dir=knowledge --exclude-dir=test --exclude=CHANGELOG.md | sed 's|^\./||' || true; }
fi
n=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  sed -i "s|$old_re|$new_rep|g" "$f"
  echo "cambiar-origen: $f"; n=$((n + 1))
done < <(lista)
printf '%s\n' "$NEW" > kit/ORIGEN
echo "cambiar-origen: $OLD -> $NEW en $n ficheros (y kit/ORIGEN)"

dueno="${OLD%%/*}"
resto="$(git grep -nF -e "$dueno" -- . ':!CHANGELOG.md' ':!knowledge' ':!kit/test' ':!kit/ORIGEN' 2>/dev/null | cut -c1-110 || true)"
if [ -n "$resto" ]; then
  echo "cambiar-origen: quedan referencias al autor anterior ($dueno), que no son del origen; revisalas a mano:"
  printf '%s\n' "$resto"
fi
