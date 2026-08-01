#!/usr/bin/env bash
# test_install_gitleaks.sh — install.sh detecta gitleaks si ya esta, y
# degrada con aviso (no rompe la instalacion) si no esta y no se pide
# instalarlo. No descarga nada por red: prueba solo la logica de deteccion
# y de degradacion, no la descarga real (eso se verifica a mano, ver
# kit/docs/07-verify.md).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

# --- Caso 1: gitleaks YA esta en PATH -> no se ofrece instalar -------------
FAKEBIN="$tmp/fakebin"; mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/gitleaks" <<'EOF'
#!/bin/sh
echo "gitleaks version 8.30.1 (stub)"
EOF
chmod +x "$FAKEBIN/gitleaks"

CLAUDE_HOME="$tmp/dot1"
out="$(PATH="$FAKEBIN:$PATH" CLAUDE_HOME="$CLAUDE_HOME" bash "$KIT/install.sh" < /dev/null 2>&1)"
rc=$?
ck "$rc" "0" "install.sh (gitleaks ya presente) sale con exit 0"
ck "$(echo "$out" | grep -qc 'gitleaks ya presente' && echo y || echo n)" "y" "reporta gitleaks ya presente, sin intentar instalar"

# --- Caso 2: gitleaks AUSENTE, no interactivo, sin GITLEAKS_AUTO_INSTALL ---
# PATH restringido a solo lo imprescindible para que install.sh corra, sin
# gitleaks en ningun sitio (ni PATH ni ~/.local/bin, via HOME temporal).
RESTRICTED="$tmp/restrictedbin"; mkdir -p "$RESTRICTED"
for b in bash uname date cp mkdir chmod cmp dirname basename sed sha256sum tar install curl mktemp cat; do
  p="$(command -v "$b" 2>/dev/null || true)"
  [ -n "$p" ] && ln -sf "$p" "$RESTRICTED/$b"
done
ln -sf /usr/bin/grep "$RESTRICTED/grep"
ln -sf /usr/bin/find "$RESTRICTED/find"
ln -sf /usr/bin/rm "$RESTRICTED/rm" 2>/dev/null || ln -sf /bin/rm "$RESTRICTED/rm"

FAKEHOME="$tmp/fakehome"; mkdir -p "$FAKEHOME"
CLAUDE_HOME2="$tmp/dot2"
set +e
out2="$(env -i HOME="$FAKEHOME" PATH="$RESTRICTED" CLAUDE_HOME="$CLAUDE_HOME2" bash "$KIT/install.sh" < /dev/null 2>&1)"
rc2=$?
set -e
ck "$rc2" "0" "install.sh (gitleaks ausente, sin pedirlo) NO rompe la instalacion"
ck "$(echo "$out2" | grep -qc 'gitleaks no instalado' && echo y || echo n)" "y" "avisa con claridad que la Capa 2 no puede activarse"
ck "$([ -f "$CLAUDE_HOME2/CLAUDE.md" ] && echo y || echo n)" "y" "la Capa 1 (resto de la instalacion) se completo igual"
ck "$([ -x "$FAKEHOME/.local/bin/gitleaks" ] && echo si || echo no)" "no" "no se forzo ninguna instalacion sin consentimiento"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
