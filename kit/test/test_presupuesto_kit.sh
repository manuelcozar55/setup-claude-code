#!/usr/bin/env bash
# test_presupuesto_kit.sh — presupuesto de piezas del kit por defecto (simplificación 3.0.0). Sin red.
# Cuenta lo que instala `install.sh` SIN flags: hooks cableados en kit/claude/settings.json, los de SessionStart,
# agentes y skills (todo lo de kit/claude menos las piezas de kit/opcional.sh). Falla si algo pasa de su tope.
# Los topes son el recuento tras W1+W3. Subir uno exige decir qué se retira o por qué compensa: no se sube
# «por si acaso». Es el complemento de test_presupuesto_contexto.sh, que mide caracteres y no piezas.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
pass=0; fail=0
# shellcheck source=SCRIPTDIR/../opcional.sh
. "$KIT/opcional.sh"

TOPE_HOOKS=17
TOPE_SESSIONSTART=2
TOPE_AGENTES=5
TOPE_SKILLS=1

juzga() { [ "$1" -le "$2" ]; }   # medida, tope
ck() {
  if juzga "$2" "$3"; then echo "ok - $1: $2 (tope $3)"; pass=$((pass+1))
  else echo "NOT ok - $1: $2 pasa del tope $3"; fail=$((fail+1)); fi
}

hooks="$(jq '[.hooks[][] | .hooks[]] | length' "$KIT/claude/settings.json")"
ss="$(jq '[(.hooks.SessionStart // [])[] | .hooks[]] | length' "$KIT/claude/settings.json")"
agentes=0; for f in "$KIT"/claude/agents/*.md; do opcional_de "agents/$(basename "$f")" >/dev/null || agentes=$((agentes+1)); done
skills=0; for d in "$KIT"/claude/skills/*/; do opcional_de "skills/$(basename "$d")/x" >/dev/null || skills=$((skills+1)); done

ck "hooks cableados por defecto" "$hooks" "$TOPE_HOOKS"
ck "hooks de SessionStart por defecto" "$ss" "$TOPE_SESSIONSTART"
ck "agentes instalados por defecto" "$agentes" "$TOPE_AGENTES"
ck "skills instaladas por defecto" "$skills" "$TOPE_SKILLS"

# Una pieza opcional que se cuela en el camino por defecto sube el recuento: se vería aquí.
if [ "$(opcional_de "agents/pr-test-analyzer.md")" = "revisores" ] && [ "$(opcional_de "skills/retro/SKILL.md")" = "skills-extra" ]; then
  echo "ok - los revisores y skills-extra no cuentan como por defecto"; pass=$((pass+1))
else echo "NOT ok - opcional.sh no marca revisores o skills-extra como opcionales"; fail=$((fail+1)); fi

# falsable: un recuento por encima del tope hace caer la comprobación; uno igual o por debajo, no
if juzga $((TOPE_HOOKS+1)) "$TOPE_HOOKS" || ! juzga "$TOPE_HOOKS" "$TOPE_HOOKS"; then
  echo "NOT ok - falsable: el presupuesto no distingue tope+1 del tope"; fail=$((fail+1))
else echo "ok - falsable: tope+1 hooks da FAIL; el tope exacto, ok"; pass=$((pass+1)); fi

echo "== $pass ok, $fail fallos =="
[ "$fail" -eq 0 ]
