#!/usr/bin/env bash
# test_claude_md_template.sh — la plantilla de instrucciones que install.sh reparte:
# kit/claude/CLAUDE.md (capa fina de Claude Code) importa kit/claude/AGENTS.md (nucleo
# comun a Claude Code, Codex y opencode).
#
# Por que: la plantilla llego a 6,5 KB sin un sensor de tamano propio y con prosa muerta
# (Headroom, ventana de 1M) que el kit ni instala. Aqui se miden los dos techos (bytes/4,
# como test_harness_structure.sh), las lineas que resuelven contradicciones y que toda
# ruta citada exista en el kit: una referencia rota manda al modelo a leer un fichero que
# no esta.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
C="$KIT/claude/CLAUDE.md"; A="$KIT/claude/AGENTS.md"
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }
tokens(){ echo $(( $(wc -c < "$1" | tr -d ' ') / 4 )); }
has(){ grep -qF -- "$2" "$1" 2>/dev/null && echo y || echo n; }

# rutas_rotas <fichero...>: imprime cada `~/.claude/<x>` o import `@<x>` (a inicio de
# linea, que es como Claude Code importa) sin su <x> en kit/claude/.
rutas_rotas() {
  local f r
  for f in "$@"; do
    [ -f "$f" ] || { echo "$f: no existe"; continue; }
    # shellcheck disable=SC2088 # el ~ es el literal que se busca en el markdown
    while IFS= read -r r; do
      [ -n "$r" ] && { [ -e "$KIT/claude/$r" ] || echo "$f -> $r"; }
    done < <({ grep -oE '~/\.claude/[A-Za-z0-9._/-]+' "$f" | sed 's|^~/\.claude/||'
               grep -oE '^@[A-Za-z0-9._/-]+' "$f" | sed 's|^@||'; } | sed 's|/$||')
  done
}

ck "$([ -f "$A" ] && echo y || echo n)" "y" "existe kit/claude/AGENTS.md"
ck "$(head -1 "$C")" "@AGENTS.md" "CLAUDE.md empieza importando @AGENTS.md"
ck "$([ "$(tokens "$C")" -le 900 ] && echo y || echo n)" "y" "CLAUDE.md <= 900 aprox-tokens (medido: $(tokens "$C"))"
ck "$([ -f "$A" ] && [ "$(tokens "$A")" -le 1800 ] && echo y || echo n)" "y" "AGENTS.md <= 1800 aprox-tokens"
ck "$(rutas_rotas "$C" "$A")" "" "toda ruta ~/.claude/<x> o @<x> citada existe en kit/claude/"

ck "$(has "$A" 'estas reglas > skills de plugins > comportamiento por defecto; una tarea trivial salta toda ceremonia')" "y" "linea de precedencia"
ck "$(has "$A" 'una sola ronda de aclaración; el test va tras la lógica nueva, antes solo para reproducir un bug')" "y" "linea de desempates"
ck "$(has "$C" 'Ceremonia según riesgo')" "y" "ceremonia segun riesgo"
# shellcheck disable=SC2016 # los backticks son los del markdown de la plantilla, literales
ck "$(has "$C" '`.claude/estado/nucleo.md` es el estado; el hook avisa cuándo actualizarlo; tras compactar llega inyectado; la historia va a `diario.md`.')" "y" "nucleo.md en una sola frase"
# shellcheck disable=SC2016 # los backticks son los del markdown de la plantilla, literales
ck "$(has "$C" 'Si el proyecto tiene `ESTADO.md` en la raíz y no `nucleo.md`, ese es su estado; no crees `nucleo.md`.')" "y" "ESTADO.md sin nucleo.md es el estado"
ck "$(grep -c 'nucleo.md' "$C" "$A" | awk -F: '{s+=$2} END{print s}')" "2" "nucleo.md se cita en dos frases entre las dos: el estado y la excepción de ESTADO.md"
ck "$(has "$A" 'recuerda <términos>')" "y" "AGENTS.md ensena recuerda"
ck "$(grep -liE 'headroom|\[1m\]|ventana de 1M|ccstatusline|/home/|~/work|~/repos' "$C" "$A" | wc -l | tr -d ' ')" "0" \
  "sin Headroom, ventana 1M, ccstatusline ni rutas privadas"

# v3: las reglas que la auditoria encontro mentirosas (oraculo, parche, parada de fase).
D="$KIT/claude/skills/deep-change/SKILL.md"
# shellcheck disable=SC2016 # los backticks son los del markdown, literales
ck "$(grep -cF '`oraculo -- <cmd>`' "$C")" "1" "CLAUDE.md cita oraculo una vez, con su forma"
# shellcheck disable=SC2016
ck "$(grep -cF '`handoff`' "$C")" "1" "CLAUDE.md cita handoff una vez"
ck "$(has "$C" 'Cambio mínimo por parche; nunca reescribir un fichero entero')" "y" "parche minimo en vez de reescribir"
ck "$(has "$C" 'Fin de fase = parada válida')" "y" "fin de fase es parada valida"
ck "$(has "$C" 'autocompact es solo el airbag')" "y" "autocompact queda de airbag"
ck "$(has "$D" 'una rama nunca aísla configuración viva')" "y" "deep-change: una rama no aisla config viva"
# shellcheck disable=SC2016
ck "$(has "$D" 'cada `[x]` cerrado va a diario con su comando y hash')" "y" "deep-change: [x] cerrado va a diario con comando y hash"

# Falsabilidad del comprobador de rutas: una ruta inventada de cada forma debe salir.
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
printf '@NO-EXISTE.md\nlee ~/.claude/skills/no-existe/SKILL.md\n' > "$T/roto.md"
ck "$(rutas_rotas "$T/roto.md" | wc -l | tr -d ' ')" "2" "falsabilidad: acusa un @import y una ~/.claude/ inexistentes"

echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
