#!/usr/bin/env bash
# test_uninstall.sh — uninstall.sh (raiz del repo) restaura el backup mas
# reciente, soportando los dos origenes que produce este kit: los backups
# internos de kit/install.sh y los ZIP de scripts/backup.sh.
#
# --dry-run (el modo por defecto) nunca toca nada -- se comprueba con un
# checksum del directorio antes/despues, no solo "mirando" la salida.
# --apply restaura de verdad. La falsabilidad la aporta el caso del ZIP con
# checksum invalido: si uninstall.sh no verificara nada, este caso pasaria.
#
# Cada caso usa su propio HOME temporal (no solo CLAUDE_HOME): uninstall.sh
# delega en scripts/backup.sh para su backup de seguridad, y ese script usa
# mas rutas derivadas de $HOME (BUCLE_DIR, CLAUDE_JSON) que hay que aislar
# para no arrastrar estado real de la maquina a un test.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$HERE/../.."
UNINSTALL="$REPO/uninstall.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

# Checksum recursivo de un directorio: contenido + rutas relativas.
tree_checksum() {
  ( cd "$1" && find . -type f -exec sha256sum {} + | LC_ALL=C sort | sha256sum | cut -d' ' -f1 )
}

# ---------------------------------------------------------- entorno comun
setup_home() {  # $1 = nombre del HOME temporal
  local h="$tmp/$1"
  mkdir -p "$h"
  printf '%s\n' "$h"
}

# ================================================== Caso 1: --list ========
H1="$(setup_home home1)"
export HOME="$H1" CLAUDE_HOME="$H1/.claude" BACKUP_DIR="$H1/backups"
out_empty="$(bash "$UNINSTALL" --list 2>&1)"
ck "$(echo "$out_empty" | grep -qic 'no hay backups' && echo y || echo n)" "y" "--list sin backups lo dice con claridad"

bash "$REPO/kit/install.sh" >/dev/null 2>&1
echo "MODIFICADO" >> "$CLAUDE_HOME/CLAUDE.md"
bash "$REPO/kit/install.sh" >/dev/null 2>&1   # genera un backup interno

out_list="$(bash "$UNINSTALL" --list 2>&1)"
ck "$(echo "$out_list" | grep -qc '^internal' && echo y || echo n)" "y" "--list enumera el backup interno con su tipo"
ck "$(echo "$out_list" | grep -Eqc '[0-9]{4}-[0-9]{2}-[0-9]{2}' && echo y || echo n)" "y" "--list muestra una fecha legible"
ck "$(echo "$out_list" | grep -Eqc '[0-9]+(B|KiB|MiB)' && echo y || echo n)" "y" "--list muestra un tamano legible"

# ============================================ Caso 2: --dry-run no toca nada
before="$(tree_checksum "$H1")"
out_dry="$(bash "$UNINSTALL" --dry-run 2>&1)"
after="$(tree_checksum "$H1")"
ck "$before" "$after" "--dry-run no modifica nada (checksum del arbol identico antes/despues)"
ck "$(echo "$out_dry" | grep -qic 'dry-run' && echo y || echo n)" "y" "--dry-run lo deja explicito en la salida"
ck "$(echo "$out_dry" | grep -qic -- '--apply' && echo y || echo n)" "y" "--dry-run indica como restaurar de verdad"

# Sin argumentos == --dry-run (el modo por defecto)
before2="$(tree_checksum "$H1")"
bash "$UNINSTALL" >/dev/null 2>&1
after2="$(tree_checksum "$H1")"
ck "$before2" "$after2" "sin argumentos (modo por defecto) tampoco modifica nada"

# El backup interno mas reciente contiene el CLAUDE.md de ANTES de la 2a
# instalacion (kit + "MODIFICADO"): eso es lo que --apply debe traer de
# vuelta, no el contenido actual (que ya es el kit "limpio" tras esa 2a
# instalacion).
latest_backup_dir="$(find "$CLAUDE_HOME/backups" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort | tail -1)"
expected_restore="$(cat "$latest_backup_dir/CLAUDE.md")"
bash "$UNINSTALL" --apply >/tmp/uninstall_apply_out.$$.log 2>&1
apply_rc=$?
ck "$apply_rc" "0" "--apply sale con exit 0"
after_restore="$(cat "$CLAUDE_HOME/CLAUDE.md")"
ck "$([ "$expected_restore" = "$after_restore" ] && echo mismo || echo distinto)" "mismo" \
  "--apply restaura el CLAUDE.md del backup interno mas reciente (contenido MODIFICADO)"
ck "$(find "$BACKUP_DIR" -maxdepth 1 -name 'claude-state-*.zip' 2>/dev/null | wc -l | tr -d ' ')" "1" \
  "--apply hizo primero su propio backup de seguridad (ZIP en BACKUP_DIR)"
rm -f "/tmp/uninstall_apply_out.$$.log"

# ============================================ Caso 4: ZIP de scripts/backup.sh
H2="$(setup_home home2)"
export HOME="$H2" CLAUDE_HOME="$H2/.claude" BACKUP_DIR="$H2/backups"
bash "$REPO/kit/install.sh" >/dev/null 2>&1
bash "$REPO/scripts/backup.sh" >/dev/null 2>&1
echo "SERA_SOBREESCRITO" >> "$CLAUDE_HOME/CLAUDE.md"

out_dry_zip="$(bash "$UNINSTALL" --dry-run 2>&1)"
ck "$(echo "$out_dry_zip" | grep -qc '^zip$\|zip de scripts/backup.sh\|snapshot ZIP' && echo y || echo n)" "y" \
  "--dry-run identifica el origen ZIP cuando es el backup mas reciente"
ck "$(grep -qc SERA_SOBREESCRITO "$CLAUDE_HOME/CLAUDE.md" && echo y || echo n)" "y" "--dry-run (con ZIP) no toco el fichero real"

# scripts/backup.sh nombra el ZIP con granularidad de 1 segundo (sin PID ni
# aleatorio, a diferencia del STAMP de install.sh) y aborta si ya existe uno
# igual: el backup de seguridad que hace --apply antes de restaurar chocaria
# con el ZIP que se acaba de crear arriba si cayeran en el mismo segundo.
sleep 1
bash "$UNINSTALL" --apply >/dev/null 2>&1
ck "$(grep -qc SERA_SOBREESCRITO "$CLAUDE_HOME/CLAUDE.md" 2>/dev/null; echo $?)" "1" \
  "--apply (ZIP) restauro sobre el cambio no respaldado"

# ============================================ Caso 5: falsabilidad — ZIP con
# checksum invalido debe rechazarse (si esto pasara, la verificacion seria
# decorativa, como comprueba test_gitattributes.sh / test_exec_modes.sh con
# sus propios casos fabricados).
H3="$(setup_home home3)"
export HOME="$H3" CLAUDE_HOME="$H3/.claude" BACKUP_DIR="$H3/backups"
mkdir -p "$CLAUDE_HOME" "$BACKUP_DIR"
stage="$tmp/stage-bad"
mkdir -p "$stage/claude-state-bad/claude"
echo "hola" > "$stage/claude-state-bad/claude/CLAUDE.md"
echo "0000000000000000000000000000000000000000000000000000000000000  claude/CLAUDE.md" \
  > "$stage/claude-state-bad/MANIFEST.sha256"
( cd "$stage" && zip -qr "$BACKUP_DIR/claude-state-bad.zip" claude-state-bad )

set +e
out_bad="$(bash "$UNINSTALL" --dry-run 2>&1)"; rc_bad=$?
set -e
ck "$rc_bad" "1" "ZIP con checksum invalido: uninstall.sh NO restaura, sale con exit distinto de 0"
ck "$(echo "$out_bad" | grep -qic 'checksum' && echo y || echo n)" "y" "el motivo del rechazo se explica (checksum)"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
