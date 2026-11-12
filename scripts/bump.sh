#!/usr/bin/env bash
# bump.sh X.Y.Z [--cockpit A.B.C] [--sin-sensores]
# Sube la version del kit en TODOS los sitios donde vive y corre los sensores de version. Descubre los sitios
# con git grep (no con una lista fija): cualquier fichero versionado que cite la version actual, salvo
# CHANGELOG.md (historia), knowledge/ (historia) y kit/test (fixtures). Con --cockpit sube tambien la version del
# cockpit (plugin.json, README, kit/docs/11-cockpit.md). No toca el CHANGELOG: escribe tu la seccion nueva
# (con «### Cifras» o «Sin cifras: <motivo>») antes o despues; los sensores no pasaran sin ella.
# POSIX: sed -E y awk sin extensiones de gawk (Debian trae mawk).
set -euo pipefail
usage() { echo "Uso: bash scripts/bump.sh X.Y.Z [--cockpit A.B.C] [--sin-sensores]" >&2; exit 64; }

NEW=""; COCKPIT=""; SENSORES=1
while [ $# -gt 0 ]; do
  case $1 in
    --cockpit) [ $# -ge 2 ] || usage; COCKPIT=$2; shift 2 ;;
    --sin-sensores) SENSORES=0; shift ;;
    -h|--help) usage ;;
    -*) usage ;;
    *) [ -z "$NEW" ] || usage; NEW=$1; shift ;;
  esac
done
[ -n "$NEW" ] || usage
semver='^[0-9]+\.[0-9]+\.[0-9]+$'
[[ $NEW =~ $semver ]] || { echo "bump: '$NEW' no es X.Y.Z" >&2; exit 64; }
[ -z "$COCKPIT" ] || [[ $COCKPIT =~ $semver ]] || { echo "bump: '$COCKPIT' no es A.B.C" >&2; exit 64; }

cd "$(dirname "${BASH_SOURCE[0]}")/.."
[ -f VERSION ] || { echo "bump: no encuentro VERSION: ejecuta desde un clon del repo" >&2; exit 1; }
OLD="$(tr -d '[:space:]' < VERSION)"
[[ $OLD =~ $semver ]] || { echo "bump: VERSION ('$OLD') no es X.Y.Z" >&2; exit 1; }
[ "$OLD" != "$NEW" ] || { echo "bump: ya estas en $NEW" >&2; exit 1; }

# git grep si hay repo; si no (paquete sin .git), find.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  lista() { git grep -lF -e "$OLD" -- . ':!CHANGELOG.md' ':!knowledge' ':!kit/test' ':!kit/evals' || true; }
else
  lista() { grep -rlF -e "$OLD" . --exclude-dir=knowledge --exclude-dir=test --exclude-dir=evals --exclude=CHANGELOG.md | sed 's|^\./||' || true; }
fi
old_re="${OLD//./\\.}"
cambiados=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  # Dos pasadas: dos citas separadas por un solo caracter comparten el separador y la primera pasada salta la segunda.
  sed -E -i -e "s/(^|[^0-9.])${old_re}(\$|[^0-9])/\1${NEW}\2/g" -e "s/(^|[^0-9.])${old_re}(\$|[^0-9])/\1${NEW}\2/g" "$f"
  echo "bump: $f  $OLD -> $NEW"; cambiados=$((cambiados + 1))
done < <(lista)

if [ -n "$COCKPIT" ]; then
  PJ=kit/mods/cockpit/.claude-plugin/plugin.json
  sed -E -i "s/(\"version\": *\")[0-9]+\.[0-9]+\.[0-9]+\"/\1${COCKPIT}\"/" "$PJ"
  sed -E -i "s/(cockpit: )[0-9]+\.[0-9]+\.[0-9]+/\1${COCKPIT}/" README.md
  sed -E -i "s/(incluye cockpit )[0-9]+\.[0-9]+\.[0-9]+/\1${COCKPIT}/" kit/docs/11-cockpit.md
  echo "bump: cockpit -> $COCKPIT (plugin.json, README.md, kit/docs/11-cockpit.md)"
fi

# Lo que queda: citas de la version vieja fuera de las zonas de historia.
resto="$(lista || true)"
if [ -n "$resto" ]; then echo "bump: AUN citan $OLD: $resto" >&2; exit 1; fi
if ! grep -q "^## \[$NEW\]" CHANGELOG.md; then
  echo "bump: AVISO: CHANGELOG.md no tiene la seccion «## [$NEW] - AAAA-MM-DD». Escribela (con «### Cifras» o «Sin cifras: <motivo>»); los sensores no pasaran sin ella." >&2
fi
echo "bump: $cambiados ficheros editados ($OLD -> $NEW)"

[ "$SENSORES" -eq 1 ] || exit 0
rc=0
for t in test_doc_claims test_settings_template test_changelog_cifras; do
  if bash "kit/test/$t.sh" >/dev/null 2>&1; then echo "sensor ok:    $t"; else echo "sensor ROJO:  $t (bash kit/test/$t.sh para ver el motivo)"; rc=1; fi
done
exit "$rc"
