#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

export CLAUDE_HOME="$tmp/dot"
bash "$KIT/install.sh" >/dev/null 2>&1
set +e; bash "$KIT/doctor.sh" >/dev/null 2>&1; rc=$?; set -e
ck "$rc" "0" "doctor PASS sobre instalación limpia"

# Rompe un hook referenciado -> FAIL
rm -f "$CLAUDE_HOME/hooks/branch-guard.sh"
set +e; bash "$KIT/doctor.sh" >/dev/null 2>&1; rc=$?; set -e
ck "$rc" "1" "doctor FAIL con hook ausente"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
