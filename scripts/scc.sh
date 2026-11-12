#!/usr/bin/env bash
# Delegado: el lanzador vive instalado en $CLAUDE_HOME/bin/scc (lo deja install.sh --apply). Sin instalar,
# carga el cockpit y los plugins desde este clon.
set -euo pipefail
SCRIPT=$(readlink -f -- "${BASH_SOURCE[0]}")
REPO=$(cd "$(dirname "$SCRIPT")/.." && pwd)
INSTALADO="${CLAUDE_HOME:-$HOME/.claude}/bin/scc"
if [ -x "$INSTALADO" ]; then exec "$INSTALADO" "$@"; fi
exec claude --plugin-dir "$REPO/kit/mods/cockpit" --plugin-dir "$REPO/kit/plugins/esenciales" "$@"
