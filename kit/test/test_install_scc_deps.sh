#!/usr/bin/env bash
# test_install_scc_deps.sh — W4 entregables 10 y 11:
#  10. install.sh --apply copia el cockpit y los plugins a CLAUDE_HOME/scc (sin tests ni node_modules, dentro del
#      manifiesto) e instala el lanzador bin/scc enlazado en el bindir: scc --version informa de la version del
#      kit y de claude; scc -p hola pasa a claude un --plugin-dir por directorio copiado. --sin-cockpit lo omite
#      y --plan lo muestra. uninstall --kit lo quita todo.
#  11. install.sh (tambien --plan) comprueba python3, jq, git y bash >= 5: sin jq/git para con la orden; sin
#      python3 avisa de las capas apagadas y exige --sin-python. doctor da FAIL sin python3 si sus capas estan
#      cableadas. Con un PATH recortado (symlinks a todo menos python).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."; REPO="$KIT/.."
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }
VER="$(tr -d '[:space:]' < "$REPO/VERSION")"

# claude falso: imprime sus argumentos, uno por linea.
mkdir -p "$tmp/fake"; printf '#!/bin/sh\nif [ "$1" = "--version" ]; then echo "9.9.9 (fake)"; exit 0; fi\nfor a in "$@"; do echo "ARG:$a"; done\n' > "$tmp/fake/claude"; chmod +x "$tmp/fake/claude"

# ---- 10. lanzador y copia
export HOME="$tmp/h"; mkdir -p "$HOME"; export CLAUDE_HOME="$HOME/.claude"
bash "$KIT/install.sh" --apply >"$tmp/i.log" 2>&1
ck "$([ -f "$CLAUDE_HOME/scc/mods/cockpit/.claude-plugin/plugin.json" ] && echo y)" "y" "copia el cockpit a CLAUDE_HOME/scc/mods/cockpit"
ck "$([ -d "$CLAUDE_HOME/scc/plugins/esenciales/skills" ] && echo y)" "y" "copia los plugins esenciales"
ck "$(find "$CLAUDE_HOME/scc" \( -name tests -o -name node_modules \) | wc -l | tr -d ' ')" "0" "sin tests ni node_modules"
ck "$(grep -c '  scc/mods/cockpit/' "$CLAUDE_HOME/.kit-manifest" | awk '{print ($1>0)?"y":"n"}')" "y" "lo copiado entra en el manifiesto"
ck "$([ -L "$HOME/.local/bin/scc" ] && [ -x "$CLAUDE_HOME/bin/scc" ] && echo y)" "y" "bin/scc instalado y enlazado en el bindir"
out="$(PATH="$tmp/fake:$PATH" "$HOME/.local/bin/scc" --version 2>&1)"; rc=$?
ck "$rc" "0" "scc --version sale 0"
ck "$(echo "$out" | grep -c "scc (kit) $VER")" "1" "scc --version imprime la version del kit instalada"
ck "$(echo "$out" | grep -c 'claude 9.9.9')" "1" "scc --version imprime la de claude"
out="$(PATH="$tmp/fake:$PATH" "$HOME/.local/bin/scc" -p hola 2>&1)"
ck "$(echo "$out" | grep -cx "ARG:$CLAUDE_HOME/scc/mods/cockpit\|ARG:$CLAUDE_HOME/scc/plugins/esenciales")" "2" "scc -p hola pasa los dos --plugin-dir a CLAUDE_HOME/scc"
ck "$(echo "$out" | grep -c '^ARG:--plugin-dir$')" "2" "uno por directorio"
ck "$(echo "$out" | tail -2 | tr '\n' ' ')" "ARG:-p ARG:hola " "y despues los argumentos de la persona, tal cual"
out="$(PATH="/usr/bin:/bin" "$CLAUDE_HOME/bin/scc" --version 2>&1)"; rc=$?
ck "$rc" "0" "scc --version sale 0 aunque claude no este en el PATH"

# --plan lo muestra; --sin-cockpit lo omite
H2="$tmp/h2"; mkdir -p "$H2"
out="$(HOME="$H2" CLAUDE_HOME="$H2/.claude" TMPDIR="$tmp" bash "$KIT/install.sh" --plan 2>&1)"
ck "$(echo "$out" | grep -c 'scc/mods/cockpit/.claude-plugin/plugin.json')" "1" "--plan lista los ficheros del cockpit"
ck "$(echo "$out" | grep -c 'cockpit y plugins del kit: se copiarian')" "1" "--plan lo explica"
out="$(HOME="$H2" CLAUDE_HOME="$H2/.claude" TMPDIR="$tmp" bash "$KIT/install.sh" --plan --sin-cockpit 2>&1)"
ck "$(echo "$out" | grep -c 'scc/mods/cockpit')" "0" "--plan --sin-cockpit no lista el cockpit"
H3="$tmp/h3"; mkdir -p "$H3"
HOME="$H3" CLAUDE_HOME="$H3/.claude" bash "$KIT/install.sh" --apply --sin-cockpit >/dev/null 2>&1
ck "$([ -e "$H3/.claude/scc" ] && echo y)" "" "--sin-cockpit: no hay CLAUDE_HOME/scc"
out="$(PATH="$tmp/fake:$PATH" "$H3/.claude/bin/scc" -p hola 2>&1 | tr '\n' ' ')"
ck "$out" "ARG:-p ARG:hola " "scc sin cockpit arranca claude sin --plugin-dir"
ck "$(HOME="$H3" CLAUDE_HOME="$H3/.claude" bash "$KIT/install.sh" --apply --sin-cockpit --plan >/dev/null 2>&1; echo $?)" "64" "dos modos siguen dando 64"
ck "$(bash "$KIT/install.sh" --enable-secrets-layer2 --sin-cockpit >/dev/null 2>&1; echo $?)" "64" "--enable-secrets-layer2 no admite modificadores"

# uninstall --kit quita la copia y el enlace
HOME="$H3" CLAUDE_HOME="$H3/.claude" bash "$KIT/install.sh" --apply >/dev/null 2>&1
HOME="$H3" CLAUDE_HOME="$H3/.claude" bash "$REPO/uninstall.sh" --kit --apply >/dev/null 2>&1
ck "$(find "$H3" -path "$H3/.claude/backups" -prune -o -type f -print -o -type l -print | wc -l | tr -d ' ')" "0" "uninstall --kit deja el HOME vacio (copia del cockpit y enlace scc incluidos)"

# ---- 11. dependencias con PATH recortado
mkdir -p "$tmp/path-sinpy" "$tmp/path-sinjq" "$tmp/path-singit"
for d in /usr/bin /bin; do
  for f in "$d"/*; do
    b="${f##*/}"; [ -x "$f" ] && [ -f "$f" ] || continue
    case "$b" in python*|pydoc*|py3*) continue ;; esac
    [ -e "$tmp/path-sinpy/$b" ] || ln -s "$f" "$tmp/path-sinpy/$b"
  done
done
cp -a "$tmp/path-sinpy/." "$tmp/path-sinjq/"; rm -f "$tmp/path-sinjq/jq"
cp -a "$tmp/path-sinpy/." "$tmp/path-singit/"; rm -f "$tmp/path-singit/git"
H4="$tmp/h4"; mkdir -p "$H4"
out="$(HOME="$H4" CLAUDE_HOME="$H4/.claude" PATH="$tmp/path-sinpy" bash "$KIT/install.sh" --apply 2>&1)"; rc=$?
ck "$rc" "1" "sin python3: --apply para con rc 1"
ck "$(echo "$out" | grep -c 'falta python3')" "1" "y dice que falta python3"
ck "$(echo "$out" | grep -c 'Sentinel' )" "1" "nombra Sentinel entre las capas apagadas"
ck "$(echo "$out" | grep -c 'write-guard\|stale-read-guard\|efectividad')" "3" "nombra write-guard, stale-read-guard y efectividad"
ck "$(echo "$out" | grep -c -- '--sin-python')" "2" "y exige --sin-python para seguir"
ck "$(find "$H4" -mindepth 1 | wc -l | tr -d ' ')" "0" "sin python3 no se escribe nada"
out="$(HOME="$H4" CLAUDE_HOME="$H4/.claude" TMPDIR="$tmp" PATH="$tmp/path-sinpy" bash "$KIT/install.sh" --plan 2>&1)"; rc=$?
ck "$rc" "1" "--plan tambien comprueba python3"
out="$(HOME="$H4" CLAUDE_HOME="$H4/.claude" PATH="$tmp/path-sinpy" bash "$KIT/install.sh" --apply --sin-python 2>&1)"; rc=$?
ck "$rc" "0" "--sin-python deja instalar"
ck "$(echo "$out" | grep -c 'SIN python3')" "1" "y lo recuerda"
out="$(HOME="$H4" CLAUDE_HOME="$H4/.claude" PATH="$tmp/path-sinpy" bash "$KIT/doctor.sh" 2>&1)"; rc=$?
ck "$(echo "$out" | grep -c 'FAIL · python3')" "1" "doctor: FAIL (no WARN) si falta python3 con las capas cableadas"
ck "$([ "$rc" -ne 0 ] && echo y)" "y" "doctor sale distinto de 0"
H5="$tmp/h5"; mkdir -p "$H5"
out="$(HOME="$H5" CLAUDE_HOME="$H5/.claude" PATH="$tmp/path-sinjq" bash "$KIT/install.sh" --plan 2>&1)"; rc=$?
ck "$rc" "1" "sin jq: para"
ck "$(echo "$out" | grep -c 'brew install jq')" "1" "con la orden para macOS ademas de la de Debian"
out="$(HOME="$H5" CLAUDE_HOME="$H5/.claude" PATH="$tmp/path-singit" bash "$KIT/install.sh" --plan 2>&1)"; rc=$?
ck "$rc" "1" "sin git: para"
ck "$(echo "$out" | grep -c 'apt install git')" "1" "con la orden de Debian/Ubuntu"
ck "$(echo "$out" | grep -c 'brew install git')" "1" "y la de macOS"
ck "$(find "$H5" -mindepth 1 | wc -l | tr -d ' ')" "0" "sin jq ni git no se escribe nada"

echo "== $pass ok, $fail fallos =="
[ "$fail" -eq 0 ]
