#!/bin/bash
# secret-guard.sh — Blocks git add of .env, credentials, private keys
# Source: yurukusa/claude-code-hooks (MIT)
# Protocol: exit 2 = block
#
# Capa 1 (name-only) of the two-layer secrets architecture: this hook decides
# from the shell command text alone, before the tool runs. Guessing what a
# shell command will do from PreToolUse text would require a real shell
# tokenizer + pathspec resolver + secret scanner, all in bash, within a hook
# time budget — and it would still only see the working tree, not what
# actually gets committed. That's why real content scanning lives in Capa 2
# instead: a `pre-commit` hook (hooks/git/pre-commit) that runs gitleaks over
# the staged index. See docs/05-security.md for the full rationale, and
# kit/test/test_guards.sh + kit/test/test_secret_content_gitleaks.sh for the
# regression coverage of both layers.
#
# No bare "secret" token: it used to match "secreto" as a substring (a false
# positive). Extensions are anchored to end-of-token, not end-of-string.

INPUT=$(cat)

# Fail-closed: sin jq no hay decision posible, y permitir en silencio apagaba toda la
# Capa 1 sin un mensaje. Denegar puede frenar trabajo legitimo, y por eso install.sh
# exige jq en una puerta de dependencia: llegar aqui sin el es una instalacion incompleta.
if ! command -v jq >/dev/null 2>&1; then
  echo "BLOCKED (fail-closed): falta jq en el PATH, asi que secret-guard no puede leer el comando." >&2
  echo "Instala jq (apt install jq) y reintenta." >&2
  exit 2
fi
if ! COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); then
  echo "BLOCKED (fail-closed): el payload de PreToolUse no es JSON parseable; secret-guard no puede leer el comando." >&2
  exit 2
fi
[[ -z "$COMMAND" ]] && exit 0

# Anchored to (^|[;&|(]) so "cd x && git add key" and "(git add key)" don't
# evade the guard — a bare "^" only catches git add at the very start.
# rc=1 is "not a git add" and we exit; rc>=2 is "the regex did not compile", which `|| exit 0`
# turned into a silent allow. Keep them apart: a broken filter must deny, not fall through.
echo "$COMMAND" | grep -qE '(^|[;&|(])\s*git\s+add'
rc_filter=$?
if [ "$rc_filter" -ge 2 ]; then
  echo "BLOCKED: secret-guard cannot evaluate the command (grep rc=$rc_filter)." >&2
  exit 2
fi
[ "$rc_filter" -eq 0 ] || exit 0

# Block .env files (allow known-safe template variants: .env.example, .env.template, .env.sample, .env.dist)
if echo "$COMMAND" | grep -qiE 'git\s+add\s+.*\.env' && \
   ! echo "$COMMAND" | grep -qiE '\.env\.(example|template|sample|dist)'; then
  echo "BLOCKED: Staging .env file — add to .gitignore instead." >&2
  exit 2
fi

# Block credential/key files by name (extensions anchored to end-of-token, not
# end-of-string: a token ends at whitespace, end of command, or a closing
# quote/paren, but NOT at "/" -- so ".p12" inside a directory name like
# bundle.p12/data still doesn't match. No bare "secret" token, it matched
# inside unrelated words like "secreto")
if echo "$COMMAND" | grep -qiE 'git\s+add\s+.*(\.pem|\.p12|\.pfx|\.jks|\.keystore|\.key|credentials\.json)([[:space:]]|$|['\''")])'; then
  echo "BLOCKED: Staging potential credential file." >&2
  echo "Command: $COMMAND" >&2
  exit 2
fi

# Block git add -A / git add . only when .env is NOT gitignored
if echo "$COMMAND" | grep -qE 'git\s+add\s+(-A|\.)' && [ -f ".env" ]; then
  if ! git check-ignore -q .env 2>/dev/null; then
    echo "BLOCKED: git add -A/. with untracked .env present — add to .gitignore first." >&2
    exit 2
  fi
fi

exit 0
