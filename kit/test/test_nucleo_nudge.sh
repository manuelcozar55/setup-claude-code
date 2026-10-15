#!/usr/bin/env bash
# test_nucleo_nudge.sh — contrato de kit/claude/hooks/nucleo-nudge.sh (PostToolUse): pide al modelo
# actualizar nucleo.md por bandas del airbag (50/70/85 %), una vez por banda y sesión, solo con el
# nucleo rancio (> 10 min) o ausente, en ≤ 400 chars y con la ruta exacta; si no toca, nada.
# Uso: test_nucleo_nudge.sh [ruta al hook]. Sin red; HOME falso en un mktemp que se borra.
set -u
H=$(realpath "${1:-$(dirname "$0")/../claude/hooks/nucleo-nudge.sh}"); T=$(mktemp -d); trap 'rm -rf -- "$T"' EXIT
export HOME=$T/home GIT_CEILING_DIRECTORIES=$T; unset CLAUDE_PROJECT_DIR CLAUDE_CODE_AUTO_COMPACT_WINDOW
FAIL=0
ok() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (esperado '$3', sale '$2')"; FAIL=1; fi; }
R=$T/repo; mkdir -p "$R/.claude/estado" "$HOME"; git -C "$R" init -q
NUC=$R/.claude/estado/nucleo.md
# Ventana por defecto 200 000 → airbag de 167 000 tokens.
mk() { jq -cn --argjson n "$2" '{type:"assistant",message:{usage:{input_tokens:1000,cache_read_input_tokens:($n-1000)},content:[]}}' >"$T/$1.jsonl"; }
run() { jq -cn --arg c "$R" --arg s "$1" --arg t "$T/$2.jsonl" '{session_id:$s,transcript_path:$t,cwd:$c,hook_event_name:"PostToolUse",tool_name:"Bash"}' | bash "$H"; }
ctx() { jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }
mk p20 33400; mk p60 100200; mk p72 120240; mk p90 150300

echo x >"$NUC"; touch -d '-30 minutes' "$NUC"
ok "20 % → vacío" "$(run s1 p20)" ""
OUT=$(run s1 p60); C=$(ctx <<<"$OUT")
ok "60 % + nucleo viejo → nudge" "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$OUT")" PostToolUse
ok "nudge: cita la banda, la edad y la ruta exacta" "$(command grep -c "CONTEXTO 60 % del airbag. nucleo.md lleva 30 min .* en $NUC\." <<<"$C")" 1
ok "nudge ≤ 400 chars" "$([ "${#C}" -le 400 ] && echo si)" si
ok "misma banda dos veces → una sola" "$(run s1 p60)" ""
ok "banda siguiente (70 %) sí avisa" "$(run s1 p72 | ctx | command grep -c '72 % del airbag')" 1
ok "85 %: pide cerrar el turno para /handoff" "$(run s1 p90 | ctx | command grep -c '/handoff')" 1
ok "otra sesión tiene sus propias bandas" "$(run s2 p60 | ctx | command grep -c '60 % del airbag')" 1
# Compactar no cambia el session_id: sin rearme, solo avisaba en el primer ciclo de la sesión.
run s5 p60 >/dev/null; run s5 p20 >/dev/null
ok "bajo el 50 % se rearma: 60 % avisa otra vez" "$(run s5 p60 | ctx | command grep -c '60 % del airbag')" 1
touch "$NUC"
ok "60 % + nucleo fresco → vacío" "$(run s3 p60)" ""
rm -f "$NUC"
ok "sin nucleo → pide crearlo con la plantilla" "$(run s4 p60 | ctx | command grep -c "créalo en $NUC con la forma de .*templates/nucleo.md")" 1
ok "session_id con barras → nada (va a un nombre de fichero)" "$(run '../x' p60)" ""
ok "stdin roto → nada y exit 0" "$(echo 'no json' | bash "$H"; echo "rc=$?")" "rc=0"

# Camino caliente: corre tras CADA herramienta. Se mide el camino largo (nucleo rancio, transcript
# leído, banda ya avisada). Mejor de 5: en un runner cargado una sola medida miente.
echo x >"$NUC"; touch -d '-30 minutes' "$NUC"
IN=$(jq -cn --arg c "$R" --arg t "$T/p60.jsonl" '{session_id:"s1",transcript_path:$t,cwd:$c}'); best=99999
for _ in 1 2 3 4 5; do
  t0=$(date +%s%N); bash "$H" <<<"$IN" >/dev/null; ms=$(( ($(date +%s%N) - t0) / 1000000 ))
  [ "$ms" -lt "$best" ] && best=$ms
done
ok "tiempo < 50 ms (mejor de 5: ${best} ms)" "$([ "$best" -lt 50 ] && echo si)" si
exit $FAIL
