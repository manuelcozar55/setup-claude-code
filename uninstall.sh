#!/usr/bin/env bash
# uninstall.sh — restaura el backup mas reciente de Claude Code, soportando
# los dos origenes que este repo produce: los backups internos incrementales
# de kit/install.sh ($CLAUDE_HOME/backups/<STAMP>/, solo los ficheros que una
# reinstalacion sobreescribio) y los snapshots completos en ZIP de
# scripts/backup.sh ($BACKUP_DIR/claude-state-*.zip, con MANIFEST.sha256 y
# una raiz claude-state-<ts>/claude/...).
#
# Por defecto NO TOCA NADA (--dry-run): solo muestra que se restauraria.
# Restaurar de verdad exige --apply, y antes de escribir nada hace su propio
# backup del estado actual via scripts/backup.sh (nunca se destruye sin red).
#
# Uso:
#   uninstall.sh              (== --dry-run) muestra que se restauraria
#   uninstall.sh --list       enumera los backups disponibles, sin restaurar
#   uninstall.sh --dry-run    idem que sin argumentos, explicito
#   uninstall.sh --apply      restaura de verdad (con backup previo de seguridad)
#
# Overrides (igual que scripts/backup.sh):
#   CLAUDE_HOME  (def. $HOME/.claude)   BACKUP_DIR  (def. $HOME/backups)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/backups}"

die() { printf '\033[31mFAIL\033[0m %s\n' "$*" >&2; exit 1; }
ok()  { printf '\033[32m ok \033[0m %s\n' "$*"; }
inf() { printf '     %s\n' "$*"; }

# GNU/uutils usan sha256sum; macOS usa shasum -a 256. Igual que scripts/backup.sh.
if command -v sha256sum >/dev/null 2>&1; then
  sha_chk() { sha256sum -c "$@"; }
elif command -v shasum >/dev/null 2>&1; then
  sha_chk() { shasum -a 256 -c "$@"; }
else
  die "no hay sha256sum ni shasum: no se puede verificar el manifiesto"
fi

# date -d es GNU; date -r es BSD/macOS. Se intenta uno y se cae al otro.
# El epoch puede venir con fraccion de segundo (find -printf '%T@'); se
# recorta a segundos enteros porque ni 'date -d @N' en macOS ni 'date -r'
# aceptan fracciones.
fmt_date() {
  local epoch="${1%.*}"
  date -d "@$epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "epoch:$epoch"
}

MODE="dry-run"
case "${1:-}" in
  --list)    MODE="list" ;;
  --dry-run) MODE="dry-run" ;;
  --apply)   MODE="apply" ;;
  "")        : ;;
  *) die "uso: $0 [--list|--dry-run|--apply]" ;;
esac

# ------------------------------------------------------------ descubrimiento
# Cada linea: tipo|epoch|tamano-bytes|ruta. 'internal' son los directorios
# de $CLAUDE_HOME/backups/<STAMP>/; 'zip' son los snapshots de backup.sh.
# El epoch se toma con 'find -printf %T@' (precision de sub-segundo en
# GNU findutils), no con 'stat -c %Y' (solo segundo entero): dos backups
# internos creados en el mismo segundo (p.ej. dos reinstalaciones seguidas
# en un test) necesitan ese desempate para que "el mas reciente" sea correcto.
epoch_of() { find "$1" -maxdepth 0 -printf '%T@\n' 2>/dev/null || stat -f %m "$1"; }

list_internal_backups() {
  local d
  [ -d "$CLAUDE_HOME/backups" ] || return 0
  for d in "$CLAUDE_HOME/backups"/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    printf 'internal|%s|%s|%s\n' "$(epoch_of "$d")" \
      "$(du -sb "$d" 2>/dev/null | cut -f1 || du -sk "$d" | awk '{print $1*1024}')" "$d"
  done
}

list_zip_backups() {
  local z
  [ -d "$BACKUP_DIR" ] || return 0
  for z in "$BACKUP_DIR"/claude-state-*.zip; do
    [ -f "$z" ] || continue
    printf 'zip|%s|%s|%s\n' "$(epoch_of "$z")" \
      "$(stat -c %s "$z" 2>/dev/null || stat -f %z "$z")" "$z"
  done
}

all_backups() {  # mas reciente primero
  { list_internal_backups; list_zip_backups; } | sort -t'|' -k2 -rg
}

resolve_latest() {
  local latest
  latest="$(all_backups | head -1)"
  [ -n "$latest" ] || die "no hay ningun backup en \$CLAUDE_HOME/backups ($CLAUDE_HOME/backups) ni en \$BACKUP_DIR ($BACKUP_DIR)"
  printf '%s\n' "$latest"
}

# ----------------------------------------------------------------- --list
cmd_list() {
  local type epoch size path found=0
  while IFS='|' read -r type epoch size path; do
    found=1
    printf '%-9s %s  %8s  %s\n' "$type" "$(fmt_date "$epoch")" "$(numfmt --to=iec-i --suffix=B "$size" 2>/dev/null || echo "${size}B")" "$path"
  done < <(all_backups)
  if [ "$found" -eq 0 ]; then
    echo "No hay backups en \$CLAUDE_HOME/backups ($CLAUDE_HOME/backups) ni en \$BACKUP_DIR ($BACKUP_DIR)."
  fi
}

# ------------------------------------------------------- restauracion: internal
restore_internal_plan() {
  local dir="$1" f rel
  echo "  origen: backup interno de install.sh ($dir)"
  echo "  restauraria (solo los ficheros que ese backup contiene):"
  while IFS= read -r f; do
    rel="${f#"$dir"/}"
    printf '    %s  ->  %s/%s\n' "$f" "$CLAUDE_HOME" "$rel"
  done < <(find "$dir" -type f)
}

restore_internal_apply() {
  local dir="$1" f rel
  while IFS= read -r f; do
    rel="${f#"$dir"/}"
    mkdir -p "$CLAUDE_HOME/$(dirname "$rel")"
    cp -p "$f" "$CLAUDE_HOME/$rel"
    inf "restaurado: $rel"
  done < <(find "$dir" -type f)
}

# ------------------------------------------------------------- restauracion: zip
# Extrae a un temporal y, si hay MANIFEST.sha256, verifica antes de seguir.
# Imprime la ruta de la raiz extraida (claude-state-<ts>/) por stdout.
extract_and_verify_zip() {
  local zip="$1" tmp root
  tmp="$(mktemp -d)"
  unzip -qq "$zip" -d "$tmp" || { rm -rf "$tmp"; die "no se pudo extraer el ZIP: $zip"; }
  root="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -1)"
  [ -n "$root" ] || { rm -rf "$tmp"; die "el ZIP no tiene un directorio raiz: $zip"; }
  if [ -f "$root/MANIFEST.sha256" ]; then
    if ! ( cd "$root" && sha_chk MANIFEST.sha256 >/dev/null 2>&1 ); then
      rm -rf "$tmp"
      die "los checksums del ZIP NO coinciden ($zip): corrupto o manipulado, no se restaura"
    fi
    ok "checksums del ZIP verificados: $zip" >&2
  fi
  printf '%s\n' "$root"
}

restore_zip_plan() {
  local zip="$1" root
  echo "  origen: snapshot ZIP de scripts/backup.sh ($zip)"
  root="$(extract_and_verify_zip "$zip")"
  echo "  restauraria: $root/claude/  ->  $CLAUDE_HOME/"
  [ -f "$root/claude.json" ] && echo "  restauraria: $root/claude.json  ->  \$HOME/.claude.json"
  rm -rf "${root%/*}"
}

restore_zip_apply() {
  local zip="$1" root
  root="$(extract_and_verify_zip "$zip")"
  mkdir -p "$CLAUDE_HOME"
  cp -a "$root/claude/." "$CLAUDE_HOME/"
  ok "restaurado $CLAUDE_HOME desde $root/claude/"
  if [ -f "$root/claude.json" ]; then
    cp -p "$root/claude.json" "$HOME/.claude.json"
    ok "restaurado \$HOME/.claude.json"
  fi
  rm -rf "${root%/*}"
}

# ------------------------------------------------------- backup de seguridad
# Nunca se restaura sin red: antes de escribir nada de verdad, se respalda el
# estado actual con la misma herramienta que produce los ZIP que este script
# sabe restaurar (scripts/backup.sh), reutilizando su verificacion.
safety_backup() {
  if [ ! -d "$CLAUDE_HOME" ] || [ -z "$(find "$CLAUDE_HOME" -mindepth 1 -maxdepth 1 2>/dev/null)" ]; then
    echo "== \$CLAUDE_HOME vacio o inexistente: nada que respaldar antes de restaurar =="
    return 0
  fi
  if [ ! -f "$HERE/scripts/backup.sh" ]; then
    echo "==> aviso: no se encontro scripts/backup.sh; se omite el backup de seguridad previo" >&2
    return 0
  fi
  echo "== backup de seguridad del estado actual antes de restaurar =="
  CLAUDE_HOME="$CLAUDE_HOME" BACKUP_DIR="$BACKUP_DIR" bash "$HERE/scripts/backup.sh" \
    || die "fallo el backup de seguridad previo; abortando la restauracion (nada se ha tocado)"
}

case "$MODE" in
  list)
    cmd_list
    exit 0
    ;;
  dry-run)
    entry="$(resolve_latest)"
    IFS='|' read -r type epoch size path <<< "$entry"
    echo "== modo dry-run: no se modifica nada =="
    echo "backup mas reciente ($(fmt_date "$epoch")): $path"
    case "$type" in
      internal) restore_internal_plan "$path" ;;
      zip)      restore_zip_plan "$path" ;;
    esac
    echo
    echo "Para restaurar de verdad:  $0 --apply"
    exit 0
    ;;
  apply)
    entry="$(resolve_latest)"
    IFS='|' read -r type epoch size path <<< "$entry"
    echo "== restaurando desde ($(fmt_date "$epoch")): $path =="
    safety_backup
    case "$type" in
      internal) restore_internal_apply "$path" ;;
      zip)      restore_zip_apply "$path" ;;
    esac
    ok "restauracion completada desde $path"
    ;;
esac
