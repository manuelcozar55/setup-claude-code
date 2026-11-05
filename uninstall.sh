#!/usr/bin/env bash
# uninstall.sh — RESTAURA un backup de Claude Code (no desinstala el kit: sus
# ficheros se quedan en $CLAUDE_HOME; solo se devuelve lo que la instalacion
# sobreescribio). Soporta los dos origenes que este repo produce: los backups
# internos incrementales de kit/install.sh ($CLAUDE_HOME/backups/<STAMP>/, solo
# los ficheros que una reinstalacion sobreescribio) y los snapshots completos en
# ZIP de scripts/backup.sh (con MANIFEST.sha256 y una raiz claude-state-<ts>/claude/...).
# Sin --from solo se elige entre los backups internos: un ZIP es un snapshot
# completo, y restaurarlo por ser "el mas reciente" pisaria todo con un estado posterior.
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
#   uninstall.sh [--dry-run|--apply] --from FICHERO   restaura ese ZIP (o ese directorio de backup)
#   uninstall.sh --help       esta ayuda
#
# Overrides (igual que scripts/backup.sh):
#   CLAUDE_HOME  (def. $HOME/.claude)   BACKUP_DIR  (def. $HOME/backups)
# El claude.json se restaura AL LADO de $CLAUDE_HOME, no en $HOME.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CLAUDE_HOME="${CLAUDE_HOME%/}"
CLAUDE_HOME="${CLAUDE_HOME:-/}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/backups}"
# Destino del claude.json, derivado de $CLAUDE_HOME y no de $HOME: con el valor por
# defecto sale el mismo $HOME/.claude.json de siempre, pero con un CLAUDE_HOME temporal
# deja de pisar el fichero REAL de quien ejecuta el script (25 proyectos y el historial
# de sesiones dentro). No se hace sobreescribible: el derivarlo ES la proteccion.
CLAUDE_JSON="$(dirname "$CLAUDE_HOME")/.claude.json"
JSON_ENTRY=0

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

usage() { echo "uso: $0 [--list|--dry-run|--apply] [--from FICHERO]   (restaura un backup; no desinstala el kit)"; }
MODE="dry-run"; FROM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --list)    MODE="list" ;;
    --dry-run) MODE="dry-run" ;;
    --apply)   MODE="apply" ;;
    --from)    [ -n "${2:-}" ] || die "--from exige un fichero ZIP o un directorio de backup"; FROM="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "argumento no reconocido: $1" ;;
  esac
  shift
done

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
  if [ -n "$FROM" ]; then
    if [ -d "$FROM" ]; then printf 'internal|%s|0|%s\n' "$(epoch_of "$FROM")" "${FROM%/}"
    elif [ -f "$FROM" ]; then printf 'zip|%s|0|%s\n' "$(epoch_of "$FROM")" "$FROM"
    else die "no existe: $FROM"
    fi
    return
  fi
  latest="$(list_internal_backups | sort -t'|' -k2 -rg | head -1)"
  [ -n "$latest" ] || die "no hay ningun backup interno en $CLAUDE_HOME/backups (los ZIP de $BACKUP_DIR solo se restauran con --from FICHERO)"
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
  while IFS= read -r -d '' f; do
    rel="${f#"$dir"/}"
    mkdir -p "$CLAUDE_HOME/$(dirname "$rel")"
    cp -pT --remove-destination "$f" "$CLAUDE_HOME/$rel"
    inf "restaurado: $rel"
  done < <(find "$dir" -type f -print0)
}

# El snapshot guarda enlaces, no sus arboles ajenos. Resolver conflictos antes
# del backup y de cualquier copia evita restauraciones parciales por topologia.
restore_preflight() {
  local dir="$1" parent="$CLAUDE_HOME" f dst
  [ -d "$dir" ] && [ ! -L "$dir" ] || die "el origen debe ser un directorio real: $dir"
  while :; do
    [ ! -L "$parent" ] || die "directorio de destino enlazado: $parent"
    [ ! -e "$parent" ] || [ -d "$parent" ] || die "destino no es directorio: $parent"
    [ "$parent" != / ] && [ "$parent" != . ] || break
    parent="$(dirname "$parent")"
  done
  while IFS= read -r -d '' f; do
    dst="$CLAUDE_HOME${f#"$dir"}"
    if [ -d "$f" ] && [ ! -L "$f" ]; then
      [ ! -L "$dst" ] || die "directorio de destino enlazado: $dst"
      [ ! -e "$dst" ] || [ -d "$dst" ] || die "destino no es directorio: $dst"
    else
      [ ! -d "$dst" ] || [ -L "$dst" ] || die "no se reemplaza un directorio por un fichero o enlace: $dst"
    fi
  done < <(find "$dir" -mindepth 1 -print0)
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
    if { [ -s "$root/MANIFEST.sha256" ] || [ -n "$(find "$root" -type f ! -name MANIFEST.sha256 -print -quit)" ]; } \
      && ! ( cd "$root" && sha_chk MANIFEST.sha256 >/dev/null 2>&1 ); then
      rm -rf "$tmp"
      die "los checksums del ZIP NO coinciden ($zip): corrupto o manipulado, no se restaura"
    fi
    ok "checksums del ZIP verificados: $zip" >&2
  fi
  printf '%s\n' "$root"
}

# Un rollback de entrada tiene precedencia sobre el payload portable. Se
# valida antes de respaldar o escribir; los enlaces archivados nunca se leen.
restore_global_source() {
  local root="$1"
  JSON_SOURCE="$root/claude.json"; JSON_ENTRY=0
  if [ -e "$root/.claude-json-entry.json" ] || [ -L "$root/.claude-json-entry.json" ]; then
    if ! JSON_SOURCE=$(python3 - "$root" <<'PY'
import base64
import json
import os
from pathlib import Path
import re
import sys
import tempfile

try:
    root = Path(sys.argv[1])
    record = root / ".claude-json-entry.json"
    manifest = root / "MANIFEST.sha256"
    if record.is_symlink() or not record.is_file() or manifest.is_symlink() or not manifest.is_file():
        raise ValueError("registro y manifiesto deben ser ficheros regulares")
    # sha256sum separa por LF; otros separadores pueden ser bytes del nombre.
    covered = {
        match.group(1)
        for line in manifest.read_bytes().split(b"\n")
        if (match := re.fullmatch(rb"[0-9a-fA-F]{64} [ *](?:\./)?(.+)", line))
    }
    if record.name.encode("ascii") not in covered:
        raise ValueError("registro sin checksum")
    entry = json.loads(record.read_text(encoding="utf-8"))
    if not isinstance(entry, dict):
        raise ValueError("el registro debe ser un objeto")
    if entry == {"type": "file"}:
        payload = root / "claude.json"
        if payload.is_symlink() or not payload.is_file() or payload.name.encode("ascii") not in covered:
            raise ValueError("payload regular sin checksum")
        print(payload)
    elif set(entry) == {"type", "target_b64"} and entry["type"] == "link" and isinstance(entry["target_b64"], str):
        target = base64.b64decode(entry["target_b64"], validate=True)
        if not target or b"\0" in target:
            raise ValueError("destino de enlace invalido")
        temporary = os.fsencode(tempfile.mkdtemp(prefix=".json-entry-", dir=root)) + b"/entry"
        os.symlink(target, temporary)
        print(os.fsdecode(temporary))
    else:
        raise ValueError("tipo o campos del registro invalidos")
except (OSError, ValueError) as error:
    sys.exit(f"registro global invalido: {error}")
PY
    ); then
      die "registro de entrada global invalido; no se restaura"
    fi
    JSON_ENTRY=1
  elif [ -L "$JSON_SOURCE" ]; then
    JSON_ENTRY=1
  fi
}

restore_zip_plan() {
  local zip="$1" root
  echo "  origen: snapshot ZIP de scripts/backup.sh ($zip)"
  root="$(extract_and_verify_zip "$zip")"
  trap 'rm -rf "${root%/*}"' EXIT
  restore_global_source "$root"
  echo "  restauraria: $root/claude/  ->  $CLAUDE_HOME/"
  if [ -L "$JSON_SOURCE" ] || [ -f "$JSON_SOURCE" ]; then
    echo "  restauraria: $JSON_SOURCE  ->  $CLAUDE_JSON"
  fi
  rm -rf "${root%/*}"
  trap - EXIT
}

restore_zip_apply() {
  local root="$1"
  mkdir -p "$CLAUDE_HOME"
  cp -aT --remove-destination "$root/claude" "$CLAUDE_HOME"
  ok "restaurado $CLAUDE_HOME desde $root/claude/"
  if [ -L "$JSON_SOURCE" ] || [ -f "$JSON_SOURCE" ]; then
    cp -aT --remove-destination "$JSON_SOURCE" "$CLAUDE_JSON"
    ok "restaurado $CLAUDE_JSON"
  fi
}

# ------------------------------------------------------- backup de seguridad
# Nunca se restaura sin red: antes de escribir nada de verdad, se respalda el
# estado actual con la misma herramienta que produce los ZIP que este script
# sabe restaurar (scripts/backup.sh), reutilizando su verificacion.
# CLAUDE_JSON viaja tambien: sin el, backup.sh respaldaria su propio default
# ($HOME/.claude.json) y no el fichero que --apply esta a punto de sobreescribir.
safety_backup() {
  if [ ! -e "$CLAUDE_JSON" ] && [ ! -L "$CLAUDE_JSON" ] \
    && { [ ! -d "$CLAUDE_HOME" ] || [ -z "$(find "$CLAUDE_HOME" -mindepth 1 -maxdepth 1 2>/dev/null)" ]; }; then
    echo "== \$CLAUDE_HOME vacio o inexistente: nada que respaldar antes de restaurar =="
    return 0
  fi
  if [ ! -f "$HERE/scripts/backup.sh" ]; then
    die "no se encontro scripts/backup.sh; no se restaura sin backup de seguridad"
  fi
  echo "== backup de seguridad del estado actual antes de restaurar =="
  # Prefijo propio: el ZIP de seguridad no debe parecerse a un backup periodico ni competir con el.
  SCC_BACKUP_JSON_ENTRY="$JSON_ENTRY" BACKUP_PREFIX="claude-safety" CLAUDE_HOME="$CLAUDE_HOME" BACKUP_DIR="$BACKUP_DIR" CLAUDE_JSON="$CLAUDE_JSON" bash "$HERE/scripts/backup.sh" \
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
    printf 'Para restaurar de verdad:  bash %q --apply --from %q\n' "$HERE/uninstall.sh" "$path"
    exit 0
    ;;
  apply)
    entry="$(resolve_latest)"
    IFS='|' read -r type epoch size path <<< "$entry"
    # La raiz es una eleccion explicita; sus alias se conservan. CLAUDE_JSON
    # ya quedo ligado a la ruta elegida, antes de resolver el destino fisico.
    IFS= read -r -d '' CLAUDE_HOME < <(realpath -mz -- "$CLAUDE_HOME")
    echo "== restaurando desde ($(fmt_date "$epoch")): $path =="
    case "$type" in
      internal) restore_preflight "$path" ;;
      zip)
        root="$(extract_and_verify_zip "$path")"
        trap 'rm -rf "${root%/*}"' EXIT
        restore_global_source "$root"
        restore_preflight "$root/claude"
        if [ -L "$JSON_SOURCE" ] || [ -f "$JSON_SOURCE" ]; then
          # El payload escribe en el fichero global elegido, respaldado por
          # sus bytes. Una operacion de entrada conserva la ruta lexica.
          if [ "$JSON_ENTRY" -eq 0 ] && [ -L "$CLAUDE_JSON" ] && [ -f "$CLAUDE_JSON" ]; then
            IFS= read -r -d '' CLAUDE_JSON < <(realpath -ez -- "$CLAUDE_JSON")
          fi
          [ ! -d "$CLAUDE_JSON" ] || [ -L "$CLAUDE_JSON" ] \
            || die "no se reemplaza un directorio por claude.json: $CLAUDE_JSON"
        fi
        ;;
    esac
    safety_backup
    case "$type" in
      internal) restore_internal_apply "$path" ;;
      zip)      restore_zip_apply "$root" ;;
    esac
    ok "restauracion completada desde $path"
    ;;
esac
