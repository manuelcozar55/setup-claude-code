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
# Uso:
#   optional-hook.sh <cmd> [args...]              # ejecutable en PATH o ruta absoluta
#   optional-hook.sh --python <script.py> [args]  # resuelve el intérprete él solo
set -u

if [ "${1:-}" = "--python" ]; then
  shift
  script="${1:-}"

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

  [ -n "$py" ] && [ -x "$py" ] || exit 0
  [ -n "$script" ] && [ -f "$script" ] || exit 0
  exec "$py" "$@"
fi

cmd="${1:-}"
[ -n "$cmd" ] || exit 0

# Ruta absoluta ejecutable, o comando resoluble en PATH. Cualquier otra cosa
# (incluido un binario de tercero no instalado) es un no-op silencioso.
if [ -x "$cmd" ] || command -v "$cmd" >/dev/null 2>&1; then
  exec "$@"
fi
exit 0
