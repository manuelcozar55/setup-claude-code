#!/usr/bin/env bash
# test_mod_cockpit.sh — estructura y saneado del mod `cockpit` (kit/mods/cockpit).
# Sin red y sin el CLI `claude`: si esta en PATH ademas corre `plugin validate`,
# si no imprime SKIP. Los terminos privados se construyen por concatenacion para
# que ni esta suite los contenga como literal.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MOD="$HERE/../mods/cockpit"
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
pass=0; fail=0
check() { if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 (got $1 want $2)"; fail=$((fail+1)); fi; }
exists() { if [ -f "$MOD/$1" ]; then echo "ok - existe $1"; pass=$((pass+1)); else echo "NOT ok - falta $1"; fail=$((fail+1)); fi; }

PRIVATE="ci""rce|fc""irce|manuel""cozar|mco""zar|/home""/[a-z]|8456""586f|b860""1471"
# Solo se excluyen los tipos que genera Claude Code (gitignorados); plugin.json y types/ propios si se escanean
leaks() { find "$1" \( -name node_modules -o -path '*/.claude-plugin/types' \) -prune -o -type f -print0 | xargs -0 -r grep -IlEi "$PRIVATE" 2>/dev/null | wc -l | tr -d ' '; }

name="$(jq -r '.name // empty' "$MOD/.claude-plugin/plugin.json" 2>/dev/null || true)"
check "${name:+ok}" "ok" "plugin.json es JSON valido y tiene name"
# La versión del cockpit es una: plugin.json manda; la doc la cita y el marketplace, si la lleva, coincide.
ver="$(jq -r '.version // empty' "$MOD/.claude-plugin/plugin.json" 2>/dev/null || true)"
mver="$(jq -r '.plugins[] | select(.name == "cockpit") | .version // empty' "$MOD/../../../.claude-plugin/marketplace.json" 2>/dev/null || true)"
check "$(grep -c "cockpit $ver\\.\$" "$MOD/../../docs/11-cockpit.md")" "1" "la doc cita la version de plugin.json ($ver)"
check "${mver:-$ver}" "$ver" "el marketplace no contradice la version de plugin.json"
for f in hooks/register.tsx hooks/hooks.json tsconfig.json .gitignore types/index.d.ts \
         tests/cockpit.test.tsx tests/dock.test.tsx tests/handoff.test.tsx; do exists "$f"; done
check "$(jq -r '.modules[0]' "$MOD/hooks/hooks.json")" "./register.tsx" "hooks.json apunta a register.tsx"
check "$(grep -c 'claude-plugin/types' "$MOD/.gitignore")" "1" "tipos generados por Claude Code gitignorados"
check "$(find "$MOD" -name node_modules -prune -o -path '*/.claude/*' -print | wc -l | tr -d ' ')" "0" "sin estado privado (.claude/)"
check "$(leaks "$MOD")" "0" "sin terminos privados en el mod"

# El handoff lo fusiona el CLI (kit/claude/bin/handoff): el mod solo redacta el borrador y lo delega.
MERGE='mergeNucleo|keepCopies|excludeState|ALIAS'
merges() { grep -cE "$MERGE" "$1" || true; }
check "$(merges "$MOD/hooks/register.tsx")" "0" "sin funciones de fusion en TS (las hace el CLI handoff)"
check "$(grep -c 'bin:.*\/bin/handoff' "$MOD/hooks/register.tsx")" "1" "el mod declara el CLI bin/handoff (su resolución se prueba en los tests funcionales)"

# Falsabilidad: un termino privado plantado tiene que dar rojo.
cp -R "$MOD" "$tmp/mod"
printf 'x %s\n' "ci""rce" > "$tmp/mod/hooks/planted.txt"
check "$(leaks "$tmp/mod")" "1" "falsabilidad: termino privado plantado detectado"
printf 'export function mergeNucleo() {}\n' >> "$tmp/mod/hooks/register.tsx"
check "$(merges "$tmp/mod/hooks/register.tsx")" "1" "falsabilidad: una funcion de fusion plantada detectada"

if command -v claude >/dev/null 2>&1; then
  set +e; (cd "$MOD" && claude plugin validate . >/dev/null 2>&1); rc=$?; set -e
  check "$rc" "0" "claude plugin validate"
else
  echo "SKIP - claude no esta en PATH (plugin validate)"
  [ -z "${SCC_SKIP_LOG:-}" ] || echo "SKIP: plugin validate del cockpit (test_mod_cockpit.sh): claude no esta en PATH" >> "$SCC_SKIP_LOG"
fi

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
