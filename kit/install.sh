#!/usr/bin/env bash
# install.sh — Instala el kit saneado en CLAUDE_HOME (idempotente, con backup).
# Uso: [CLAUDE_HOME=$HOME/.claude] bash install.sh
set -euo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
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
for f in "$KIT"/claude/agents/*; do [ -e "$f" ] && install_file "$f" "$CLAUDE_HOME/agents/$(basename "$f")"; done
for f in "$KIT"/claude/hooks/*;  do [ -e "$f" ] && install_file "$f" "$CLAUDE_HOME/hooks/$(basename "$f")"; done
for f in "$KIT"/sentinel/*;      do [ -e "$f" ] && install_file "$f" "$CLAUDE_HOME/sentinel/$(basename "$f")"; done
chmod +x "$CLAUDE_HOME"/hooks/*.sh 2>/dev/null || true

echo "==> Config instalada. Terceros (ver docs/): superpowers, Headroom, agent-browser, venv de tools."
echo "==> Rellena tus claves:  cp $KIT/.env.example \$HOME/.claude/.env  &&  editar"
echo "==> Verifica:            bash $KIT/doctor.sh"
