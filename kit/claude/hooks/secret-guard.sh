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
# Lo que separa "no hay comando que revisar" de "no he podido leer el comando" NO es que
# la salida venga vacia: es el CODIGO DE SALIDA de jq. Sin jq (rc=127) la sustitucion
# dejaba COMMAND vacia, el `[[ -z ]]` de abajo lo confundia con el primer caso y este
# guard PERMITIA en silencio justo lo que con jq bloquea. rc=0 con salida vacia sigue
# permitiendo (un evento que no es Bash no trae .tool_input.command, y ahi permitir es
# correcto); rc!=0 significa que el guard esta ciego, y un guard ciego no puede autorizar.
# Se bloquea con exit 2 + stderr: el mismo protocolo que usan los checks de abajo, y el
# unico que no necesita jq para emitirse.
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); JQ_RC=$?
if [[ "$JQ_RC" -ne 0 ]]; then
  echo "BLOCKED: cannot read the hook input with jq (rc=$JQ_RC: jq missing from PATH, or input that is not readable JSON)." >&2
  echo "secret-guard.sh will not allow a command it could not inspect. Install jq, or remove this hook deliberately." >&2
  exit 2
fi
[[ -z "$COMMAND" ]] && exit 0

# Anchored to (^|[;&|(]) so "cd x && git add key" and "(git add key)" don't
# evade the guard — a bare "^" only catches git add at the very start.
echo "$COMMAND" | grep -qE '(^|[;&|(])\s*git\s+add' || exit 0

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
