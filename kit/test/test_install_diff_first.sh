#!/usr/bin/env bash
# test_install_diff_first.sh — install.sh detecta cuando CLAUDE_HOME es EN SI
# MISMO un repositorio git con remoto (p.ej. un "claude-config-private" del
# usuario) y, en ese caso, NUNCA escribe encima: genera aparte el arbol que
# instalaria y muestra el diff contra lo instalado, saliendo con exit 0 (no
# es un error, es el modo por defecto en ese escenario). --apply fuerza la
# escritura real; --plan fuerza el modo diff aunque no sea un repo git.
#
# El caso "un HOME temporal normal escribe igual que siempre" es la garantia
# de que este cambio no rompe las otras 16 suites; el caso de falsabilidad
# demuestra que la deteccion SI dispara de verdad (no un chequeo que nunca
# se activa), siguiendo el patron de test_gitattributes.sh / test_exec_modes.sh.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

# --- Caso 1: HOME temporal normal (no es repo git) -> escribe, como siempre
export CLAUDE_HOME="$tmp/dot-normal"
bash "$KIT/install.sh" >/dev/null 2>&1
ck "$([ -f "$CLAUDE_HOME/CLAUDE.md" ] && echo y || echo n)" "y" "HOME temporal normal: install.sh sigue escribiendo (comportamiento intacto)"

# --- Caso 2: CLAUDE_HOME ES un repo git con remoto -> NO escribe, sale 0 ---
export CLAUDE_HOME="$tmp/dot-git"
mkdir -p "$CLAUDE_HOME"
git -C "$CLAUDE_HOME" init -q
git -C "$CLAUDE_HOME" remote add origin https://example.com/claude-config-private.git
echo "MIO, NO TOCAR" > "$CLAUDE_HOME/CLAUDE.md"

set +e
out="$(MCHARNESS_OUT="$tmp/out-1" bash "$KIT/install.sh" 2>&1)"; rc=$?
set -e
ck "$rc" "0" "CLAUDE_HOME repo git con remoto: install.sh sale con exit 0 (no es un error)"
ck "$(cat "$CLAUDE_HOME/CLAUDE.md")" "MIO, NO TOCAR" "CLAUDE_HOME repo git con remoto: NO se escribe encima"
ck "$([ -d "$tmp/out-1" ] && echo y || echo n)" "y" "se genera el arbol que se instalaria en MCHARNESS_OUT"
ck "$(echo "$out" | grep -qic 'diff' && echo y || echo n)" "y" "la salida menciona el diff"
ck "$(echo "$out" | grep -qic -- '--apply' && echo y || echo n)" "y" "la salida indica como forzar la escritura real (--apply)"

# --- Caso 3: --apply en ese mismo escenario -> SI escribe -------------------
set +e
MCHARNESS_OUT="$tmp/out-2" bash "$KIT/install.sh" --apply >/dev/null 2>&1; rc3=$?
set -e
ck "$rc3" "0" "--apply sobre CLAUDE_HOME (repo git con remoto): sale con exit 0"
ck "$([ -f "$CLAUDE_HOME/settings.json" ] && echo y || echo n)" "y" "--apply SI escribe (instala settings.json)"
# CLAUDE.md es prosa escrita a mano y no se puede fusionar: --apply escribe todo lo demas,
# pero NO la pisa; deja la del kit al lado. Antes SI la sobreescribia (con backup), y eso
# costo trabajo irrecuperable en una maquina real: un backup que hay que descubrir no es una
# salvaguarda, es una autopsia. El proposito de este caso -- que --apply no sea un no-op --
# lo sostiene la asercion de settings.json de arriba y el backup de aqui abajo.
ck "$(cat "$CLAUDE_HOME/CLAUDE.md")" "MIO, NO TOCAR" "--apply NO pisa un CLAUDE.md escrito a mano"
ck "$([ -f "$CLAUDE_HOME/CLAUDE.kit.md" ] && echo y || echo n)" "y" "--apply deja la version del kit en CLAUDE.kit.md"
# Y el mecanismo de backup sigue vivo bajo --apply, sobre un fichero que el kit SI posee.
echo "# MOD" >> "$CLAUDE_HOME/.gitleaks.toml"
set +e; MCHARNESS_OUT="$tmp/out-3" bash "$KIT/install.sh" --apply >/dev/null 2>&1; set -e
ck "$(find "$CLAUDE_HOME/backups" -mindepth 2 -maxdepth 2 -name .gitleaks.toml 2>/dev/null | wc -l | tr -d ' ')" "1" "--apply sigue haciendo backup de lo que el kit SI posee"

# --- Caso 4: --plan fuerza el modo diff aunque NO sea un repo git ----------
export CLAUDE_HOME="$tmp/dot-noplan"
set +e
MCHARNESS_OUT="$tmp/out-3" bash "$KIT/install.sh" --plan >/dev/null 2>&1; rc4=$?
set -e
ck "$rc4" "0" "--plan sobre CLAUDE_HOME normal (no repo git): sale con exit 0"
ck "$([ -e "$CLAUDE_HOME" ] && echo existe || echo no)" "no" "--plan NO escribe en CLAUDE_HOME aunque no sea un repo git"
ck "$([ -d "$tmp/out-3" ] && echo y || echo n)" "y" "--plan genera igualmente el arbol en MCHARNESS_OUT"

# --- Auto-falsabilidad: ¿la deteccion SI dispara de verdad? -----------------
# Un directorio git SIN remoto no debe activar el modo diff (solo cuenta un
# repo git CON remoto configurado): si esto no se cumpliera, el chequeo
# dispararia siempre que hubiera un .git y no seria una comprobacion real.
export CLAUDE_HOME="$tmp/dot-git-sin-remoto"
mkdir -p "$CLAUDE_HOME"
git -C "$CLAUDE_HOME" init -q
set +e
bash "$KIT/install.sh" >/dev/null 2>&1; rc5=$?
set -e
ck "$rc5" "0" "repo git SIN remoto: install.sh sale 0"
ck "$([ -f "$CLAUDE_HOME/CLAUDE.md" ] && echo y || echo n)" "y" "repo git SIN remoto NO activa el modo diff (escribe igual, falsabilidad del check)"

# --- Caso 5: sin MCHARNESS_OUT, el arbol va a un temporal, no al cwd -------
# La copia que se generaba en $PWD se quedaba ahi: una instantanea del arbol
# instalable que envejece en el arbol de trabajo, con nueve divergencias en la
# direccion peligrosa, y que despues se lee como si fuera fuente. El artefacto
# de un diff es efimero: su sitio es un temporal.
export CLAUDE_HOME="$tmp/dot-tmpout"
mkdir -p "$tmp/cwd-limpio"
set +e
out5="$(cd "$tmp/cwd-limpio" && env -u MCHARNESS_OUT bash "$KIT/install.sh" --plan 2>&1)"; rc5b=$?
set -e
ck "$rc5b" "0" "--plan sin MCHARNESS_OUT: sale con exit 0"
ck "$([ -e "$tmp/cwd-limpio/.mcharness-out" ] && echo existe || echo no)" "no" \
   "--plan sin MCHARNESS_OUT NO deja .mcharness-out en el directorio de trabajo"
ruta5="$(printf '%s\n' "$out5" | sed -n 's/.*generado en: //p' | head -1)"
ck "$(case "$ruta5" in "$tmp/cwd-limpio"*) echo dentro ;; "") echo ninguna ;; *) echo fuera ;; esac)" "fuera" \
   "el arbol se genera fuera del directorio de trabajo y la salida dice donde"

# --- Caso 6: dos '--plan' seguidos no acumulan un arbol por invocacion ------
# El primer arreglo (mktemp -d por invocacion) resolvio el cwd pero abrio una
# fuga: cada '--plan' dejaba un cckit-diff.XXXXXX nuevo en /tmp y nada lo
# limpiaba (sin trap). La correccion usa una ruta fija por uid, borrada y
# recreada al INICIO de cada run: el arbol sobrevive a la ejecucion para que
# el usuario copie de el a mano (asi lo dice el mensaje de cierre de la
# funcion), pero nunca hay mas de uno acumulandose.
export CLAUDE_HOME="$tmp/dot-tmpout6"
tmpdir6="$tmp/tmpdir-fijo"
mkdir -p "$tmpdir6"
set +e
TMPDIR="$tmpdir6" env -u MCHARNESS_OUT bash "$KIT/install.sh" --plan >/dev/null 2>&1; rc6a=$?
TMPDIR="$tmpdir6" env -u MCHARNESS_OUT bash "$KIT/install.sh" --plan >/dev/null 2>&1; rc6b=$?
set -e
ck "$rc6a" "0" "--plan (1a pasada) sin MCHARNESS_OUT: sale con exit 0"
ck "$rc6b" "0" "--plan (2a pasada) sin MCHARNESS_OUT: sale con exit 0"
ck "$(find "$tmpdir6" -maxdepth 1 -name 'cckit-diff*' | wc -l | tr -d ' ')" "1" \
   "dos '--plan' seguidos dejan un solo arbol cckit-diff, no uno por invocacion"
dir6="$(find "$tmpdir6" -maxdepth 1 -name 'cckit-diff*' -print -quit)"
ck "$([ -n "$dir6" ] && [ -d "$dir6" ] && echo y || echo n)" "y" \
   "el arbol sigue existiendo tras salir el proceso (sobrevive para que el usuario copie de el)"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
