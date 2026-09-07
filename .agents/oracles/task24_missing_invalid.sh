#!/usr/bin/env bash
# Oracle for task 24 closure: kill the two surviving mutants M5/M7
# (invalid_state, authority_missing). GREEN iff:
#   1. the shared helper defines both real-state constructors,
#   2. all three bridge suites build each real state and assert the bridge
#      BLOCKS (exit 2 / decision block) against the REAL producer,
#   3. the full three-suite run reports 0 failed.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
H="$HERE/kit/lib/verify/mch_real_governed.sh"
grep -q 'mrg_build_invalid_state' "$H" 2>/dev/null || { echo "helper sin mrg_build_invalid_state"; fail=1; }
grep -q 'mrg_build_authority_missing' "$H" 2>/dev/null || { echo "helper sin mrg_build_authority_missing"; fail=1; }
for f in test_claude_stop_bridge test_codex_profile test_copilot_profile; do
  s="$HERE/kit/test/$f.sh"
  grep -q 'mrg_build_invalid_state' "$s" 2>/dev/null || { echo "$f sin invalid_state"; fail=1; }
  grep -q 'mrg_build_authority_missing' "$s" 2>/dev/null || { echo "$f sin authority_missing"; fail=1; }
  out="$(bash "$s" 2>&1 | tail -1)"
  echo "$out" | grep -qE '0 failed' || { echo "$f no verde: $out"; fail=1; }
done
[ "$fail" = 0 ] && echo "OK: mutantes M5/M7 muertos, tres suites verdes" || exit 1
