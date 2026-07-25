#!/bin/bash
# secret-guard.sh — Blocks git add of .env, credentials, private keys
# Source: yurukusa/claude-code-hooks (MIT)
# Protocol: exit 2 = block

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0

echo "$COMMAND" | grep -qE '^\s*git\s+add' || exit 0

# Block .env files (allow known-safe template variants: .env.example, .env.template, .env.sample, .env.dist)
if echo "$COMMAND" | grep -qiE 'git\s+add\s+.*\.env' && \
   ! echo "$COMMAND" | grep -qiE '\.env\.(example|template|sample|dist)'; then
  echo "BLOCKED: Staging .env file — add to .gitignore instead." >&2
  exit 2
fi

# Block credential/key files
if echo "$COMMAND" | grep -qiE 'git\s+add\s+.*(credentials|secret|\.pem|\.key|\.p12|\.pfx|\.jks|\.keystore)'; then
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
