#!/usr/bin/env bash
# PreCompact hook — runs before context compaction
# Reads from stdin: {"hook_event_name":"PreCompact","trigger":"manual|auto","custom_instructions":"..."}
# El campo es `trigger`. `triggerReason` no existe en el binario (0 apariciones en 2.1.258):
# con ese nombre este hook imprimia siempre "(unknown)".
INPUT=$(cat)
TRIGGER=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('trigger','unknown'))" 2>/dev/null || echo "unknown")
echo "[PreCompact] Context compaction triggered ($TRIGGER). Current work state preserved." >&2
# Exit 0 = proceed normally
exit 0
