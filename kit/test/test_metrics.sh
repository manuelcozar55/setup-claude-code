#!/usr/bin/env bash
# test_metrics.sh — scripts/metrics.py sobre un directorio de transcripts
# SINTETICO (nunca sobre ~/.claude/projects real). Fabrica 2 sesiones
# principales + 1 transcript de subagente (que debe quedar excluido), con
# un turno de retrabajo y una llamada a Bash con `make test`, y comprueba
# valores EXACTOS conocidos. Termina cambiando el fixture para comprobar
# que las metricas cambian como se espera (falsabilidad): si no cambiaran,
# el test estaria comprobando una constante, no el comportamiento del script.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
REPO="$(cd "$KIT/.." && pwd)"
METRICS="$REPO/scripts/metrics.py"
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

if ! command -v jq >/dev/null 2>&1; then
  echo "NOT ok - jq requerido para este test"
  exit 1
fi

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
PROJECTS="$tmp/projects"; OUTDIR="$tmp/out"
mkdir -p "$PROJECTS/testproj" "$OUTDIR"

write_session() { # ruta, texto_user, comando_bash_del_tool_use
  local path="$1" text="$2" cmd="$3"
  mkdir -p "$(dirname "$path")"
  {
    printf '{"type":"user","timestamp":"2026-01-01T10:00:00Z","message":{"role":"user","content":%s}}\n' "$(jq -Rn --arg s "$text" '$s')"
    printf '{"type":"assistant","timestamp":"2026-01-01T10:01:00Z","message":{"model":"claude-sonnet-4-5","usage":{"input_tokens":100,"output_tokens":50},"content":[{"type":"tool_use","name":"Bash","input":{"command":%s}}]}}\n' "$(jq -Rn --arg s "$cmd" '$s')"
  } > "$path"
}

run_metrics() {
  CLAUDE_PROJECTS_DIR="$PROJECTS" METRICS_OUT_DIR="$OUTDIR" /usr/bin/python3 "$METRICS"
}

# --- fixture inicial --------------------------------------------------------
# sesion A: turno de retrabajo ("no, ... corrige eso") + oraculo (make test)
write_session "$PROJECTS/testproj/session-aaa.jsonl" \
  "no, esta mal, corrige eso por favor" "make test"
# sesion B: turno normal, sin retrabajo, sin oraculo
write_session "$PROJECTS/testproj/session-bbb.jsonl" \
  "implementa la funcion de calculo de totales" "ls -la"
# subagente de la sesion A: retrabajo Y oraculo propios, para comprobar que
# NO se cuelan en las metricas de sesiones principales
write_session "$PROJECTS/testproj/session-aaa/subagents/sub1.jsonl" \
  "no, mal, arregla eso" "pytest"

out="$(run_metrics)"

ck "$(echo "$out" | jq -r '.sessions')" "2" "cuenta 2 sesiones principales, ignora el transcript de subagente"
ck "$(echo "$out" | jq -r '.rework_sessions')" "1" "1 de 2 sesiones tiene retrabajo (el del subagente no cuenta)"
ck "$(echo "$out" | jq -r '.rework_sessions_pct')" "50.0" "rework_sessions_pct = 50.0% (1/2, no 2/3)"
ck "$(echo "$out" | jq -r '.sessions_with_correction_pct')" "50.0" "sessions_with_correction_pct es alias de rework_sessions_pct"
ck "$(echo "$out" | jq -r '.sessions_with_oracle')" "1" "1 sesion corrio el oraculo (el del subagente no cuenta)"
ck "$(echo "$out" | jq -r '.sessions_with_oracle_pct')" "50.0" "sessions_with_oracle_pct = 50.0%"
ck "$(echo "$out" | jq -r '.subagents.transcripts')" "1" "el transcript de subagente se contabiliza aparte, en subagents.transcripts"

for f in "$OUTDIR"/metrics-*.json "$OUTDIR/latest.json"; do
  ck "$([ -f "$f" ] && echo y || echo n)" "y" "metrics.py escribe snapshot: $(basename "$f")"
done

# --- falsabilidad: si cambio el fixture, las metricas DEBEN cambiar --------
# (a) quito el retrabajo de la sesion A -> rework_sessions_pct debe caer a 0
write_session "$PROJECTS/testproj/session-aaa.jsonl" \
  "implementa la funcion de calculo de totales, gracias" "make test"
out2="$(run_metrics)"
ck "$(echo "$out2" | jq -r '.rework_sessions')" "0" "falsabilidad: sin frases de retrabajo, rework_sessions cae a 0"
ck "$(echo "$out2" | jq -r '.rework_sessions_pct')" "0.0" "falsabilidad: rework_sessions_pct cae a 0.0"

# (b) anado el oraculo tambien a la sesion B -> sessions_with_oracle sube a 2
write_session "$PROJECTS/testproj/session-bbb.jsonl" \
  "implementa la funcion de calculo de totales" "shellcheck script.sh"
out3="$(run_metrics)"
ck "$(echo "$out3" | jq -r '.sessions_with_oracle')" "2" "falsabilidad: 2 sesiones corren el oraculo cuando las 2 lo hacen"
ck "$(echo "$out3" | jq -r '.sessions_with_oracle_pct')" "100.0" "falsabilidad: sessions_with_oracle_pct sube a 100.0"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
