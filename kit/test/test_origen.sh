#!/usr/bin/env bash
# test_origen.sh — el repo de origen (owner/repo) vive en kit/ORIGEN y scripts/cambiar-origen.sh lo reescribe
# donde aparece (W4 entregable 6). Sobre una copia del repo: tras cambiar-origen no queda ninguna aparicion
# del origen anterior fuera de CHANGELOG/knowledge, y los sensores que lo usan (plantilla de settings,
# install-plugins, fusion de settings) siguen en verde con el origen nuevo. Mide tambien el estado real:
# toda aparicion del origen en el repo esta en una de las categorias que el script conoce.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$HERE/../.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }
read -r ORIG < "$REPO/kit/ORIGEN"

# En el repo real, fuera de la historia y de los tests, las apariciones estan donde el script las reescribe.
ck "$(git -C "$REPO" grep -lF "$ORIG" -- . ':!CHANGELOG.md' ':!knowledge' ':!kit/test' ':!kit/ORIGEN' | grep -c .)" "$(cd "$REPO" && grep -rlF "$ORIG" . --exclude-dir=.git --exclude-dir=knowledge --exclude-dir=test --exclude=CHANGELOG.md --exclude=ORIGEN | grep -c .)" "git grep y grep ven las mismas apariciones (ninguna escondida en un ignorado)"
ck "$(grep -c "$ORIG" "$REPO/kit/install-plugins.sh")" "1" "install-plugins.sh solo cita el origen como valor por defecto de su lectura de kit/ORIGEN"
ck "$(grep -c 'ORIGEN' "$REPO/kit/install-plugins.sh")" "3" "y lee kit/ORIGEN"

R="$tmp/r"; mkdir -p "$R"
git -C "$REPO" ls-files -z --cached --others --exclude-standard | (cd "$REPO" && xargs -0 -I{} cp --parents -p {} "$R" 2>/dev/null)
git -C "$R" init -q && git -C "$R" add -A
NEW="otra-org/mi-fork"
out="$(cd "$R" && bash scripts/cambiar-origen.sh "$NEW" 2>&1)"; rc=$?
ck "$rc" "0" "cambiar-origen.sh $NEW sale 0"
ck "$(cat "$R/kit/ORIGEN")" "$NEW" "kit/ORIGEN lleva el origen nuevo"
ck "$(cd "$R" && git grep -lF "$ORIG" -- . ':!CHANGELOG.md' ':!knowledge' | wc -l | tr -d ' ')" "0" "no queda ninguna aparicion del origen anterior (salvo CHANGELOG y knowledge)"
ck "$(jq -r '.extraKnownMarketplaces["setup-claude-code"].source.repo' "$R/kit/claude/settings.json")" "$NEW" "settings.json apunta al origen nuevo"
ck "$(grep -c "^claude plugin marketplace add $NEW@v" <(cd "$R" && PATH="$tmp/nada:/usr/bin:/bin" bash kit/install-plugins.sh 2>/dev/null))" "1" "install-plugins.sh imprime el origen nuevo"
ck "$(echo "$out" | grep -c 'quedan referencias al autor anterior')" "1" "avisa de los datos de autoria que no son del origen"
for t in test_settings_template test_install_plugins test_install_settings_merge; do
  ck "$(cd "$R" && bash "kit/test/$t.sh" >/dev/null 2>&1; echo $?)" "0" "con el origen nuevo sigue verde: $t"
done
ck "$(cd "$R" && bash scripts/cambiar-origen.sh "$NEW" >/dev/null 2>&1; echo $?)" "1" "cambiar al mismo origen se rechaza"
ck "$(cd "$R" && bash scripts/cambiar-origen.sh "sin-barra" >/dev/null 2>&1; echo $?)" "64" "un origen sin owner/repo se rechaza con 64"

echo "== $pass ok, $fail fallos =="
[ "$fail" -eq 0 ]
