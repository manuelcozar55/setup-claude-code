#!/usr/bin/env bash
# Oracle for task 24: structural conformance + adversarial mutation matrix.
# GREEN iff the three deliverables are present:
#   1. the shared real-governed helper exists,
#   2. all three bridge suites source it AND exercise real rc0/rc1,
#   3. the surviving schema-only probe (task23_gate_contract_probe.sh) is retired.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
H="$HERE/kit/lib/verify/mch_real_governed.sh"
[ -f "$H" ] || { echo "FALTA helper $H"; fail=1; }
grep -q 'mrg_build_green' "$H" 2>/dev/null || { echo "helper sin mrg_build_green"; fail=1; }
grep -q 'mrg_build_red'   "$H" 2>/dev/null || { echo "helper sin mrg_build_red"; fail=1; }
for f in test_claude_stop_bridge test_codex_profile test_copilot_profile; do
  s="$HERE/kit/test/$f.sh"
  grep -q 'mch_real_governed.sh' "$s" 2>/dev/null || { echo "$f no sourcea el helper"; fail=1; }
  grep -q 'mrg_build_green' "$s" 2>/dev/null || { echo "$f sin real green"; fail=1; }
  grep -q 'mrg_build_red'   "$s" 2>/dev/null || { echo "$f sin real red"; fail=1; }
done
[ -e "$HERE/kit/lib/verify/task23_gate_contract_probe.sh" ] && { echo "la sonda schema-only sobrevive (no retirada)"; fail=1; }
[ "$fail" = 0 ] && echo "OK: cobertura real-gobernada presente y sonda schema-only retirada" || exit 1
