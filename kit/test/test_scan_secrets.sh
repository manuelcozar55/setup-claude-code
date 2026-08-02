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

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
