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
ok "PreToolUse \"\" (todas) → nucleo-gate.sh" "$(cmd PreToolUse '' | command grep -c 'hooks/nucleo-gate.sh')" 1
ok "compuerta con timeout ≤ 5 s" "$(q '[.hooks.PreToolUse[].hooks[] | select(.command|test("nucleo-gate")) | .timeout <= 5] | (length > 0 and all)')" true
ok "Stop → stop-context-gauge.sh" "$(cmd Stop '' | command grep -c 'hooks/stop-context-gauge.sh')" 1
ok "un solo PreCompact" "$(q '.hooks.PreCompact | length')" 1
ok "PreCompact → pre-compact.sh" "$(q '.hooks.PreCompact[0].hooks[0].command' | command grep -c 'hooks/pre-compact.sh')" 1
ok "cleanupPeriodDays = 14" "$(q '.cleanupPeriodDays')" 14
ok "tui = fullscreen" "$(q '.tui')" fullscreen
ok "theme = dark" "$(q '.theme')" dark
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
ok "model sin sufijo [1m] (Opus 4.7+ trae 1M por defecto)" "$(q '.model')" opus
ok "allow reducido a lo genérico (sin dominios, graphify ni rtk personales)" "$(q '[.permissions.allow[]? | select(. != "Bash(uv tool list)")] | join(" ")')" ""
ok "ni oraculo ni handoff en allow (envuelven comandos arbitrarios)" "$(q '[.permissions.allow[]? | select(test("oraculo|handoff"))] | length')" 0
# shellcheck disable=SC2016 # $k y $m son variables de jq, no del shell
ok "todo plugin de terceros tiene su marketplace en extraKnownMarketplaces" "$(q '(.extraKnownMarketplaces // {} | keys) as $k | [.enabledPlugins | keys[] | split("@")[1] | select(. != "claude-plugins-official") | select(. as $m | $k | index($m) | not)] | join(" ")')" ""
ok "marketplace setup-claude-code apunta a manuelcozar55/setup-claude-code" "$(q '.extraKnownMarketplaces["setup-claude-code"].source.repo')" manuelcozar55/setup-claude-code
ok "sin plugins personales ni de contexto caro (codex, understand-anything, frontend-design)" "$(q '[.enabledPlugins | keys[] | select(test("^(codex|understand-anything|frontend-design)@"))] | length')" 0
# L4: el marketplace del kit va fijado al tag de esta version (source.ref de la fuente github, doc oficial
# code.claude.com/docs/en/plugins/marketplace-reference#marketplace-sources). Sin ref seguia la rama por defecto:
# un push a main del repo del marketplace llegaba a todos los companeros. Al subir VERSION hay que subir el ref.
V="$(cat "$(dirname "$S")/../../VERSION" 2>/dev/null)"
ok "marketplace setup-claude-code: source github" "$(q '.extraKnownMarketplaces["setup-claude-code"].source.source')" github
ok "marketplace setup-claude-code: ref = v<VERSION> (hoy v$V)" "$(q '.extraKnownMarketplaces["setup-claude-code"].source.ref')" "v$V"
exit $FAIL
