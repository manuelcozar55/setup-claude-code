#!/usr/bin/env bash
# Oracle for the read-only cross-repo gate verification (plan todo 23, Commit: N).
# GREEN iff the three consumed-contracts still bind the task-9 gate v2 surface
# (evidence_schema + gate_body_contract + min_producer_version) coherently with
# the real M producer. Read-only: asserts the observable contract, mutates nothing.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; RAIZ="$(cd "$HERE/../../.." && pwd)"
P="$RAIZ/kit/lib/profiles"
fail=0
for c in claude-stop-bridge codex-manual-gate copilot-manual-gate; do
  f="$P/$c.consumed-contract-v1.json"
  [ -f "$f" ] || { echo "FALTA $f"; fail=1; continue; }
  s="$(python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(d.get('evidence_schema'),d.get('gate_body_contract'),d.get('min_producer_version'))" "$f")"
  [ "$s" = "mch-gate-evidence-v2 2 0.2.0" ] || { echo "DERIVA $c: $s"; fail=1; }
done
[ "$fail" = 0 ] && echo "OK: los 3 puentes fijan gate v2 / contrato 2 / v>=0.2.0" || exit 1
