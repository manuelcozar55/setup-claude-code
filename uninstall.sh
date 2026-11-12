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
# --kit es otra cosa: DESINSTALA el kit segun el manifiesto que install.sh --apply deja en
# $CLAUDE_HOME/.kit-manifest (sha256 + ruta). Borra lo que sigue con su suma, conserva y lista lo que la
# persona modifico, quita los enlaces del bindir solo si apuntan a $CLAUDE_HOME/bin y des-fusiona de
# settings.json lo que el kit anadio (hooks del kit, statusLine, marketplace, plugins, claves de env que
# conservan el valor del kit), dejando lo demas. Copia de settings.json en $CLAUDE_HOME/backups/ antes.
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
#   uninstall.sh --kit [--apply]   desinstala el kit (simulacro por defecto; ver arriba)
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

usage() {
  echo "uso: $0 [--list|--dry-run|--apply] [--from FICHERO]   (restaura un backup; no desinstala el kit)"
  echo "     $0 --kit [--dry-run|--apply]                      (desinstala el kit segun .kit-manifest)"
  echo "     $0 --kit --settings-plantilla [--apply]           (sin copia previa a la instalacion: quita de settings.json lo igual a la plantilla del kit)"
}
MODE="dry-run"; FROM=""; KIT_MODE=0; SETTINGS_PLANTILLA=0
while [ $# -gt 0 ]; do
  case "$1" in
    --list)    MODE="list" ;;
    --dry-run) MODE="dry-run" ;;
    --apply)   MODE="apply" ;;
    --kit)     KIT_MODE=1 ;;
    --settings-plantilla) SETTINGS_PLANTILLA=1 ;;
    --from)   [ -n "${2:-}" ] || die "--from exige un fichero ZIP o un directorio de backup"; FROM="$2"; shift ;;
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
  [ -n "$latest" ] || die "no hay ningun backup interno en $CLAUDE_HOME/backups (los ZIP de $BACKUP_DIR solo se restauran con --from FICHERO). Para quitar el kit: bash $HERE/uninstall.sh --kit --apply"
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

# ------------------------------------------------------------ desinstalar el kit
# jq de la des-fusion. Entradas: $kit (la plantilla, o {}), $pre (settings.json de antes de la primera
# instalacion, o null) y $names (scripts del kit: los del manifiesto mas los de la plantilla). Un hook es del
# kit con la misma regla que usa install.sh para fusionar: todo lo que su comando nombra es un script del kit
# o un interprete/envoltorio conocido. Sin $pre solo se tocan hooks, statusLine, marketplace, plugins y env
# (lo que el kit anade y se reconoce por su valor); con $pre tambien permisos y el resto de claves del kit.
read -r -d '' UNMERGE_JQ <<'JQ' || true
def propio: ("/" + .) as $t | any($names[]; . as $s | $t | endswith("/.claude/hooks/" + $s) or endswith("/.claude/sentinel/" + $s));
def del_kit: [(.command | strings // "") | splits(" +") | gsub("[\"\u0027]"; "") | select(length > 0)]
  | any(.[]; propio) and all(.[]; propio or startswith("-") or (sub(".*/"; "") | test("^(optional-hook\\.sh|python[0-9.]*|bash|sh)$")));
def undo_hooks:
  if (.hooks | type) == "object" then
    .hooks |= (with_entries(
        if (.value | type) == "array" then
          .value |= [.[] | if (type == "object" and (.hooks | type) == "array")
                           then (.hooks |= map(select((type == "object" and del_kit) | not))) | select(.hooks | length > 0)
                           else . end]
        else . end)
      | with_entries(select((.value | type) != "array" or (.value | length) > 0)))
    | if .hooks == {} then del(.hooks) else . end
  else . end;
def sin_pre($k): $pre == null or ($pre | has($k) | not);
def undo_map($k):
  if ($kit[$k] | type) == "object" and (.[$k] | type) == "object" then
    reduce ($kit[$k] | to_entries[]) as $e (.;
      if .[$k][$e.key] == $e.value and ($pre == null or ($pre[$k] // {} | has($e.key) | not)) then del(.[$k][$e.key]) else . end)
    | if .[$k] == {} and sin_pre($k) then del(.[$k]) else . end
  else . end;
def undo_mkt:
  if ($kit.extraKnownMarketplaces | type) == "object" and (.extraKnownMarketplaces | type) == "object" then
    reduce ($kit.extraKnownMarketplaces | keys[]) as $m (.;
      if .extraKnownMarketplaces | has($m) then
        if $pre != null and ($pre.extraKnownMarketplaces // {} | has($m)) then .extraKnownMarketplaces[$m] = $pre.extraKnownMarketplaces[$m]
        else del(.extraKnownMarketplaces[$m]) end
      else . end)
    | if .extraKnownMarketplaces == {} and sin_pre("extraKnownMarketplaces") then del(.extraKnownMarketplaces) else . end
  else . end;
def undo_perm:
  if $pre != null and (.permissions | type) == "object" then
    (($pre.permissions // {}) as $pp | ($kit.permissions // {}) as $kp |
      reduce ("allow", "deny") as $l (.;
        if (.permissions[$l] | type) == "array" then
          .permissions[$l] |= map(select(. as $x | ((($kp[$l] // []) | index($x)) == null) or ((($pp[$l] // []) | index($x)) != null)))
          | if .permissions[$l] == [] and ($pp | has($l) | not) then del(.permissions[$l]) else . end
        else . end)
      | if $pp | has("disableBypassPermissionsMode") then .permissions.disableBypassPermissionsMode = $pp.disableBypassPermissionsMode
        else del(.permissions.disableBypassPermissionsMode) end
      | if .permissions == {} and ($pre | has("permissions") | not) then del(.permissions) else . end)
  else . end;
def undo_resto:
  if $pre == null then . else
    reduce ($kit | keys[] | select(. as $k | ["hooks","env","permissions","extraKnownMarketplaces","enabledPlugins","statusLine"] | index($k) | not)) as $k (.;
      if .[$k] == $kit[$k] and ($pre | has($k) | not) then del(.[$k]) else . end) end;
undo_hooks
| if $kit.statusLine != null and .statusLine == $kit.statusLine and sin_pre("statusLine") then del(.statusLine) else . end
| undo_mkt | undo_map("enabledPlugins") | undo_map("env") | undo_perm | undo_resto
JQ

# Sin copia previa a la instalacion no se sabe que era de la persona. Lo que queda igual, valor a valor, a la
# plantilla: reglas de permisos identicas y claves escalares con el valor de la plantilla. Entrada: settings.json
# ya des-fusionado; $kit: la plantilla. LEFT_JQ lo enumera; STRIP_JQ lo quita.
read -r -d '' PLANT_DEFS <<'JQ' || true
def scal: type as $t | $t == "string" or $t == "number" or $t == "boolean";
def lista($o; $l): ($o.permissions // {}) | if type == "object" then (.[$l] // []) else [] end | if type == "array" then . else [] end;
def claves: $kit | to_entries[] | select(.key != "permissions" and (.value | scal)) | .key;
JQ
read -r -d '' PLANT_LEFT_JQ <<'JQ' || true
. as $cur | [
  (("allow", "deny") as $l | lista($kit; $l)[] as $r | select(lista($cur; $l) | index($r) != null) | "permissions.\($l): \($r)"),
  (claves as $k | select($cur[$k] == $kit[$k]) | "\($k): \($kit[$k])"),
  (select($kit.permissions.disableBypassPermissionsMode != null and $cur.permissions.disableBypassPermissionsMode == $kit.permissions.disableBypassPermissionsMode) | "permissions.disableBypassPermissionsMode: \($kit.permissions.disableBypassPermissionsMode)")
] | .[]
JQ
read -r -d '' PLANT_STRIP_JQ <<'JQ' || true
reduce ("allow", "deny") as $l (.;
  if (.permissions | type) == "object" and (.permissions[$l] | type) == "array"
  then .permissions[$l] -= lista($kit; $l) | if .permissions[$l] == [] then del(.permissions[$l]) else . end
  else . end)
| reduce claves as $k (.; if .[$k] == $kit[$k] then del(.[$k]) else . end)
| if (.permissions | type) == "object" and $kit.permissions.disableBypassPermissionsMode != null
     and .permissions.disableBypassPermissionsMode == $kit.permissions.disableBypassPermissionsMode
  then del(.permissions.disableBypassPermissionsMode) else . end
| if .permissions == {} then del(.permissions) else . end
JQ

kit_uninstall() {
  local apply=0 man="$CLAUDE_HOME/.kit-manifest" line sha rel p n real="" bk stamp tmpj newj names kitjson prejson
  local rm_list=() keep_list=() lk_rm=() lk_keep=() settings_unmerge=0 d plant=() plant_hint=""
  [ "$MODE" = apply ] && apply=1
  [ "$MODE" != list ] || die "--kit no se combina con --list"
  [ -z "$FROM" ] || die "--kit no se combina con --from"
  if [ ! -f "$man" ] && [ ! -e "$CLAUDE_HOME/.kit-version" ] && [ ! -e "$CLAUDE_HOME/.kit-settings-pre.json" ] \
     && [ ! -e "$CLAUDE_HOME/.kit-docs.sha256" ] && [ ! -e "$CLAUDE_HOME/hooks/branch-guard.sh" ] && [ ! -e "$CLAUDE_HOME/bin/handoff" ]; then
    echo "no hay kit instalado en $CLAUDE_HOME (ni manifiesto ni ficheros del kit): nada que desinstalar"
    return 0
  fi
  [ -f "$man" ] || die "hay ficheros del kit en $CLAUDE_HOME pero no $man: el kit no se instalo con una version que lo escriba (1.11 o posterior). Reinstala con bash $HERE/kit/install.sh --apply y repite, o restaura un backup con uninstall.sh (sin --kit)"
  command -v jq >/dev/null 2>&1 || die "uninstall --kit necesita jq"
  local localbin="$HOME/.local/bin"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    sha="${line%%  *}"; rel="${line#*  }"
    case "$rel" in
      "~bin/"*)
        n="${rel#\~bin/}"
        case "$n" in */*|"") continue ;; esac
        if [ -L "$localbin/$n" ] && [ "$(realpath -m -- "$localbin/$n")" = "$(realpath -m -- "$CLAUDE_HOME/bin/$n")" ]; then lk_rm+=("$n")
        elif [ -e "$localbin/$n" ] || [ -L "$localbin/$n" ]; then lk_keep+=("$n"); fi
        continue ;;
      /*|*..*) continue ;;
    esac
    p="$CLAUDE_HOME/$rel"
    if [ -L "$p" ]; then keep_list+=("$rel (enlace: no es del kit)")
    elif [ ! -e "$p" ]; then :
    elif [ "$(sha256sum "$p" | cut -d' ' -f1)" = "$sha" ]; then rm_list+=("$rel")
    else keep_list+=("$rel (modificado por ti)"); fi
  done < "$man"
  case " ${rm_list[*]:-} " in *" settings.json "*) ;; *) [ -f "$CLAUDE_HOME/settings.json" ] && settings_unmerge=1 ;; esac

  names="$(
    { while IFS= read -r line; do rel="${line#*  }"; case "$rel" in hooks/*/*|sentinel/*/*) ;; hooks/*|sentinel/*) echo "${rel##*/}" ;; esac; done < "$man"
      [ -f "$HERE/kit/claude/settings.json" ] && jq -r '[.hooks // {} | .. | .command? // empty | splits(" +") | select(test("\\.claude/(hooks|sentinel)/")) | sub(".*/"; "")] | .[]' "$HERE/kit/claude/settings.json"
      printf '%s\n' smart_approve.py preflight.sh stop-session-summary.sh
    } | sort -u | grep -v '^optional-hook.sh$' | jq -R . | jq -s -c .)"
  kitjson="$HERE/kit/claude/settings.json"; [ -f "$kitjson" ] || kitjson=""
  prejson="$CLAUDE_HOME/.kit-settings-pre.json"; [ -f "$prejson" ] || prejson=""

  tmpj="$(mktemp -d)"; trap 'rm -r "$tmpj"' RETURN
  newj="$tmpj/settings.json"
  if [ "$settings_unmerge" -eq 1 ]; then
    real="$CLAUDE_HOME/settings.json"; [ -L "$real" ] && real="$(readlink -f "$real")"
    if ! jq empty "$real" 2>/dev/null; then
      settings_unmerge=0; keep_list+=("settings.json (no es JSON valido: no se toca)")
    elif jq --argjson names "$names" --slurpfile k <(if [ -n "$kitjson" ]; then cat "$kitjson"; else echo '{}'; fi) \
         --slurpfile pr <(if [ -n "$prejson" ]; then cat "$prejson"; else echo null; fi) \
         '$k[0] as $kit | $pr[0] as $pre | '"$UNMERGE_JQ" "$real" > "$newj"; then
      if [ -n "$prejson" ] && [ "$(jq -S . "$newj")" = "$(jq -S . "$prejson")" ]; then cp "$prejson" "$newj"; fi
      if [ -z "$prejson" ] && [ -n "$kitjson" ]; then
        mapfile -t plant < <(jq -r --slurpfile k "$kitjson" '$k[0] as $kit | '"$PLANT_DEFS $PLANT_LEFT_JQ" "$newj")
        if [ "${#plant[@]}" -gt 0 ] && [ "$SETTINGS_PLANTILLA" -eq 1 ]; then
          if jq --slurpfile k "$kitjson" '$k[0] as $kit | '"$PLANT_DEFS $PLANT_STRIP_JQ" "$newj" > "$tmpj/s2.json"; then cp "$tmpj/s2.json" "$newj"
          else plant=(); keep_list+=("settings.json (--settings-plantilla fallo: no se toca)"); fi
        fi
      fi
    else
      settings_unmerge=0; keep_list+=("settings.json (la des-fusion fallo: no se toca)")
    fi
  fi

  echo "== uninstall --kit ($([ "$apply" -eq 1 ] && echo apply || echo 'dry-run: no se modifica nada')) sobre $CLAUDE_HOME =="
  echo "  se borrarian ${#rm_list[@]} ficheros del kit (su suma coincide con el manifiesto)"
  if [ "${#lk_rm[@]}" -gt 0 ]; then echo "  enlaces de $localbin que se quitarian: ${lk_rm[*]}"; fi
  if [ "${#lk_keep[@]}" -gt 0 ]; then echo "  enlaces de $localbin que NO se tocan (no apuntan a $CLAUDE_HOME/bin): ${lk_keep[*]}"; fi
  if [ "$settings_unmerge" -eq 1 ]; then
    echo "  settings.json: se des-fusiona lo del kit; cambios:"
    diff <(jq -S . "$real") <(jq -S . "$newj") | sed -n '1,40p' | sed 's/^/    /' || true
    if [ "${#plant[@]}" -gt 0 ] && [ "$SETTINGS_PLANTILLA" -eq 1 ]; then
      echo "  settings.json: --settings-plantilla quita ${#plant[@]} entradas iguales a la plantilla del kit:"
      printf '    %s\n' "${plant[@]}"
    elif [ "${#plant[@]}" -gt 0 ]; then
      echo "  settings.json: quedan ${#plant[@]} entradas iguales a la plantilla del kit; se conservan porque no hay copia previa"
      echo "  a la instalacion (.kit-settings-pre.json) y no se sabe si eran tuyas:"
      printf '    %s\n' "${plant[@]}"
      plant_hint="$(printf 'Para quitar de settings.json lo igual a la plantilla del kit:  bash %q --kit --settings-plantilla --apply' "$HERE/uninstall.sh")"
      echo "  $plant_hint"
      keep_list+=("settings.json: ${#plant[@]} entradas iguales a la plantilla del kit (ver arriba)")
    fi
  fi
  if [ "${#keep_list[@]}" -gt 0 ]; then
    echo "  se CONSERVAN (no coinciden con lo que instalo el kit):"
    printf '    %s\n' "${keep_list[@]}"
  fi
  if [ "$apply" -eq 0 ]; then
    echo
    printf 'Para desinstalar de verdad:  bash %q --kit --apply\n' "$HERE/uninstall.sh"
    return 0
  fi

  stamp="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo uninstall)-$$"
  bk="$CLAUDE_HOME/backups/uninstall-$stamp"
  mkdir -p "$bk"
  [ -f "$CLAUDE_HOME/settings.json" ] && cp -pL "$CLAUDE_HOME/settings.json" "$bk/settings.json"
  cp -p "$man" "$bk/.kit-manifest"
  ok "copia previa en $bk"
  for rel in "${rm_list[@]}"; do
    rm -f -- "$CLAUDE_HOME/$rel"
    d="$(dirname "$rel")"
    while [ "$d" != . ] && rmdir -- "$CLAUDE_HOME/$d" 2>/dev/null; do d="$(dirname "$d")"; done
  done
  for n in "${lk_rm[@]}"; do rm -f -- "${localbin:?}/$n"; done
  if [ "$settings_unmerge" -eq 1 ]; then cat "$newj" > "$real"; ok "settings.json des-fusionado"; fi
  rm -f -- "$man" "$CLAUDE_HOME/.kit-version" "$CLAUDE_HOME/.kit-settings-pre.json" "$CLAUDE_HOME/.kit-docs.sha256"
  ok "kit desinstalado: ${#rm_list[@]} ficheros borrados, ${#keep_list[@]} conservados"
  echo "  La copia de settings.json y del manifiesto esta en $bk"
  if [ -n "$plant_hint" ]; then
    echo "  settings.json conserva ${#plant[@]} entradas iguales a la plantilla del kit (sin copia previa no se sabe si eran tuyas)."
    echo "  $plant_hint"
  fi
}

if [ "$KIT_MODE" -eq 1 ]; then
  kit_uninstall
  exit 0
fi

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
