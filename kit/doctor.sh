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
  # shellcheck disable=SC2016 # patron literal para grep -oE, no interpolacion de shell
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
n=$(find "$CLAUDE_HOME/agents" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
if [ "$n" -ge 1 ]; then
  pass "agentes instalados: $n  (fuente: find agents/*.md)"
else
  warn "sin agentes"
fi

# 4. venv de tools (opcional -> WARN)
if [ -x "$HOME/.venvs/tools/bin/python3" ]; then pass "venv tools presente"; else warn "venv tools ausente (opcional; ver docs/02-install.md)"; fi

# 5. Headroom (opcional -> WARN)
if command -v rtk >/dev/null 2>&1; then pass "Headroom rtk presente"; else warn "Headroom no instalado (opcional; ver docs/03-headroom.md)"; fi

# 5b. gitleaks (opcional -> WARN): requerido solo para activar la Capa 2 de
# secretos (hooks/git/pre-commit); la Capa 1 (secret-guard.sh) funciona sin él.
gitleaks_bin=""
if command -v gitleaks >/dev/null 2>&1; then gitleaks_bin="gitleaks"
elif [ -x "$HOME/.local/bin/gitleaks" ]; then gitleaks_bin="$HOME/.local/bin/gitleaks"
fi
if [ -n "$gitleaks_bin" ]; then
  gitleaks_ver="$("$gitleaks_bin" version 2>/dev/null | tr -d '\n')"
  pass "gitleaks presente${gitleaks_ver:+ ($gitleaks_ver)}  (fuente: command -v gitleaks)"
else
  warn "gitleaks no instalado: la Capa 2 de secretos (pre-commit) no puede activarse (ver docs/05-security.md)"
fi

# 5c. marca persistente de checksum de gitleaks no coincidente (ver install.sh)
# install.sh nunca falla por esto (dependencia opcional), pero deja esta marca
# para que quien no vio la salida del instalador se entere igualmente.
if [ -f "$CLAUDE_HOME/.gitleaks-checksum-mismatch" ]; then
  fail "checksum de gitleaks no coincidio en una instalacion anterior: ver $CLAUDE_HOME/.gitleaks-checksum-mismatch (posible ataque a la cadena de suministro; ver CONTRIBUTING.md)"
fi

# 5d. Capa 2 de secretos: core.hooksPath en el repo actual (opcional -> WARN)
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  hooks_path="$(git config --get core.hooksPath 2>/dev/null || true)"
  if [ -n "$hooks_path" ]; then
    pass "Capa 2 activa en este repo: core.hooksPath=$hooks_path  (fuente: git config --get core.hooksPath)"
  else
    warn "Capa 2 de secretos no activada en este repo: core.hooksPath sin configurar (opt-in con: bash $KIT/install.sh --enable-secrets-layer2)"
  fi
else
  warn "no estas dentro de un repo git: no se puede comprobar la Capa 2 (core.hooksPath)"
fi

# 6. gate de secretos sobre el kit
if bash "$KIT/scan-secrets.sh" "$KIT" >/dev/null 2>&1; then pass "kit sin secretos  (fuente: scan-secrets.sh)"; else fail "scan-secrets detectó material sensible en el kit"; fi

echo "== $( [ "$fails" -eq 0 ] && echo 'OK (0 FAIL)' || echo "$fails FAIL" ) =="
[ "$fails" -eq 0 ]
