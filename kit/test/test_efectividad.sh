#!/usr/bin/env bash
# test_efectividad.sh — contrato de kit/claude/bin/efectividad sobre un CLAUDE_HOME sintético
# (fixtures/efectividad/home): valores exactos, ventanas, formatos, --registrar y falsabilidad por mutación.
# Uso: test_efectividad.sh [ruta al CLI]. Sin red; todo lo que se muta o escribe va en copias bajo un mktemp.
set -u
C=$(realpath "${1:-$(dirname "$0")/../claude/bin/efectividad}"); FX=$(realpath "$(dirname "$0")/fixtures/efectividad/home")
T=$(mktemp -d); trap 'rm -rf -- "$T"' EXIT
export HOME=$T/home; mkdir -p "$HOME"; unset CLAUDE_HOME CC_GUARD_LOG
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


# Atribución: con «[ruta/hooks/x]:» manda la ruta; sin ruta ni prefijo propio es block-dangerous-commands.sh (el único
# guard del kit que deniega por JSON, y a esos Claude Code no les antepone la ruta); una ruta fuera de hooks/ es «otro».
JG=$(cli --home "$(dirname "$FX")/home-guards" "${V[@]}" --json)
ok "guards: sin ruta → block-dangerous-commands.sh 2" "$(j "$JG" "$W.bloqueos_por_guard[\"block-dangerous-commands.sh\"]")" 2
ok "guards: con ruta manda la ruta → secret-guard.sh 1" "$(j "$JG" "$W.bloqueos_por_guard[\"secret-guard.sh\"]")" 1
ok "guards: ruta ajena a hooks/ → otro 1" "$(j "$JG" "$W.bloqueos_por_guard.otro")" 1
ok "guards: 4 bloqueos, 0 reformulados" "$(j "$JG" "$W.bloqueos")/$(j "$JG" "$W.reformulados")" "4/0"

# Registro único de guards (audit-logs/guard-decisions.jsonl): sin registro la tabla lo dice; con él salen deny/ask por guard y por regla,
# y «reformulado <60 s» exige MISMO cwd (transcript) que la decisión. Los cwd se inyectan en una copia: el fixture compartido no los lleva.
ok "sin registro: json guards_log null" "$(j "$J" "$W.guards_log")" null
ok "sin registro: la tabla lo dice" "$(cli --home "$FX" "${V[@]}" | grep -c 'sin registro')" 1
copia; sed -i 's|"timestamp": "2026-11-02T09:59:59Z"|"cwd": "/w", &|; s|"timestamp": "2026-11-02T10:00:30Z"|"cwd": "/w", &|; s|"timestamp": "2026-11-02T10:06:30Z"|"cwd": "/w", &|' "$T/h/projects/-p1/s1.jsonl"
mkdir -p "$T/h/audit-logs"; GL=$T/h/audit-logs/guard-decisions.jsonl
{ echo '{"ts":"2026-11-02T10:00:00Z","guard":"destructive-guard.sh","decision":"deny","rule":"rm on sensitive path","cwd":"/w","mode":"","unattended":false,"tool":"Bash","cmd":"rm -rf /tmp/x/foo"}'
  echo '{"ts":"2026-11-02T10:05:00Z","guard":"sentinel","decision":"ask","rule":"x","cwd":"/w","mode":"","unattended":true,"tool":"Bash","cmd":"rm -rf /tmp/x/bar"}'
  echo '{"ts":"2026-11-02T10:08:00Z","guard":"sentinel","decision":"ask","rule":"x","cwd":"/otro","mode":"","unattended":false,"tool":"Bash","cmd":"rm -rf /tmp/x/foo"}'
  echo 'basura que no es JSON'
  echo '{"ts":"2026-10-01T10:00:00Z","guard":"secret-guard.sh","decision":"deny","rule":"fuera de ventana","cwd":"/w","cmd":"c"}'; } > "$GL"
JL=$(cli --home "$T/h" "${V[@]}" --json); G='.ventanas[0].guards_log'
ok "log: 3 decisiones en la ventana (la de octubre y la basura no cuentan)" "$(j "$JL" "$G.decisiones")" 3
ok "log: deny 1, ask 2, desatendidas 1" "$(j "$JL" "$G | [.deny, .ask, .desatendidas] | join(\",\")")" "1,2,1"
ok "log: destructive-guard reformulado (mismo cwd, 30 s)" "$(j "$JL" "$G.por_guard[\"destructive-guard.sh\"].reformulados")" 1
ok "log: sentinel sin reformulado (90 s en /w; el otro cwd no cuenta)" "$(j "$JL" "$G.por_guard.sentinel.reformulados")" 0
ok "log: fp_pct" "$(j "$JL" "$G.fp_pct")" 33.3
ok "log: por regla" "$(j "$JL" "$G.por_regla[\"sentinel: x\"]")" 2
ok "log: la tabla y el detalle por guard" "$(cli --home "$T/h" "${V[@]}" | grep -cE 'decisiones de guards .*3 \(deny 1, ask 2\)|^  sentinel .*ask 2')" 2
CC_GUARD_LOG=$T/h/otro.jsonl; export CC_GUARD_LOG
ok "CC_GUARD_LOG que no existe: sin registro" "$(j "$(cli --home "$T/h" "${V[@]}" --json)" "$G")" null
unset CC_GUARD_LOG

exit $FAIL
