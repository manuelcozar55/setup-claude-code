#!/bin/bash
# test_shellcheck_honest_gate.sh — donde la doc afirma que `shellcheck -x` es una
# condicion de entrega, tiene que quedar claro QUIEN la ejecuta: la CI, no el
# oraculo local `make test`.
#
# Por que existe (F-25/COH-09, boundary del todo 17): CLAUDE.md listaba en "Antes de
# commitear" el escaneo de secretos, `shellcheck -x` sobre todo `.sh` y `make test`
# en la misma frase, como si el humano (o el oraculo verde) los corriera todos por
# igual. Pero `make test` NO ejecuta shellcheck -- se comprueba abajo -- y quien lo
# hace de verdad como puerta es `.github/workflows/ci.yml` (shellcheck -x sobre todo
# .sh versionado). Prometer una puerta que el oraculo de referencia no ejecuta hace
# que un verde local se lea como entrega completa cuando no lo es. La doc debe
# atribuir shellcheck a la CI. Esta suite lo falsifica.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
REPO="$(cd "$KIT/.." && pwd)"
CLAUDE="$REPO/CLAUDE.md"
CI="$REPO/.github/workflows/ci.yml"
MK="$REPO/Makefile"
pass=0; fail=0

check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi; }

# Hecho 1: `make test` NO invoca el binario shellcheck (el oraculo local no es la
# puerta). Se busca una invocacion real (`shellcheck ` como comando), no el nombre
# de una suite que lleve la palabra en el fichero.
if grep -qE '(^|[[:space:];&|(])shellcheck[[:space:]]' "$MK"; then mk_runs_sc=1; else mk_runs_sc=0; fi
check "make test no ejecuta shellcheck (no es la puerta)" "$mk_runs_sc"

# Hecho 2: la CI SI ejecuta shellcheck -x como puerta.
if grep -qiE 'shellcheck -x' "$CI"; then ci_gate=0; else ci_gate=1; fi
check "la CI ejecuta shellcheck -x como puerta real" "$ci_gate"

# Asercion: si CLAUDE.md nombra shellcheck como paso antes de commitear, tiene que
# atribuirlo a la CI en el mismo documento (no confundirlo con make test).
if grep -qi 'shellcheck' "$CLAUDE"; then
  if grep -qiE 'shellcheck.*\bCI\b|\bCI\b.*shellcheck' "$CLAUDE"; then attr=0; else attr=1; fi
  check "CLAUDE.md atribuye shellcheck a la CI, no al oraculo local" "$attr"
else
  check "CLAUDE.md no menciona shellcheck sin atribuirlo" 0
fi

echo "PASS=$pass FAIL=$fail SKIP=0"
[ "$fail" -eq 0 ]
