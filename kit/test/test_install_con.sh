#!/usr/bin/env bash
# test_install_con.sh — piezas opcionales: una instalacion sin flags deja solo el nucleo, `--con <pieza>` instala cada
# una (ficheros + lo que cablea en settings.json), una actualizacion NUNCA retira en silencio lo que ya hay y
# `uninstall.sh --kit --pieza` la quita sola. La lista de piezas sale de kit/opcional.sh.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."; REPO="$KIT/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }
# shellcheck source=SCRIPTDIR/../opcional.sh
. "$KIT/opcional.sh"
inst() { local h=$1; shift; HOME="$h" CLAUDE_HOME="$h/.claude" bash "$KIT/install.sh" "$@" > "$h.log" 2>&1; }
unin() { local h=$1; shift; HOME="$h" CLAUDE_HOME="$h/.claude" bash "$REPO/uninstall.sh" "$@" > "$h.unin.log" 2>&1; }
# Cuantos ficheros de una pieza hay instalados en $1/.claude
cuenta() { local h=$1 p=$2 n=0 f rel; while IFS= read -r -d '' f; do rel="${f#"$h/.claude/"}"; [ "$(opcional_de "$rel")" = "$p" ] && n=$((n+1)); done < <(find "$h/.claude" -path "$h/.claude/backups" -prune -o -type f -print0); echo "$n"; }
# Entradas de settings.json que son de la pieza: hooks que nombran sus scripts, y plugins que habilita.
cableado() { jq -r --arg p "$2" --slurpfile k "$KIT/opcional-settings.json" '
    def nombres: [.. | .command? | strings | splits(" +") | gsub("\""; "") | sub(".*/"; "") | select(test("\\.(py|sh)$") and . != "optional-hook.sh")];
    ([$k[0][$p].hooks // {} | nombres] | add // []) as $n
    | [.hooks // {} | nombres | .[] | select(. as $c | $n | index($c) != null)] | length' "$1/.claude/settings.json"; }
plugins_hab() { jq -r --arg p "$2" --slurpfile k "$KIT/opcional-settings.json" '
    ($k[0][$p].enabledPlugins // {}) as $e | [(.enabledPlugins // {}) | to_entries[] | select(.value == true and ($e[.key] == true))] | length' "$1/.claude/settings.json"; }

# Argumentos
set +e
HOME="$tmp/a1" CLAUDE_HOME="$tmp/a1/.claude" bash "$KIT/install.sh" --con nada >/dev/null 2>&1; ck "$?" "64" "--con con una pieza desconocida da 64"
ck "$(find "$tmp/a1" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')" "0" "y no escribe nada"
HOME="$tmp/a2" CLAUDE_HOME="$tmp/a2/.claude" bash "$KIT/install.sh" --con >/dev/null 2>&1; ck "$?" "64" "--con sin pieza da 64"
for v in '' ',' ' , '; do
  HOME="$tmp/a3" CLAUDE_HOME="$tmp/a3/.claude" bash "$KIT/install.sh" --plan --con "$v" >/dev/null 2>&1; ck "$?" "64" "--con '$v' (sin ninguna pieza) da 64"
done
HOME="$tmp/a3" CLAUDE_HOME="$tmp/a3/.claude" bash "$KIT/install.sh" --plan --con 'revisores,' >/dev/null 2>&1; ck "$?" "0" "--con 'revisores,' (coma sobrante) sigue valiendo"
for v in '' ','; do
  HOME="$tmp/a3" CLAUDE_HOME="$tmp/a3/.claude" bash "$REPO/uninstall.sh" --kit --pieza "$v" >/dev/null 2>&1; ck "$?" "1" "uninstall --pieza '$v' (sin ninguna pieza) falla"
done
set -e

for p in $PIEZAS_OPCIONALES; do
  H="$tmp/h-$p"; mkdir -p "$H"
  inst "$H" --apply
  ck "$(cuenta "$H" "$p")" "0" "$p: sin --con no se instala ningun fichero suyo"
  ck "$(cableado "$H" "$p")" "0" "$p: sin --con settings.json no cablea sus hooks"
  ck "$(plugins_hab "$H" "$p")" "0" "$p: sin --con settings.json no habilita sus plugins"
  ck "$(grep -c "opcional, no instalado:.* $p" "$H.log")" "1" "$p: el instalador dice que no esta instalada y como pedirla"
  inst "$H" --apply --con "$p"
  ck "$([ "$(cuenta "$H" "$p")" -gt 0 ] && echo y)" "y" "$p: --con $p instala sus ficheros"
  ck "$(grep -c "opcional, no instalado:.* $p" "$H.log")" "0" "$p: instalada ya no figura como no instalada"
  ck "$(grep -c '^==> doctor: OK, [0-9]* WARN' "$H.log")" "1" "$p: el instalador acaba con el veredicto de doctor en una linea"
  ck "$(tail -n 1 "$H.log" | grep -c '^==> doctor: ')" "1" "$p: y es la ultima linea"
  if [ "$(jq -e --arg p "$p" '.[$p]' "$KIT/opcional-settings.json" >/dev/null 2>&1; echo $?)" = 0 ]; then
    ck "$([ "$(( $(cableado "$H" "$p") + $(plugins_hab "$H" "$p") ))" -gt 0 ] && echo y)" "y" "$p: --con $p cablea lo suyo en settings.json"
  fi
  c1="$(cableado "$H" "$p")"; inst "$H" --apply --con "$p"
  ck "$(cableado "$H" "$p")" "$c1" "$p: repetir --con no duplica"
  # Actualizar sin --con: se conserva, se actualiza y se dice con la orden para quitarla.
  antes="$(cuenta "$H" "$p")"; cab="$(cableado "$H" "$p")"
  inst "$H" --apply
  ck "$(cuenta "$H" "$p")" "$antes" "$p: actualizar sin --con no la retira"
  ck "$(cableado "$H" "$p")" "$cab" "$p: ni la descablea"
  ck "$(grep -c "conservado (ya estaba instalado): $p. Para quitarlo: bash .*uninstall.sh --kit --pieza $p --apply" "$H.log")" "1" "$p: lo dice con la orden para quitarla"
  # Quitar solo esa pieza: lo demas del kit se queda.
  unin "$H" --kit --pieza "$p"
  ck "$(cuenta "$H" "$p")" "$antes" "$p: --pieza sin --apply es un simulacro"
  unin "$H" --kit --pieza "$p" --apply
  ck "$(cuenta "$H" "$p")" "0" "$p: uninstall --pieza $p --apply borra sus ficheros"
  ck "$(cableado "$H" "$p")" "0" "$p: y quita lo que cablea"
  ck "$(plugins_hab "$H" "$p")" "0" "$p: y lo que habilita"
  ck "$([ -x "$H/.claude/hooks/branch-guard.sh" ] && [ -f "$H/.claude/.kit-manifest" ] && echo y)" "y" "$p: el nucleo y el manifiesto siguen"
  inst "$H" --apply
  ck "$(cuenta "$H" "$p")" "0" "$p: tras quitarla, actualizar sin --con no la reinstala"
done

# Todas juntas y la desinstalacion completa las retira todas
H="$tmp/h-todas"; mkdir -p "$H"
con="${PIEZAS_OPCIONALES// /,}"
inst "$H" --apply --con "$con"
n=0; for p in $PIEZAS_OPCIONALES; do [ "$(cuenta "$H" "$p")" -gt 0 ] && n=$((n+1)); done
ck "$n" "$(echo "$PIEZAS_OPCIONALES" | wc -w | tr -d ' ')" "--con a,b,c instala todas las piezas pedidas"
unin "$H" --kit --apply
ck "$(find "$H" -path "$H/.claude/backups" -prune -o -type f -print -o -type l -print | grep -vc '\.log$')" "0" "uninstall --kit retira todo, lo opcional incluido"

# rc del instalador: 0 con doctor en OK o con solo WARN, 1 solo si doctor da algun FAIL (doctor de mentira en una copia)
R="$tmp/rc"; mkdir -p "$R"; cp -r "$KIT" "$R/kit"; rm -r "$R/kit/test"; cp "$REPO/VERSION" "$R/VERSION"
for caso in ok:0 warn:0 fail:1; do
  nombre="${caso%%:*}"; esperado="${caso##*:}"; H="$tmp/rc-$nombre"; mkdir -p "$H"
  case $nombre in
    ok)   printf '%s\n' '#!/usr/bin/env bash' 'echo "PASS todo"' > "$R/kit/doctor.sh" ;;
    warn) printf '%s\n' '#!/usr/bin/env bash' 'echo "WARN algo opcional"' > "$R/kit/doctor.sh" ;;
    fail) printf '%s\n' '#!/usr/bin/env bash' 'echo "FAIL algo roto"; exit 1' > "$R/kit/doctor.sh" ;;
  esac
  HOME="$H" CLAUDE_HOME="$H/.claude" bash "$R/kit/install.sh" --apply > "$H.log" 2>&1 && rc=0 || rc=$?
  ck "$rc" "$esperado" "rc del instalador con doctor en $nombre"
  ck "$(tail -n 1 "$H.log" | grep -c '^==> doctor: ')" "1" "$nombre: el veredicto sigue siendo la ultima linea"
done

echo "== $pass ok, $fail fallos =="
[ "$fail" -eq 0 ]
