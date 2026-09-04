#!/usr/bin/env bash
# test_autonomy.sh — scripts/autonomy.sh como herramienta manual.
#
# El Stop hook ya no lo consulta: el criterio de exito vive en el journal de mch
# (T-006), que es append-only, en vez de en un fichero que el agente puede borrar.
# Lo que se mide aqui es solo el estado que el script guarda y devuelve; el
# comportamiento del gate lo mide kit/test/test_verify_gate.sh.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
AUT="$PWD/scripts/autonomy.sh"
pass=0; fail=0

ck() { if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1))
       else echo "NOT ok - $3 (obtenido '$1', esperado '$2')"; fail=$((fail+1)); fi; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export MCHARNESS_STATE="$T/state"

# --- 1. El oraculo debe ser inmune a la reescritura de comandos (M-001) -----
"$AUT" start --session g0 --oracle "pytest -q" --goal "x" >/dev/null 2>&1
ck "$?" "1" "rechaza un oraculo por nombre suelto (seria reescrito: MISTAKES M-001)"
"$AUT" start --session g0 --oracle "make test" --goal "x" >/dev/null 2>&1
ck "$?" "0" "acepta 'make ...'"
"$AUT" start --session g0b --oracle "/usr/bin/true" --goal "x" >/dev/null 2>&1
ck "$?" "0" "acepta una ruta absoluta"
"$AUT" stop --session g0 >/dev/null 2>&1; "$AUT" stop --session g0b >/dev/null 2>&1

# --- 2. Presupuesto de intentos --------------------------------------------
"$AUT" start --session g1 --oracle "/bin/false" --goal "x" --max-repairs 2 >/dev/null
"$AUT" attempt --session g1 >/dev/null 2>&1; ck "$?" "0" "intento 1 dentro del presupuesto"
"$AUT" attempt --session g1 >/dev/null 2>&1; ck "$?" "0" "intento 2 dentro del presupuesto"
"$AUT" attempt --session g1 >/dev/null 2>&1; ck "$?" "1" "intento 3 agota el presupuesto de 2"
"$AUT" stop --session g1 >/dev/null

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ] || exit 1
