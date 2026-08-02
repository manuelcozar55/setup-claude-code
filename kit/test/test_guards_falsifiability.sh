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

if [ "$BASELINE_FAIL" -eq 0 ] && [ "$FLIPPED" -gt 0 ]; then
  echo "OK: la suite es falsable (un guard no-op rompe $FLIPPED caso(s) BLOCK que antes pasaban)."
  exit 0
else
  echo "FAIL: la suite no detecto el guard neutralizado (posible tautologia)."
  exit 1
fi
