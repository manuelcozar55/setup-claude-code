#!/usr/bin/env bash
# test_harness_structure.sh — presupuesto de complejidad y estructura del
# harness mcharness (v0.1.0). El presupuesto aplica SOLO a lo que este release
# anade (.claude/, config/, knowledge/): la linea base heredada del kit
# (kit/claude/agents/, kit/claude/settings.json) queda explicitamente FUERA
# del computo y se documenta en la salida, no se recomputa contra ella.
#
# Todo directorio/fichero nuevo (.claude/, config/settings.template.json,
# knowledge/SOURCES.md) puede no existir aun en este punto del desarrollo:
# cada check degrada con un "ok - ... (aun no creado)" en vez de fallar.
#
# Requiere jq (ya es dependencia dura del kit, ver kit/doctor.sh).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
REPO="$(cd "$KIT/.." && pwd)"
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq requerido"; echo "PASS=0 FAIL=1"; exit 1; }

cd "$REPO"

# --- Helpers reutilizados tanto en los checks reales como en la sección de
# falsabilidad (misma logica, no una copia "de mentira" para el fixture). ---

validate_agent_frontmatter() {
  local f="$1"
  [ "$(sed -n '1p' "$f")" = "---" ] || return 1
  local closing
  closing="$(awk 'NR>1 && /^---$/{print NR; exit}' "$f")"
  [ -n "$closing" ] || return 1
  local fm
  fm="$(sed -n "2,$((closing - 1))p" "$f")"
  echo "$fm" | grep -qE '^name:[[:space:]]*[^[:space:]]' || return 1
  echo "$fm" | grep -qE '^description:[[:space:]]*[^[:space:]]' || return 1
  return 0
}

find_broken_links() {
  local dirs=("$@") f dir link target
  local files=()
  for d in "${dirs[@]}"; do
    [ -d "$d" ] || continue
    while IFS= read -r -d '' f; do files+=("$f"); done < <(find "$d" -type f -name '*.md' -print0)
  done
  for f in "${files[@]}"; do
    dir="$(dirname "$f")"
    while IFS= read -r link; do
      case "$link" in
        http://*|https://*|mailto:*|"#"*) continue ;;
      esac
      link="${link%%#*}"
      [ -z "$link" ] && continue
      target="$dir/$link"
      [ -e "$target" ] || echo "$f -> $link"
    done < <(grep -oE '\[[^]]+\]\([^)]+\)' "$f" 2>/dev/null | sed -E 's/^\[[^]]+\]\(([^)]+)\)$/\1/')
  done
}

extract_oracle_rows() {
  awk '/^## Registro/{flag=1; next} flag && /^###/{flag=0} flag' "$1" \
    | grep '^|' | grep -v '^| *---' | grep -vi 'Proyecto'
}

validate_oracle_row() {
  local line="$1"
  local IFS='|'
  local cols
  read -ra cols <<< "$line"
  local comando="${cols[2]:-}" fecha="${cols[4]:-}"
  comando="$(printf '%s' "$comando" | sed -E 's/^ *//; s/ *$//; s/`//g')"
  fecha="$(printf '%s' "$fecha" | sed -E 's/^ *//; s/ *$//')"
  [ -n "$comando" ] || return 1
  [[ "$fecha" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
  case "$comando" in
    /*) ;;
    "rtk proxy "*) ;;
    make|"make "*) ;;
    *) return 1 ;;
  esac
  return 0
}

extract_sources_rows() {
  awk '/^\|/{print}' "$1" | grep -v '^| *---' | grep -vi 'URL'
}

# Extrae campos POR PATRON, no por indice de columna: la tabla puede llevar columnas
# extra (orden, autor, estado) sin romper el validador. Acoplar el parser a posiciones
# convierte cualquier mejora de la tabla en un fallo de test.
source_field() {   # source_field <fila> <url|tipo|fecha|ventana>
  local line="$1"
  case "$2" in
    url)     printf '%s' "$line" | grep -oE 'https?://[^ |]+' | head -1 ;;
    tipo)    printf '%s' "$line" | grep -oiE '\b(primaria|secundaria)\b' | head -1 | tr '[:upper:]' '[:lower:]' ;;
    fecha)   printf '%s' "$line" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 ;;
    ventana) printf '%s' "$line" | grep -oE '\| *[0-9]+ *(d|dias|días)? *\|' | grep -oE '[0-9]+' | head -1 ;;
  esac
}

validate_source_row() {
  local line="$1" url tipo fecha ventana
  url="$(source_field "$line" url)"
  tipo="$(source_field "$line" tipo)"
  fecha="$(source_field "$line" fecha)"
  ventana="$(source_field "$line" ventana)"
  # Una fuente sin URL navegable (p.ej. una cita de red social) se admite si la fila
  # identifica la fuente de otra forma; lo que NO se admite es que falte procedencia.
  [ -n "$url" ] || printf '%s' "$line" | grep -qE '\|[^|]{6,}\|' || return 1
  case "$tipo" in primaria|secundaria) ;; *) return 1 ;; esac
  [[ "$fecha" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
  [[ "$ventana" =~ ^[0-9]+$ ]] || return 1
  return 0
}

is_stale() {
  local fecha="$1" ventana="$2" fecha_epoch now_epoch
  fecha_epoch="$(date -d "$fecha" +%s)"
  now_epoch="$(date +%s)"
  [ "$now_epoch" -gt "$((fecha_epoch + ventana * 86400))" ]
}

n_hooks_of() { jq -r '[.hooks[][]?.hooks[]?] | length' "$1" 2>/dev/null || echo 0; }

echo "== 1) test_complexity_budget =="
n_base_agents=$(find kit/claude/agents -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
n_base_hooks=$(n_hooks_of kit/claude/settings.json)
echo "  nota: linea base heredada FUERA de este presupuesto -- kit/claude/agents/ = $n_base_agents agentes, kit/claude/settings.json = $n_base_hooks hooks (todos con timeout=10s)."

if [ -d .claude/agents ]; then
  n="$(find .claude/agents -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')"
  ck "$([ "$n" -le 6 ] && echo y || echo n)" "y" ".claude/agents/*.md <= 6 (medido: $n)"
else
  ck "y" "y" ".claude/agents/ aun no creado (presupuesto pasa por vacio)"
fi

if [ -d .claude/skills ]; then
  n="$(find .claude/skills -maxdepth 2 -name 'SKILL.md' | wc -l | tr -d ' ')"
  ck "$([ "$n" -le 6 ] && echo y || echo n)" "y" ".claude/skills/*/SKILL.md <= 6 (medido: $n)"
else
  ck "y" "y" ".claude/skills/ aun no creado (presupuesto pasa por vacio)"
fi

if [ -f config/settings.template.json ]; then
  n="$(n_hooks_of config/settings.template.json)"
  ck "$([ "$n" -le 3 ] && echo y || echo n)" "y" "hooks declarados en config/settings.template.json <= 3 (medido: $n)"
else
  ck "y" "y" "config/settings.template.json aun no creado (presupuesto pasa por vacio)"
fi

echo "== 2) test_claude_md_budget =="
if [ -f CLAUDE.md ]; then
  n_lines="$(wc -l < CLAUDE.md | tr -d ' ')"
  ck "$([ "$n_lines" -lt 100 ] && echo y || echo n)" "y" "CLAUDE.md < 100 lineas (medido: $n_lines)"
  n_chars="$(wc -c < CLAUDE.md | tr -d ' ')"
  approx_tokens=$((n_chars / 4))
  ck "$([ "$approx_tokens" -lt 900 ] && echo y || echo n)" "y" "CLAUDE.md aprox tokens (chars/4) < 900 (medido: $approx_tokens)"
else
  ck "y" "y" "CLAUDE.md no existe en la raiz del repo (presupuesto pasa por vacio)"
fi

echo "== 3) test_agents_valid =="
if [ -d .claude/agents ]; then
  bad=0
  for f in .claude/agents/*.md; do
    [ -f "$f" ] || continue
    if ! validate_agent_frontmatter "$f"; then
      bad=$((bad + 1)); echo "  frontmatter invalido: $f"
    fi
  done
  ck "$([ "$bad" -eq 0 ] && echo y || echo n)" "y" "todo .claude/agents/*.md tiene frontmatter YAML valido con name/description no vacios (invalidos: $bad)"
else
  ck "y" "y" ".claude/agents/ aun no creado (check de frontmatter pasa por vacio)"
fi

mapfile -t broken_links < <(find_broken_links .claude knowledge)
for b in "${broken_links[@]:-}"; do [ -n "$b" ] && echo "  enlace roto: $b"; done
ck "$([ "${#broken_links[@]}" -eq 0 ] && echo y || echo n)" "y" "ningun enlace markdown [x](ruta relativa) roto en .claude/** ni knowledge/** (rotos: ${#broken_links[@]})"

echo "== 4) test_oracle_registry =="
# Regla M-001 (knowledge/MISTAKES.md): el hook PreToolUse/Bash sustituye el
# ejecutable en posicion de comando, asi que un oraculo invocado por nombre
# suelto no ejecuta lo que dice. Por eso todo comando de este registro debe
# empezar por / (ruta absoluta), por "rtk proxy" o por "make".
if [ -f knowledge/ORACLES.md ]; then
  mapfile -t rows < <(extract_oracle_rows knowledge/ORACLES.md)
  ck "$([ "${#rows[@]}" -ge 1 ] && echo y || echo n)" "y" "hay filas en la tabla de registro de knowledge/ORACLES.md (${#rows[@]})"
  bad=0
  for r in "${rows[@]}"; do
    if ! validate_oracle_row "$r"; then bad=$((bad + 1)); echo "  fila invalida: $r"; fi
  done
  ck "$([ "$bad" -eq 0 ] && echo y || echo n)" "y" "toda fila del registro tiene comando (/ | rtk proxy | make) y fecha YYYY-MM-DD (invalidas: $bad)"
else
  ck "y" "y" "knowledge/ORACLES.md no existe (check pasa por vacio)"
fi

echo "== 5) test_sources_freshness =="
if [ -f knowledge/SOURCES.md ]; then
  mapfile -t srows < <(extract_sources_rows knowledge/SOURCES.md)
  bad=0; stale_unmarked=0
  for r in "${srows[@]}"; do
    if ! validate_source_row "$r"; then
      bad=$((bad + 1)); echo "  fila invalida en SOURCES.md: $r"
      continue
    fi
    fecha="$(source_field "$r" fecha)"
    ventana="$(source_field "$r" ventana)"
    if is_stale "$fecha" "$ventana"; then
      if echo "$r" | grep -q '\[STALE\]'; then
        echo "  aviso: entrada vencida y marcada [STALE] correctamente: $r"
      else
        stale_unmarked=$((stale_unmarked + 1)); echo "  entrada vencida SIN marcar [STALE]: $r"
      fi
    fi
  done
  ck "$([ "$bad" -eq 0 ] && echo y || echo n)" "y" "toda entrada de SOURCES.md tiene URL, tipo (primaria/secundaria), fecha YYYY-MM-DD y ventana en dias (invalidas: $bad)"
  ck "$([ "$stale_unmarked" -eq 0 ] && echo y || echo n)" "y" "ninguna entrada vencida queda sin marcar [STALE] (sin marcar: $stale_unmarked)"
else
  ck "y" "y" "knowledge/SOURCES.md no existe (check pasa por vacio)"
fi

echo "== 6) test_no_secrets =="
set +e
scan_out="$(bash "$KIT/scan-secrets.sh" "$REPO" 2>&1)"; scan_rc=$?
set -e
ck "$scan_rc" "0" "kit/scan-secrets.sh $REPO sin hallazgos"
[ "$scan_rc" -ne 0 ] && echo "$scan_out"

if command -v gitleaks >/dev/null 2>&1; then
  set +e
  gl_out="$(gitleaks dir --no-banner -c "$KIT/claude/.gitleaks.toml" "$REPO" 2>&1)"; gl_rc=$?
  set -e
  ck "$gl_rc" "0" "gitleaks dir -c kit/claude/.gitleaks.toml sobre el repo completo sin hallazgos"
  [ "$gl_rc" -ne 0 ] && echo "$gl_out"
else
  echo "  gitleaks no instalado: degradando a grep de patrones basico (no falla la suite por ausencia de la herramienta, ver test_install_gitleaks.sh)"
  set +e
  grep -rInE 'sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY' --exclude-dir=.git "$REPO" >/dev/null 2>&1
  grep_rc=$?
  set -e
  ck "$([ "$grep_rc" -eq 1 ] && echo y || echo n)" "y" "grep de patrones basico (fallback sin gitleaks) sin hallazgos"
fi

echo "== 7) test_hook_timeouts =="
echo "  nota: linea base heredada kit/claude/settings.json usa timeout=10s en sus $n_base_hooks hooks y queda FUERA de este presupuesto."
if [ -f config/settings.template.json ]; then
  mapfile -t hook_lines < <(jq -r '[.hooks[][]?.hooks[]?] | .[] | (.command // "SIN_COMANDO") + "|" + (if has("timeout") then (.timeout|tostring) else "SIN_TIMEOUT" end)' config/settings.template.json)
  bad=0
  for h in "${hook_lines[@]}"; do
    cmd="${h%|*}"; to="${h##*|}"
    if [ "$to" = "SIN_TIMEOUT" ]; then
      bad=$((bad + 1)); echo "  NOT ok - hook sin timeout declarado: $cmd"
    elif ! [[ "$to" =~ ^[0-9]+$ ]] || [ "$to" -gt 5 ]; then
      bad=$((bad + 1)); echo "  NOT ok - hook con timeout > 5s: $cmd (timeout=$to)"
    fi
  done
  ck "$([ "${#hook_lines[@]}" -ge 1 ] && echo y || echo n)" "y" "hay hooks declarados en config/settings.template.json (${#hook_lines[@]})"
  ck "$([ "$bad" -eq 0 ] && echo y || echo n)" "y" "todo hook de config/settings.template.json tiene timeout explicito <= 5 (invalidos: $bad)"
else
  ck "y" "y" "config/settings.template.json aun no creado (check de timeouts pasa por vacio)"
fi

echo "== 8) test_ci_workflow_parses =="
# CI no puede cazar su propio error de sintaxis: si el YAML no parsea, el workflow ni
# arranca y GitHub reporta "failure" en 0 s sin logs. Paso exactamente eso con un name:
# sin comillas que contenia ': '. Este check es el unico sensor posible para ese fallo,
# y tiene que vivir FUERA de CI, aqui.
WF=".github/workflows/ci.yml"
if [ -f "$WF" ]; then
  PYYAML=""
  for c in "$HOME/.venvs/tools/bin/python3" /usr/bin/python3 python3; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import yaml' 2>/dev/null; then PYYAML="$c"; break; fi
  done
  if [ -n "$PYYAML" ]; then
    if "$PYYAML" -c "import yaml,sys; yaml.safe_load(open('$WF'))" 2>/dev/null; then
      ck y y "$WF parsea como YAML valido"
    else
      ck n y "$WF parsea como YAML valido"
    fi
  else
    # Degradacion sin pyyaml: se detecta el patron concreto que rompio el workflow.
    malos=$(grep -cE '^\s*- name: [^"'"'"'].*: ' "$WF" || true)
    ck "$malos" "0" "ningun 'name:' sin comillas contiene ': ' (rompe el parser; sin pyyaml se usa grep)"
  fi
else
  ck y y "no hay workflow de CI (check pasa por vacio)"
fi

echo "== Falsabilidad =="
# Cada check falsable de arriba se ejecuta aqui contra un caso fabricado a
# proposito para demostrar que dispara de verdad, no que siempre pasa.
FTMP="$(mktemp -d)"; trap 'rm -rf "$FTMP"' EXIT
falsified=0

printf 'un agente sin frontmatter, a proposito.\n' > "$FTMP/bad-agent.md"
if validate_agent_frontmatter "$FTMP/bad-agent.md"; then
  ck "n" "y" "test_agents_valid SI detecta un agente sin frontmatter fabricado"
else
  ck "y" "y" "test_agents_valid SI detecta un agente sin frontmatter fabricado"
  falsified=$((falsified + 1))
fi

bad_oracle_row='| proyecto-fabricado | make test | resultado ok |  | 1s | alta |'
if validate_oracle_row "$bad_oracle_row"; then
  ck "n" "y" "test_oracle_registry SI detecta una fila sin fecha fabricada"
else
  ck "y" "y" "test_oracle_registry SI detecta una fila sin fecha fabricada"
  falsified=$((falsified + 1))
fi

mkdir -p "$FTMP/config"
cat > "$FTMP/config/settings.template.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo hola","timeout":30}]}]}}
JSON
n_over="$(jq -r '[.hooks[][]?.hooks[]? | select(.timeout > 5)] | length' "$FTMP/config/settings.template.json")"
if [ "$n_over" -gt 0 ]; then
  ck "y" "y" "test_hook_timeouts SI detecta un hook con timeout=30 fabricado"
  falsified=$((falsified + 1))
else
  ck "n" "y" "test_hook_timeouts SI detecta un hook con timeout=30 fabricado"
fi

mkdir -p "$FTMP/knowledge"
printf '[ver esto](./no-existe-de-verdad.md)\n' > "$FTMP/knowledge/con-link-roto.md"
mapfile -t bl < <(find_broken_links "$FTMP/knowledge")
if [ "${#bl[@]}" -gt 0 ]; then
  ck "y" "y" "test_agents_valid (enlaces) SI detecta un enlace markdown roto fabricado"
  falsified=$((falsified + 1))
else
  ck "n" "y" "test_agents_valid (enlaces) SI detecta un enlace markdown roto fabricado"
fi

old_date="$(date -d '-9999 days' +%Y-%m-%d)"
bad_source_row="| http://example.com/fabricado | primaria | $old_date | 30 |"
if validate_source_row "$bad_source_row" && is_stale "$old_date" "30"; then
  ck "y" "y" "test_sources_freshness SI detecta una entrada vencida fabricada"
  falsified=$((falsified + 1))
else
  ck "n" "y" "test_sources_freshness SI detecta una entrada vencida fabricada"
fi

ck "$([ "$falsified" -ge 4 ] && echo y || echo n)" "y" "al menos 4 checks demuestran deteccion real sobre casos fabricados a proposito (detectados: $falsified de 5) -- si fuera 0, la suite seria decorativa"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
