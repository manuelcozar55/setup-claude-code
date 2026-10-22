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
#
# shellcheck disable=SC2016 # las cadenas '...$CLAUDE_HOME...' pasadas a check()
# son literales a proposito: se expanden dentro de eval "$2" (ver check()),
# no en el momento de escribirlas aqui arriba.
# shellcheck disable=SC2034 # CLAUDE_HOME si se usa: dentro de esas cadenas,
# via el eval de check(); shellcheck no seva el uso indirecto.
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

# Inventario completo: cada fichero que install.sh despliega desde kit/claude,
# incluidas skills recursivas, y Sentinel. -f acepta symlinks que resuelven a un
# fichero: el instalador los preserva para permitir componentes proyectados.
# __pycache__ contiene resultados de compilacion, no componentes del kit.
for tree in claude sentinel; do
  while IFS= read -r -d '' src; do
    rel="${src#"$KIT/$tree/"}"
    case "$tree" in
      claude) dst="$CLAUDE_HOME/$rel"; nombre="$rel" ;;
      sentinel) dst="$CLAUDE_HOME/sentinel/$rel"; nombre="sentinel/$rel" ;;
    esac
    check "$nombre instalado" '[ -f "$dst" ]'
    if [ -x "$src" ]; then
      check "$nombre ejecutable" '[ -x "$dst" ]'
    fi
  done < <(find "$KIT/$tree" -type d -name __pycache__ -prune -o -type f -print0)
done

echo "=================================="
if [ "$fail" -eq 0 ]; then
  echo "OK: post-condiciones de instalacion verificadas"
else
  echo "FAIL: la instalacion no cumple las post-condiciones esperadas"
fi
exit "$fail"
