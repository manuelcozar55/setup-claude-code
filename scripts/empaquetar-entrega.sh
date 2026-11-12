#!/usr/bin/env bash
# empaquetar-entrega.sh [--out DIR] [REF]
# Genera el paquete de entrega reproducible desde un tag o commit (REF, por defecto HEAD), sin mirar el arbol de
# trabajo: todo sale de `git archive`. En DIR (por defecto ./entrega) deja:
#   scc-vX.Y.Z/            SOLO el producto (ver PRODUCTO abajo)
#   scc-vX.Y.Z.zip         el mismo directorio en ZIP (orden y fechas fijados por el commit)
#   scc-vX.Y.Z.bundle      git bundle de la rama release/scc-vX.Y.Z-debian en ese commit (clonable sin red)
#   PROCEDENCIA.json       commit, version, fechas y si el arbol de trabajo estaba limpio
#   SHA256SUMS             suma de todo lo anterior (cd DIR && sha256sum -c SHA256SUMS)
# Necesita git, jq, sha256sum y zip (o python3 como alternativa a zip).
set -euo pipefail
usage() { echo "Uso: bash scripts/empaquetar-entrega.sh [--out DIR] [REF]" >&2; exit 64; }

OUT="./entrega"; REF="HEAD"; ref_dado=0
while [ $# -gt 0 ]; do
  case $1 in
    --out) [ $# -ge 2 ] || usage; OUT=$2; shift 2 ;;
    -h|--help) usage ;;
    -*) usage ;;
    *) [ "$ref_dado" -eq 0 ] || usage; REF=$1; ref_dado=1; shift ;;
  esac
done

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"
for c in git jq sha256sum; do command -v "$c" >/dev/null 2>&1 || { echo "empaquetar: falta $c" >&2; exit 1; }; done
COMMIT="$(git rev-parse --verify "$REF^{commit}")" || { echo "empaquetar: '$REF' no es un tag ni un commit" >&2; exit 1; }
VERSION="$(git show "$COMMIT:VERSION" | tr -d '[:space:]')"
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "empaquetar: VERSION ('$VERSION') en $REF no es X.Y.Z" >&2; exit 1; }
NOMBRE="scc-v$VERSION"
if git show-ref --verify --quiet "refs/tags/$REF" && [ "$REF" != "v$VERSION" ]; then
  echo "empaquetar: AVISO: el tag $REF no coincide con VERSION ($VERSION)" >&2
fi
LIMPIO=false
if [ -z "$(git status --porcelain)" ] && [ "$(git rev-parse HEAD)" = "$COMMIT" ]; then LIMPIO=true; fi

# Lo que necesita quien recibe el kit (C-transferencia I1). Sin kit/test ni kit/evals, sin knowledge/ ni el
# harness de la raiz. scripts/{backup,scc,aceptacion-local}.sh los usan uninstall.sh, ENTREGA.md y la aceptacion.
PRODUCTO=(kit uninstall.sh scripts/backup.sh scripts/scc.sh scripts/aceptacion-local.sh
  ENTREGA.md README.md VERSION BUILD_ID LICENSE NOTICE THIRD-PARTY.md SECURITY.md CHANGELOG.md)
EXCLUIDOS=(':(exclude)kit/test' ':(exclude)kit/evals')

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
if [ -e "$OUT/$NOMBRE" ] || [ -e "$OUT/$NOMBRE.zip" ]; then
  echo "empaquetar: $OUT ya contiene $NOMBRE: usa otro --out o vacialo tu (este script no borra)" >&2; exit 1
fi
mkdir "$OUT/$NOMBRE"
git archive "$COMMIT" -- "${PRODUCTO[@]}" "${EXCLUIDOS[@]}" | tar -x -C "$OUT/$NOMBRE"
FECHA_COMMIT="$(git show -s --format=%cI "$COMMIT")"
EPOCH="$(git show -s --format=%ct "$COMMIT")"

# ZIP determinista: orden fijo y fechas del commit.
(
  cd "$OUT"
  find "$NOMBRE" -exec touch -d "@$EPOCH" {} +
  if command -v zip >/dev/null 2>&1; then
    find "$NOMBRE" | LC_ALL=C sort | zip -X -q "$NOMBRE.zip" -@
  else
    python3 -I -m zipfile -c "$NOMBRE.zip" "$NOMBRE"
  fi
)

# Bundle: la rama que ENTREGA.md manda clonar, creada en un repo temporal para no tocar este.
TMPB="$(mktemp -d)"; trap 'rm -r "$TMPB"' EXIT
git init -q --bare "$TMPB/b"
git -C "$TMPB/b" fetch -q "$REPO" "$COMMIT:refs/heads/release/$NOMBRE-debian"
git -C "$TMPB/b" bundle create "$OUT/$NOMBRE.bundle" "release/$NOMBRE-debian" >/dev/null 2>&1

jq -n --arg commit "$COMMIT" --arg ref "$REF" --arg version "$VERSION" --arg fecha "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg fecha_commit "$FECHA_COMMIT" --argjson limpio "$LIMPIO" \
  '{commit: $commit, ref: $ref, version: $version, fecha_empaquetado: $fecha, fecha_commit: $fecha_commit, arbol_limpio: $limpio}' \
  > "$OUT/PROCEDENCIA.json"

(
  cd "$OUT"
  { find "$NOMBRE" -type f | LC_ALL=C sort; echo "$NOMBRE.zip"; echo "$NOMBRE.bundle"; echo PROCEDENCIA.json; } \
    | while IFS= read -r f; do sha256sum -- "$f"; done > SHA256SUMS
)
echo "empaquetar: $NOMBRE listo en $OUT (commit $COMMIT, arbol limpio: $LIMPIO)"
echo "  comprueba: cd $OUT && sha256sum -c SHA256SUMS"
