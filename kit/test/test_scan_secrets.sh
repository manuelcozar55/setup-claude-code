#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCAN="$HERE/../scan-secrets.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
check() { if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 (got $1 want $2)"; fail=$((fail+1)); fi; }

# Caso limpio -> PASS (exit 0)
mkdir -p "$tmp/clean"
# shellcheck disable=SC2016 # '$HOME' literal a proposito: el fixture prueba
# que un "$HOME" sin expandir en texto no dispara el scanner de secretos.
printf 'ANTHROPIC_API_KEY=your-key-here\nhome=%s/.claude\nmail: you@example.com\n' '$HOME' > "$tmp/clean/ok.txt"
set +e; bash "$SCAN" "$tmp/clean" >/dev/null 2>&1; rc=$?; set -e
check "$rc" "0" "kit limpio pasa"

# Caso con clave -> FAIL (exit 1)
mkdir -p "$tmp/dirty"
printf 'key=sk-ant-api03-%s\n' "$(printf 'A%.0s' {1..40})" > "$tmp/dirty/leak.txt"
set +e; bash "$SCAN" "$tmp/dirty" >/dev/null 2>&1; rc=$?; set -e
check "$rc" "1" "clave sk- detectada"

# Caso con ruta /root/ -> FAIL
mkdir -p "$tmp/root"; printf 'path=/root/.claude/x\n' > "$tmp/root/leak.txt"
set +e; bash "$SCAN" "$tmp/root" >/dev/null 2>&1; rc=$?; set -e
check "$rc" "1" "ruta /root detectada"

# Caso con email real (no example) -> FAIL
mkdir -p "$tmp/mail"; printf 'contact real.person@company.io\n' > "$tmp/mail/leak.txt"
set +e; bash "$SCAN" "$tmp/mail" >/dev/null 2>&1; rc=$?; set -e
check "$rc" "1" "email real detectado"

# Caso prosa kebab-case (no debe falso-positivar) -> PASS
mkdir -p "$tmp/kebab"; printf 'Proceso risk-mitigation-and-compliance-review y task-driven-development-workflow.\n' > "$tmp/kebab/ok.txt"
set +e; bash "$SCAN" "$tmp/kebab" >/dev/null 2>&1; rc=$?; set -e
check "$rc" "0" "prosa kebab-case no falso-positiva"

# Caso con la ruta del home de una persona concreta -> FAIL
# El defecto real que lo motiva: la copia de origen de sentinel habia sustituido /root/
# por el home literal de un usuario al cambiar de maquina, plantilla de allowlist incluida.
mkdir -p "$tmp/homedir"; printf 'allow: /home/juanperez/.claude/hooks/\n' > "$tmp/homedir/leak.txt"
set +e; bash "$SCAN" "$tmp/homedir" >/dev/null 2>&1; rc=$?; set -e
check "$rc" "1" "ruta del home de un usuario concreto detectada"

# Y los marcadores de posicion NO deben falso-positivar (ciuser lo usan los fixtures de CI)
mkdir -p "$tmp/homeph"; printf 'ej: /home/ciuser/x y /home/usuario/y y /home/*/z\n' > "$tmp/homeph/ok.txt"
set +e; bash "$SCAN" "$tmp/homeph" >/dev/null 2>&1; rc=$?; set -e
check "$rc" "0" "marcadores de posicion de home no falso-positivan"

# Dentro de un repo git, lo IGNORADO no se escanea; lo trackeado si.
# Por que se prueba: test_harness_structure.sh corre este escaner sobre la raiz, y antes
# daba rojo en la maquina de quien tuviera scratch en disco y verde en CI (clon limpio).
if command -v git >/dev/null 2>&1; then
  mkdir -p "$tmp/repo"
  git -C "$tmp/repo" init -q 2>/dev/null
  printf 'scratch/\n' > "$tmp/repo/.gitignore"
  mkdir -p "$tmp/repo/scratch"
  printf 'path=/root/.claude/x\n' > "$tmp/repo/scratch/ignorado.txt"
  set +e; bash "$SCAN" "$tmp/repo" >/dev/null 2>&1; rc=$?; set -e
  check "$rc" "0" "un fichero IGNORADO con un hallazgo no ensucia el resultado"
  printf 'path=/root/.claude/x\n' > "$tmp/repo/trackeado.txt"
  git -C "$tmp/repo" add trackeado.txt 2>/dev/null
  set +e; bash "$SCAN" "$tmp/repo" >/dev/null 2>&1; rc=$?; set -e
  check "$rc" "1" "el mismo hallazgo en un fichero TRACKEADO si falla (la exclusion no es un agujero)"
else
  echo "skip - git ausente: no se prueba la enumeracion consciente de git"
fi

# --- El nombre de la cuenta A SECAS, sin ruta delante ----------------------
# El patron /home/<cuenta>/ solo ve la cuenta cuando viene dentro de una ruta. En el
# journal de mcharness el nombre iba suelto, en un campo `actor`, y por eso ese fichero
# se dio por limpio 131 veces seguidas: el patron no PODIA coincidir. La ausencia de
# coincidencias solo vale si el patron puede coincidir.
CUENTA="$(id -un 2>/dev/null || echo "")"
mkdir -p "$tmp/cuenta"; printf 'actor: %s\n' "$CUENTA" > "$tmp/cuenta/journal.txt"
set +e; salida="$(bash "$SCAN" "$tmp/cuenta" 2>&1)"; rc=$?; set -e
if [ "${#CUENTA}" -ge 8 ]; then
  check "$rc" "1" "el nombre de la cuenta a secas se detecta"
else
  # Nombre corto: el escaner NO debe mirarlo (seria ruido), pero tampoco puede callarlo.
  check "$(printf '%s' "$salida" | grep -qi 'no se ha comprobado' && echo y || echo n)" "y" \
        "con una cuenta demasiado corta el escaner DICE que ese check no se ha hecho"
fi

# Falsabilidad, en la otra direccion: un nombre generico no puede enrojecer el arbol.
# 'runner' es el caso real -es la cuenta de GitHub Actions- y aparece dentro de
# kit/test-runner.sh: sin esta guarda, el gate saldria rojo en CI por un fichero propio.
mkdir -p "$tmp/generico"; printf 'bash kit/test-runner.sh\nusuario: runner\n' > "$tmp/generico/x.txt"
set +e; SCAN_SECRETS_CUENTA=runner bash "$SCAN" "$tmp/generico" >/dev/null 2>&1; rc=$?; set -e
check "$rc" "0" "un nombre de cuenta generico (runner) no enrojece un arbol que lo menciona"

# Y que el detector no aprueba por vacio: el mismo arbol con la cuenta real dentro si cae.
mkdir -p "$tmp/generico2"; printf 'bash kit/test-runner.sh\nusuario: %s\n' "$CUENTA" > "$tmp/generico2/x.txt"
set +e; bash "$SCAN" "$tmp/generico2" >/dev/null 2>&1; rc=$?; set -e
if [ "${#CUENTA}" -ge 8 ]; then
  check "$rc" "1" "falsabilidad: el mismo arbol con la cuenta real dentro SI cae"
fi

# --- El hueco que cede la excepcion de gitleaks -----------------------------
# claude/.gitleaks.toml exime del generic-api-key cualquier secreto que sea 64
# hex en minuscula, porque esa es la forma de las huellas que mch sella. El
# comentario de esa config promete que este escaner cubre lo que alli se cede:
# una credencial de 64 hex ASIGNADA en un fichero de config. Sin este caso, la
# promesa seria una frase.
HEX64=$(printf 'clave-sintetica-para-el-test' | sha256sum | cut -d" " -f1)
mkdir -p "$tmp/hex64"; printf 'API_KEY = %s\n' "$HEX64" > "$tmp/hex64/config.yaml"
set +e; bash "$SCAN" "$tmp/hex64" >/dev/null 2>&1; rc=$?; set -e
check "$rc" "1" "API_KEY con un valor de 64 hex en un .yaml se detecta"

# Control: la palabra sin valor detras es prosa, no una credencial.
mkdir -p "$tmp/hex64b"; printf 'exporta API_KEY antes de arrancar\nAPI_KEY no lleva valor aqui\n' > "$tmp/hex64b/notas.md"
set +e; bash "$SCAN" "$tmp/hex64b" >/dev/null 2>&1; rc=$?; set -e
check "$rc" "0" "mencionar API_KEY sin valor detras no enrojece"

# Y el journal de mch, que esta LLENO de 64 hex, no puede dispararlo: la clave
# de esas lineas es una ruta de fichero, no un nombre de credencial.
mkdir -p "$tmp/hex64c/.agents"
printf '{"event":"start","sensor_hashes":{"kit/test/test_scan_secrets.sh": "%s"}}\n' "$HEX64" > "$tmp/hex64c/.agents/journal.jsonl"
set +e; bash "$SCAN" "$tmp/hex64c" >/dev/null 2>&1; rc=$?; set -e
check "$rc" "0" "las huellas selladas en el journal no disparan el check de 64 hex"

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
