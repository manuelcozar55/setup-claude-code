#!/usr/bin/env bash
# Stop hook — append session summary to log
LOG_DIR="$HOME/.claude/session-logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/$(date +%Y-%m).log"
echo "--- Session ended: $(date '+%Y-%m-%d %H:%M') | cwd: $PWD ---" >> "$LOG"
echo "stop-session-summary: logged to $LOG"
