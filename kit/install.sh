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

# --- Puerta de dependencia: jq ----------------------------------------------
# jq no es opcional: los cinco guards de Bash leen el comando del payload de
# PreToolUse con jq, y fallan en CERRADO si no esta (deniegan en vez de permitir
# en silencio). Instalar sin jq dejaria un kit que bloquea cada comando de Bash,
# asi que se para aqui, antes de escribir nada, y con la orden que lo arregla.
if ! command -v jq >/dev/null 2>&1; then
  cat >&2 <<EOF
==> Falta jq, y este kit lo necesita.

Los cinco guards de Bash (block-dangerous-commands, branch-guard,
destructive-guard, secret-guard, bash-write-guard) leen el comando con jq. Sin jq no pueden
decidir, y fallan en cerrado: DENIEGAN todo comando de Bash. Instalarlo asi
te dejaria Claude Code bloqueado, asi que no se instala nada.

Instala jq y repite:

  sudo apt install jq      # Debian / Ubuntu / WSL2
  sudo dnf install jq      # Fedora
  sudo pacman -S jq        # Arch
EOF
  exit 1
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

# --- Modo diff-first: CLAUDE_HOME es un repo git ajeno con remoto ----------
# Si $CLAUDE_HOME es en si mismo un repositorio git con al menos un remoto
# configurado, se asume que es un repo de configuracion propio del usuario
# (p.ej. un "claude-config-private") y nunca se escribe encima sin que el
# usuario lo vea: se genera aparte el arbol que se instalaria y se muestra
# el diff contra lo instalado. --apply fuerza la escritura real; --plan
# fuerza el modo diff aunque CLAUDE_HOME no sea un repo git (util en tests).
is_git_repo_with_remote() {
  git -C "$CLAUDE_HOME" rev-parse --git-dir >/dev/null 2>&1 || return 1
  [ -n "$(git -C "$CLAUDE_HOME" remote 2>/dev/null)" ]
}

MODE_APPLY=0
MODE_PLAN=0
case "${1:-}" in
  --apply) MODE_APPLY=1 ;;
  --plan)  MODE_PLAN=1 ;;
esac

install_file() {  # src dst
  local src="$1" dst="$2"
  # Un symlink suele apuntar a otro repo (skills proyectadas): cp escribiria a traves de el.
  if [ -L "$dst" ]; then
    echo "   omitido (symlink, no se toca): ${dst#"$CLAUDE_HOME"/}"
    return 0
  fi
  if [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then
    mkdir -p "$(dirname "$BK/${dst#"$CLAUDE_HOME"/}")"
    cp -p "$dst" "$BK/${dst#"$CLAUDE_HOME"/}"
    echo "   backup: ${dst#"$CLAUDE_HOME"/}"
  fi
  cp -p "$src" "$dst"
}

# settings.json NO se reemplaza si ya existe: se fusiona. Regla, y es deliberada:
#   - `hooks`      -> gana el KIT. La cadena de guards es lo que el kit aporta.
#   - `permissions`-> UNION. Nunca se pierde un deny (seguridad) ni un allow (tu trabajo).
#     Salvo `permissions.disableBypassPermissionsMode`, que queda en "disable" siempre: con la
#     union ganaba tu valor, y un "" previo dejaba el modo sin permisos al alcance.
#   - `env`        -> tus claves ganan, y las nuevas del kit se anaden.
#   - todo lo demas (model, statusLine, theme, enabledPlugins...) -> lo tuyo, intacto. La
#     statusLine y el tema oscuro del kit solo llegan a quien no tenia los suyos.
# Por que existe esto: reemplazar el fichero entero borraba en silencio el ajuste personal.
# Medido en una maquina real al reinstalar: se perdieron ENABLE_TOOL_SEARCH (que vale ~30k de
# contexto por sesion), ANTHROPIC_MODEL con el sufijo de la ventana de 1M,
# CLAUDE_CODE_AUTO_COMPACT_WINDOW y tres limites mas. Habia backup, pero un backup que hay que
# descubrir no es una salvaguarda: es una autopsia.
install_settings() {  # src dst
  local src="$1" dst="$2" tmp real name
  # Sin fichero previo no hay nada que fusionar. El caso "sin jq" ya no llega hasta aqui:
  # la puerta de dependencia del principio aborta antes, sin tocar tu settings.json.
  if [ ! -f "$dst" ]; then
    install_file "$src" "$dst"; return
  fi
  if ! jq empty "$dst" 2>/dev/null; then
    echo "   AVISO: $dst no es JSON valido; se reemplaza con backup" >&2
    install_file "$src" "$dst"; return
  fi
  # El temporal va en el MISMO directorio que $dst para que el mv de abajo sea un rename
  # atomico (no cruza sistemas de ficheros): un fallo a mitad del cp anterior dejaba tu
  # settings.json truncado, y no hay medio settings.json que valga.
  # Un settings.json enlazado (p.ej. a un repo propio) se fusiona A TRAVES del enlace y el
  # enlace se conserva: el mv de abajo sobre el enlace lo sustituia por un fichero regular.
  name="${dst#"$CLAUDE_HOME"/}"; real="$dst"
  [ -L "$dst" ] && real="$(readlink -f "$dst")"
  tmp="$(mktemp "$real.XXXXXX")"
  if jq -s '
      .[0] as $kit | .[1] as $old |
      ($kit + $old)
      | .env = (($kit.env // {}) + ($old.env // {}))
      | .hooks = ($kit.hooks // $old.hooks)
      | .permissions = ((($kit.permissions // {}) + ($old.permissions // {}))
          | .allow = (($kit.permissions.allow // []) + (($old.permissions.allow // []) - ($kit.permissions.allow // [])))
          | .deny  = (($kit.permissions.deny  // []) + (($old.permissions.deny  // []) - ($kit.permissions.deny  // []))))
      | .permissions.disableBypassPermissionsMode = "disable"
    ' "$src" "$real" > "$tmp" && jq empty "$tmp" 2>/dev/null; then
    if ! cmp -s "$tmp" "$real"; then
      mkdir -p "$(dirname "$BK/$name")"
      cp -p "$real" "$BK/$name"
      echo "   backup: $name (fusionado: hooks del kit, permisos unidos, tu env y tu model intactos)"
      if jq -e '.permissions.disableBypassPermissionsMode | . != null and . != "disable"' "$real" >/dev/null 2>&1; then
        echo "   permissions.disableBypassPermissionsMode: tu valor se sustituye por \"disable\" (gana el kit)"
      fi
      chmod --reference="$real" "$tmp"
      mv "$tmp" "$real"
    fi
    rm -f "$tmp"
  else
    rm -f "$tmp"
    echo "   AVISO: la fusion de settings.json fallo; se deja el tuyo intacto" >&2
  fi
}

# Tres claves tuyas dejan al kit sin efecto, y la fusion las respeta porque son tuyas: se avisa.
# disableAllHooks apaga todos los hooks, guards incluidos; defaultMode bypassPermissions pide el
# modo sin permisos, que el "disable" del kit deja inerte; env.CC_ALLOW_DESTRUCTIVE=1 apaga destructive-guard.sh. Se mira el fichero que queda: al
# aplicar, el ya fusionado; en el plan, el instalado.
avisos_settings() {  # settings.json
  local f="$1"
  if [ ! -f "$f" ] || ! jq empty "$f" 2>/dev/null; then return 0; fi
  if jq -e '.disableAllHooks == true' "$f" >/dev/null; then
    echo "==> AVISO: $f tiene disableAllHooks: true: no corre ningun hook, tampoco los guards del kit."
    echo "    Quita la clave para tener la proteccion del kit. doctor.sh lo marca como FAIL."
  fi
  # CC_ALLOW_DESTRUCTIVE=1 apaga destructive-guard.sh. La fusion respeta tu env, asi que un 1 previo sobrevive.
  if jq -e '(.env.CC_ALLOW_DESTRUCTIVE // "" | tostring) == "1"' "$f" >/dev/null; then
    echo "==> AVISO: $f tiene env.CC_ALLOW_DESTRUCTIVE=1: destructive-guard.sh queda apagado."
    echo "    Quita la clave para tener esa proteccion del kit. doctor.sh lo marca como WARN."
  fi
  if jq -e '.permissions.defaultMode == "bypassPermissions"' "$f" >/dev/null; then
    echo "==> AVISO: $f tiene permissions.defaultMode: bypassPermissions. Con disableBypassPermissionsMode"
    echo "    en \"disable\" (lo fija el kit al instalar) queda inerte: quitalo o elige otro modo."
  fi
}

# CLAUDE.md y AGENTS.md son instrucciones que escribes tu: no se pisan si ya las has tocado. Se
# deja la del kit al lado, como CLAUDE.kit.md o AGENTS.kit.md, y se avisa. Reemplazarla borraba
# trabajo irrecuperable por fusion automatica -- una prosa no se puede fusionar como un JSON.
CLAUDE_MD_PREVIO=0
install_claude_md() {  # src dst
  local src="$1" dst="$2"
  if [ ! -f "$dst" ]; then cp -p "$src" "$dst"; return; fi
  if cmp -s "$src" "$dst"; then return; fi
  local n; n="$(basename "$dst" .md)"
  # Un CLAUDE.md propio sin el import deja AGENTS.md instalado pero sin que nadie lo lea.
  if [ "$n" = "CLAUDE" ] && ! command grep -qE '^[[:space:]]*@[^[:space:]]*AGENTS\.md' "$dst"; then CLAUDE_MD_PREVIO=1; fi
  cp -p "$src" "$(dirname "$dst")/$n.kit.md"
  echo "   $n.md ya existe y la has modificado: NO se toca."
  echo "   La version del kit queda en $n.kit.md para que compares y copies lo que quieras."
}

install_kit_files() {  # base-dir: $CLAUDE_HOME al aplicar, o el arbol de plan
  local base="$1" f rel
  mkdir -p "$base/hooks/lib" "$base/agents" "$base/sentinel" "$base/templates" "$base/bin"
  install_claude_md "$KIT/claude/CLAUDE.md"       "$base/CLAUDE.md"
  install_claude_md "$KIT/claude/AGENTS.md"       "$base/AGENTS.md"
  install_settings  "$KIT/claude/settings.json"   "$base/settings.json"
  install_file "$KIT/claude/sentinel-allowlist.json" "$base/sentinel-allowlist.json"
  install_file "$KIT/claude/.gitleaks.toml"       "$base/.gitleaks.toml"
  install_file "$KIT/claude/statusline-command.sh" "$base/statusline-command.sh"
  for f in "$KIT"/claude/agents/*; do [ -f "$f" ] && install_file "$f" "$base/agents/$(basename "$f")"; done
  while IFS= read -r -d '' f; do
    rel="${f#"$KIT"/claude/skills/}"
    mkdir -p "$base/skills/$(dirname "$rel")"
    install_file "$f" "$base/skills/$rel"
  done < <(find "$KIT/claude/skills" -type f -print0 2>/dev/null)
  for f in "$KIT"/claude/hooks/*;  do [ -f "$f" ] && install_file "$f" "$base/hooks/$(basename "$f")"; done
  for f in "$KIT"/claude/hooks/lib/*; do [ -f "$f" ] && install_file "$f" "$base/hooks/lib/$(basename "$f")"; done
  for f in "$KIT"/claude/bin/*;    do [ -f "$f" ] && install_file "$f" "$base/bin/$(basename "$f")"; done
  for f in "$KIT"/claude/templates/*; do [ -f "$f" ] && install_file "$f" "$base/templates/$(basename "$f")"; done
  for f in "$KIT"/sentinel/*;      do [ -f "$f" ] && install_file "$f" "$base/sentinel/$(basename "$f")"; done
  mkdir -p "$base/hooks/git"
  install_file "$KIT/claude/hooks/git/pre-commit" "$base/hooks/git/pre-commit"
  chmod +x "$base"/hooks/*.sh "$base"/hooks/git/pre-commit "$base"/statusline-command.sh "$base"/bin/* 2>/dev/null || true
}

# handoff y oraculo se llaman a pelo en las instrucciones y los hooks: sin estar en el PATH, «command not
# found». Se enlazan en ~/.local/bin SOLO si el hueco esta libre o ya es un enlace nuestro (a $CLAUDE_HOME/bin):
# un fichero o un enlace ajeno es de la persona y no se pisa.
# Y solo si CLAUDE_HOME es ~/.claude: una instalacion de prueba (tests, CI, CLAUDE_HOME=/ruta/alternativa)
# enlazaba en el ~/.local/bin real y, al borrar su ruta, dejaba enlaces colgantes que ya no se reparaban
# (contaban como ajenos). Con otro CLAUDE_HOME se imprimen las ordenes y no se escribe.
LOCAL_BIN="$HOME/.local/bin"
CLIS="handoff oraculo"
clis_enlazables() { [ "$(realpath -m -- "$CLAUDE_HOME")" = "$(realpath -m -- "$HOME/.claude")" ]; }
cli_estado() {  # nombre -> libre | nuestro | ajeno
  local dst="$LOCAL_BIN/$1"
  if [ -L "$dst" ]; then
    # Ruta canonica y no prefijo de texto: bin/../../x empezaba por "$CLAUDE_HOME/bin/" y contaba como nuestro.
    # realpath -m resuelve el enlace aunque este colgante; nuestro = su destino vive en nuestro bin/.
    if [ "$(dirname -- "$(realpath -m -- "$dst")")" = "$(realpath -m -- "$CLAUDE_HOME/bin")" ]; then echo nuestro; else echo ajeno; fi
  elif [ -e "$dst" ]; then echo ajeno
  else echo libre
  fi
}
enlazar_clis() {
  local c st
  LINK_AJENOS=""
  if ! clis_enlazables; then
    echo "   CLAUDE_HOME ($CLAUDE_HOME) no es $HOME/.claude: no se toca $LOCAL_BIN. Si quieres los enlaces:"
    for c in $CLIS; do echo "     ln -s \"$CLAUDE_HOME/bin/$c\" \"$LOCAL_BIN/$c\""; done
    return 0
  fi
  for c in $CLIS; do
    st="$(cli_estado "$c")"
    # Sin forzar el enlace (ni -f): si entre la comprobacion y el ln aparece algo, ln falla y se trata como ajeno en vez de pisarlo.
    # Un enlace nuestro con otra grafia o colgante se retira (solo es un enlace) y se recrea con la ruta exacta.
    if [ "$st" = nuestro ] && [ "$(readlink "$LOCAL_BIN/$c")" != "$CLAUDE_HOME/bin/$c" ]; then
      rm -f -- "${LOCAL_BIN:?}/$c"; st=libre
    fi
    if [ "$st" = libre ]; then
      mkdir -p "$LOCAL_BIN"
      ln -s "$CLAUDE_HOME/bin/$c" "$LOCAL_BIN/$c" 2>/dev/null || st=ajeno
    fi
    if [ "$st" = ajeno ]; then
      LINK_AJENOS="$LINK_AJENOS $c"
      echo "   AVISO: $LOCAL_BIN/$c ya existe y no es un enlace a $CLAUDE_HOME/bin: no se toca." >&2
    else
      echo "   enlace: $LOCAL_BIN/$c -> $CLAUDE_HOME/bin/$c"
    fi
  done
}
aviso_path() {
  case ":$PATH:" in *":$LOCAL_BIN:"*) return 0 ;; esac
  # Con CLAUDE_HOME no estandar no se enlazo nada: decir que "no se encontraran" suena a que si estan enlazados.
  if ! clis_enlazables; then
    echo "==> AVISO: $LOCAL_BIN no esta en tu PATH. No se enlazo nada: si creas los enlaces de arriba, tendras que"
    echo "    añadir esa carpeta al PATH para usarlos por su nombre; sin enlaces, usa la ruta $CLAUDE_HOME/bin/<nombre>."
    return 0
  fi
  echo "==> AVISO: $LOCAL_BIN no esta en tu PATH, asi que handoff y oraculo no se encontraran."
  echo "    Abre una terminal nueva (Debian/Ubuntu lo añade al iniciar sesion si la carpeta ya existe)"
  echo "    o añade a tu ~/.bashrc:  export PATH=\"\$HOME/.local/bin:\$PATH\""
}

run_diff_first() {
  local out marker=".mcharness-out-marker" real_out real_home solape=0
  if [ -n "${MCHARNESS_OUT:-}" ]; then
    out="$MCHARNESS_OUT"
    real_out="$(realpath -m -- "$out")"; real_home="$(realpath -m -- "$CLAUDE_HOME")"
    # Solape = iguales o una contiene a la otra: generar el plan ahi pisaria la instalacion.
    case "$real_out/" in "$real_home"/*) solape=1 ;; esac
    case "$real_home/" in "$real_out"/*) solape=1 ;; esac
    if [ "$solape" -eq 1 ]; then
      echo "==> MCHARNESS_OUT ($out) solapa con CLAUDE_HOME ($CLAUDE_HOME): no se genera el plan ahi." >&2
      exit 1
    fi
    if [ -e "$out" ] || [ -L "$out" ]; then
      if [ -f "$out/$marker" ] && [ ! -L "$out" ]; then
        # Solo un arbol que escribio este mismo script (lleva su marcador).
        rm -rf -- "$out"
      elif [ -d "$out" ] && [ ! -L "$out" ] && [ -z "$(ls -A -- "$out")" ]; then
        :
      else
        echo "==> MCHARNESS_OUT ($out) existe y no es un plan anterior de este instalador (sin marcador): no se borra." >&2
        exit 1
      fi
    fi
  else
    # Directorio nuevo y exclusivo por ejecucion: no hay nada previo que borrar. Se conserva
    # a proposito: el paso 2 del texto de abajo manda copiar a mano desde ahi.
    out="$(mktemp -d "${TMPDIR:-/tmp}/mcharness-plan.XXXXXX")"
  fi
  mkdir -p "$out"; : > "$out/$marker"
  install_kit_files "$out"

  if is_git_repo_with_remote; then
    echo "==> $CLAUDE_HOME es un repositorio git con remoto configurado: no se escribe nada ahi."
  else
    echo "==> Modo --plan: no se escribe nada en $CLAUDE_HOME."
  fi
  echo "    Arbol que se instalaria, generado en: $out"
  echo

  local rel
  local new=() changed=() same=()
  while IFS= read -r -d '' f; do
    rel="${f#"$out"/}"
    if [ ! -e "$CLAUDE_HOME/$rel" ]; then
      new+=("$rel")
    elif cmp -s "$f" "$CLAUDE_HOME/$rel"; then
      same+=("$rel")
    else
      changed+=("$rel")
    fi
  done < <(find "$out" -type f ! -name "$marker" -print0)

  echo "==> nuevos (no existen en $CLAUDE_HOME):"
  if [ "${#new[@]}" -gt 0 ]; then printf '    %s\n' "${new[@]}"; else echo "    (ninguno)"; fi
  echo "==> identicos (nada que hacer):"
  if [ "${#same[@]}" -gt 0 ]; then printf '    %s\n' "${same[@]}"; else echo "    (ninguno)"; fi
  echo "==> modificados (diff completo abajo):"
  if [ "${#changed[@]}" -eq 0 ]; then echo "    (ninguno)"; fi

  for rel in "${changed[@]}"; do
    echo "----- diff: $rel -----"
    diff -u "$CLAUDE_HOME/$rel" "$out/$rel" || true
  done
  avisos_settings "$CLAUDE_HOME/settings.json"

  if is_git_repo_with_remote; then
    echo
    echo "==> $CLAUDE_HOME es tu propio repo git (con remoto): no se sobreescribe sin"
    echo "    que lo veas. Que hacer:"
  else
    echo
    echo "==> --plan solo muestra lo que se instalaria; $CLAUDE_HOME no se ha tocado. Que hacer:"
  fi
  echo
  if clis_enlazables; then
    echo "==> En modo aplicar (--apply) tambien se enlazarian handoff y oraculo en $LOCAL_BIN (solo si el hueco"
    echo "    esta libre o ya es un enlace a $CLAUDE_HOME/bin). Estado ahora:"
    for c in $CLIS; do echo "      $c: $(cli_estado "$c")"; done
  else
    echo "==> En modo aplicar (--apply) no se tocaria $LOCAL_BIN: CLAUDE_HOME no es $HOME/.claude."
    echo "    Se imprimirian las ordenes ln -s para que enlaces tu, si quieres."
  fi
  cat <<EOF
      1. Revisa arriba los ficheros nuevos/modificados (arbol completo en $out).
      2. Copia a mano lo que quieras adoptar de $out a $CLAUDE_HOME.
      3. Commitea esos cambios en TU repo (el privado), como de costumbre.

    Si en vez de eso quieres que este instalador escriba directamente sobre
    $CLAUDE_HOME (con el backup habitual de siempre), vuelve a lanzarlo con:
        bash $KIT/install.sh --apply
EOF
}

if [ "$MODE_APPLY" -eq 0 ] && { [ "$MODE_PLAN" -eq 1 ] || is_git_repo_with_remote; }; then
  run_diff_first
  exit 0
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo backup)-$$-${RANDOM:-0}"
BK="$CLAUDE_HOME/backups/$STAMP"

echo "==> Instalando en $CLAUDE_HOME"
install_kit_files "$CLAUDE_HOME"

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

echo "==> Config instalada. Terceros (ver docs/): agent-browser, venv de tools. Plugins: install-plugins.sh."
echo "==> CLIs handoff y oraculo (valen en Claude Code, Codex y opencode):"
enlazar_clis
if [ -f "$KIT/.env.example" ]; then
  echo "==> Rellena tus claves:  cp $KIT/.env.example \$HOME/.claude/.env  &&  editar"
else
  echo "==> Plantilla de credenciales no incluida: los servicios externos son opcionales."
fi
echo "==> Capa 2 de secretos (gitleaks pre-commit) es opt-in, por repositorio. Actívala DONDE QUIERAS con:"
echo "       bash $KIT/install.sh --enable-secrets-layer2   # ejecútalo dentro del repo a proteger"
echo "    o el one-liner manual:  git config core.hooksPath \"$CLAUDE_HOME/hooks/git\""
echo "==> Verifica:            bash $KIT/doctor.sh"
if [ "$CLAUDE_MD_PREVIO" -eq 1 ]; then
  echo
  echo "==> AVISO: ya tenias un CLAUDE.md y no se ha tocado. Añade @AGENTS.md a tu CLAUDE.md;"
  echo "    la plantilla del kit quedo en CLAUDE.kit.md. Sin eso, Claude no lee las instrucciones del kit."
fi
avisos_settings "$CLAUDE_HOME/settings.json"
aviso_path
if [ -n "${LINK_AJENOS:-}" ]; then
  echo "==> AVISO: no se enlazo$LINK_AJENOS (ya existia en $LOCAL_BIN). Usa la ruta $CLAUDE_HOME/bin/<nombre> o resuelve el conflicto."
fi
