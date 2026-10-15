#!/usr/bin/env bash
# test_plugin_esenciales.sh — estructura del plugin `esenciales` (kit/plugins/esenciales):
# plugin.json valido, exactamente 6 skills con frontmatter, LICENSE MIT, sin hooks/ (no
# inyecta nada al arrancar), ni rastro del namespace original ni de las skills que se
# dejaron fuera, y listado en el marketplace del repo. Falsable: plantar una referencia
# excluida o un hooks/ en una copia tiene que dar rojo.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$HERE/../.."
P="$ROOT/kit/plugins/esenciales"
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

EXCLUIDAS="test-driven-development|verification-before-completion|requesting-code-review|receiving-code-review|executing-plans|using-git-worktrees|writing-skills|using-superpowers"
# El README explica por que se excluyeron y tiene que poder nombrarlas; las skills no.
restos(){ { grep -rlF 'superpowers:' "$1" 2>/dev/null; grep -rlE "$EXCLUIDAS" "$1" --exclude=README.md 2>/dev/null; } | wc -l | tr -d ' '; }

ck "$(jq -r '.name // empty' "$P/.claude-plugin/plugin.json" 2>/dev/null || true)" "esenciales" "plugin.json es JSON valido con name esenciales"
ck "$(find "$P/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')" "6" "exactamente 6 skills"
for d in "$P"/skills/*/; do
  n="$(basename "$d")"
  fm="$(awk 'NR==1&&$0!="---"{exit} NR>1&&$0=="---"{exit} NR>1{print}' "$d/SKILL.md" 2>/dev/null)"
  ck "$(printf '%s\n' "$fm" | sed -n 's/^name: *//p' | tr -d "\"'")" "$n" "$n: SKILL.md con name == carpeta"
  ck "$(printf '%s\n' "$fm" | grep -qE '^description: *[^ >|]' && echo y || echo n)" "y" "$n: description no vacio"
done
ck "$(restos "$P")" "0" "sin 'superpowers:' ni nombres de las 8 skills excluidas"
ck "$([ -e "$P/hooks" ] && echo si || echo no)" "no" "sin directorio hooks/"
ck "$(grep -q 'Permission is hereby granted' "$P/LICENSE" 2>/dev/null && echo y || echo n)" "y" "LICENSE MIT presente"
ck "$(jq -r '.plugins[] | select(.name=="esenciales") | .source' "$ROOT/.claude-plugin/marketplace.json")" "./kit/plugins/esenciales" "marketplace.json lo lista"

# Falsabilidad: una referencia excluida plantada en una skill tiene que contar.
cp -R "$P" "$tmp/p"
printf 'usa %s\n' "superpowers"":executing-plans" >> "$tmp/p/skills/writing-plans/SKILL.md"
ck "$(restos "$tmp/p")" "2" "falsabilidad: referencia plantada detectada"

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
