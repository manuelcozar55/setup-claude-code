#!/usr/bin/env bash
# install.sh — Instala el kit saneado en CLAUDE_HOME (idempotente, con backup).
# Plataforma: Linux / WSL2 unicamente (ver kit/docs/02-install.md).
# Uso: [CLAUDE_HOME=$HOME/.claude] bash install.sh
#      bash install.sh --enable-secrets-layer2   (activa la Capa 2 de secretos
#      en el repo git DESDE el que se invoca; opt-in, por repositorio)
set -euo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
GITLEAKS_VERSION="8.30.1"

# --- Puerta de plataforma ---------------------------------------------------
# Solo Linux/WSL2: es lo unico que prueba la CI de este repo
# (.github/workflows/ci.yml). No se promete un soporte (macOS, Windows
# nativo) que no se puede demostrar con un pipeline real. No es un fallo
# tuyo. Ver kit/docs/02-install.md.
os="$(uname -s)"
if [ "$os" != "Linux" ]; then
  cat >&2 <<EOF
==> Plataforma no soportada: $os

Este kit solo soporta Linux y WSL2 (Windows Subsystem for Linux): es lo
unico que prueba la CI de este repo (.github/workflows/ci.yml), y no se
quiere prometer un soporte que no se puede demostrar con un pipeline real.
No es un fallo tuyo, es una politica deliberada.

Si estas en Windows, instala WSL2 y corre este instalador dentro de tu
distribucion Linux (no en PowerShell/cmd). Detalle en kit/docs/02-install.md.
EOF
  exit 1
fi
if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; then
  echo "==> Detectado WSL2 (${WSL_DISTRO_NAME:-distro desconocida}). Soportado igual que Linux nativo."
fi

# --- Subcomando: activar la Capa 2 de secretos en el repo actual ------------
# core.hooksPath es config POR REPOSITORIO. install.sh nunca la toca por su
# cuenta: modificar la config de git de un repo que el usuario no ha nombrado
# explicitamente es exactamente el tipo de accion invasiva que hace que se
# desinstale una herramienta. Este subcomando es opt-in y explicito: solo
# actua si lo invocas tu mismo, estando dentro del repo que quieres proteger.
# Ver kit/docs/05-security.md para el razonamiento completo.
if [ "${1:-}" = "--enable-secrets-layer2" ]; then
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "==> --enable-secrets-layer2 debe ejecutarse DENTRO del repo git que quieres proteger." >&2
    exit 1
  fi
  if [ ! -x "$CLAUDE_HOME/hooks/git/pre-commit" ]; then
    echo "==> Falta $CLAUDE_HOME/hooks/git/pre-commit. Instala primero el kit: bash $KIT/install.sh" >&2
    exit 1
  fi
  git config core.hooksPath "$CLAUDE_HOME/hooks/git"
  echo "==> Capa 2 de secretos activada en $(git rev-parse --show-toplevel) -> core.hooksPath=$CLAUDE_HOME/hooks/git"
  exit 0
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo backup)-$$-${RANDOM:-0}"
BK="$CLAUDE_HOME/backups/$STAMP"

echo "==> Instalando en $CLAUDE_HOME"
mkdir -p "$CLAUDE_HOME/hooks" "$CLAUDE_HOME/agents" "$CLAUDE_HOME/sentinel"

install_file() {  # src dst
  local src="$1" dst="$2"
  if [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then
    mkdir -p "$(dirname "$BK/${dst#$CLAUDE_HOME/}")"
    cp -p "$dst" "$BK/${dst#$CLAUDE_HOME/}"
    echo "   backup: ${dst#$CLAUDE_HOME/}"
  fi
  cp -p "$src" "$dst"
}

install_file "$KIT/claude/CLAUDE.md"            "$CLAUDE_HOME/CLAUDE.md"
install_file "$KIT/claude/settings.json"        "$CLAUDE_HOME/settings.json"
install_file "$KIT/claude/sentinel-allowlist.json" "$CLAUDE_HOME/sentinel-allowlist.json"
install_file "$KIT/claude/.gitleaks.toml"       "$CLAUDE_HOME/.gitleaks.toml"
for f in "$KIT"/claude/agents/*; do [ -e "$f" ] && install_file "$f" "$CLAUDE_HOME/agents/$(basename "$f")"; done
for f in "$KIT"/claude/hooks/*;  do [ -f "$f" ] && install_file "$f" "$CLAUDE_HOME/hooks/$(basename "$f")"; done
for f in "$KIT"/sentinel/*;      do [ -e "$f" ] && install_file "$f" "$CLAUDE_HOME/sentinel/$(basename "$f")"; done
mkdir -p "$CLAUDE_HOME/hooks/git"
install_file "$KIT/claude/hooks/git/pre-commit" "$CLAUDE_HOME/hooks/git/pre-commit"
chmod +x "$CLAUDE_HOME"/hooks/*.sh "$CLAUDE_HOME"/hooks/git/pre-commit 2>/dev/null || true

# --- gitleaks: dependencia de la Capa 2 (opcional; la Capa 1 no la necesita) -
gitleaks_present() {
  if command -v gitleaks >/dev/null 2>&1; then return 0; fi
  if [ -x "$HOME/.local/bin/gitleaks" ]; then return 0; fi
  return 1
}

maybe_install_gitleaks() {
  if gitleaks_present; then
    echo "==> gitleaks ya presente."
    return 0
  fi

  local want="${GITLEAKS_AUTO_INSTALL:-}"
  if [ -z "$want" ]; then
    if [ -t 0 ] && [ -t 1 ]; then
      read -r -p "==> gitleaks no encontrado. ¿Instalarlo en \$HOME/.local/bin (con verificacion de checksum)? [y/N] " want
    else
      want="n"
    fi
  fi
  case "$want" in
    1|y|Y|yes|YES) : ;;
    *)
      echo "==> gitleaks no instalado: la Capa 2 de secretos (pre-commit) no podra activarse."
      echo "    La Capa 1 (secret-guard.sh) sigue activa sin el. Instalalo a mano"
      echo "    (kit/docs/02-install.md) o vuelve a correr con GITLEAKS_AUTO_INSTALL=1."
      return 0
      ;;
  esac

  local arch tmp_dir url sums_url expected tarball
  case "$(uname -m)" in
    x86_64) arch="x64" ;;
    aarch64|arm64) arch="arm64" ;;
    *)
      echo "==> Arquitectura $(uname -m) no soportada por la instalacion automatica de gitleaks. Instalalo a mano."
      return 0
      ;;
  esac

  tmp_dir="$(mktemp -d)"
  tarball="gitleaks_${GITLEAKS_VERSION}_linux_${arch}.tar.gz"
  url="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${tarball}"
  sums_url="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_checksums.txt"

  echo "==> Descargando gitleaks $GITLEAKS_VERSION ($arch)..."
  if ! curl -fsSL --max-time 30 -o "$tmp_dir/$tarball" "$url"; then
    echo "==> No se pudo descargar gitleaks (sin red o release inaccesible). La Capa 2 sigue sin activarse."
    rm -rf "$tmp_dir"; return 0
  fi
  if ! curl -fsSL --max-time 30 -o "$tmp_dir/checksums.txt" "$sums_url"; then
    echo "==> No se pudo descargar el fichero de checksums de gitleaks. La Capa 2 sigue sin activarse."
    rm -rf "$tmp_dir"; return 0
  fi

  # El fichero de checksums referencia el binario por su nombre original de
  # release (mismo nombre con el que se guarda aqui): sha256sum -c compara
  # contra ese fichero exacto en el directorio actual.
  expected="$(grep " ${tarball}\$" "$tmp_dir/checksums.txt" || true)"
  if [ -z "$expected" ]; then
    echo "==> No se encontro el checksum esperado en el fichero de checksums publicado. Abortando (no se puede verificar integridad)."
    rm -rf "$tmp_dir"; return 0
  fi
  if ! ( cd "$tmp_dir" && echo "$expected" | sha256sum -c - >/dev/null 2>&1 ); then
    echo "==> El checksum de gitleaks no coincide con el publicado. Abortando (descarga corrupta o no confiable)."
    rm -rf "$tmp_dir"; return 0
  fi

  if ! tar -xzf "$tmp_dir/$tarball" -C "$tmp_dir" gitleaks 2>/dev/null; then
    echo "==> No se pudo extraer el binario de gitleaks. La Capa 2 sigue sin activarse."
    rm -rf "$tmp_dir"; return 0
  fi

  mkdir -p "$HOME/.local/bin"
  if install -m 0755 "$tmp_dir/gitleaks" "$HOME/.local/bin/gitleaks" 2>/dev/null; then
    echo "==> gitleaks $GITLEAKS_VERSION instalado y verificado (checksum SHA-256) en \$HOME/.local/bin/gitleaks."
  else
    echo "==> Sin permisos para instalar en \$HOME/.local/bin. La Capa 2 sigue sin activarse."
  fi
  rm -rf "$tmp_dir"
  return 0
}

maybe_install_gitleaks

echo "==> Config instalada. Terceros (ver docs/): superpowers, Headroom, agent-browser, venv de tools."
echo "==> Rellena tus claves:  cp $KIT/.env.example \$HOME/.claude/.env  &&  editar"
echo "==> Capa 2 de secretos (gitleaks pre-commit) es opt-in, por repositorio. Actívala DONDE QUIERAS con:"
echo "       bash $KIT/install.sh --enable-secrets-layer2   # ejecútalo dentro del repo a proteger"
echo "    o el one-liner manual:  git config core.hooksPath \"$CLAUDE_HOME/hooks/git\""
echo "==> Verifica:            bash $KIT/doctor.sh"
