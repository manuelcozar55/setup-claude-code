#!/usr/bin/env bash
# Oracle for task 24 extension: kill the two surviving mutants M2/M3
# (authority_incompatible, authority_untrusted). GREEN iff:
#   1. the shared helper defines both broken-authority constructors,
#   2. all three bridge suites build each real broken-authority state and
#      assert the bridge BLOCKS,
#   3. the full three-suite run reports 0 failed.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
H="$HERE/kit/lib/verify/mch_real_governed.sh"
grep -q 'mrg_build_authbreak' "$H" 2>/dev/null || { echo "helper sin mrg_build_authbreak"; fail=1; }
grep -q 'mrg_build_untrusted' "$H" 2>/dev/null || { echo "helper sin mrg_build_untrusted"; fail=1; }
for f in test_claude_stop_bridge test_codex_profile test_copilot_profile; do
  s="$HERE/kit/test/$f.sh"
  grep -q 'mrg_build_authbreak' "$s" 2>/dev/null || { echo "$f sin authbreak"; fail=1; }
  grep -q 'mrg_build_untrusted' "$s" 2>/dev/null || { echo "$f sin untrusted"; fail=1; }
  out="$(bash "$s" 2>&1 | tail -1)"
  echo "$out" | grep -qE '0 failed' || { echo "$f no verde: $out"; fail=1; }
done
[ "$fail" = 0 ] && echo "OK: mutantes M2/M3 muertos, tres suites verdes" || exit 1
