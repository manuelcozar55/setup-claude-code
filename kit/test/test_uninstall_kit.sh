#!/usr/bin/env bash
# test_uninstall_kit.sh — uninstall.sh --kit desinstala de verdad, segun el manifiesto de install.sh:
#   1. HOME vacio -> install --apply -> uninstall --kit --apply: el listado de ficheros vuelve a ser el de antes
#      (salvo backups/), enlaces del bindir incluidos.
#   2. HOME con settings.json y CLAUDE.md propios: quedan byte a byte como antes de instalar.
#   3. Lo modificado por la persona se conserva y se lista; un enlace ajeno del bindir no se toca.
#   4. Simulacro por defecto: no cambia nada. Sin manifiesto: error que explica que hacer.
# Falsable: con un manifiesto sin sumas validas no se borra nada. HOME aislado, sin red.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$HERE/../.."
UN="$REPO/uninstall.sh"; INST="$REPO/kit/install.sh"
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }
listado() { ( cd "$1" && find . -path ./.claude/backups -prune -o \( -type f -o -type l \) -print | LC_ALL=C sort ); }
tree_sum() { ( cd "$1" && find . -type f -exec sha256sum {} + | LC_ALL=C sort | sha256sum | cut -d' ' -f1 ); }
nuevo_home() { export HOME="$tmp/$1"; export CLAUDE_HOME="$HOME/.claude" BACKUP_DIR="$HOME/backups"; mkdir -p "$HOME"; }

# ---- 1. HOME vacio
nuevo_home h1
listado "$HOME" > "$tmp/antes1"
bash "$INST" --apply >/dev/null 2>&1
ck "$([ -L "$HOME/.local/bin/handoff" ] && echo y)" "y" "install enlazo handoff en el bindir"
before="$(tree_sum "$HOME")"
bash "$UN" --kit >"$tmp/dry1" 2>&1; rc=$?
ck "$rc" "0" "--kit sin --apply (simulacro) sale 0"
ck "$(tree_sum "$HOME")" "$before" "el simulacro no cambia nada"
ck "$(grep -c -- '--kit --apply' "$tmp/dry1")" "1" "el simulacro dice como ejecutar de verdad"
bash "$UN" --kit --apply >"$tmp/ap1" 2>&1; rc=$?
ck "$rc" "0" "--kit --apply sale 0"
listado "$HOME" > "$tmp/despues1"
ck "$(diff "$tmp/antes1" "$tmp/despues1" | wc -l | tr -d ' ')" "0" "HOME vacio: el listado de ficheros y enlaces vuelve a ser el de antes (salvo backups/)"
ck "$(find "$CLAUDE_HOME/backups" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" "1" "deja una copia previa en backups/"
ck "$(find "$CLAUDE_HOME" -mindepth 1 -maxdepth 1 ! -name backups | wc -l | tr -d ' ')" "0" "no quedan directorios vacios del kit"

# ---- 2. HOME con settings.json y CLAUDE.md propios (formato a mano, a proposito)
nuevo_home h2
mkdir -p "$CLAUDE_HOME/hooks"
printf '{\n\t"model": "sonnet",\n  "env": {"MIA": "1"},\n\t"permissions": {"allow": ["Bash(mio:*)"]},\n  "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "/usr/bin/mio-stop.sh"}]}]}\n}\n' > "$CLAUDE_HOME/settings.json"
printf '# Mis reglas\nSin AGENTS.\n' > "$CLAUDE_HOME/CLAUDE.md"
echo '#!/bin/sh' > "$CLAUDE_HOME/hooks/mio.sh"
mkdir -p "$HOME/.local/bin"; printf '#!/bin/sh\n' > "$HOME/.local/bin/cupo"; chmod +x "$HOME/.local/bin/cupo"
cp -p "$CLAUDE_HOME/settings.json" "$tmp/s.antes"; cp -p "$CLAUDE_HOME/CLAUDE.md" "$tmp/c.antes"
listado "$HOME" > "$tmp/antes2"
bash "$INST" --apply >/dev/null 2>&1
ck "$(jq -r '.permissions.deny | length > 3' "$CLAUDE_HOME/settings.json")" "true" "tras instalar, settings.json lleva los permisos del kit"
bash "$UN" --kit --apply >"$tmp/ap2" 2>&1; rc=$?
ck "$rc" "0" "--kit --apply con ficheros propios sale 0"
ck "$(cmp -s "$CLAUDE_HOME/settings.json" "$tmp/s.antes" && echo y)" "y" "settings.json propio queda byte a byte como antes de instalar"
ck "$(cmp -s "$CLAUDE_HOME/CLAUDE.md" "$tmp/c.antes" && echo y)" "y" "CLAUDE.md propio queda byte a byte"
listado "$HOME" > "$tmp/despues2"
ck "$(diff "$tmp/antes2" "$tmp/despues2" | wc -l | tr -d ' ')" "0" "el listado vuelve a ser el de antes (hook propio y enlace ajeno incluidos)"

# ---- 3. modificado por la persona se conserva y se lista
nuevo_home h3
bash "$INST" --apply >/dev/null 2>&1
echo "# mio" >> "$CLAUDE_HOME/hooks/branch-guard.sh"
rm "$HOME/.local/bin/cupo"; printf '#!/bin/sh\n' > "$HOME/.local/bin/cupo"
echo '{"a":1}' > "$tmp/otro.json"
bash "$UN" --kit --apply >"$tmp/ap3" 2>&1; rc=$?
ck "$rc" "0" "sale 0 aunque conserve ficheros"
ck "$([ -f "$CLAUDE_HOME/hooks/branch-guard.sh" ] && echo y)" "y" "el hook modificado se conserva"
ck "$(grep -c 'hooks/branch-guard.sh (modificado por ti)' "$tmp/ap3")" "1" "y se lista como conservado"
ck "$([ -f "$HOME/.local/bin/cupo" ] && [ ! -L "$HOME/.local/bin/cupo" ] && echo y)" "y" "un fichero ajeno en el bindir no se toca"
ck "$([ -L "$HOME/.local/bin/handoff" ] && echo y)" "" "el enlace propio del kit se quita"
ck "$([ -e "$CLAUDE_HOME/hooks/destructive-guard.sh" ] && echo y)" "" "el resto de hooks sin tocar se borra"
ck "$([ -e "$CLAUDE_HOME/.kit-manifest" ] && echo y)" "" "el manifiesto se retira"

# ---- 4. un enlace que apunta a otro sitio no se quita
nuevo_home h4
bash "$INST" --apply >/dev/null 2>&1
ln -sfn /bin/true "$HOME/.local/bin/oraculo"
bash "$UN" --kit --apply >/dev/null 2>&1
ck "$(readlink "$HOME/.local/bin/oraculo")" "/bin/true" "un enlace del bindir que no apunta a CLAUDE_HOME/bin no se quita"

# ---- 5. sin manifiesto y manifiesto sin sumas validas
nuevo_home h5
mkdir -p "$CLAUDE_HOME"
bash "$UN" --kit >"$tmp/o5" 2>&1; rc=$?
ck "$rc" "1" "sin manifiesto: rc 1"
ck "$(grep -c 'install.sh --apply' "$tmp/o5")" "1" "y dice que reinstalar"
nuevo_home h6
bash "$INST" --apply >/dev/null 2>&1
sed -i 's/^[0-9a-f]\{64\}/0000000000000000000000000000000000000000000000000000000000000000/' "$CLAUDE_HOME/.kit-manifest"
bash "$UN" --kit --apply >/dev/null 2>&1
ck "$([ -f "$CLAUDE_HOME/hooks/branch-guard.sh" ] && [ -f "$CLAUDE_HOME/bin/handoff" ] && echo y)" "y" "falsable: con sumas que no coinciden no se borra ningun fichero del kit"

# ---- 6. el modo antiguo no cambia: sin backup, remite a --kit
nuevo_home h7
mkdir -p "$CLAUDE_HOME"
bash "$UN" >"$tmp/o7" 2>&1; rc=$?
ck "$rc" "1" "sin backup y sin --kit: sigue fallando"
ck "$(grep -c -- '--kit' "$tmp/o7")" "1" "y el mensaje remite a --kit"

echo "== $pass ok, $fail fallos =="
[ "$fail" -eq 0 ]
