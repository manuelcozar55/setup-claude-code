#!/usr/bin/env bash
# test_mapa.sh — kit/docs/MAPA.md es un fichero generado y no puede quedarse atrás del código:
#   1. Regenerarlo con scripts/generar-mapa.sh no cambia nada.
#   2. Todo interruptor (${CC_*}, ${NUCLEO_*}, ${COCKPIT_*}, ${CUPO_*}) que leen los hooks, bin/ y Sentinel sale en MAPA.md.
#   3. Todo hook cableado en settings.json sale en MAPA.md con su descripción.
#   4. Sin cabecera normalizada el generador falla (no inventa texto), y una variable de la tabla de interruptores
#      que el script no lee también lo hace.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."; ROOT="$KIT/.."
GEN="$ROOT/scripts/generar-mapa.sh"; MAPA="$KIT/docs/MAPA.md"
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

bash "$GEN" "$tmp/MAPA.md"; ck "$?" "0" "el generador termina bien sobre el kit"
if diff -u "$MAPA" "$tmp/MAPA.md" >"$tmp/diff"; then ck 0 0 "1: regenerar no cambia kit/docs/MAPA.md"
else head -20 "$tmp/diff"; ck 1 0 "1: kit/docs/MAPA.md esta desactualizado (bash scripts/generar-mapa.sh kit/docs/MAPA.md)"; fi

# 2: otra extraccion, independiente de la del generador
falta=""
for v in $(cat "$KIT"/claude/hooks/*.sh "$KIT"/claude/hooks/*.py "$KIT"/claude/hooks/lib/*.sh "$KIT"/claude/bin/* "$KIT"/sentinel/*.py \
    | grep -oE '\$\{(CC|NUCLEO|COCKPIT|CUPO)_[A-Z0-9_]+' | tr -d '$' | tr -d '{' | sort -u); do
  grep -qF "\`$v\`" "$MAPA" || falta="$falta $v"
done
ck "$falta" "" "2: todo interruptor del codigo sale en MAPA.md"

# 3: cada hook cableado, con su script y su descripcion
sin=""
while read -r s; do
  linea="$(grep -F "| \`$s\` |" "$MAPA" | head -1)"
  [ -n "$linea" ] || { sin="$sin $s(falta)"; continue; }
  d="$(awk -F' [|] ' '{ print $4 }' <<<"$linea")"
  [ "${#d}" -ge 20 ] || sin="$sin $s(sin descripcion)"
done < <(jq -r '.hooks[][].hooks[].command' "$KIT/claude/settings.json" | while read -r c; do grep -oE '\.claude/(hooks|sentinel)/[A-Za-z0-9_.-]+' <<<"$c" | tail -1; done | sed 's|.*/||' | sort -u)
ck "$sin" "" "3: todo hook cableado sale en MAPA.md con descripcion"
n_fil="$(jq -r '.hooks[][].hooks[].command' "$KIT/claude/settings.json" | wc -l)"
n_map="$(awk '/^## Hooks cableados/ { d = 1 } /^## Variables/ { d = 0 } d && /^\| (PreToolUse|PostToolUse|SessionStart|PreCompact|PostCompact|Stop|SubagentStart|SubagentStop|SessionEnd) /' "$MAPA" | wc -l)"
ck "$n_map" "$n_fil" "3: una fila por cada entrada de settings.json"

# 4: el generador se niega a inventar
mkdir -p "$tmp/kit"; cp -r "$KIT/claude" "$KIT/sentinel" "$tmp/kit/"
grep -v '^# QUE-HACE:' "$KIT/claude/hooks/nucleo-nudge.sh" > "$tmp/kit/claude/hooks/nucleo-nudge.sh"
MAPA_KIT="$tmp/kit" bash "$GEN" >/dev/null 2>"$tmp/err"; rc=$?
ck "$([ "$rc" -ne 0 ] && echo si)" "si" "4: sin cabecera normalizada el generador falla"
ck "$(grep -c 'nucleo-nudge.sh no tiene descripción' "$tmp/err")" "1" "4: y dice que script es"
cp "$KIT/claude/hooks/nucleo-nudge.sh" "$tmp/kit/claude/hooks/nucleo-nudge.sh"
printf 'pre-compact.sh\tNUCLEO_INVENTADA\tno existe\n' > "$tmp/tsv"
MAPA_KIT="$tmp/kit" MAPA_TSV="$tmp/tsv" bash "$GEN" >/dev/null 2>"$tmp/err"; rc=$?
ck "$([ "$rc" -ne 0 ] && echo si)" "si" "4: una variable de la tabla que el script no lee hace fallar al generador"
MAPA_KIT="$tmp/kit" bash "$GEN" >/dev/null 2>&1; ck "$?" "0" "4: restituida la cabecera, vuelve a funcionar"

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ] || exit 1
