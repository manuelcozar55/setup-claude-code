#!/usr/bin/env bash
# test_bump.sh — scripts/bump.sh sube la version en todos los sitios y corre los sensores (W4 entregable 3).
# Sobre una copia del repo: bump.sh 9.9.9 deja 0 citas de la version anterior fuera de CHANGELOG/knowledge/tests,
# no toca la historia, y los sensores de version pasan; --cockpit sube plugin.json y sus dos citas; entradas
# invalidas se rechazan sin tocar nada. Solo awk/sed POSIX.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$HERE/../.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

copia() {  # destino: el arbol versionado (mas lo nuevo sin versionar) de este repo
  mkdir -p "$1"
  git -C "$REPO" ls-files -z --cached --others --exclude-standard | (cd "$REPO" && xargs -0 -I{} cp --parents -p {} "$1" 2>/dev/null)
  git -C "$1" init -q && git -C "$1" add -A
}
OLD="$(tr -d '[:space:]' < "$REPO/VERSION")"
COCK_OLD="$(jq -r .version "$REPO/kit/mods/cockpit/.claude-plugin/plugin.json")"

W="$tmp/w"; copia "$W"
# La seccion nueva del CHANGELOG la escribe la persona (bump no la inventa).
awk 'done == 0 && /^## \[[0-9]/ { print "## [9.9.9] - 2026-01-01\n\n### Cifras\n\nSin cifras: copia de prueba.\n"; done = 1 } { print }' "$W/CHANGELOG.md" > "$W/CL.new" && mv "$W/CL.new" "$W/CHANGELOG.md"
cl_antes="$(sha256sum < "$W/CHANGELOG.md")"
kn_antes="$(cd "$W" && find knowledge -type f | sort | xargs sha256sum | sha256sum)"

out="$(cd "$W" && bash scripts/bump.sh 9.9.9 2>&1)"; rc=$?
ck "$rc" "0" "bump.sh 9.9.9 sale 0 (sensores incluidos)"
ck "$(echo "$out" | grep -c '^sensor ok:')" "3" "y corrio los tres sensores en verde"
ck "$(cat "$W/VERSION")" "9.9.9" "VERSION sube"
ck "$(cd "$W" && git grep -lF "$OLD" -- . ':!CHANGELOG.md' ':!knowledge' ':!kit/test' ':!kit/evals' | wc -l | tr -d ' ')" "0" "0 ficheros citan la version anterior fuera de la historia"
ck "$(cd "$W" && git grep -F '"ref": "v9.9.9"' -- kit/claude/settings.json | wc -l | tr -d ' ')" "1" "el ref del marketplace en settings.json sube"
ck "$(grep -c 'scc-v9.9.9' "$W/BUILD_ID")" "1" "BUILD_ID sube"
ck "$(grep -c 'release/scc-v9.9.9-debian' "$W/ENTREGA.md")" "1" "el nombre de la rama de release en ENTREGA.md sube"
ck "$(sha256sum < "$W/CHANGELOG.md")" "$cl_antes" "no toca el CHANGELOG"
ck "$(cd "$W" && find knowledge -type f | sort | xargs sha256sum | sha256sum)" "$kn_antes" "no toca knowledge/"
ck "$(jq -r .version "$W/kit/mods/cockpit/.claude-plugin/plugin.json")" "$COCK_OLD" "sin --cockpit el cockpit no cambia"

# --cockpit
out="$(cd "$W" && bash scripts/bump.sh 9.9.10 --cockpit 7.7.7 --sin-sensores 2>&1)"; rc=$?
ck "$rc" "0" "bump.sh 9.9.10 --cockpit 7.7.7 sale 0"
ck "$(jq -r .version "$W/kit/mods/cockpit/.claude-plugin/plugin.json")" "7.7.7" "plugin.json del cockpit sube"
ck "$(grep -c 'cockpit: 7.7.7' "$W/README.md")" "1" "README cita el cockpit nuevo"
ck "$(grep -c 'incluye cockpit 7.7.7' "$W/kit/docs/11-cockpit.md")" "1" "11-cockpit.md cita el cockpit nuevo"
ck "$(echo "$out" | grep -c 'AVISO: CHANGELOG')" "1" "avisa de que falta la seccion 9.9.10 del CHANGELOG"

# Rechazos
for malo in "1.2" "v1.2.3" "x"; do
  ck "$(cd "$W" && bash scripts/bump.sh "$malo" >/dev/null 2>&1; echo $?)" "64" "rechaza '$malo' con 64"
done
ck "$(cd "$W" && bash scripts/bump.sh 9.9.10 >/dev/null 2>&1; echo $?)" "1" "rechaza subir a la version que ya hay"
ck "$(cat "$W/VERSION")" "9.9.10" "los rechazos no tocan nada"

# Sin git (paquete): mismo resultado con find
P="$tmp/p"; copia "$P"; rm -rf "$P/.git"
(cd "$P" && bash scripts/bump.sh 9.9.9 --sin-sensores >/dev/null 2>&1); rc=$?
ck "$rc" "0" "sin .git tambien funciona"
ck "$(cat "$P/VERSION")" "9.9.9" "y sube VERSION"

echo "== $pass ok, $fail fallos =="
[ "$fail" -eq 0 ]
