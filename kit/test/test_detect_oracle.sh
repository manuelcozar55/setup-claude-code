#!/usr/bin/env bash
# Verifica scripts/detect-oracle.sh contra proyectos sinteticos.
# Nunca toca proyectos reales del usuario: todo ocurre en un temporal.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
DET="$PWD/scripts/detect-oracle.sh"
pass=0; fail=0

ck() { # ck <obtenido> <esperado> <descripcion>
  if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1))
  else echo "NOT ok - $3 (obtenido: '$1' | esperado: '$2')"; fail=$((fail+1)); fi
}

# Esta suite no llama a jq, pero scripts/detect-oracle.sh si: lo usa para leer los
# scripts de package.json. Sin jq, los tres casos de proyecto Node devolvian cadena
# vacia en vez de "pnpm test"/"yarn test"/"npm test" -- tres rojos que solo decian que
# faltaba una herramienta. Se omite declarandolo, como ya hacen otras diez suites
# de este repo.
if ! command -v jq >/dev/null 2>&1; then
  echo "skip - jq ausente: detect-oracle.sh lee los scripts de package.json con jq"
  echo "== 0 passed, 0 failed, 1 skipped =="; exit 0
fi

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

mk() { mkdir -p "$T/$1"; printf '%s' "$T/$1"; }

# --- 1. Makefile con target test gana a todo lo demas -----------------------
d=$(mk make-proj)
printf 'test:\n\techo hola\n' > "$d/Makefile"
printf '{"scripts":{"test":"jest"}}' > "$d/package.json"   # tambien hay node
ck "$("$DET" "$d" 2>/dev/null)" "make test" "Makefile con target test gana sobre package.json"

# --- 2. Makefile SIN target test no dispara ---------------------------------
d=$(mk make-notest)
printf 'build:\n\techo hola\n' > "$d/Makefile"
ck "$("$DET" "$d" 2>/dev/null)" "" "Makefile sin target 'test' no produce oraculo"

# --- 3. Node: elige el gestor segun el lockfile -----------------------------
d=$(mk node-pnpm)
printf '{"scripts":{"test":"vitest"}}' > "$d/package.json"; : > "$d/pnpm-lock.yaml"
ck "$("$DET" "$d" 2>/dev/null)" "pnpm test" "package.json + pnpm-lock -> pnpm test"

d=$(mk node-yarn)
printf '{"scripts":{"test":"vitest"}}' > "$d/package.json"; : > "$d/yarn.lock"
ck "$("$DET" "$d" 2>/dev/null)" "yarn test" "package.json + yarn.lock -> yarn test"

d=$(mk node-npm)
printf '{"scripts":{"test":"vitest"}}' > "$d/package.json"
ck "$("$DET" "$d" 2>/dev/null)" "npm test" "package.json sin lock -> npm test"

# --- 4. El placeholder de npm init NO es un oraculo -------------------------
d=$(mk node-placeholder)
printf '{"scripts":{"test":"echo \\"Error: no test specified\\" && exit 1"}}' > "$d/package.json"
ck "$("$DET" "$d" 2>/dev/null)" "" "el scripts.test por defecto de npm init no cuenta como oraculo"

# --- 5. Python: usa el venv DEL PROYECTO, por ruta absoluta -----------------
d=$(mk py-proj)
printf '[pytest]\n' > "$d/pytest.ini"
mkdir -p "$d/.venv/bin"; printf '#!/bin/sh\n' > "$d/.venv/bin/pytest"; chmod +x "$d/.venv/bin/pytest"
got="$("$DET" "$d" 2>/dev/null)"
ck "$got" "$d/.venv/bin/pytest -q" "pytest.ini + .venv del proyecto -> ruta absoluta al venv"
case "$got" in /*) r=abs ;; *) r=rel ;; esac
ck "$r" "abs" "el comando de pytest es ruta absoluta (inmune a la reescritura del hook, M-001)"

# --- 6. Config de pytest SIN venv: no se inventa un oraculo -----------------
# Este es el caso peligroso: caer al venv de herramientas daria rojo por ImportError
# y culparia al codigo de un fallo de entorno.
d=$(mk py-sinvenv)
printf '[pytest]\n' > "$d/pytest.ini"
ck "$("$DET" "$d" 2>/dev/null)" "" "config de pytest sin venv del proyecto -> NO emite oraculo"
# Se captura primero y se filtra despues: con 'set -o pipefail', $DET saliendo con 1
# (no encontro oraculo, que es lo correcto aqui) haria fallar el pipeline aunque el grep
# acertase. Es la segunda vez que este patron muerde -- ver MISTAKES.md M-003.
why_out="$("$DET" --why "$d" 2>&1)"
if printf '%s' "$why_out" | grep -q "no hay sensor"; then
  echo "ok - y explica que es 'no hay sensor', no 'da rojo'"; pass=$((pass+1))
else
  echo "NOT ok - deberia explicar la diferencia entre no-invocable y rojo"; fail=$((fail+1))
fi

# --- 7. Otros ecosistemas ---------------------------------------------------
d=$(mk rust); : > "$d/Cargo.toml"
ck "$("$DET" "$d" 2>/dev/null)" "cargo test" "Cargo.toml -> cargo test"
d=$(mk go); : > "$d/go.mod"
ck "$("$DET" "$d" 2>/dev/null)" "go test ./..." "go.mod -> go test"

# --- 8. Proyecto vacio: exit 1, sin inventar --------------------------------
d=$(mk vacio)
"$DET" "$d" >/dev/null 2>&1
ck "$?" "1" "proyecto sin marcadores -> exit 1 (no inventa un oraculo)"

# --- 9. Falsabilidad: el detector CAMBIA cuando cambia el proyecto ----------
# Sin esto, todos los checks de arriba podrian estar pasando por casualidad.
d=$(mk falsable)
before="$("$DET" "$d" 2>/dev/null)"
printf 'test:\n\ttrue\n' > "$d/Makefile"
after="$("$DET" "$d" 2>/dev/null)"
if [ "$before" != "$after" ] && [ "$after" = "make test" ]; then
  echo "ok - falsabilidad: anadir un Makefile con target test cambia el veredicto ('$before' -> '$after')"; pass=$((pass+1))
else
  echo "NOT ok - el detector no reacciona a un cambio real del proyecto"; fail=$((fail+1))
fi

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ] || exit 1
