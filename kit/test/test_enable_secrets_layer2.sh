#!/usr/bin/env bash
# test_enable_secrets_layer2.sh — `install.sh --enable-secrets-layer2` activa
# core.hooksPath SOLO en el repo git desde el que se invoca explicitamente,
# nunca de forma automatica ni en repos que el usuario no ha nombrado.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

export CLAUDE_HOME="$tmp/dot"
bash "$KIT/install.sh" < /dev/null >/dev/null 2>&1

# --- install.sh normal NUNCA toca core.hooksPath por su cuenta -------------
NAMED="$tmp/named-repo"; mkdir -p "$NAMED"; git -C "$NAMED" init -q
( cd "$NAMED" && bash "$KIT/install.sh" < /dev/null >/dev/null 2>&1 )
hp="$(git -C "$NAMED" config core.hooksPath 2>/dev/null || echo '(vacio)')"
ck "$hp" "(vacio)" "install.sh normal no toca core.hooksPath aunque corra dentro de un repo"

# --- --enable-secrets-layer2 activa la Capa 2 SOLO en el repo indicado ----
( cd "$NAMED" && bash "$KIT/install.sh" --enable-secrets-layer2 < /dev/null >/dev/null 2>&1 )
rc=$?
ck "$rc" "0" "--enable-secrets-layer2 sale con exit 0 dentro de un repo con el kit instalado"
ck "$(git -C "$NAMED" config core.hooksPath)" "$CLAUDE_HOME/hooks/git" "activa core.hooksPath al hook instalado, en ESE repo"

# --- Otro repo, no nombrado, no se toca ------------------------------------
OTHER="$tmp/other-repo"; mkdir -p "$OTHER"; git -C "$OTHER" init -q
hp2="$(git -C "$OTHER" config core.hooksPath 2>/dev/null || echo '(vacio)')"
ck "$hp2" "(vacio)" "un repo no nombrado explicitamente queda sin tocar"

# --- Fuera de un repo git -> falla con mensaje claro, no crashea -----------
NOTGIT="$tmp/notgit"; mkdir -p "$NOTGIT"
set +e
out="$(cd "$NOTGIT" && bash "$KIT/install.sh" --enable-secrets-layer2 < /dev/null 2>&1)"
rc2=$?
set -e
ck "$rc2" "1" "--enable-secrets-layer2 fuera de un repo git falla (exit 1)"
ck "$(echo "$out" | grep -qc 'DENTRO del repo git' && echo y || echo n)" "y" "mensaje explica que hay que correrlo dentro del repo"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
