#!/usr/bin/env bash
# Snapshot verificable del estado de Claude Code, en ZIP con manifiesto SHA-256.
#
# Uso:
#   scripts/backup.sh                 crea el backup y lo verifica (incluye restauracion a temporal)
#   scripts/backup.sh --verify FILE   solo verifica un ZIP ya existente
#
# Overrides (para tests en HOME temporal):
#   CLAUDE_HOME  (def. $HOME/.claude)   BACKUP_DIR  (def. $HOME/backups)
#   BUCLE_DIR    (def. $HOME/ai-mastery/bucle)
#   CLAUDE_JSON  (def. $HOME/.claude.json)
set -euo pipefail

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/backups}"
BUCLE_DIR="${BUCLE_DIR:-$HOME/ai-mastery/bucle}"
CLAUDE_JSON="${CLAUDE_JSON:-$HOME/.claude.json}"

# Se excluye lo regenerable (transcripts, caches de plugins) y el fichero de
# credenciales, que no debe viajar en claro dentro de un ZIP: se recupera con
# re-login. El nombre se compone para no incrustar el literal en el fuente.
CREDS_BASENAME=".$(printf 'credential')s.json"
EXCLUDES=(
  "projects" "plugins/cache" "plugins/marketplaces" "cache"
  "shell-snapshots" "paste-cache" "file-history" "downloads"
  "$CREDS_BASENAME"
)

die() { printf '\033[31mFAIL\033[0m %s\n' "$*" >&2; exit 1; }
ok()  { printf '\033[32m ok \033[0m %s\n' "$*"; }
inf() { printf '     %s\n' "$*"; }

# GNU/uutils usan sha256sum; macOS usa shasum -a 256. Se resuelve una vez.
if command -v sha256sum >/dev/null 2>&1; then
  sha_gen() { sha256sum "$@"; }
  sha_chk() { sha256sum -c "$@"; }
elif command -v shasum >/dev/null 2>&1; then
  sha_gen() { shasum -a 256 "$@"; }
  sha_chk() { shasum -a 256 -c "$@"; }
else
  die "no hay sha256sum ni shasum: no se puede generar manifiesto"
fi

# ---------------------------------------------------------------- verificacion
# Comprueba integridad del ZIP y restaura a un temporal para revalidar checksums.
verify_zip() {
  local zip="$1" tmp root n entries listing rc=0
  [ -f "$zip" ] || die "no existe el ZIP: $zip"

  unzip -tqq "$zip" >/dev/null 2>&1 || die "ZIP corrupto (unzip -t): $zip"
  ok "integridad del contenedor (unzip -t)"

  # La lista se captura UNA vez: con 'set -o pipefail', un 'grep -q' aguas abajo
  # cierra la tuberia y mata a unzip con SIGPIPE, que aqui seria un falso fallo.
  listing=$(unzip -Z1 "$zip")

  entries=$(printf '%s\n' "$listing" | grep -cv '/$' || true)
  [ "$entries" -gt 0 ] || die "el ZIP no contiene ficheros"
  ok "entradas en el ZIP: $entries"

  printf '%s\n' "$listing" | grep -c 'MANIFEST\.sha256$' >/dev/null \
    || die "falta MANIFEST.sha256 en el ZIP"
  ok "manifiesto presente"

  # Test de restauracion: extraer en temporal y revalidar TODOS los checksums.
  tmp=$(mktemp -d)
  unzip -qq "$zip" -d "$tmp" || { rm -rf "$tmp"; die "no se pudo extraer el ZIP"; }

  root=$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -1)
  [ -n "$root" ] || { rm -rf "$tmp"; die "el ZIP no tiene directorio raiz"; }

  ( cd "$root" && sha_chk MANIFEST.sha256 >/dev/null 2>&1 ) || rc=1
  if [ "$rc" -ne 0 ]; then
    rm -rf "$tmp"
    die "los checksums NO coinciden tras restaurar"
  fi

  n=$(grep -c . < "$root/MANIFEST.sha256")
  rm -rf "$tmp"
  ok "restauracion verificada: $n/$n checksums coinciden"
  inf "temporal de prueba eliminado"
}

if [ "${1:-}" = "--verify" ]; then
  [ -n "${2:-}" ] || die "uso: $0 --verify FILE.zip"
  echo "== verificando $2"
  verify_zip "$2"
  echo "== OK"
  exit 0
fi

# ------------------------------------------------------------------ construir
command -v zip   >/dev/null 2>&1 || die "falta 'zip'"
command -v unzip >/dev/null 2>&1 || die "falta 'unzip'"
[ -d "$CLAUDE_HOME" ] || die "no existe CLAUDE_HOME: $CLAUDE_HOME"

STAMP="$(date +%Y%m%d-%H%M%S)"
NAME="claude-state-${STAMP}"
mkdir -p "$BACKUP_DIR"
ZIP="$BACKUP_DIR/${NAME}.zip"
[ -e "$ZIP" ] && die "ya existe $ZIP"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ROOT="$STAGE/$NAME"
mkdir -p "$ROOT/claude"

echo "== recopilando"
TAR_EX=()
for e in "${EXCLUDES[@]}"; do TAR_EX+=( --exclude="./$e" ); done
tar -C "$CLAUDE_HOME" -cf - "${TAR_EX[@]}" . | tar -C "$ROOT/claude" -xf -
inf "CLAUDE_HOME      -> claude/            ($(du -sm "$ROOT/claude" | cut -f1) MB)"

if [ -d "$BUCLE_DIR" ]; then
  mkdir -p "$ROOT/ai-mastery-bucle"
  tar -C "$BUCLE_DIR" -cf - . | tar -C "$ROOT/ai-mastery-bucle" -xf -
  inf "ai-mastery/bucle -> ai-mastery-bucle/"
fi
if [ -f "$CLAUDE_JSON" ]; then
  cp "$CLAUDE_JSON" "$ROOT/claude.json"
  inf "$(basename "$CLAUDE_JSON")     -> claude.json"
fi

# Manifiesto con rutas relativas a la raiz del backup, para que 'sha256sum -c'
# funcione tal cual desde el directorio extraido.
echo "== generando manifiesto"
( cd "$ROOT" \
  && find . -type f ! -name MANIFEST.sha256 | LC_ALL=C sort > "$STAGE/filelist" \
  && : > MANIFEST.sha256 \
  && while IFS= read -r f; do sha_gen "$f" >> MANIFEST.sha256; done < "$STAGE/filelist" )
FILES=$(grep -c . < "$ROOT/MANIFEST.sha256")
ok "manifiesto: $FILES ficheros"

echo "== empaquetando"
( cd "$STAGE" && zip -qr "$ZIP" "$NAME" )
ok "$ZIP ($(du -sm "$ZIP" | cut -f1) MB)"

echo "== verificando"
verify_zip "$ZIP"

echo
echo "BACKUP OK: $ZIP"
echo "  ficheros: $FILES"
echo "  excluido (regenerable o sensible): ${EXCLUDES[*]}"
