#!/usr/bin/env bash
# scan-secrets.sh — Gate determinista de secretos/PII sobre el kit.
# Uso: scan-secrets.sh [DIR]   (default: carpeta del propio script)
# Exit 0 = limpio (PASS); 1 = hallazgos (FAIL).
set -euo pipefail
TARGET="${1:-$(cd "$(dirname "$0")" && pwd)}"
SELF="$(basename "$0")"

# Patrones de VALOR (no de nombre). Los nombres de variables (ANTHROPIC_API_KEY) son válidos.
PATTERNS=(
  'sk-[A-Za-z0-9_-]{20,}'
  'pplx-[A-Za-z0-9]{20,}'
  'gh[oprsu]_[A-Za-z0-9]{20,}'
  'AKIA[0-9A-Z]{16}'
  'xox[baprs]-[A-Za-z0-9-]{10,}'
  '-----BEGIN [A-Z ]*PRIVATE KEY'
  '/root/'
)
found=0
report() { echo "LEAK: $1"; found=1; }

while IFS= read -r -d '' f; do
  base="$(basename "$f")"
  # El propio escáner y su test documentan patrones: se excluyen.
  [ "$base" = "$SELF" ] && continue
  [ "$base" = "test_scan_secrets.sh" ] && continue
  for p in "${PATTERNS[@]}"; do
    if grep -InE "$p" "$f" >/dev/null 2>&1; then
      report "patrón /$p/ en $f"; grep -InE "$p" "$f" | head -2
    fi
  done
  # Emails que no sean de ejemplo/noreply = PII.
  if grep -InoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$f" 2>/dev/null \
       | grep -viE '@example\.(com|org)|noreply@|you@example|manuelcozar55@gmail\.com' >/dev/null 2>&1; then
    report "email real en $f"
    grep -InoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$f" \
      | grep -viE '@example\.(com|org)|noreply@|you@example|manuelcozar55@gmail\.com' | head -2
  fi
done < <(find "$TARGET" -type f -not -path '*/.git/*' -print0)

if [ "$found" -ne 0 ]; then echo "FAIL: secretos/PII detectados en $TARGET"; exit 1; fi
echo "PASS: sin secretos/PII en $TARGET"
