#!/usr/bin/env bash
# sumar-tests.sh — agrega los resumenes que kit/test-runner.sh fue dejando en
# kit/test/.make-test.log y los suma en UN total real de `make test`.
#
# Por que existe: el target test corria 30 suites sueltas y la ultima linea
# en pantalla era el resumen de la ULTIMA suite (== 92 passed, 0 failed ==
# de test_evals.sh), que se leia como si fuera el total del target. No lo
# era: el total real sumando las 30 suites es otra cifra. El formato de esta
# linea es a proposito distinto de '== N passed, M failed ==' para que no se
# pueda confundir con el resumen de una suite.
#
# Si una suite no deja un resumen parseable, se nombra en vez de sumarse en
# silencio como si tuviera 0 passed/0 failed: eso seria otro verde falso.
#
# test_guards_falsifiability.sh era el caso real y legitimo sin tally propio
# (su veredicto es un unico cheque -- "cayeron los N casos esperados" -- no
# una bateria numerable); desde H-1 declara ese cheque como "PASS=1 FAIL=0"
# (o 0/1 si falla) y ya no cae en este cubo. Si de verdad aparece una suite
# que deja de imprimir su resumen por un bug (como test_metrics.sh antes de
# A2), el veredicto de mas abajo ya NO lo pasa por alto: cuenta como "no se
# pudo verificar", que es distinto tanto de "fallaron aserciones" (eso lo
# sigue decidiendo solo total_fail > 0) como de un passed silencioso.
set -euo pipefail
LOG="kit/test/.make-test.log"
if [ ! -f "$LOG" ]; then
  echo "#### TOTAL make test: sin datos ($LOG no existe) ####"
  exit 1
fi

RESUMEN_RE='^(== [0-9]+ passed, [0-9]+ failed(, [0-9]+ skipped)? ==|PASS=[0-9]+ FAIL=[0-9]+( SKIP=[0-9]+)?)$'

total_pass=0
total_fail=0
total_skip=0
n=0
sin_resumen=()

suite=""
block=""

flush() {
  [ -n "$suite" ] || return 0
  n=$((n + 1))
  local linea p f s
  # Solo cuenta como resumen la ULTIMA linea no vacia del bloque, nunca
  # cualquier linea con esa forma que aparezca antes: test_guards_falsifiability.sh,
  # por ejemplo, ECHOA dos "PASS=N FAIL=M" ajenos (de invocar test_guards.sh dos
  # veces) y termina con un veredicto "OK:"/"FAIL:" sin tally propio. Buscar la
  # forma en cualquier parte del bloque le habria atribuido a esta suite los 10
  # "fallos" de su demostracion de falsabilidad como si fueran suyos: el mismo
  # error de fondo que A1 corrige (afirmar por coincidencia, no por ancla).
  linea=$(printf '%s\n' "$block" | sed -e '/^[[:space:]]*$/d' | tail -n1 || true)
  if ! printf '%s' "$linea" | grep -qE "$RESUMEN_RE"; then
    sin_resumen+=("$suite")
    return 0
  fi
  if [[ "$linea" == PASS=* ]]; then
    p=$(printf '%s' "$linea" | grep -oE 'PASS=[0-9]+' | grep -oE '[0-9]+')
    f=$(printf '%s' "$linea" | grep -oE 'FAIL=[0-9]+' | grep -oE '[0-9]+')
    s=$(printf '%s' "$linea" | grep -oE 'SKIP=[0-9]+' | grep -oE '[0-9]+' || echo 0)
  else
    p=$(printf '%s' "$linea" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+')
    f=$(printf '%s' "$linea" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+')
    s=$(printf '%s' "$linea" | grep -oE '[0-9]+ skipped' | grep -oE '[0-9]+' || echo 0)
  fi
  total_pass=$((total_pass + p))
  total_fail=$((total_fail + f))
  total_skip=$((total_skip + s))
}

while IFS= read -r linea; do
  if [[ "$linea" == "### "* ]]; then
    flush
    suite="${linea#\#\#\# }"
    block=""
  else
    block+="$linea"$'\n'
  fi
done < "$LOG"
flush

echo "########################################"
echo "#### TOTAL make test: $n suites -- $total_pass passed, $total_fail failed, $total_skip skipped ####"
if [ "${#sin_resumen[@]}" -gt 0 ]; then
  echo "#### AVISO: suite(s) sin resumen parseable, NO contadas arriba: ${sin_resumen[*]} ####"
fi
echo "########################################"

# Tres veredictos, no dos: "fallo" y "no pude verificarlo" son cosas
# distintas y antes de esto compartian el mismo exit 0 que "paso". Un
# total_skip>0 (p.ej. las suites que dependen de jq y no lo encuentran) o una
# suite sin resumen parseable significan que parte del target NO SE EJECUTO
# o no se pudo leer su resultado -- eso no es un passed, aunque total_fail
# sea 0.
if [ "$total_fail" -gt 0 ]; then
  echo "#### VEREDICTO: FALLO -- $total_fail aserciones en rojo ####"
  exit 1
fi
if [ "$total_skip" -gt 0 ] || [ "${#sin_resumen[@]}" -gt 0 ]; then
  echo "#### VEREDICTO: NO SE PUDO VERIFICAR -- $total_skip caso(s) saltado(s) y ${#sin_resumen[@]} suite(s) sin resumen parseable; ninguna assertion en rojo, pero tampoco se ejecuto/leyo todo ####"
  exit 2
fi
echo "#### VEREDICTO: PASO -- $n suites, $total_pass passed, 0 failed, 0 skipped ####"
exit 0
