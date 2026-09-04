#!/usr/bin/env bash
# test_install_gitleaks_checksum.sh — install.sh detecta un checksum de
# gitleaks que NO coincide con el fijado en el script, y lo trata como una
# señal potencial de ataque a la cadena de suministro: no rompe el resto de
# la instalación (dependencia opcional), pero deja una marca persistente en
# CLAUDE_HOME que doctor.sh puede leer despues, y el binario recibido NUNCA
# se instala. No descarga nada por red: se stubea curl para servir un
# tarball fabricado (no el real), de forma que el mismatch es determinista
# sin depender de que el hash fijado sea correcto o incorrecto.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

RESTRICTED="$tmp/restrictedbin"; mkdir -p "$RESTRICTED"
# `jq` va en la lista por la misma razon que en test_install_gitleaks.sh: install.sh lo exige en
# una puerta de dependencia y sin el aborta a proposito. Lo que aqui se mide es un checksum de
# gitleaks que no coincide, no la ausencia de jq.
for b in bash uname date cp mkdir chmod cmp dirname basename sed sha256sum tar install mktemp cat rm jq; do
  p="$(command -v "$b" 2>/dev/null || true)"
  [ -n "$p" ] && ln -sf "$p" "$RESTRICTED/$b"
done
ln -sf /usr/bin/grep "$RESTRICTED/grep"
ln -sf /usr/bin/find "$RESTRICTED/find"

# curl "falso": en vez de descargar, escribe un tarball fabricado (no el
# oficial) en el destino pedido con -o. Su sha256 no coincidira con el hash
# fijado en install.sh salvo colision, asi que dispara el mismatch siempre.
cat > "$RESTRICTED/curl" <<'EOF'
#!/bin/sh
out=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$out" ] && printf 'esto no es el binario real de gitleaks\n' > "$out"
exit 0
EOF
chmod +x "$RESTRICTED/curl"

FAKEHOME="$tmp/fakehome"; mkdir -p "$FAKEHOME"
CLAUDE_HOME="$tmp/dot"
set +e
out="$(env -i HOME="$FAKEHOME" PATH="$RESTRICTED" CLAUDE_HOME="$CLAUDE_HOME" GITLEAKS_AUTO_INSTALL=1 \
       bash "$KIT/install.sh" < /dev/null 2>&1)"
rc=$?
set -e

ck "$rc" "0" "install.sh NO muere por un checksum de gitleaks que no coincide (dependencia opcional)"
ck "$(echo "$out" | grep -qc 'ALERTA' && echo y || echo n)" "y" "avisa con una ALERTA distinguible del caso 'sin red'"
ck "$([ -f "$CLAUDE_HOME/.gitleaks-checksum-mismatch" ] && echo y || echo n)" "y" "deja una marca persistente en CLAUDE_HOME"
ck "$(grep -qc 'expected_sha256=' "$CLAUDE_HOME/.gitleaks-checksum-mismatch" 2>/dev/null && echo y || echo n)" "y" "la marca incluye el hash esperado"
ck "$([ -x "$FAKEHOME/.local/bin/gitleaks" ] && echo si || echo no)" "no" "el binario con checksum invalido NUNCA se instala"
ck "$([ -f "$CLAUDE_HOME/CLAUDE.md" ] && echo y || echo n)" "y" "el resto de la instalacion (Capa 1) se completo igual"

# doctor.sh debe reportar la marca como FAIL, para quien no vio la salida
# del instalador.
set +e
doctor_out="$(env -i HOME="$FAKEHOME" PATH="/usr/bin:/bin:$RESTRICTED" CLAUDE_HOME="$CLAUDE_HOME" bash "$KIT/doctor.sh" 2>&1)"
doctor_rc=$?
set -e
ck "$doctor_rc" "1" "doctor.sh sale con FAIL mientras la marca de mismatch exista"
ck "$(echo "$doctor_out" | grep -qc 'checksum de gitleaks no coincidio' && echo y || echo n)" "y" "doctor.sh reporta explicitamente el mismatch"

# Una instalacion posterior CON gitleaks ya presente limpia la marca (no deja
# basura permanente si el usuario lo resuelve instalando a mano).
FAKEBIN="$tmp/fakebin"; mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/gitleaks" <<'EOF'
#!/bin/sh
echo "gitleaks version 8.30.1 (stub)"
EOF
chmod +x "$FAKEBIN/gitleaks"
PATH="$FAKEBIN:$RESTRICTED" CLAUDE_HOME="$CLAUDE_HOME" bash "$KIT/install.sh" < /dev/null >/dev/null 2>&1
ck "$([ -f "$CLAUDE_HOME/.gitleaks-checksum-mismatch" ] && echo si || echo no)" "no" "la marca se limpia cuando gitleaks pasa a estar presente"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
