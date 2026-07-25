#!/usr/bin/env bash
# PreCompact hook — runs before context compaction
# Reads from stdin: {"conversation": [...], "summary": "...", "triggerReason": "..."}
INPUT=$(cat)
TRIGGER=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('triggerReason','unknown'))" 2>/dev/null || echo "unknown")
echo "[PreCompact] Context compaction triggered ($TRIGGER). Current work state preserved." >&2
# Exit 0 = proceed normally
exit 0
