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

# --- SHA-256 de gitleaks, fijados en ESTE repo (no en la red) ---------------
# Ancla de confianza: el fichero gitleaks_${GITLEAKS_VERSION}_checksums.txt
# que publica la release protege contra corrupcion en transito, pero lo sirve
# el mismo host que el tarball -- quien pueda comprometer uno puede servir el
# otro a juego. Fijar el hash aqui, versionado y revisable en un PR, mueve el
# ancla fuera de lo que la red sirva ese dia. Obtenidos y verificados a mano
# contra la release oficial v8.30.1 (ver CONTRIBUTING.md, "Actualizar
# gitleaks", para el proceso de refrescarlos en el proximo bump de version).
GITLEAKS_SHA256_LINUX_X64="551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb"
GITLEAKS_SHA256_LINUX_ARM64="e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080"

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

# --- Subcomando: instalar Headroom y cablearlo (opt-in) ---------------------
# Headroom es de terceros y el kit NO lo redistribuye: se instala desde PyPI
# (paquete headroom-ai) en el venv del usuario.
#
# El orden de los pasos es la parte importante, y es lo que arregla el fallo que
# tenia este kit: primero instalar, luego arrancar, luego COMPROBAR que responde,
# y solo entonces escribir ANTHROPIC_BASE_URL en settings.json. Hacerlo al reves
# --distribuir la variable y esperar que el proxy aparezca-- dejaba a quien
# instalaba el kit en limpio con Claude Code apuntando a un puerto muerto.
# Contrato probado en kit/test/test_with_headroom.sh.
if [ "${1:-}" = "--with-headroom" ]; then
  HR_PORT="${HEADROOM_PORT:-8787}"
  VENV="${TOOLS_VENV:-$HOME/.venvs/tools}"
  UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  DRY="${HEADROOM_DRY_RUN:-0}"

  if [ ! -f "$CLAUDE_HOME/settings.json" ]; then
    echo "==> Instala primero el kit:  bash $KIT/install.sh" >&2
    exit 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "==> jq es necesario para cablear settings.json sin romperlo." >&2
    exit 1
  fi

  # 1. Paquete en el venv de tools (nunca pip del sistema).
  if [ "$DRY" != "1" ]; then
    if [ ! -x "$VENV/bin/python3" ]; then
      echo "==> Creando venv de tools en $VENV"
      python3 -m venv "$VENV" || { echo "==> No se pudo crear el venv." >&2; exit 1; }
    fi
    # El extra es [proxy], y no es opcional: sin el, el proxy no arranca y falla
    # con "No module named 'httpx'". Y NO se usa [all]: expande a trece extras,
    # entre ellos [ml] (torch + huggingface-hub), que mide ~900 MB frente a
    # 7,2 GB sin comprar nada aqui -- el motor de compresion usa ONNX Runtime,
    # que ya viene en [proxy]. Ver kit/docs/03-headroom.md.
    echo "==> Instalando 'headroom-ai[proxy]' en $VENV (no [all]: ver docs/03-headroom.md)"
    "$VENV/bin/pip" install -q --upgrade 'headroom-ai[proxy]' || {
      echo "==> Fallo la instalacion de headroom-ai[proxy] (sin red o paquete inaccesible)." >&2
      echo "    No se ha tocado settings.json." >&2
      exit 1
    }
    mkdir -p "$HOME/.local/bin"
    ln -sf "$VENV/bin/headroom" "$HOME/.local/bin/headroom"
  fi

  # 2. Helper del output-shaper. Reduce tokens de SALIDA, que no se cachean, asi
  # que es la unica palanca de ahorro que no arriesga el prefijo cacheado. Los
  # toggles no se propagan por Environment= ni por el manifest: el unico canal
  # es un POST en vivo, y por eso hay que repetirlo en cada arranque.
  # HEADROOM_OUTPUT_HOLDOUT=0.1 deja un 10 % del trafico sin moldear a proposito,
  # para que el ahorro siga siendo medible en vez de una cifra que hay que creerse.
  SHAPER="$CLAUDE_HOME/headroom-apply-shaper.sh"
  cat > "$SHAPER" <<SHAPEREOF
#!/usr/bin/env bash
# Generado por install.sh --with-headroom. Aplica los toggles de runtime.
# NUNCA falla el arranque del servicio: si fallara, systemd marcaria la unidad
# como failed y con Restart entraria en bucle de reinicios.
set -uo pipefail
URL=http://127.0.0.1:${HR_PORT}
PAYLOAD='{"HEADROOM_OUTPUT_SHAPER":"1","HEADROOM_OUTPUT_HOLDOUT":"0.1"}'
if ! curl -sf --retry 60 --retry-delay 1 --retry-connrefused -m 3 "\$URL/readyz" >/dev/null 2>&1; then
  echo "headroom shaper: /readyz no respondio; no se aplico nada"; exit 0
fi
resp=\$(curl -sf -m 5 -X POST "\$URL/admin/runtime-env" \\
         -H 'content-type: application/json' -d "\$PAYLOAD" 2>&1)
if [[ "\$resp" == *'"HEADROOM_OUTPUT_SHAPER":"1"'* ]]; then
  echo "headroom shaper: aplicado OK (output-shaper=1, holdout=0.1)"
else
  echo "headroom shaper: NO aplicado. respuesta: \$resp"
fi
exit 0
SHAPEREOF
  chmod +x "$SHAPER"

  # 3. Unidad de usuario. Una sola, a proposito: ver docs/03-headroom.md sobre
  # las dos unidades peleando por el puerto.
  mkdir -p "$UNIT_DIR"
  cat > "$UNIT_DIR/headroom-proxy.service" <<UNITEOF
[Unit]
Description=Headroom LLM context compression proxy
Documentation=https://github.com/headroomlabs-ai/headroom
After=network.target
# Sin limite de intentos, y va en [Unit]: en [Service] systemd lo ignora en
# silencio y la unidad muere en 'failed' tras 5 arranques en 10 s.
StartLimitIntervalSec=0

[Service]
Type=simple
# Modo cache EXPLICITO. De los perfiles de ahorro, solo 'coding' usa modo cache;
# los demas usan 'token', que reescribe los turnos anteriores e invalida el
# prefijo cacheado de Anthropic -- que es de donde sale casi todo el ahorro.
# No se confia en el default porque la propia herramienta se contradice sobre
# cual es (ver kit/docs/03-headroom.md).
ExecStart=%h/.local/bin/headroom proxy --port ${HR_PORT} --mode cache --no-telemetry
Environment=HEADROOM_SAVINGS_PROFILE=coding
Environment=PATH=%h/.local/bin:%h/.venvs/tools/bin:/usr/local/bin:/usr/bin:/bin
# El '-' es deliberado: si el shaper falla, la unidad NO debe quedar en failed.
ExecStartPost=-${SHAPER}
Restart=always
RestartSec=3

# Endurecimiento: escribible solo lo imprescindible.
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=%h/.headroom %h/.cache/huggingface
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

[Install]
WantedBy=default.target
UNITEOF
  echo "==> Unidad escrita: $UNIT_DIR/headroom-proxy.service"

  # 4. Arrancar.
  if [ "$DRY" != "1" ]; then
    if ! command -v systemctl >/dev/null 2>&1; then
      echo "==> Sin systemd: arranca el proxy a mano y vuelve a lanzar esto." >&2
      echo "    \$HOME/.local/bin/headroom proxy --port $HR_PORT --mode cache" >&2
      exit 1
    fi
    mkdir -p "$HOME/.headroom" "$HOME/.cache/huggingface"
    systemctl --user daemon-reload
    systemctl --user enable --now headroom-proxy.service || true
    # linger: que el proxy arranque con la maquina y no al primer login.
    loginctl enable-linger "${USER:-$(id -un)}" >/dev/null 2>&1 || true
  fi

  # 5. Readiness. /readyz y no /health: /health es agregado y se pone en rojo si
  # cualquier subcomprobacion falla (p.ej. el backend semantico que no se instala).
  ready=0
  if [ -n "${HEADROOM_FAKE_READY:-}" ]; then
    [ "$HEADROOM_FAKE_READY" = "1" ] && ready=1
  else
    for _ in $(seq 1 30); do
      if curl -fsS -m 1 -o /dev/null "http://127.0.0.1:$HR_PORT/readyz" 2>/dev/null; then ready=1; break; fi
      sleep 1
    done
  fi

  if [ "$ready" -ne 1 ]; then
    echo "==> El proxy no responde en 127.0.0.1:$HR_PORT/readyz tras 30 s." >&2
    echo "    settings.json NO se ha tocado: es deliberado. Cablear la API a un" >&2
    echo "    proxy que no contesta deja Claude Code sin poder conectar." >&2
    echo "    Diagnostico:  systemctl --user status headroom-proxy" >&2
    echo "                  journalctl --user -u headroom-proxy -n 50" >&2
    exit 1
  fi

  # 6. Y solo ahora, cablear.
  tmp_s="$(mktemp)"
  if jq --arg u "http://127.0.0.1:$HR_PORT" '.env.ANTHROPIC_BASE_URL = $u' \
       "$CLAUDE_HOME/settings.json" > "$tmp_s" && jq empty "$tmp_s" 2>/dev/null; then
    mv "$tmp_s" "$CLAUDE_HOME/settings.json"
  else
    rm -f "$tmp_s"
    echo "==> No se pudo actualizar settings.json; se deja intacto." >&2
    exit 1
  fi

  echo "==> Headroom cableado: ANTHROPIC_BASE_URL=http://127.0.0.1:$HR_PORT"
  echo "==> NO ejecutes 'headroom install': crearia una segunda unidad peleando"
  echo "    por el puerto $HR_PORT. Esta unidad es la unica fuente de verdad."
  echo "==> Verifica:  bash $KIT/doctor.sh"
  exit 0
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo backup)-$$-${RANDOM:-0}"
BK="$CLAUDE_HOME/backups/$STAMP"

echo "==> Instalando en $CLAUDE_HOME"
mkdir -p "$CLAUDE_HOME/hooks" "$CLAUDE_HOME/agents" "$CLAUDE_HOME/sentinel"

install_file() {  # src dst
  local src="$1" dst="$2"
  if [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then
    mkdir -p "$(dirname "$BK/${dst#"$CLAUDE_HOME"/}")"
    cp -p "$dst" "$BK/${dst#"$CLAUDE_HOME"/}"
    echo "   backup: ${dst#"$CLAUDE_HOME"/}"
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
    rm -f "$CLAUDE_HOME/.gitleaks-checksum-mismatch" 2>/dev/null || true
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

  local arch tmp_dir url tarball expected_sha256
  case "$(uname -m)" in
    x86_64) arch="x64"; expected_sha256="$GITLEAKS_SHA256_LINUX_X64" ;;
    aarch64|arm64) arch="arm64"; expected_sha256="$GITLEAKS_SHA256_LINUX_ARM64" ;;
    *)
      echo "==> Arquitectura $(uname -m) no soportada por la instalacion automatica de gitleaks. Instalalo a mano."
      return 0
      ;;
  esac

  tmp_dir="$(mktemp -d)"
  tarball="gitleaks_${GITLEAKS_VERSION}_linux_${arch}.tar.gz"
  url="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${tarball}"

  echo "==> Descargando gitleaks $GITLEAKS_VERSION ($arch)..."
  if ! curl -fsSL --max-time 30 -o "$tmp_dir/$tarball" "$url"; then
    echo "==> No se pudo descargar gitleaks (sin red o release inaccesible). La Capa 2 sigue sin activarse."
    rm -rf "$tmp_dir"; return 0
  fi

  # Verificacion de integridad contra el hash FIJADO en este script (arriba),
  # no contra el checksums.txt que publica la propia release: ese fichero lo
  # sirve el mismo host que el tarball, asi que no protege contra una release
  # comprometida, solo contra corrupcion en transito -- y el hash fijado ya
  # cubre eso. Se decide no consultar tambien el checksums.txt de red como
  # comprobacion secundaria: no anadiria ninguna garantia que el pin no de ya
  # (si el pin se queda obsoleto en un bump de GITLEAKS_VERSION, esta misma
  # comparacion falla igual, de forma segura, en vez de necesitar una segunda
  # fuente de red para notarlo) y si anadiria una llamada de red y una
  # superficie de fallo mas.
  if ! ( cd "$tmp_dir" && echo "$expected_sha256  $tarball" | sha256sum -c - >/dev/null 2>&1 ); then
    echo "==> ALERTA: el checksum de gitleaks no coincide con el fijado en kit/install.sh." >&2
    echo "    Puede ser una release comprometida, un binario servido distinto del esperado," >&2
    echo "    o que GITLEAKS_VERSION se subio sin actualizar el hash (ver CONTRIBUTING.md)." >&2
    echo "    Abortando instalacion de gitleaks; la Capa 2 sigue sin activarse." >&2
    mkdir -p "$CLAUDE_HOME"
    {
      echo "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo desconocido)"
      echo "version=$GITLEAKS_VERSION"
      echo "arch=$arch"
      echo "expected_sha256=$expected_sha256"
    } >> "$CLAUDE_HOME/.gitleaks-checksum-mismatch"
    rm -rf "$tmp_dir"
    return 2
  fi

  if ! tar -xzf "$tmp_dir/$tarball" -C "$tmp_dir" gitleaks 2>/dev/null; then
    echo "==> No se pudo extraer el binario de gitleaks. La Capa 2 sigue sin activarse."
    rm -rf "$tmp_dir"; return 0
  fi

  mkdir -p "$HOME/.local/bin"
  if install -m 0755 "$tmp_dir/gitleaks" "$HOME/.local/bin/gitleaks" 2>/dev/null; then
    echo "==> gitleaks $GITLEAKS_VERSION instalado y verificado (checksum SHA-256 fijado en el repo) en \$HOME/.local/bin/gitleaks."
    rm -f "$CLAUDE_HOME/.gitleaks-checksum-mismatch" 2>/dev/null || true
  else
    echo "==> Sin permisos para instalar en \$HOME/.local/bin. La Capa 2 sigue sin activarse."
  fi
  rm -rf "$tmp_dir"
  return 0
}

gl_rc=0
maybe_install_gitleaks || gl_rc=$?
if [ "$gl_rc" -eq 2 ]; then
  echo "==> Revisa \$CLAUDE_HOME/.gitleaks-checksum-mismatch y kit/docs/05-security.md antes de reintentar. doctor.sh tambien lo reporta."
fi

echo "==> Config instalada. Terceros (ver docs/): superpowers, Headroom, agent-browser, venv de tools."
echo "==> Rellena tus claves:  cp $KIT/.env.example \$HOME/.claude/.env  &&  editar"
echo "==> Capa 2 de secretos (gitleaks pre-commit) es opt-in, por repositorio. Actívala DONDE QUIERAS con:"
echo "       bash $KIT/install.sh --enable-secrets-layer2   # ejecútalo dentro del repo a proteger"
echo "    o el one-liner manual:  git config core.hooksPath \"$CLAUDE_HOME/hooks/git\""
echo "==> Verifica:            bash $KIT/doctor.sh"
