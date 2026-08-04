#!/usr/bin/env bash
# test_install_platform_gate.sh — la puerta de plataforma de install.sh
# aborta en no-Linux, con mensaje claro y SIN dejar nada a medias (no crea
# CLAUDE_HOME), y no interfiere con Linux/WSL2 real.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

# uname simulado -> "Darwin", para probar la puerta sin depender de la
# plataforma real donde corre este test.
FAKEBIN="$tmp/fakebin"; mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/uname" <<'EOF'
#!/bin/sh
echo "Darwin"
EOF
chmod +x "$FAKEBIN/uname"

export CLAUDE_HOME="$tmp/dot"
set +e
out="$(PATH="$FAKEBIN:$PATH" bash "$KIT/install.sh" < /dev/null 2>&1)"
rc=$?
set -e

ck "$rc" "1" "install.sh aborta (exit 1) en plataforma no-Linux"
ck "$(echo "$out" | grep -qc 'Plataforma no soportada' && echo y || echo n)" "y" "mensaje explica la politica"
ck "$([ -e "$CLAUDE_HOME" ] && echo existe || echo no)" "no" "no crea CLAUDE_HOME (nada a medias)"

# Camino feliz: uname real (Linux en CI) sigue instalando sin problema.
set +e; bash "$KIT/install.sh" < /dev/null >/dev/null 2>&1; rc2=$?; set -e
ck "$rc2" "0" "install.sh sigue funcionando en Linux real"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
