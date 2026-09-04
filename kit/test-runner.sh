#!/usr/bin/env bash
# test-runner.sh — corre una suite de kit/test/ para el target `test` del
# Makefile: muestra su salida en vivo (igual que antes) y la deja marcada en
# kit/test/.make-test.log para que kit/sumar-tests.sh sume el agregado real al
# final. Vive fuera de kit/test/ a proposito: el check de paridad CI/Makefile
# (kit/test/test_harness_structure.sh, "9) test_ci_paridad_con_el_Makefile")
# escanea el Makefile buscando 'kit/test/*.sh' y lo compara contra ci.yml; un
# wrapper con ese patron se contaria a si mismo como una suite mas que CI "no
# corre".
#
# pipefail es obligatorio aqui: sin el, `tee` (que casi nunca falla) taparia
# el codigo de salida real de la suite y `make test` seguiria de largo tras
# un fallo real.
set -o pipefail
suite="$1"
printf '### %s\n' "$suite" >> kit/test/.make-test.log
bash "$suite" 2>&1 | tee -a kit/test/.make-test.log
rc=$?
# El resumen que la suite imprime dice lo que la suite CREIA; el codigo de
# salida dice como acabo de verdad. Una suite que imprime "0 failed" y muere
# despues -un `set -e` en la limpieza, un timeout, un trap- se contaba como
# verde, porque el agregado solo leia la linea. Anotarlo aqui es lo que le
# permite a kit/sumar-tests.sh no fiarse de una sola de las dos senales.
printf '### rc=%s\n' "$rc" >> kit/test/.make-test.log
exit "$rc"
