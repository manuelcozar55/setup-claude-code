#!/usr/bin/env bash
# generar-mapa.sh — genera kit/docs/MAPA.md desde kit/claude/settings.json y el código del kit.
# Uso: scripts/generar-mapa.sh [fichero]   (sin argumento, escribe en la salida estándar)
# Cada hook cableado debe traer su descripción en la cabecera (`# QUE-HACE: …` o `nombre — …`);
# si falta, el script falla: nunca inventa texto. MAPA_KIT apunta a otra copia de kit/ (lo usa el test).
# Los interruptores explicados a mano viven en scripts/mapa-interruptores.tsv (script, variable, texto)
# y se validan contra el código: la variable tiene que aparecer en el script.
# Las comillas simples llevan acentos graves de Markdown a propósito (SC2016); `$(grep …)` itera nombres sin espacios.
# shellcheck disable=SC2016,SC2013
set -euo pipefail
export LC_ALL=C
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KIT=${MAPA_KIT:-$ROOT/kit}
TSV=${MAPA_TSV:-$ROOT/scripts/mapa-interruptores.tsv}
SET=$KIT/claude/settings.json
HOOKS=$KIT/claude/hooks
PREFIJO='^((CC|NUCLEO|COCKPIT|CUPO)_[A-Z0-9_]+|PYTHON_HOOK_BIN|CLAUDE_HOME)$'
FALLOS=0
fallo() { echo "generar-mapa: $*" >&2; FALLOS=1; }

# desc <fichero>: la descripción de la cabecera, o nada.
desc() {
  awk '
    NR > 12 { exit }
    /^# QUE-HACE:/ { sub(/^# QUE-HACE: */, ""); q = $0; exit }
    f == "" {
      l = $0; sub(/^# /, "", l); sub(/^"""/, "", l)
      i = index(l, " — ")
      if (i > 1 && substr(l, 1, i - 1) !~ / /) { f = substr(l, i + 5); c = 1 }
      next
    }
    c > 0 && c < 4 && index(f, ". ") == 0 && $0 !~ /^(#?$|""")/ { l = $0; sub(/^# ?/, "", l); f = f " " l; c++ }
    END {
      if (q == "") { i = index(f " ", ". "); if (i > 0) f = substr(f, 1, i) }
      r = (q != "") ? q : f; gsub(/[ \t]+$/, "", r); gsub(/\|/, "\\|", r); print r
    }
  ' "$1"
}

# vars <fichero…>: variables de entorno que leen (${VAR:-…}, environ, getenv), solo las del kit.
vars() {
  cat "$@" 2>/dev/null \
    | grep -oE '\$\{[A-Z][A-Z0-9_]*:?-|(environ\.get\(|environ\[|getenv\()["'\''][A-Z][A-Z0-9_]*' \
    | grep -oE '[A-Z][A-Z0-9_]{2,}$|[A-Z][A-Z0-9_]*:?-$' | sed 's/:\{0,1\}-$//' \
    | grep -E "$PREFIJO" | sort -u || true
}

# ficheros que lee un script: él, las libs que carga y, si lo envuelve optional-hook.sh, este
fuentes() {
  local f=$1 envuelto=$2 l
  echo "$f"
  for l in $(grep -oE 'lib/[a-z]+\.sh' "$f" | sort -u); do [ -f "$HOOKS/$l" ] && echo "$HOOKS/$l"; done
  [ "$envuelto" = 1 ] && echo "$HOOKS/optional-hook.sh"
  return 0
}

# apagado <script>: lo que dice la tabla de interruptores para ese script
apagado() {
  [ -f "$TSV" ] || return 0
  awk -F'\t' -v s="$1" -v o="${2:+optional-hook.sh}" '($1 == s || $1 == o) && $1 !~ /^#/ { printf "%s`%s`: %s", (n++ ? "; " : ""), $2, $3 }' "$TSV"
}

celdas() { local x=$1; [ -n "$x" ] || x="—"; printf '%s' "$x"; }
lista() { local v; v=$(tr '\n' ' ' | sed 's/ $//; s/ /`, `/g'); [ -n "$v" ] && printf '`%s`' "$v" || printf '—'; }

salida() {
  echo '# Mapa del kit'
  echo
  echo '> Generado por `scripts/generar-mapa.sh` desde `kit/claude/settings.json` y el código. No lo edites a mano:'
  echo '> cambia el código (o `scripts/mapa-interruptores.tsv`) y regenera. `kit/test/test_mapa.sh` falla si no coincide.'
  echo
  echo '## Hooks cableados'
  echo
  echo 'Cada fila es una entrada de `settings.json`. Todos terminan sin bloquear salvo los guards, que bloquean con un mensaje que dice qué hacer.'
  echo 'Para quitar un hook, bórralo de `~/.claude/settings.json` y anota el script en `~/.claude/.kit-desactivados` (ver `OPERAR.md`).'
  echo
  echo '| Evento | Matcher | Script | Qué hace | Variables que lee | Cómo se apaga |'
  echo '|---|---|---|---|---|---|'
  local e m c s w d v a base f
  while IFS=$'\x1f' read -r e m c _; do
    s=$(printf '%s' "$c" | grep -oE '\.claude/(hooks|sentinel)/[A-Za-z0-9_.-]+' | tail -1 || true)
    [ -n "$s" ] || { fallo "no encuentro el script en: $c"; continue; }
    base=${s##*/}
    if [ "${s#.claude/sentinel/}" != "$s" ]; then f=$KIT/sentinel/$base; else f=$HOOKS/$base; fi
    [ -f "$f" ] || { fallo "settings.json cablea $s y no existe en el kit"; continue; }
    w=0; case $c in *optional-hook.sh*) w=1 ;; esac
    d=$(desc "$f")
    [ -n "$d" ] || { fallo "$base no tiene descripción normalizada (# QUE-HACE: … o «nombre — …»)"; d="(sin descripción)"; }
    # shellcheck disable=SC2046
    v=$(vars $(fuentes "$f" "$w") | lista)
    a=$(apagado "$base" "$([ "$w" = 1 ] && echo 1)")
    [ -n "$a" ] || a="solo quitándolo de \`settings.json\`"
    m=${m//|/\\|}
    echo "| $e | $(celdas "${m:+\`$m\`}") | \`$base\` | $d | $v | $a |"
  done < <(jq -r '.hooks | to_entries[] | .key as $e | .value[] | (.matcher // "") as $m | .hooks[] | [$e, $m, .command, (.timeout // "" | tostring)] | join("\u001f")' "$SET")

  echo
  echo '## Variables de entorno'
  echo
  echo 'Todas las que leen los hooks, las órdenes de `bin/` y Sentinel con un valor por defecto, y quién las lee.'
  echo
  echo '| Variable | La leen |'
  echo '|---|---|'
  local x n
  while read -r n; do
    x=$(for f in "$HOOKS"/*.sh "$HOOKS"/*.py "$HOOKS"/lib/*.sh "$KIT"/claude/bin/* "$KIT"/sentinel/*.py; do
          if [ -f "$f" ] && vars "$f" | grep -x "$n" >/dev/null; then printf '%s\n' "${f##*/}"; fi; done | sort -u | lista)
    echo "| \`$n\` | $x |"
  done < <(vars "$HOOKS"/*.sh "$HOOKS"/*.py "$HOOKS"/lib/*.sh "$KIT"/claude/bin/* "$KIT"/sentinel/*.py)

  echo
  echo '## Agentes'
  echo
  echo '| Agente | Para qué |'
  echo '|---|---|'
  local f
  for f in "$KIT"/claude/agents/*.md; do fm "$f" agent; done
  echo
  echo '## Skills'
  echo
  echo '| Skill | Para qué |'
  echo '|---|---|'
  for f in "$KIT"/claude/skills/*/SKILL.md; do fm "$f" skill; done

  echo
  echo '## Órdenes de `~/.claude/bin`'
  echo
  echo '| Orden | Qué hace |'
  echo '|---|---|'
  for f in "$KIT"/claude/bin/*; do
    d=$(desc "$f")
    [ -n "$d" ] || { fallo "${f##*/} no tiene descripción normalizada"; d="(sin descripción)"; }
    echo "| \`${f##*/}\` | $d |"
  done

  if [ -f "$KIT/mods/cockpit/hooks/register.tsx" ]; then
    echo
    echo '## Órdenes del cockpit (mod opcional)'
    echo
    echo '| Orden | Qué hace |'
    echo '|---|---|'
    awk '
      function vuelca(   n, d, i) {
        if (buf == "") return
        n = ""; d = ""
        if (match(buf, /name: \x27[^\x27]*\x27/)) n = substr(buf, RSTART + 7, RLENGTH - 8)
        if (match(buf, /description: \x27[^\x27]*\x27/)) d = substr(buf, RSTART + 14, RLENGTH - 15)
        i = index(d, ". "); if (i > 0) d = substr(d, 1, i - 1)
        gsub(/\|/, "\\|", d)
        if (n != "") print "| `/" n "` | " d " |"
        buf = ""
      }
      /command\.register/ { vuelca(); buf = $0; k = 4; next }
      k > 0 { buf = buf " " $0; k--; next }
      END { vuelca() }
    ' "$KIT/mods/cockpit/hooks/register.tsx"
  fi
}

# fm <fichero> <tipo>: fila con el nombre y la descripción del frontmatter
fm() {
  local n d
  n=$(awk '/^---$/ { c++; next } c == 1 && /^name:/ { sub(/^name: */, ""); print; exit }' "$1")
  d=$(awk '/^---$/ { c++; next } c == 1 && /^description:/ { sub(/^description: */, ""); gsub(/^"|"$/, ""); print; exit }' "$1")
  [ -n "$n" ] || n=$(basename "$(dirname "$1")")
  d=${d//|/\\|}
  case $d in ?*) d=$(printf '%s' "$d" | awk '{ i = index($0, ". "); print (i > 0) ? substr($0, 1, i) : $0 }') ;; esac
  echo "| \`$n\` | $d |"
}

# la tabla de interruptores no puede apuntar a una variable que el script no lee
if [ -f "$TSV" ]; then
  while IFS=$'\t' read -r s n _; do
    case $s in '' | '#'*) continue ;; esac
    f=$HOOKS/$s; [ -f "$f" ] || f=$KIT/sentinel/$s
    [ -f "$f" ] || { fallo "mapa-interruptores.tsv: $s no existe"; continue; }
    # shellcheck disable=SC2046
    vars $(fuentes "$f" 0) | grep -x "$n" >/dev/null || fallo "mapa-interruptores.tsv: $s no lee $n"
  done < "$TSV"
fi

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
salida > "$TMP"
[ "$FALLOS" = 0 ] || exit 1
if [ -n "${1:-}" ]; then cp "$TMP" "$1"; else cat "$TMP"; fi
