#!/usr/bin/env bash
# test_cockpit.sh — capas ejecutables del mod cockpit (kit/mods/cockpit):
#   1. tsc sobre una copia de lo VERSIONADO (como un clon limpio: el tsconfig no puede depender de nada generado).
#   2. contrato con el CLI real kit/claude/bin/handoff (sin claude, sin red).
#   3. claude plugin validate y claude plugin test (no cuestan dinero). Sin `claude`: SKIP anunciado, nunca verde.
# tsc: COCKPIT_TSC, o `tsc` del PATH, o `pnpm dlx typescript@5.6.3 tsc`. Sin ninguno: SKIP anunciado.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
MOD="$ROOT/kit/mods/cockpit"
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
pass=0; fail=0
check() { if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 (got $1 want $2)"; fail=$((fail+1)); fi; }
skip() { echo "SKIP - $1"; [ -z "${SCC_SKIP_LOG:-}" ] || echo "SKIP: $1 (test_cockpit.sh)" >> "$SCC_SKIP_LOG"; }

# ---- 1. tsc en un clon limpio del mod
copy="$tmp/clon"
mkdir -p "$copy"
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 && [ -n "$(git -C "$ROOT" ls-files kit/mods/cockpit)" ]; then
  (cd "$ROOT" && git ls-files -z kit/mods/cockpit | xargs -0 -I{} cp --parents {} "$copy")
else
  mkdir -p "$copy/kit/mods" && cp -R "$MOD" "$copy/kit/mods/"
fi
if [ -n "${COCKPIT_TSC:-}" ]; then read -r -a TSC <<<"$COCKPIT_TSC"
elif command -v tsc >/dev/null 2>&1; then TSC=(tsc)
elif command -v pnpm >/dev/null 2>&1 && timeout 120 pnpm dlx typescript@5.6.3 tsc --version >/dev/null 2>&1; then TSC=(pnpm dlx typescript@5.6.3 tsc)
else TSC=(); fi
if [ "${#TSC[@]}" -gt 0 ]; then
  set +e; (cd "$copy/kit/mods/cockpit" && "${TSC[@]}" -p . --noEmit >"$tmp/tsc.log" 2>&1); rc=$?; set -e
  [ "$rc" -eq 0 ] || head -20 "$tmp/tsc.log"
  check "$rc" "0" "tsc en un clon limpio del mod"
  # Falsabilidad: un error de tipos plantado tiene que dar rojo.
  printf 'export const planted: number = "x"\n' > "$copy/kit/mods/cockpit/hooks/planted.ts"
  set +e; (cd "$copy/kit/mods/cockpit" && "${TSC[@]}" -p . --noEmit >/dev/null 2>&1); rc=$?; set -e
  check "$([ "$rc" -ne 0 ] && echo rojo || echo verde)" "rojo" "falsabilidad: un error de tipos plantado da rojo"
else
  # En CI (COCKPIT_REQUIRE_TSC=1) la ausencia de tsc es un fallo, no un salto.
  if [ -n "${COCKPIT_REQUIRE_TSC:-}" ]; then check "sin tsc" "tsc" "hay un tsc con el que tipar el cockpit"
  else skip "tsc del cockpit: no hay tsc ni pnpm dlx (define COCKPIT_TSC)"; fi
fi

# ---- 2. contrato con el CLI real
# (se añade más abajo)

# ---- 3. claude plugin validate / test
if command -v claude >/dev/null 2>&1; then
  set +e
  claude plugin validate "$MOD" >"$tmp/validate.log" 2>&1; rcv=$?
  claude plugin test "$MOD" >"$tmp/test.log" 2>&1; rct=$?
  set -e
  [ "$rcv" -eq 0 ] || tail -20 "$tmp/validate.log"
  [ "$rct" -eq 0 ] || tail -30 "$tmp/test.log"
  check "$rcv" "0" "claude plugin validate"
  check "$rct" "0" "claude plugin test ($(grep -E '^ *[0-9]+ pass' "$tmp/test.log" | tr -d ' ' | head -1))"
else
  skip "claude plugin validate/test del cockpit: claude no esta en PATH"
fi

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
