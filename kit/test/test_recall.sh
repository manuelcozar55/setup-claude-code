#!/usr/bin/env bash
# test_recall.sh — scripts/recuerda (scripts/recall.py) sobre un directorio de memorias
# SINTETICO de 3 memorias (nunca sobre el almacen real). Comprueba que devuelve solo los
# parrafos que coinciden, sin acentos ni mayusculas, el indice (-l), una completa (-f) y
# rc 1 ante un termino ausente: ese rc es lo que distingue "no lo se" de "no hay nada".
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
REPO="$(cd "$KIT/.." && pwd)"
R="$REPO/scripts/recuerda"
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
M="$tmp/memory"; mkdir -p "$M"
mem() { # slug descripcion cuerpo
  printf -- '---\nname: %s\ndescription: %s\nmetadata:\n  type: project\n---\n\n%s\n' "$1" "$2" "$3" > "$M/$1.md"
}
mem compactacion-umbral "Umbral real de la compactacion" \
  "La compactación salta cerca del umbral medido.

Párrafo sin relación con el tema buscado."
mem pnpm-path "pnpm fuera del PATH" "El bin global de pnpm cambió de sitio."
mem gitlab-acceso "Acceso al GitLab" "SSH funciona; HTTPS sin token da 401."
printf -- '- [x](compactacion-umbral.md) — indice\n' > "$M/MEMORY.md"
run() { HOME="$tmp" CLAUDE_MEMORY_DIR="$M" "$R" "$@"; }

out=$(run COMPACTACION); rc=$?
ck "$rc" "0" "un termino que coincide sale 0"
ck "$(grep -c '^## compactacion-umbral' <<<"$out")" "1" "sin mayusculas: COMPACTACION encuentra la memoria"
ck "$(grep -c 'sin relación' <<<"$out")" "0" "devuelve solo el parrafo que coincide, no la memoria entera"
ck "$(grep -c '^## ' <<<"$out")" "1" "solo la memoria que coincide"

# «cambió» solo aparece acentuado y en el cuerpo: no lo salva ni el slug ni la descripcion.
ck "$(run CAMBIO | grep -c '^## pnpm-path')" "1" "sin acentos: CAMBIO encuentra «cambió» en el cuerpo"

out=$(run -l); rc=$?
ck "$rc" "0" "-l sale 0"
ck "$(grep -c '^[a-z]' <<<"$out")" "3" "-l lista las 3 memorias y no MEMORY.md"

out=$(run -f pnpm-path); rc=$?
ck "$rc" "0" "-f sale 0"
ck "$out" "$(cat "$M/pnpm-path.md")" "-f devuelve la memoria completa, frontmatter incluido"
run -f ../MEMORY >/dev/null 2>&1; ck "$?" "2" "-f rechaza un slug que sale del directorio"

run inexistentexyz >/dev/null 2>&1; ck "$?" "1" "termino ausente sale 1"
HOME="$tmp" CLAUDE_MEMORY_DIR="$tmp/no-hay" "$R" pnpm >/dev/null 2>&1; ck "$?" "2" "directorio de memorias ausente sale 2, sin traza"

echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
