#!/bin/bash
# test_guards_falsifiability.sh — demuestra que test_guards.sh mide
# comportamiento real y no es una tautologia: neutraliza secret-guard.sh
# (lo sustituye por un stub `exit 0`, "permitir siempre") y comprueba que
# eso hace CAER un numero conocido de casos BLOCK de la suite.
#
# Si este script reportase 0 caidas, test_guards.sh no estaria probando nada
# -- pasaria igual con o sin guard. El numero exacto de caidas se fija mas
# abajo (ver STUB_BLOCK_CASES) y se compara con el resultado real.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

# Numero exacto de casos BLOCK que dependen de secret-guard.sh. Comprobar solo "> 0"
# dejaba que una regresion bajara de 10 a 1 sin que nada se pusiera rojo, y ademas
# README.md cita este 10 como hecho medido: sin fijarlo aqui, esa cifra podia quedarse
# falsa en silencio. Si cambias los casos de test_guards.sh, actualiza este numero Y el
# del README en el mismo commit -- ese es justo el punto de tenerlo aqui.
STUB_BLOCK_CASES=10

STUB=$(mktemp)
printf '#!/bin/bash\nexit 0\n' > "$STUB"
chmod +x "$STUB"

BASELINE_OUT=$(bash "$HERE/test_guards.sh")
BASELINE_FAIL=$(echo "$BASELINE_OUT" | grep -oE 'FAIL=[0-9]+' | tail -1 | cut -d= -f2)

STUB_OUT=$(SECRET_GUARD_BIN="$STUB" bash "$HERE/test_guards.sh")
STUB_FAIL=$(echo "$STUB_OUT" | grep -oE 'FAIL=[0-9]+' | tail -1 | cut -d= -f2)

rm -f "$STUB"

echo "== baseline (guard real) =="
echo "$BASELINE_OUT" | tail -1
echo "== guard neutralizado (stub exit 0) =="
echo "$STUB_OUT"

FLIPPED=$((STUB_FAIL - BASELINE_FAIL))
echo "== resultado =="
echo "casos que caen al neutralizar el guard: $FLIPPED"

if [ "$BASELINE_FAIL" -ne 0 ]; then
  echo "FAIL: la baseline no esta limpia (FAIL=$BASELINE_FAIL); arregla test_guards.sh antes."
  echo "PASS=0 FAIL=1"
  exit 1
fi
if [ "$FLIPPED" -eq 0 ]; then
  echo "FAIL: la suite no detecto el guard neutralizado (posible tautologia)."
  echo "PASS=0 FAIL=1"
  exit 1
fi
if [ "$FLIPPED" -ne "$STUB_BLOCK_CASES" ]; then
  echo "FAIL: caen $FLIPPED casos, se esperaban $STUB_BLOCK_CASES (STUB_BLOCK_CASES)."
  echo "      Si el cambio es intencionado, actualiza STUB_BLOCK_CASES aqui y la cifra de README.md."
  echo "PASS=0 FAIL=1"
  exit 1
fi
echo "OK: la suite es falsable (un guard no-op rompe los $FLIPPED casos BLOCK esperados)."
# Linea de tally real para kit/sumar-tests.sh: esta suite es un unico cheque
# ("es falsable si y solo si $FLIPPED == STUB_BLOCK_CASES"), no una bateria de
# casos, asi que declara 1 passed/failed segun ese resultado -- no un tally
# fabricado de las corridas internas de test_guards.sh, que son fixtures, no
# aserciones de esta suite.
echo "PASS=1 FAIL=0"
exit 0
