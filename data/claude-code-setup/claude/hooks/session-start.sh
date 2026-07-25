#!/usr/bin/env bash
# SessionStart hook — brief context reminder
MEMORY="$HOME/.claude/projects/$(echo "$PWD" | tr '/' '-')/memory/MEMORY.md"
if [ -f "$MEMORY" ]; then
  echo "[SessionStart] Memory loaded from: $MEMORY"
  head -20 "$MEMORY" 2>/dev/null
else
  echo "[SessionStart] No project memory found. Global: ~/.claude/CLAUDE.md active."
fi
