#!/usr/bin/env bash
# test_efectividad.sh — contrato de kit/claude/bin/efectividad sobre un CLAUDE_HOME sintético
# (fixtures/efectividad/home): valores exactos, ventanas, formatos, --registrar y falsabilidad por mutación.
# Uso: test_efectividad.sh [ruta al CLI]. Sin red; todo lo que se muta o escribe va en copias bajo un mktemp.
set -u
C=$(realpath "${1:-$(dirname "$0")/../claude/bin/efectividad}"); FX=$(realpath "$(dirname "$0")/fixtures/efectividad/home")
T=$(mktemp -d); trap 'rm -rf -- "$T"' EXIT
export HOME=$T/home; mkdir -p "$HOME"; unset CLAUDE_HOME
FAIL=0
ok() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (esperado '$3', sale '$2')"; FAIL=1; fi; }
V=(--desde 2026-11-01 --hasta 2026-11-10)
cli() { python3 "$C" "$@"; }
copia() { rm -rf -- "$T/h"; cp -r "$FX" "$T/h"; }
# j JSON FILTRO: valor jq en crudo.
j() { jq -r "$2" <<<"$1"; }

J=$(cli --home "$FX" "${V[@]}" --json); RC=$?
ok "json sale 0" "$RC" 0
W='.ventanas[0]'
ok "sesiones" "$(j "$J" "$W.sesiones")" 2
ok "dias_activos" "$(j "$J" "$W.dias_activos")" 2
ok "compactaciones (el subagente no cuenta)" "$(j "$J" "$W.compactaciones")" 3
ok "compactaciones_por_dia" "$(j "$J" "$W.compactaciones_por_dia")" 1.5
ok "mensajes" "$(j "$J" "$W.mensajes")" 6
ok "correcciones" "$(j "$J" "$W.correcciones")" 1
ok "correcciones_pct" "$(j "$J" "$W.correcciones_pct")" 16.7
ok "bloqueos" "$(j "$J" "$W.bloqueos")" 2
ok "bloqueos_por_guard" "$(jq -c "$W.bloqueos_por_guard" <<<"$J")" '{"destructive-guard.sh":1,"sentinel":1}'
ok "reformulados" "$(j "$J" "$W.reformulados")" 1
ok "fp_pct" "$(j "$J" "$W.fp_pct")" 50.0
ok "frescura_n (la fila de septiembre queda fuera)" "$(j "$J" "$W.frescura_n")" 4
ok "frescura_pct" "$(j "$J" "$W.frescura_pct")" 50.0
ok "hook_errores (el clasificador no cuenta)" "$(j "$J" "$W.hook_errores")" 1
ok "sin --por-sesion no hay sesiones; antes es null" "$(j "$J" '[(.sesiones // "nada"), .antes] | map(tostring) | join(",")')" "nada,null"

J=$(cli --home "$FX" "${V[@]}" --antes 2026-11-04 --json)
ok "--antes: dos ventanas" "$(j "$J" '.ventanas | length')" 2
ok "--antes: ventana antes" "$(j "$J" '.ventanas[0] | [.sesiones, .bloqueos, .reformulados] | join(",")')" "1,2,1"
ok "--antes: ventana después" "$(j "$J" '.ventanas[1] | [.sesiones, .bloqueos, .fp_pct] | map(tostring) | join(",")')" "1,0,null"

ERR=$(cli --home "$FX" --desde 2026-12-01 2>&1 >/dev/null); RC=$?
ok "ventana sin sesiones: rc 2" "$RC" 2
ok "ventana sin sesiones: mensaje en stderr" "$ERR" "efectividad: sin sesiones en la ventana 2026-12-01 → $(date -d tomorrow +%F)"
cli --home "$FX" --desde 2026-11-01x >/dev/null 2>&1
ok "fecha mal formada: rc 1" "$?" 1
cli --home "$FX" "${V[@]}" --antes 2026-11-10 >/dev/null 2>&1
ok "--antes fuera de [desde, hasta): rc 1" "$?" 1

M=$(cli --home "$FX" "${V[@]}" --markdown)
ok "markdown: cabecera" "$(grep -cxF '### Cifras (uso real, 2026-11-01 → 2026-11-10, 2 sesiones)' <<<"$M")" 1
ok "markdown: falsos positivos" "$(grep -cF '50.0 % (1/2 bloqueos)' <<<"$M")" 1
ok "markdown: cuatro filas de cifras" "$(grep -c '^| [A-Z]' <<<"$M")" 5

S=$(cli --home "$FX" "${V[@]}" --por-sesion | awk -F'\t' 'NF==7 {print $1}' | sort | tr '\n' ' ')
ok "--por-sesion: una línea TSV por sesión" "$S" "s1 s2 "

copia; R=$T/h/session-logs/efectividad.tsv
cli --home "$T/h" "${V[@]}" --registrar >/dev/null
ok "--registrar: cabecera + 1 fila" "$(wc -l <"$R" | tr -d ' ')" 2
ok "--registrar: cabecera" "$(head -n1 "$R")" "$(printf 'ts_run\tdesde\thasta\tsesiones\tcompactaciones_por_dia\tfrescura_pct\tcorrecciones_pct\tfp_pct\tbloqueos')"
cli --home "$T/h" "${V[@]}" --registrar >/dev/null
ok "--registrar: segunda ejecución añade una fila" "$(wc -l <"$R" | tr -d ' ')" 3

copia; sed -i '/"isCompactSummary": *true/d' "$T/h/projects/-p1/s1.jsonl"
ok "mutación: sin la línea isCompactSummary de s1, compactaciones 2" "$(j "$(cli --home "$T/h" "${V[@]}" --json)" "$W.compactaciones")" 2
copia; sed -i 's/2026-11-02T10:00:30Z/2026-11-02T10:01:01Z/' "$T/h/projects/-p1/s1.jsonl"
J=$(cli --home "$T/h" "${V[@]}" --json)
ok "mutación: B a 61 s del bloqueo, reformulados 0" "$(j "$J" "$W.reformulados")" 0
ok "mutación: B a 61 s del bloqueo, fp_pct 0.0" "$(j "$J" "$W.fp_pct")" 0.0
copia; rm -f -- "$T/h/session-logs/nucleo-freshness.log"
ok "mutación: sin log de frescura, frescura_pct null" "$(j "$(cli --home "$T/h" "${V[@]}" --json)" "$W.frescura_pct")" null
ok "mutación: sin log de frescura, la tabla muestra s/d" "$(cli --home "$T/h" "${V[@]}" | grep -c 's/d')" 1

ok "CLAUDE_HOME del entorno = --home" "$(CLAUDE_HOME=$FX cli "${V[@]}" --json | jq -S -c .)" "$(cli --home "$FX" "${V[@]}" --json | jq -S -c .)"

exit $FAIL
