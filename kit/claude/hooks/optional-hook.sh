#!/usr/bin/env bash
# optional-hook.sh — ejecuta un hook solo si su dependencia existe.
#
# Por qué existe: settings.json cableaba `rtk hook claude` y el python3 del venv
# de tools directamente, y install.sh no instala ninguno de los dos (son
# terceros, ver kit/docs/02-install.md). En una instalación limpia eso significa
# exit 127 en cada llamada a tool, y en el caso del preflight de Sentinel
# --matcher ""-- en absolutamente todas. Quien seguía el README al pie de la
# letra se encontraba su primera sesión llena de errores por componentes que el
# kit nunca prometió instalar.
#
# El contrato, y el matiz que importa: dependencia ausente = no-op silencioso
# (exit 0), dependencia presente = se ejecuta y su código de salida se propaga
# TAL CUAL. Claude Code trata el 2 como "blocking error", así que un wrapper que
# normalizara códigos convertiría los guards en decoración: pasarían a permitir
# lo que deben bloquear. Falla-abierto SOLO cuando el guard no está instalado;
# nunca cuando está instalado y dice no. Contrato probado en
# kit/test/test_optional_hook.sh.
#
# Dos guards no son opcionales: el preflight de Sentinel y write-guard.py. Si falta su script (con
# intérprete presente) deniegan con exit 2. Si falta el intérprete, la máquina no puede ejecutarlos y
# el wrapper sigue sin bloquear, pero ya no calla: avisa UNA vez por sesión por additionalContext
# (el modelo y la persona ven que Sentinel o write-guard no están activos). La tabla completa de
# fallos (sin jq, sin python3, JSON roto, caída, timeout) está en SECURITY.md y en docs/05-security.md.
#
# Uso:
#   optional-hook.sh <cmd> [args...]              # ejecutable en PATH o ruta absoluta
#   optional-hook.sh --python <script.py> [args]  # resuelve el intérprete él solo
set -u

# Un aviso por sesión y guard: el marcador vive en un directorio de runtime y lleva el session_id del payload.
payload=""
warn_once() { # <clave> <mensaje>
  local sid dir marker
  [ -t 0 ] || payload=$(cat 2>/dev/null || true)
  sid=$(printf '%s' "$payload" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 | tr -c 'A-Za-z0-9_\n-' '_')
  [ -n "$sid" ] || sid=sinsesion
  dir="${CC_WARN_DIR:-${XDG_RUNTIME_DIR:-/tmp}}"
  marker="$dir/cc-degradado-$(id -u)-$sid-$1"
  # noclobber abre con O_EXCL: no sigue un enlace plantado en el directorio y, si el marcador ya existe, no avisa de nuevo.
  if ! ( set -o noclobber; : > "$marker" ) 2>/dev/null && { [ -e "$marker" ] || [ -L "$marker" ]; }; then return 0; fi
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$2"
  printf '%s\n' "$2" >&2
}

if [ "${1:-}" = "--python" ]; then
  shift
  script="${1:-}"
  guard=""
  case "$(basename "$script")" in
    sentinel_preflight.py) guard="Sentinel (rutas sensibles y comandos peligrosos)" ;;
    write-guard.py) guard="write-guard (escrituras con secretos)" ;;
  esac

  # Preferencia: el venv de tools (es donde el kit documenta las herramientas
  # Python), y si no está, el python3 del sistema. Así el hook sigue protegiendo
  # en una máquina que no montó el venv, en vez de desactivarse por completo.
  # PYTHON_HOOK_BIN permite fijarlo a mano y es lo que usan los tests.
  py="${PYTHON_HOOK_BIN:-}"
  if [ -z "$py" ]; then
    for candidate in "$HOME/.venvs/tools/bin/python3" "$(command -v python3 2>/dev/null || true)"; do
      if [ -n "$candidate" ] && [ -x "$candidate" ]; then py="$candidate"; break; fi
    done
  fi

  # Sentinel y write-guard no son opcionales: si su script falta deniegan (exit 2) en vez de
  # convertirse en un permiso silencioso. Sin intérprete siguen sin bloquear (es la máquina
  # limpia que prueba test_clean_install_resilience.sh), pero avisan una vez por sesión.
  if [ -n "$guard" ] && [ -n "$py" ] && [ -x "$py" ] && [ ! -f "$script" ]; then
    echo "BLOCKED (fail-closed): falta el guard obligatorio $script. Que hacer: reinstala el kit (./install.sh --apply)." >&2
    exit 2
  fi

  if [ -z "$py" ] || [ ! -x "$py" ]; then
    [ -n "$guard" ] && warn_once "${guard%% *}" "[SCC] $guard NO esta activo: falta python3 en esta maquina, asi que ese guard no se ejecuta (los guards bash siguen activos). Que hacer: instala python3 (apt install python3) y reinicia la sesion."
    exit 0
  fi
  [ -n "$script" ] && [ -f "$script" ] || exit 0
  # -I -S: sin site ni PYTHON*; los hooks solo usan stdlib y un .pth ajeno no entra en un guard.
  exec "$py" -I -S "$@"
fi

cmd="${1:-}"
[ -n "$cmd" ] || exit 0

# Ruta absoluta ejecutable, o comando resoluble en PATH. Cualquier otra cosa
# (incluido un binario de tercero no instalado) es un no-op silencioso.
if [ -x "$cmd" ] || command -v "$cmd" >/dev/null 2>&1; then
  exec "$@"
fi
exit 0
