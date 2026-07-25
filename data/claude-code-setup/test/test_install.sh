#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

export CLAUDE_HOME="$tmp/dot"
bash "$KIT/install.sh" >/dev/null 2>&1
ck "$([ -f "$CLAUDE_HOME/CLAUDE.md" ] && echo y)" "y" "instala CLAUDE.md"
ck "$([ -f "$CLAUDE_HOME/settings.json" ] && echo y)" "y" "instala settings.json"
ck "$([ -x "$CLAUDE_HOME/hooks/branch-guard.sh" ] && echo y)" "y" "hook ejecutable"
ck "$([ -f "$CLAUDE_HOME/sentinel/sentinel_preflight.py" ] && echo y)" "y" "instala sentinel"

# Idempotencia + backup: modifica un fichero, reinstala, debe backupear y no romper
echo "MOD" >> "$CLAUDE_HOME/CLAUDE.md"
bash "$KIT/install.sh" >/dev/null 2>&1
ck "$(ls "$CLAUDE_HOME"/backups/*/CLAUDE.md 2>/dev/null | wc -l | tr -d ' ')" "1" "backup creado al reinstalar"
ck "$?" "0" "reinstalar no falla"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
