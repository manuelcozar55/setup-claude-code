#!/bin/bash
# test_make_test_verdict.sh — que `make test` PUEDA dar veredicto justo cuando
# hace falta: con una suite en rojo.
#
# El fallo que motiva esta suite: el target `test` invocaba las 30 suites como
# comandos sueltos, asi que make ABORTABA en la primera roja y no llegaba nunca
# a kit/sumar-tests.sh. El total agregado -y su tercer veredicto, "NO SE PUDO
# VERIFICAR", que costo dos rondas construir- era inalcanzable EXACTAMENTE en
# el caso para el que se construyo. Con todo en verde el target funcionaba, que
# es la peor forma de estar roto: solo se rompe cuando lo necesitas.
#
# Segundo fallo, mas fino: el agregado leia el resumen impreso por cada suite y
# se fiaba de el. Una suite que imprime "0 failed" y MUERE despues (rc!=0, un
# `set -e` en la limpieza, un timeout) se contaba como verde. El resumen dice
# lo que la suite creia; el codigo de salida dice como acabo. Hacen falta los
# dos, y por eso test-runner.sh ahora anota `### rc=N`.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; RAIZ="$(cd "$HERE/../.." && pwd)"
SUMAR="$RAIZ/kit/sumar-tests.sh"; RUNNER="$RAIZ/kit/test-runner.sh"
pass=0; fail=0
ok(){ pass=$((pass+1)); }
ko(){ fail=$((fail+1)); echo "NOT ok - $1"; }
limpia(){ [ -n "${1:-}" ] && [ -d "$1" ] && { find "$1" -type f -delete; find "$1" -depth -type d -exec rmdir {} + ; }; }

# --- (a) el target `test` tolera que una suite falle -------------------------
# Se mide sobre el Makefile REAL, y la forma de tolerar en make es el prefijo
# `-` en la linea de receta. Sin el, make aborta y el agregado no corre.
recetas_del_target_test(){ awk '/^test:/{on=1; next} /^[A-Za-z0-9_.-]+:/{on=0} on' "$1"; }
# TAB="$(printf '\t')" y no '\t' dentro del patron: grep no interpreta \t como
# tabulador ni en BRE ni en ERE, lo toma como la letra t. Escrito asi, el primer
# grep no casaba NINGUNA linea, el segundo contaba sobre entrada vacia y este
# comprobador devolvia 0 -- "ninguna suite intolerante"-- sobre el Makefile real,
# que no tenia ni un prefijo. Un check que aprueba sin medir: exactamente lo que
# esta suite existe para impedir. Lo destapo el caso de falsabilidad de (b).
TAB="$(printf '\t')"
intolerantes(){ recetas_del_target_test "$1" | grep -E "^${TAB}.*kit/test-runner\.sh" | grep -cv "^${TAB}-" || true; }

n=$(intolerantes "$RAIZ/Makefile")
if [ "$n" -eq 0 ]; then ok
else ko "$n suite(s) del target 'test' abortan el target si fallan: make no llega a sumar-tests.sh"; fi

# --- (b) falsabilidad de (a) -------------------------------------------------
# Un comprobador que no sabe decir que NO no ha comprobado nada. Se le da un
# Makefile fabricado con el fallo dentro y tiene que verlo.
T="$(mktemp -d)"
printf 'test:\n\t-bash kit/test-runner.sh kit/test/a.sh\n\tbash kit/test-runner.sh kit/test/b.sh\n\tbash kit/sumar-tests.sh\n' > "$T/Makefile"
n=$(intolerantes "$T/Makefile")
if [ "$n" -eq 1 ]; then ok
else ko "falsabilidad: sobre un Makefile con 1 linea intolerante el comprobador dijo $n"; fi
limpia "$T"

# --- (c) el agregado decide el codigo de salida ------------------------------
log_falso(){ # $1 destino, $2 resumen de la suite, $3 rc anotado
  mkdir -p "$(dirname "$1")"
  { printf '### kit/test/inventada.sh\n'; printf '%s\n' "$2"; printf '### rc=%s\n' "$3"; } > "$1"
}
T="$(mktemp -d)"; ( cd "$T" && log_falso kit/test/.make-test.log "PASS=3 FAIL=1" 1 && bash "$SUMAR" >/dev/null 2>&1 )
rc=$?
if [ "$rc" -eq 1 ]; then ok; else ko "con una suite en rojo el agregado salio $rc, esperaba 1"; fi
limpia "$T"

# --- (d) una suite que muere DESPUES de su resumen deja de contar como verde --
T="$(mktemp -d)"; ( cd "$T" && log_falso kit/test/.make-test.log "PASS=3 FAIL=0" 1 && bash "$SUMAR" >/dev/null 2>&1 )
rc=$?
if [ "$rc" -ne 0 ]; then ok
else ko "la suite imprimio '0 failed' y murio con rc=1, y el agregado dijo PASO (rc=0)"; fi
limpia "$T"

# --- (e) falsabilidad de (d): el mismo log con rc=0 SI pasa -------------------
# Sin esto, (d) aprobaria tambien si el agregado enrojeciera siempre.
T="$(mktemp -d)"; ( cd "$T" && log_falso kit/test/.make-test.log "PASS=3 FAIL=0" 0 && bash "$SUMAR" >/dev/null 2>&1 )
rc=$?
if [ "$rc" -eq 0 ]; then ok
else ko "falsabilidad: con rc=0 y 0 failed el agregado deberia pasar, y salio $rc"; fi
limpia "$T"

# --- (f) extremo a extremo, en miniatura -------------------------------------
# Con el runner y el agregado REALES, y un Makefile que reproduce el patron del
# de verdad: una suite roja y una verde. Lo que se exige es que make LLEGUE al
# agregado -que es lo que no pasaba- y que el codigo de salida lo decida el.
T="$(mktemp -d)"; mkdir -p "$T/kit/test"
printf '#!/bin/sh\necho "PASS=1 FAIL=0"\n' > "$T/kit/test/verde.sh"
printf '#!/bin/sh\necho "PASS=0 FAIL=1"\nexit 1\n' > "$T/kit/test/roja.sh"
chmod +x "$T/kit/test/verde.sh" "$T/kit/test/roja.sh"
{ printf 'test:\n'; printf '\t@rm -f kit/test/.make-test.log\n'
  printf '\t-bash %s kit/test/roja.sh\n' "$RUNNER"
  printf '\t-bash %s kit/test/verde.sh\n' "$RUNNER"
  printf '\tbash %s\n' "$SUMAR"; } > "$T/Makefile"
salida="$(make -C "$T" test 2>&1)"; rc=$?
if printf '%s' "$salida" | grep -q 'TOTAL make test'; then ok
else ko "make aborto antes del agregado: la suite roja se llevo el target por delante"; fi
if [ "$rc" -ne 0 ] && printf '%s' "$salida" | grep -q 'VEREDICTO: FALLO'; then ok
else ko "el agregado no decidio el codigo de salida (rc=$rc)"; fi
limpia "$T"

echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
