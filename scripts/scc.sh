#!/usr/bin/env bash
set -euo pipefail
SCRIPT=$(readlink -f -- "${BASH_SOURCE[0]}")
REPO=$(cd "$(dirname "$SCRIPT")/.." && pwd)
exec claude --plugin-dir "$REPO/kit/mods/cockpit" --plugin-dir "$REPO/kit/plugins/esenciales" "$@"
