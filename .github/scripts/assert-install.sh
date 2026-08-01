#!/usr/bin/env bash
# assert-install.sh — post-condiciones de una instalacion de kit/install.sh.
#
# No basta con que install.sh salga con exit 0: eso no dice si hizo algo.
# Este script comprueba estado real (ficheros, permisos de ejecucion,
# validez del JSON) contra lo que install.sh *deberia* haber copiado, leyendo
# esa lista directamente del arbol fuente (kit/) en vez de tener una lista
# hardcodeada que se desincronice.
#
# Uso: assert-install.sh CLAUDE_HOME
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
KIT="$HERE/../../kit"
CLAUDE_HOME="${1:?uso: assert-install.sh CLAUDE_HOME}"

fail=0
check() { # desc, expresion-bash
  if eval "$2"; then
    echo "PASS · $1"
  else
    echo "FAIL · $1"
    fail=1
  fi
}

# settings.json: presente y JSON valido
check "settings.json es JSON valido" \
  '[ -f "$CLAUDE_HOME/settings.json" ] && python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$CLAUDE_HOME/settings.json"'

# settings.json contiene lo que debe: al menos una clave "hooks" no vacia
check "settings.json declara hooks" \
  'python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get(\"hooks\") else 1)" "$CLAUDE_HOME/settings.json"'

# Ficheros de config de nivel raiz
for f in CLAUDE.md settings.json sentinel-allowlist.json .gitleaks.toml; do
  check "$f instalado" '[ -f "$CLAUDE_HOME/$f" ]'
done

# Agentes: todo lo que kit/claude/agents/ trae debe estar instalado
for f in "$KIT"/claude/agents/*; do
  [ -e "$f" ] || continue
  b="$(basename "$f")"
  check "agente $b instalado" '[ -f "$CLAUDE_HOME/agents/$b" ]'
done

# Hooks: todo lo que kit/claude/hooks/ trae debe estar instalado y, si es
# .sh, ser ejecutable
for f in "$KIT"/claude/hooks/*; do
  [ -f "$f" ] || continue
  b="$(basename "$f")"
  check "hook $b instalado" '[ -f "$CLAUDE_HOME/hooks/$b" ]'
  case "$b" in
    *.sh) check "hook $b ejecutable" '[ -x "$CLAUDE_HOME/hooks/$b" ]' ;;
  esac
done

# Hook de git (pre-commit, Capa 2 de secretos)
check "hooks/git/pre-commit instalado" '[ -f "$CLAUDE_HOME/hooks/git/pre-commit" ]'
check "hooks/git/pre-commit ejecutable" '[ -x "$CLAUDE_HOME/hooks/git/pre-commit" ]'

# Sentinel
for f in "$KIT"/sentinel/*; do
  [ -e "$f" ] || continue
  b="$(basename "$f")"
  check "sentinel/$b instalado" '[ -e "$CLAUDE_HOME/sentinel/$b" ]'
done

echo "=================================="
if [ "$fail" -eq 0 ]; then
  echo "OK: post-condiciones de instalacion verificadas"
else
  echo "FAIL: la instalacion no cumple las post-condiciones esperadas"
fi
exit "$fail"
