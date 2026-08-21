#!/usr/bin/env bash
# Detecta el comando de verificacion de un proyecto, sin preguntar a nadie.
#
# Por que existe: el harness pedia al usuario que declarase un oraculo. Pedir no funciona
# -- la medicion decia 27,7 % de sesiones con oraculo pese a tener reglas exigiendolo.
# Esto lo averigua solo, y lo que se averigua solo no depende de que nadie se acuerde.
#
# Uso:  detect-oracle.sh [DIR]        imprime el comando, o nada si no hay
#       detect-oracle.sh --why [DIR]  imprime ademas por que lo eligio
#
# Salida: exit 0 con el comando en stdout, exit 1 si no se encontro ninguno.
set -uo pipefail

WHY=0
[ "${1:-}" = "--why" ] && { WHY=1; shift; }
D="${1:-$PWD}"
[ -d "$D" ] || exit 1

emit() {  # emit <comando> <razon>
  printf '%s\n' "$1"
  [ "$WHY" -eq 1 ] && printf '  motivo: %s\n' "$2" >&2
  exit 0
}

# El orden es deliberado: de mas especifico y barato a mas generico y caro. Un `make test`
# declarado por el proyecto sabe mas que cualquier heuristica nuestra sobre el proyecto.

# 1. Makefile con target test: es una declaracion explicita del propio proyecto.
if [ -f "$D/Makefile" ] && grep -qE '^test:' "$D/Makefile" 2>/dev/null; then
  emit "make test" "Makefile declara un target 'test'"
fi
if [ -f "$D/justfile" ] && grep -qE '^test:' "$D/justfile" 2>/dev/null; then
  emit "just test" "justfile declara una receta 'test'"
fi

# 2. Python. Se busca un interprete que REALMENTE tenga pytest, y se emite por ruta
#    absoluta: invocarlo por nombre suelto lo expone a la reescritura del hook de Bash
#    (ver knowledge/MISTAKES.md M-001), y entonces el oraculo no ejecuta lo que dice.
if [ -f "$D/pytest.ini" ] || [ -f "$D/tox.ini" ] || [ -f "$D/conftest.py" ] \
   || [ -f "$D/tests/conftest.py" ] \
   || { [ -f "$D/pyproject.toml" ] && grep -q 'tool.pytest' "$D/pyproject.toml" 2>/dev/null; }; then
  base="$(basename "$D")"
  # Candidatos, en orden de confianza. Se prueban variantes del nombre porque un venv
  # suele llamarse como el nucleo del proyecto ("riego" para "sistema-riego").
  cands=( "$D/.venv/bin/pytest" "$D/venv/bin/pytest" "$HOME/.venvs/$base/bin/pytest" )
  for variant in "${base#*-}" "${base%%-*}" "${base//-/_}"; do
    [ -n "$variant" ] && [ "$variant" != "$base" ] && cands+=( "$HOME/.venvs/$variant/bin/pytest" )
  done
  for py in "${cands[@]}"; do
    if [ -x "$py" ]; then
      emit "$py -q" "hay config de pytest y un venv del proyecto en $(dirname "$py")"
    fi
  done
  # DELIBERADAMENTE no se cae a ~/.venvs/tools: es el venv de herramientas y no tiene las
  # dependencias del proyecto. Usarlo daria rojo por ImportError, no por el codigo -- un
  # oraculo que culpa al codigo de un fallo de entorno es peor que no tener oraculo.
  # Config de pytest pero ningun interprete: es un oraculo DECLARADO y NO INVOCABLE.
  # No es lo mismo que "da rojo": es que no hay sensor. Se dice, no se finge.
  [ "$WHY" -eq 1 ] && echo "  aviso: hay config de pytest pero ningun venv DEL PROYECTO con pytest. Oraculo declarado y NO invocable: eso no es 'da rojo', es que no hay sensor." >&2
fi

# 3. Node. Se lee el script real en vez de asumir que existe.
if [ -f "$D/package.json" ] && command -v jq >/dev/null 2>&1; then
  t=$(jq -r '.scripts.test // empty' "$D/package.json" 2>/dev/null)
  if [ -n "$t" ] && [ "$t" != "echo \"Error: no test specified\" && exit 1" ]; then
    if [ -f "$D/pnpm-lock.yaml" ]; then   emit "pnpm test" "package.json define scripts.test y hay pnpm-lock"
    elif [ -f "$D/yarn.lock" ]; then      emit "yarn test" "package.json define scripts.test y hay yarn.lock"
    else                                  emit "npm test"  "package.json define scripts.test"; fi
  fi
fi

# 4. Otros ecosistemas, por marcador de proyecto.
[ -f "$D/Cargo.toml" ]  && emit "cargo test"  "Cargo.toml presente"
[ -f "$D/go.mod" ]      && emit "go test ./..." "go.mod presente"
[ -f "$D/build.gradle" ] || [ -f "$D/build.gradle.kts" ] && emit "./gradlew test" "proyecto Gradle"
[ -f "$D/pom.xml" ]     && emit "mvn -q test" "pom.xml presente"

# 5. Ultimo recurso: un linter no prueba que el codigo haga lo correcto, pero es un sensor
#    computacional real y es infinitamente mejor que ninguno.
if find "$D" -maxdepth 2 -name '*.sh' -not -path '*/.git/*' -print -quit 2>/dev/null | grep -q .; then
  command -v shellcheck >/dev/null 2>&1 && \
    emit "shellcheck -x \$(find . -name '*.sh' -not -path './.git/*')" "hay scripts .sh y shellcheck disponible"
fi

exit 1
