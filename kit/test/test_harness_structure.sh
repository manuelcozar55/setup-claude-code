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

command -v jq >/dev/null 2>&1 || { echo "skip - jq ausente: esta suite cuenta hooks del settings.template.json con jq"; echo "== 0 passed, 0 failed, 1 skipped =="; exit 0; }

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
    # El sufijo de unidad es OBLIGATORIO a proposito. Cuando era opcional, este
    # patron casaba con la PRIMERA columna numerica de la fila -- que es el '#'
    # de orden -- y el sensor leia "365 d" como "4 dias": las filas 1..4 salian
    # vencidas por su numero de orden y tumbaban `make test` entero (2026-08-25).
    # Una fila sin unidad ya no cuela como ventana: cae en validate_source_row
    # como fila invalida, que es un fallo ruidoso en vez de una lectura silenciosa
    # y equivocada.
    ventana) printf '%s' "$line" | grep -oE '\| *[0-9]+ *(d|dias|días) *\|' | grep -oE '[0-9]+' | head -1 ;;
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
  # En CI la degradacion no vale: el paso que instala gitleaks corre antes en el mismo job, asi
  # que si aqui falta es que alguien lo movio o lo borro -- y un grep de tres patrones no es el
  # escaneo por contenido que este check promete. Fuera de CI si degrada (ver el else de abajo).
  if [ "${CI:-}" = "true" ]; then
    ck "n" "y" "gitleaks disponible en CI (sin el, el escaneo por contenido del repo se degrada en silencio)"
  fi
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
  # El presupuesto de 5 s protege el CAMINO CALIENTE: UserPromptSubmit corre en cada prompt
  # y PostToolUse en cada llamada a herramienta, asi que ahi cada milisegundo se paga cientos
  # de veces. El Stop hook no esta en ese camino -- corre una vez al final del turno -- y en
  # modo autonomo su trabajo ES ejecutar el oraculo. Declararlo a 5 s no lo hacia barato: lo
  # hacia INUTIL, porque Claude Code mata el hook antes de que el oraculo termine (el
  # `make test` de este mismo repo tarda ~30 s) y el gate falla EN ABIERTO, dejando cerrar el
  # turno con el oraculo en rojo. El presupuesto de un Stop hook no es un numero fijo: es
  # coherencia con el `timeout` que el propio script se aplica por dentro.
  mapfile -t hook_lines < <(jq -r '.hooks | to_entries[] | .key as $ev | .value[]? | .hooks[]? | $ev + "|" + (.command // "SIN_COMANDO") + "|" + (if has("timeout") then (.timeout|tostring) else "SIN_TIMEOUT" end)' config/settings.template.json)
  bad=0
  for h in "${hook_lines[@]}"; do
    ev="${h%%|*}"; rest="${h#*|}"; cmd="${rest%|*}"; to="${rest##*|}"
    if [ "$to" = "SIN_TIMEOUT" ] || ! [[ "$to" =~ ^[0-9]+$ ]]; then
      bad=$((bad + 1)); echo "  NOT ok - hook sin timeout numerico declarado: $ev $cmd"
      continue
    fi
    if [ "$ev" = "Stop" ]; then
      script=".claude/hooks/$(basename "$cmd")"
      interno=$(grep -oE '\btimeout [0-9]+' "$script" 2>/dev/null | grep -oE '[0-9]+' | sort -rn | head -1)
      if [ -n "$interno" ] && [ "$to" -lt "$interno" ]; then
        bad=$((bad + 1))
        echo "  NOT ok - el Stop hook se mata antes de acabar su propio trabajo: $cmd declara timeout=$to pero ejecuta con 'timeout $interno'"
      fi
    elif [ "$to" -gt 5 ]; then
      bad=$((bad + 1)); echo "  NOT ok - hook de camino caliente con timeout > 5s: $ev $cmd (timeout=$to)"
    fi
  done
  ck "$([ "${#hook_lines[@]}" -ge 1 ] && echo y || echo n)" "y" "hay hooks declarados en config/settings.template.json (${#hook_lines[@]})"
  ck "$([ "$bad" -eq 0 ] && echo y || echo n)" "y" "timeouts coherentes: camino caliente <= 5s, Stop >= su timeout interno (invalidos: $bad)"

  # Falsabilidad: con el timeout=5 que traia originalmente el Stop hook, el check tiene que
  # saltar. Sin esto, todo lo anterior podria estar pasando por no mirar donde debe.
  f_int=$(grep -oE '\btimeout [0-9]+' .claude/hooks/verify-gate.sh 2>/dev/null | grep -oE '[0-9]+' | sort -rn | head -1)
  ck "$([ -n "$f_int" ] && [ 5 -lt "$f_int" ] && echo y || echo n)" "y" "falsabilidad: un Stop hook a 5s con 'timeout $f_int' dentro se detecta como incoherente"
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

echo "== 9) test_ci_paridad_con_el_Makefile =="
# La deriva ya ocurrio y nadie la vio: el Makefile corria 25 suites y ci.yml 23. Las dos
# ausentes eran test_doc_claims.sh y test_evals.sh, justo las que impiden que la doc mienta,
# asi que un PR que rompiera una cifra del README pasaba CI en verde. El sensor que existia
# (test_doc_claims.sh) comparaba kit/test/ contra el Makefile, no contra CI.
MK="Makefile"
if [ -f "$MK" ] && [ -f "$WF" ]; then
  ausentes=$(comm -23 \
    <(grep -oE 'kit/test/[A-Za-z0-9_]+\.sh' "$MK" | sort -u) \
    <(grep -oE 'kit/test/[A-Za-z0-9_]+\.sh' "$WF" | sort -u) | grep -c . || true)
  ck "$ausentes" "0" "toda suite del Makefile corre tambien en ci.yml (ausentes en CI: $ausentes)"
else
  ck "y" "y" "Makefile o ci.yml ausente (check por vacio)"
fi

echo "== 10) test_diagramas_mermaid =="
# Un diagrama es codigo: se versiona, se difea, y una IA lo lee como texto estructurado. Por eso
# van en fences `mermaid` --que GitHub renderiza nativo-- y no en PNG: una imagen es vistosa para
# un humano e ILEGIBLE para un agente, y no se puede revisar en un diff. Estos checks vigilan las
# cuatro cosas que rompen un diagrama asi sin que nadie se entere, porque el fence roto no
# aparece como error: aparece como un bloque de texto crudo en la pagina.
#
# El de los rellenos palidos es un fallo real de este repo: cinco `fill:#eef3ff` con texto
# `#1a1a1a` se leian bien en el tema claro y quedaban ilegibles en el oscuro de GitHub. La regla
# --todo `fill:` con texto blanco-- fuerza tonos medios, que se leen sobre los dos fondos.
mermaid_md=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  mermaid_md="$(git ls-files "*.md" 2>/dev/null)"
fi
if [ -z "$mermaid_md" ]; then
  ck "y" "y" "sin .md versionados (check por vacio)"
else
  mm_total=0; mm_abiertos=0; mm_malos=0; mm_palidos=0; mm_mudos=0; mm_flojos=0
  for f in $mermaid_md; do
    [ -f "$f" ] || continue
    # shellcheck disable=SC2046 # el troceado en palabras es el objetivo: awk emite 5 enteros
    set -- $(awk '
  function hx(s,  i,c,v) { v=0; for (i=1; i<=length(s); i++) { c=tolower(substr(s,i,1)); v = v*16 + index("0123456789abcdef", c) - 1 } return v }
  function canal(x) { x = x/255; return (x <= 0.03928) ? x/12.92 : ((x+0.055)/1.055)^2.4 }
  function luma(h) { return 0.2126*canal(hx(substr(h,1,2))) + 0.7152*canal(hx(substr(h,3,2))) + 0.0722*canal(hx(substr(h,5,2))) }
  function contraste(a, b,  la, lb, hi, lo) { la=luma(a); lb=luma(b); hi=(la>lb)?la:lb; lo=(la>lb)?lb:la; return (hi+0.05)/(lo+0.05) }
  /^```mermaid[[:space:]]*$/ { dentro=1; total++; tipo=""; etiq=0; next }
  dentro && /^```[[:space:]]*$/ {
      dentro=0
      if (tipo !~ /^(flowchart|graph|sequenceDiagram|stateDiagram|classDiagram|erDiagram|gitGraph|journey|pie|timeline|quadrantChart|mindmap)/) malos++
      else if (tipo ~ /^(flowchart|graph)/ && etiq == 0) mudos++
      next }
  dentro {
      linea=$0; sub(/^[[:space:]]+/, "", linea)
      if (tipo == "" && linea != "" && linea !~ /^%%/) tipo=linea
      if (linea ~ /--(>|-)\|/) etiq=1
      if (linea ~ /fill:#/ && linea !~ /color:#([Ff][Ff][Ff]|[Ff][Ff][Ff][Ff][Ff][Ff])([,[:space:]]|$)/) palidos++
      if (match(linea, /fill:#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]/)) {
          relleno = substr(linea, RSTART+6, 6)
          if (contraste(relleno, "FFFFFF") < 4.5) flojos++
      }
  }
  END { if (dentro) abiertos++; printf "%d %d %d %d %d %d\n", total+0, abiertos+0, malos+0, palidos+0, mudos+0, flojos+0 }
' "$f")
    mm_total=$((mm_total + $1)); mm_abiertos=$((mm_abiertos + $2))
    mm_malos=$((mm_malos + $3)); mm_palidos=$((mm_palidos + $4))
    mm_mudos=$((mm_mudos + $5)); mm_flojos=$((mm_flojos + $6))
  done
  ck "$([ "$mm_total" -ge 5 ] && echo y || echo n)" "y" "hay diagramas mermaid que medir (encontrados: $mm_total)"
  ck "$mm_abiertos" "0" "todo bloque mermaid cierra su fence (sin cerrar: $mm_abiertos)"
  ck "$mm_malos" "0" "todo bloque declara un tipo de diagrama que mermaid conoce (invalidos: $mm_malos)"
  ck "$mm_palidos" "0" "todo fill: lleva texto blanco, o seria ilegible en el tema oscuro (palidos: $mm_palidos)"
  ck "$mm_mudos" "0" "todo flowchart etiqueta al menos una flecha; una flecha muda solo dice \"relacionados de algun modo\" (mudos: $mm_mudos)"
  ck "$mm_flojos" "0" "todo fill: alcanza 4.5:1 de contraste WCAG AA con su texto -- legibilidad MEDIDA, no supuesta (por debajo: $mm_flojos)"
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
# La fila fabricada tiene que tener la MISMA FORMA que las de SOURCES.md: columna
# '#' delante y unidad en la ventana. Sin la columna '#' este caso no ejercitaba
# la ambiguedad que hacia que source_field leyera el indice de fila como ventana,
# asi que el check pasaba sin cubrir el bug que tenia delante (2026-08-25).
bad_source_row="| 9 | http://example.com/fabricado | Autor Fabricado | primaria | $old_date | 30 d | vigente |"
if validate_source_row "$bad_source_row" && is_stale "$old_date" "30"; then
  ck "y" "y" "test_sources_freshness SI detecta una entrada vencida fabricada"
  falsified=$((falsified + 1))
else
  ck "n" "y" "test_sources_freshness SI detecta una entrada vencida fabricada"
fi


# Falsabilidad de la 9: un Makefile con una suite que CI no corre tiene que detectarse.
tmp_mk="$(mktemp)"
printf 'test:\n\tbash kit/test/test_fabricada_que_ci_no_corre.sh\n' > "$tmp_mk"
n_f=$(comm -23 \
  <(grep -oE 'kit/test/[A-Za-z0-9_]+\.sh' "$tmp_mk" | sort -u) \
  <(grep -oE 'kit/test/[A-Za-z0-9_]+\.sh' "$WF" | sort -u) | grep -c . || true)
rm -f "$tmp_mk"
if [ "$n_f" -ge 1 ]; then
  ck "y" "y" "test_ci_paridad SI detecta una suite fabricada que CI no corre"
  falsified=$((falsified + 1))
else
  ck "n" "y" "test_ci_paridad SI detecta una suite fabricada que CI no corre"
fi


# Falsabilidad de la 10: un bloque con relleno palido, sin tipo y con la flecha muda tiene que
# disparar los tres checks a la vez.
tmp_md="$(mktemp)"
# shellcheck disable=SC2016 # las comillas invertidas son una valla markdown literal, no una sustitucion
printf '```mermaid\n    A --> B\n    style A fill:#eef3ff,color:#1a1a1a\n```\n' > "$tmp_md"
# shellcheck disable=SC2046 # el troceado en palabras es el objetivo: awk emite 5 enteros
set -- $(awk '
  function hx(s,  i,c,v) { v=0; for (i=1; i<=length(s); i++) { c=tolower(substr(s,i,1)); v = v*16 + index("0123456789abcdef", c) - 1 } return v }
  function canal(x) { x = x/255; return (x <= 0.03928) ? x/12.92 : ((x+0.055)/1.055)^2.4 }
  function luma(h) { return 0.2126*canal(hx(substr(h,1,2))) + 0.7152*canal(hx(substr(h,3,2))) + 0.0722*canal(hx(substr(h,5,2))) }
  function contraste(a, b,  la, lb, hi, lo) { la=luma(a); lb=luma(b); hi=(la>lb)?la:lb; lo=(la>lb)?lb:la; return (hi+0.05)/(lo+0.05) }
  /^```mermaid[[:space:]]*$/ { dentro=1; total++; tipo=""; etiq=0; next }
  dentro && /^```[[:space:]]*$/ {
      dentro=0
      if (tipo !~ /^(flowchart|graph|sequenceDiagram|stateDiagram|classDiagram|erDiagram|gitGraph|journey|pie|timeline|quadrantChart|mindmap)/) malos++
      else if (tipo ~ /^(flowchart|graph)/ && etiq == 0) mudos++
      next }
  dentro {
      linea=$0; sub(/^[[:space:]]+/, "", linea)
      if (tipo == "" && linea != "" && linea !~ /^%%/) tipo=linea
      if (linea ~ /--(>|-)\|/) etiq=1
      if (linea ~ /fill:#/ && linea !~ /color:#([Ff][Ff][Ff]|[Ff][Ff][Ff][Ff][Ff][Ff])([,[:space:]]|$)/) palidos++
      if (match(linea, /fill:#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]/)) {
          relleno = substr(linea, RSTART+6, 6)
          if (contraste(relleno, "FFFFFF") < 4.5) flojos++
      }
  }
  END { if (dentro) abiertos++; printf "%d %d %d %d %d %d\n", total+0, abiertos+0, malos+0, palidos+0, mudos+0, flojos+0 }
' "$tmp_md")
rm -f "$tmp_md"
if [ "$3" -ge 1 ] && [ "$4" -ge 1 ] && [ "$6" -ge 1 ]; then
  ck "y" "y" "test_diagramas_mermaid SI detecta el bloque fabricado: sin tipo, relleno palido y contraste por debajo de AA"
  falsified=$((falsified + 1))
else
  ck "n" "y" "test_diagramas_mermaid SI detecta el bloque fabricado: sin tipo, relleno palido y contraste por debajo de AA"
fi

ck "$([ "$falsified" -ge 6 ] && echo y || echo n)" "y" "al menos 6 checks demuestran deteccion real sobre casos fabricados a proposito (detectados: $falsified de 7) -- si fuera 0, la suite seria decorativa"

echo "== 11) test_omision_no_es_aprobado =="
# Una suite que decide no hacer su trabajo no puede imprimir "ok" ni sumar un passed.
# Hay tres estados, no dos, y el del medio existe precisamente para esto: "no se pudo
# verificar". test_doctor_drift.sh tenia DOS salidas asi -sin checkout de git, y sin
# ningun hook con dos versiones en el historial- y las dos imprimian
# `ok - ... suite omitida` y `== 1 passed, 0 failed ==`. En un entorno sin historial
# -un `git archive`, un clon superficial, un tarball- la suite reportaba un aprobado
# por cero mediciones, y el agregado lo sumaba como verde.
omisiones_aprobadas(){ grep -lE "^[[:space:]]*echo \"ok - .*(omitida|se omite)" "$@" 2>/dev/null | grep -c . || true; }
n=$(omisiones_aprobadas kit/test/test_*.sh)
ck "$n" "0" "ninguna suite imprime 'ok' por trabajo que decidio no hacer (suites asi: $n)"

# Falsabilidad del detector: sobre un fichero fabricado con el fallo dentro tiene que verlo.
tmp_om="$(mktemp -d)"
printf '#!/bin/bash\necho "ok - algo: suite omitida"\n' > "$tmp_om/test_fabricada.sh"
if [ "$(omisiones_aprobadas "$tmp_om"/test_*.sh)" = "1" ]; then
  ck "y" "y" "falsabilidad: el detector SI ve la omision aprobada en un fichero fabricado"
  falsified=$((falsified + 1))
else
  ck "n" "y" "falsabilidad: el detector SI ve la omision aprobada en un fichero fabricado"
fi
rm -f "$tmp_om"/test_*.sh; rmdir "$tmp_om"

# Y por ejecucion, que es lo que de verdad importa: forzada la omision -un arbol sin
# historial de git-, test_doctor_drift.sh tiene que declarar skip, no aprobado. Se monta
# con un symlink para no copiar el kit: `cd` conserva la ruta logica, asi que el REPO que
# la suite deduce es el directorio temporal, que no es un checkout.
tmp_sl="$(mktemp -d)"; ln -s "$(cd "$(dirname "$0")/.." && pwd)" "$tmp_sl/kit"
out_om="$(bash "$tmp_sl/kit/test/test_doctor_drift.sh" 2>&1 || true)"
ck "$(printf '%s' "$out_om" | grep -qE '^(skip|ok) - el kit no es un checkout de git' && echo y || echo n)" "y" \
   "el andamio SI fuerza la omision (si no, los dos checks de abajo aprobarian sin medir)"
ck "$(printf '%s' "$out_om" | grep -qE '^skip - ' && echo y || echo n)" "y" \
   "omitida de verdad, test_doctor_drift declara skip"
ck "$(printf '%s' "$out_om" | tail -1 | grep -q 'skipped' && echo y || echo n)" "y" \
   "y su resumen lo dice, que es lo unico que el agregado de make test puede leer"
rm -f "$tmp_sl/kit"; rmdir "$tmp_sl"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
