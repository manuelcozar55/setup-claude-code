#!/usr/bin/env bash
# test_settings_template.sh — contrato de la plantilla kit/claude/settings.json: registra los hooks
# del estado de proyecto (nucleo.md), limita la retención de transcripts, fija la ventana del airbag
# y no arrastra restos de LangSmith ni de un proxy (ANTHROPIC_BASE_URL). Solo jq, sin red.
set -u
S="${1:-$(dirname "$0")/../claude/settings.json}"
FAIL=0
ok() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (esperado '$3', sale '$2')"; FAIL=1; fi; }
q() { jq -r "$1" "$S" 2>/dev/null; }
# Comando registrado para un hook, por evento y matcher ("" = sin matcher).
cmd() { q "[.hooks.$1[]? | select((.matcher // \"\") == \"$2\") | .hooks[].command] | join(\" \")"; }

ok "JSON válido" "$(jq empty "$S" 2>/dev/null && echo si)" si
ok "SessionStart startup|clear|resume → session-start-clear.sh" "$(cmd SessionStart 'startup|clear|resume' | command grep -c 'hooks/session-start-clear.sh')" 1
ok "SessionStart compact → session-start-compact.sh" "$(cmd SessionStart compact | command grep -c 'hooks/session-start-compact.sh')" 1
ok "PostToolUse \"\" (todas) → nucleo-nudge.sh" "$(cmd PostToolUse '' | command grep -c 'hooks/nucleo-nudge.sh')" 1
ok "nudge con timeout ≤ 5 s (camino caliente)" "$(q '[.hooks.PostToolUse[].hooks[] | select(.command|test("nucleo-nudge")) | .timeout <= 5] | (length > 0 and all)')" true
ok "Stop → stop-context-gauge.sh" "$(cmd Stop '' | command grep -c 'hooks/stop-context-gauge.sh')" 1
ok "un solo PreCompact" "$(q '.hooks.PreCompact | length')" 1
ok "PreCompact → pre-compact.sh" "$(q '.hooks.PreCompact[0].hooks[0].command' | command grep -c 'hooks/pre-compact.sh')" 1
ok "cleanupPeriodDays = 14" "$(q '.cleanupPeriodDays')" 14
ok "env fija CLAUDE_CODE_AUTO_COMPACT_WINDOW (entero)" "$(q '.env.CLAUDE_CODE_AUTO_COMPACT_WINDOW // "" | test("^[0-9]+$")')" true
ok "sin CLAUDE_AUTOCOMPACT_PCT_OVERRIDE (es un hook de test)" "$(q '.env | has("CLAUDE_AUTOCOMPACT_PCT_OVERRIDE")')" false
ok "sin ANTHROPIC_BASE_URL" "$(q '.env | has("ANTHROPIC_BASE_URL")')" false
ok "sin restos de LangSmith" "$(command grep -ci 'langsmith' "$S")" 0
ok "allow sin comodines que ejecutan código (uv tool, rtk, graphify, npx…)" "$(q '[.permissions.allow[]? | select(test("^Bash\\((uv tool|uv run|uvx|rtk|graphify|npx|pnpm dlx|pnpm exec|python3?|node|bash|sh) \\*\\)$"))] | join(" ")')" ""
ok "todo hook registrado existe en el kit" "$(q '.hooks[][].hooks[].command' | command grep -o 'hooks/[A-Za-z0-9_.-]*' | sort -u \
  | while read -r h; do [ -f "$(dirname "$S")/$h" ] || echo "$h"; done)" ""
ok "sin smart_approve en el settings (eliminado, decisión 3 del plan v3)" "$(command grep -c 'smart_approve' "$S")" 0
ok "cadena PreToolUse/Bash = los cinco guards bash, en orden" "$(q '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command | capture("hooks/(?<n>[a-z-]+)\\.sh").n] | join(" ")')" "block-dangerous-commands branch-guard destructive-guard secret-guard bash-write-guard"
ok "deny del kit intactos aunque la política gestionada los repita (decisión 2)" "$(q '[.permissions.deny[] | select(. == "Bash(rm -rf /*)" or . == "Bash(rm -rf ~/*)" or . == "Bash(git push --force *)")] | length')" 3
exit $FAIL
