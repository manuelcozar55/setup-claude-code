#!/usr/bin/env bash
# test_backup_integrity.sh — backup con exclusion de secretos e integridad (task 16).
#
# F-11: el backup NO debe incluir .env ni ficheros de patron secreto, y el ZIP
#       debe nacer 0600 (no world-readable).
# F-21: restore EXIGE manifiesto; sin el, falla en cerrado sin escribir.
# Ademas: install->backup->restore devuelve exactamente los bytes y modos de
# los ficheros no-secretos que son propiedad del usuario.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT_REPO="$HERE/../.."
BACKUP="$ROOT_REPO/scripts/backup.sh"
UNINSTALL="$ROOT_REPO/uninstall.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

command -v zip >/dev/null 2>&1   || { echo "SKIP: falta zip"; echo "== 0 passed, 0 failed =="; exit 0; }
command -v unzip >/dev/null 2>&1 || { echo "SKIP: falta unzip"; echo "== 0 passed, 0 failed =="; exit 0; }

CH="$tmp/claude"; mkdir -p "$CH"
BK="$tmp/backups"
printf 'config-real\n'  > "$CH/settings.json"; chmod 640 "$CH/settings.json"
printf 'instrucciones\n' > "$CH/CLAUDE.md";    chmod 644 "$CH/CLAUDE.md"
# Secretos que NO deben viajar.
printf 'ANTHROPIC_API_KEY=sk-secreto\n' > "$CH/.env"
mkdir -p "$CH/agents"; printf 'agente\n' > "$CH/agents/one.md"; chmod 600 "$CH/agents/one.md"

# ---------------------------------------------------------------- backup
set +e
BACKUP_DIR="$BK" CLAUDE_HOME="$CH" BUCLE_DIR="$tmp/nada" CLAUDE_JSON="$tmp/nojson" \
  bash "$BACKUP" > "$tmp/backup.out" 2>&1
rc=$?
set -e
ck "$rc" "0" "backup.sh termina rc=0"

ZIP="$(find "$BK" -name 'claude-state-*.zip' | head -1)"
ck "$([ -n "$ZIP" ] && echo y || echo n)" "y" "backup produjo un ZIP"

# F-11 (modo): el ZIP no es legible por grupo/otros.
zmode="$(stat -c '%a' "$ZIP")"
ck "$(( 8#$zmode & 8#077 ))" "0" "ZIP sin bits de grupo/otros (0600), modo=$zmode"

# F-11 (contenido): .env ausente del ZIP.
listing="$(unzip -Z1 "$ZIP")"
ck "$(printf '%s\n' "$listing" | grep -c '/\.env$' || true)" "0" ".env NO viaja en el backup"
ck "$(printf '%s\n' "$listing" | grep -c 'settings\.json$' || true)" "1" "settings.json si viaja"

# ---------------------------------------------------------------- restore F-21
# Un ZIP sin MANIFEST debe rechazarse. Se fabrica uno benigno sin manifiesto.
BADZIPDIR="$tmp/bad"; mkdir -p "$BADZIPDIR/claude-state-000/claude"
printf 'x\n' > "$BADZIPDIR/claude-state-000/claude/settings.json"
BADZIP="$BK/claude-state-99999999-000000.zip"
( cd "$BADZIPDIR" && zip -qr "$BADZIP" "claude-state-000" )

# Aislar el HOME de restore para no tocar nada real; apuntamos al ZIP malo
# haciendolo el mas reciente.
touch "$BADZIP"
CH2="$tmp/claude2"; mkdir -p "$CH2"; printf 'previo\n' > "$CH2/keep.txt"
set +e
BACKUP_DIR="$BK" CLAUDE_HOME="$CH2" bash "$UNINSTALL" --apply > "$tmp/restore.out" 2>&1
rc=$?
set -e
ck "$([ "$rc" -ne 0 ] && echo y || echo n)" "y" "restore rechaza ZIP sin manifiesto (rc!=0)"
ck "$(cat "$CH2/keep.txt")" "previo" "restore no piso el estado previo al fallar"
rm -f "$BADZIP"

# ---------------------------------------------- round-trip bytes y modos exactos
# Dir de backup dedicado con UN SOLO ZIP (el bueno): el restore resuelve "el mas
# reciente", y con varios ZIPs del mismo segundo el desempate por mtime es
# indeterminado (test flaky). Aislar garantiza que se restaura el que se creo.
BK2="$tmp/backups-rt"; mkdir -p "$BK2"
cp "$ZIP" "$BK2/"
CH3="$tmp/claude3"; mkdir -p "$CH3"
set +e
BACKUP_DIR="$BK2" CLAUDE_HOME="$CH3" bash "$UNINSTALL" --apply > "$tmp/restore2.out" 2>&1
rc=$?
set -e
ck "$rc" "0" "restore desde ZIP con manifiesto termina rc=0"
ck "$(cat "$CH3/settings.json" 2>/dev/null)" "config-real" "restore: bytes exactos de settings.json"
ck "$(stat -c '%a' "$CH3/settings.json" 2>/dev/null)" "640" "restore: modo exacto de settings.json"
ck "$(stat -c '%a' "$CH3/agents/one.md" 2>/dev/null)" "600" "restore: modo exacto de agents/one.md"
ck "$([ -e "$CH3/.env" ] && echo presente || echo ausente)" "ausente" "restore: el secreto no reaparece (no estaba en el backup)"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
