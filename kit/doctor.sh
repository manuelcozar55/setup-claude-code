#!/usr/bin/env bash
# doctor.sh — Verifica una instalación del kit. Evidencia por componente.
# Uso: [CLAUDE_HOME=$HOME/.claude] bash doctor.sh
set -uo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL · jq no instalado (requerido por doctor; ver docs/02-install.md)"
  exit 1
fi
fails=0
pass(){ echo "PASS · $1"; }
warn(){ echo "WARN · $1"; }
fail(){ echo "FAIL · $1"; fails=$((fails+1)); }

echo "== doctor: CLAUDE_HOME=$CLAUDE_HOME =="

# 1. settings.json válido
if [ -f "$CLAUDE_HOME/settings.json" ] && jq empty "$CLAUDE_HOME/settings.json" 2>/dev/null; then
  pass "settings.json válido  (fuente: jq empty)"
else
  fail "settings.json ausente o inválido"
fi

# 2. hooks referenciados existen y son ejecutables
if [ -f "$CLAUDE_HOME/settings.json" ]; then
  refs="$(jq -r '.hooks // {} | .. | .command? // empty' "$CLAUDE_HOME/settings.json" 2>/dev/null \
          | grep -oE '\$HOME/\.claude/hooks/[^" ]+|\$HOME/\.claude/sentinel/[^" ]+' | sort -u)"
  miss=0
  while IFS= read -r r; do
    [ -z "$r" ] && continue
    path="${r/\$HOME/$HOME}"; path="${path/$HOME\/.claude/$CLAUDE_HOME}"
    if [ ! -e "$path" ]; then
      fail "hook/ref no encontrado: $r"; miss=1
    elif [[ "$path" == *.sh && ! -x "$path" ]]; then
      fail "hook no ejecutable: $r"; miss=1
    fi
  done <<< "$refs"
  [ "$miss" -eq 0 ] && pass "hooks referenciados presentes y ejecutables  (fuente: jq .hooks + test -e/-x)"
fi

# 2b. capa de IOCs de Sentinel (opcional -> WARN)
if [ -f "$CLAUDE_HOME/hooks/iocs.json" ]; then
  pass "Sentinel IOC layer activa  (fuente: test -f hooks/iocs.json)"
else
  warn "Sentinel IOC layer inactiva: falta iocs.json (opcional; ver docs/05-security.md). Los guards de Bash siguen activos."
fi

# 3. agentes
n=$(ls "$CLAUDE_HOME"/agents/*.md 2>/dev/null | wc -l | tr -d ' ')
[ "$n" -ge 1 ] && pass "agentes instalados: $n  (fuente: ls agents/*.md)" || warn "sin agentes"

# 4. venv de tools (opcional -> WARN)
if [ -x "$HOME/.venvs/tools/bin/python3" ]; then pass "venv tools presente"; else warn "venv tools ausente (opcional; ver docs/02-install.md)"; fi

# 5. Headroom (opcional -> WARN)
if command -v rtk >/dev/null 2>&1; then pass "Headroom rtk presente"; else warn "Headroom no instalado (opcional; ver docs/03-headroom.md)"; fi

# 6. gate de secretos sobre el kit
if bash "$KIT/scan-secrets.sh" "$KIT" >/dev/null 2>&1; then pass "kit sin secretos  (fuente: scan-secrets.sh)"; else fail "scan-secrets detectó material sensible en el kit"; fi

echo "== $( [ "$fails" -eq 0 ] && echo 'OK (0 FAIL)' || echo "$fails FAIL" ) =="
[ "$fails" -eq 0 ]
