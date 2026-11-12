#!/usr/bin/env bash
# test_docs_enlaces.sh — la documentacion de quien recibe el kit (README, ENTREGA, OPERAR, guia) cita solo lo que existe.
# Lo hace scripts/verificar-docs.py (python3, stdlib); aqui se ejecuta sobre el arbol y se prueba que sabe fallar:
#   enlace roto, ancla inexistente, ruta inventada, `bash` a un script que no existe, version minima distinta,
#   cockpit distinto de plugin.json, README demasiado largo, CC_NUCLEO_GATE fuera de su historia, enlaces mal contados.
# Los acentos graves de Markdown van entre comillas simples a proposito.
# shellcheck disable=SC2016
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$HERE/../.."
V="$ROOT/scripts/verificar-docs.py"
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

out="$(python3 -I "$V" --root "$ROOT" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || echo "$out" | head -20
ck "$rc" "0" "la documentacion cita solo lo que existe"

# Copia minima del arbol que lee el verificador, para romperla sin tocar el repo.
R="$tmp/r"; mkdir -p "$R"
cp "$ROOT"/*.md "$ROOT/uninstall.sh" "$R/"
cp -r "$ROOT/kit" "$ROOT/scripts" "$ROOT/knowledge" "$ROOT/config" "$R/"
chk() { python3 -I "$V" --root "$R" 2>&1; }
base="$(chk)"; ck "$(grep -vc '^ok' <<<"$base")" "0" "la copia de partida pasa limpia"

cp "$R/README.md" "$tmp/README.bak"
printf '\nVer [roto](kit/docs/no-existe.md) y [ancla](kit/docs/OPERAR.md#no-existe).\n' >> "$R/README.md"
out="$(chk)"
ck "$(grep -c 'enlace roto -> kit/docs/no-existe.md' <<<"$out")" "1" "falla con un enlace roto"
ck "$(grep -c 'ancla que no existe' <<<"$out")" "1" "falla con una ancla que no existe"
cp "$tmp/README.bak" "$R/README.md"

printf '\nMira `kit/inventada/ruta.md` y ejecuta `bash kit/no-hay.sh`.\n' >> "$R/README.md"
out="$(chk)"
ck "$(grep -c 'la ruta `kit/inventada/ruta.md` no existe' <<<"$out")" "1" "falla con una ruta inventada"
ck "$(grep -c 'cita `bash kit/no-hay.sh`' <<<"$out")" "1" "falla con un bash a un script que no existe"
cp "$tmp/README.bak" "$R/README.md"

printf '\nNecesita Claude Code 2.1.292.\n' >> "$R/README.md"
ck "$(chk | grep -c 'cita Claude Code 2.1.292')" "1" "falla con otra version de Claude Code"
cp "$tmp/README.bak" "$R/README.md"

jq '.version = "9.9.9"' "$R/kit/mods/cockpit/.claude-plugin/plugin.json" > "$tmp/pj" && cp "$tmp/pj" "$R/kit/mods/cockpit/.claude-plugin/plugin.json"
ck "$(chk | grep -c 'README.md dice cockpit .* y plugin.json 9.9.9')" "1" "falla si el cockpit del README no es el de plugin.json"
cp "$ROOT/kit/mods/cockpit/.claude-plugin/plugin.json" "$R/kit/mods/cockpit/.claude-plugin/"

for i in $(seq 1 130); do echo "linea $i" >> "$R/README.md"; done
ck "$(chk | grep -c 'README.md: .* lineas, el tope es 120')" "1" "falla con un README de mas de 120 lineas"
cp "$tmp/README.bak" "$R/README.md"

echo 'CC_NUCLEO_GATE=1' > "$R/kit/docs/otra.md"
ck "$(chk | grep -c 'kit/docs/otra.md: cita CC_NUCLEO_GATE')" "1" "falla con CC_NUCLEO_GATE fuera de su historia"
rm "$R/kit/docs/otra.md"

sed 's/crea cinco enlaces/crea tres enlaces/' "$R/kit/docs/02-install.md" > "$tmp/i" && cp "$tmp/i" "$R/kit/docs/02-install.md"
ck "$(chk | grep -c 'no dice «crea cinco enlaces»')" "1" "falla si 02-install cuenta mal los enlaces de install.sh"

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ] || exit 1
