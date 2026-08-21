#!/usr/bin/env bash
# cost-report.sh — corre scripts/metrics.py y muestra los KPIs del harness
# en una tabla, con tendencia (flecha + delta) frente al snapshot anterior
# si existe. `--json` vuelca el JSON crudo de metrics.py sin tabla.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

if ! command -v jq >/dev/null 2>&1; then
  echo "cost-report.sh requiere jq" >&2
  exit 1
fi

json_mode=0
[ "${1:-}" = "--json" ] && json_mode=1

OUT_DIR="${METRICS_OUT_DIR:-$HOME/ai-mastery/bucle/data}"

current="$(python3 "$HERE/metrics.py")"

if [ "$json_mode" -eq 1 ]; then
  printf '%s\n' "$current"
  exit 0
fi

stamp="$(date +%Y-%m-%d)"
today_file="$OUT_DIR/metrics-$stamp.json"
prev_file=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ "$f" = "$today_file" ] && continue
  prev_file="$f"
done < <(find "$OUT_DIR" -maxdepth 1 -name 'metrics-*.json' 2>/dev/null | sort)

# key|etiqueta|direccion deseada (up = mas es mejor, down = menos es mejor, flat = informativo)
kpis="rework_rate_pct|% turnos de retrabajo|down
rework_sessions_pct|% sesiones con retrabajo|down
sessions_with_oracle_pct|% sesiones que corrieron el oraculo|up
tool_error_rate_pct|% llamadas con error|down
sessions_one_shot_pct|% sesiones de un solo turno|down
cache_hit_pct|% cache hit|up
tool_calls_per_session_median|herramientas por sesion (mediana)|flat
compactions|compactaciones|down
sessions|sesiones acumuladas|flat
user_turns|turnos humanos acumulados|flat"

echo "== cost-report: KPIs del harness (fuente: $HERE/metrics.py) =="
if [ -n "$prev_file" ]; then
  echo "   tendencia vs $(basename "$prev_file")"
else
  echo "   sin snapshot anterior: no hay tendencia que mostrar"
fi
echo
printf '%-42s %10s  %-9s  %s\n' "KPI" "valor" "deseado" "tendencia"

while IFS='|' read -r key label dir; do
  [ -z "$key" ] && continue
  cur="$(printf '%s' "$current" | jq -r --arg k "$key" '.[$k]')"
  trend="—"
  if [ -n "$prev_file" ]; then
    old="$(jq -r --arg k "$key" '.[$k]' "$prev_file")"
    if [ "$old" != "null" ] && [ "$cur" != "null" ]; then
      trend="$(awk -v c="$cur" -v o="$old" -v d="$dir" 'BEGIN {
        delta = c - o
        if (delta == 0) { printf "="; exit }
        arrow = (delta > 0) ? "↑" : "↓"
        if (d == "up")        mark = (delta > 0) ? "OK" : "REVISAR"
        else if (d == "down") mark = (delta < 0) ? "OK" : "REVISAR"
        else                  mark = ""
        sign = (delta > 0) ? "+" : ""
        printf "%s%s%.1f %s", arrow, sign, delta, mark
      }')"
    fi
  fi
  printf '%-42s %10s  %-9s  %s\n' "$label" "$cur" "$dir" "$trend"
done <<EOF
$kpis
EOF
