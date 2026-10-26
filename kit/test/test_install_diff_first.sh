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
HOME="$tmp/fakehome" bash "$KIT/install.sh" >/dev/null 2>&1
ck "$([ -f "$CLAUDE_HOME/CLAUDE.md" ] && echo y || echo n)" "y" "HOME temporal normal: install.sh sigue escribiendo (comportamiento intacto)"

# --- Caso 2: CLAUDE_HOME ES un repo git con remoto -> NO escribe, sale 0 ---
export CLAUDE_HOME="$tmp/dot-git"
mkdir -p "$CLAUDE_HOME"
git -C "$CLAUDE_HOME" init -q
git -C "$CLAUDE_HOME" remote add origin https://example.com/claude-config-private.git
echo "MIO, NO TOCAR" > "$CLAUDE_HOME/CLAUDE.md"

set +e
out="$(HOME="$tmp/fakehome" MCHARNESS_OUT="$tmp/out-1" bash "$KIT/install.sh" 2>&1)"; rc=$?
set -e
ck "$rc" "0" "CLAUDE_HOME repo git con remoto: install.sh sale con exit 0 (no es un error)"
ck "$(cat "$CLAUDE_HOME/CLAUDE.md")" "MIO, NO TOCAR" "CLAUDE_HOME repo git con remoto: NO se escribe encima"
ck "$([ -d "$tmp/out-1" ] && echo y || echo n)" "y" "se genera el arbol que se instalaria en MCHARNESS_OUT"
ck "$(echo "$out" | grep -qic 'diff' && echo y || echo n)" "y" "la salida menciona el diff"
ck "$(echo "$out" | grep -qic -- '--apply' && echo y || echo n)" "y" "la salida indica como forzar la escritura real (--apply)"

# --- Caso 3: --apply en ese mismo escenario -> SI escribe -------------------
set +e
HOME="$tmp/fakehome" MCHARNESS_OUT="$tmp/out-2" bash "$KIT/install.sh" --apply >/dev/null 2>&1; rc3=$?
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
set +e; HOME="$tmp/fakehome" MCHARNESS_OUT="$tmp/out-3" bash "$KIT/install.sh" --apply >/dev/null 2>&1; set -e
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
HOME="$tmp/fakehome" bash "$KIT/install.sh" >/dev/null 2>&1; rc5=$?
set -e
ck "$rc5" "0" "repo git SIN remoto: install.sh sale 0"
ck "$([ -f "$CLAUDE_HOME/CLAUDE.md" ] && echo y || echo n)" "y" "repo git SIN remoto NO activa el modo diff (escribe igual, falsabilidad del check)"

# --- Hallazgo E6-1: --plan nunca borra lo que no escribio el, ni solapa con CLAUDE_HOME ---
export CLAUDE_HOME="$tmp/dot-solape"
HOME="$tmp/fakehome" bash "$KIT/install.sh" >/dev/null 2>&1
echo "MIO" > "$CLAUDE_HOME/mio.txt"
for o in "$CLAUDE_HOME" "$CLAUDE_HOME/sub/plan" "$tmp" "$CLAUDE_HOME/../dot-solape/."; do
  set +e; MCHARNESS_OUT="$o" bash "$KIT/install.sh" --plan >/dev/null 2>&1; rc=$?; set -e
  ck "$rc" "1" "--plan con MCHARNESS_OUT solapado ($o): exit 1"
  ck "$([ -f "$CLAUDE_HOME/mio.txt" ] && [ -f "$CLAUDE_HOME/settings.json" ] && echo y || echo n)" "y" "--plan solapado ($o): la instalacion sigue entera"
done
mkdir -p "$tmp/ajeno"; echo "AJENO" > "$tmp/ajeno/dato.txt"
set +e; MCHARNESS_OUT="$tmp/ajeno" bash "$KIT/install.sh" --plan >/dev/null 2>&1; rc=$?; set -e
ck "$rc" "1" "--plan con MCHARNESS_OUT existente sin marcador: exit 1"
ck "$(cat "$tmp/ajeno/dato.txt" 2>/dev/null)" "AJENO" "--plan no borra un directorio ajeno sin marcador"
MCHARNESS_OUT="$tmp/plan-rep" bash "$KIT/install.sh" --plan >/dev/null 2>&1
echo x > "$tmp/plan-rep/viejo.txt"
set +e; MCHARNESS_OUT="$tmp/plan-rep" bash "$KIT/install.sh" --plan >/dev/null 2>&1; rc=$?; set -e
ck "$rc" "0" "--plan repetido sobre su propio plan (con marcador): exit 0"
ck "$([ -e "$tmp/plan-rep/viejo.txt" ] && echo y || echo n)" "n" "--plan repetido regenera el arbol (borra lo anterior con marcador)"
ck "$([ -f "$tmp/plan-rep/settings.json" ] && echo y || echo n)" "y" "--plan repetido deja el arbol nuevo"
# Sin MCHARNESS_OUT ya no se usa $PWD/.mcharness-out (que se borraba a ciegas)
mkdir -p "$tmp/cwd/.mcharness-out" "$tmp/tmpd"; echo "OTRO" > "$tmp/cwd/.mcharness-out/otro.txt"
export CLAUDE_HOME="$tmp/dot-plan-defecto"
out="$(cd "$tmp/cwd" && TMPDIR="$tmp/tmpd" bash "$KIT/install.sh" --plan 2>&1)"
ck "$(cat "$tmp/cwd/.mcharness-out/otro.txt")" "OTRO" "--plan sin MCHARNESS_OUT no toca \$PWD/.mcharness-out"
ck "$(find "$tmp/tmpd" -maxdepth 1 -name 'mcharness-plan.*' | wc -l | tr -d ' ')" "1" "--plan sin MCHARNESS_OUT genera el plan en un temporal nuevo"
# --- Hallazgo E6-27: el mensaje de --plan no finge que CLAUDE_HOME sea un repo git ---
ck "$(echo "$out" | grep -c 'tu propio repo git' || true)" "0" "--plan sobre CLAUDE_HOME que no es repo: no dice «es tu propio repo git»"
ck "$(echo "$out" | grep -c -- '--plan solo muestra' || true)" "1" "--plan sobre CLAUDE_HOME que no es repo: dice que solo muestra"
ck "$(echo "$out" | grep -c 'mcharness-out-marker' || true)" "0" "el marcador no aparece como fichero del plan"
out="$(MCHARNESS_OUT="$tmp/out-git" CLAUDE_HOME="$tmp/dot-git" bash "$KIT/install.sh" 2>&1)"
ck "$(echo "$out" | grep -c 'tu propio repo git' || true)" "1" "repo git con remoto: sigue diciendo «es tu propio repo git»"

# --- Hallazgo E6-12: settings.json enlazado se fusiona a traves del enlace y sigue siendo enlace ---
export CLAUDE_HOME="$tmp/dot-link"
mkdir -p "$CLAUDE_HOME" "$tmp/repo-propio"
echo '{"model":"mi-modelo","env":{"MIA":"1"}}' > "$tmp/repo-propio/settings.json"
ln -s "$tmp/repo-propio/settings.json" "$CLAUDE_HOME/settings.json"
set +e; HOME="$tmp/fakehome" bash "$KIT/install.sh" --apply >/dev/null 2>&1; rc=$?; set -e
ck "$rc" "0" "--apply con settings.json enlazado: exit 0"
ck "$([ -L "$CLAUDE_HOME/settings.json" ] && echo y || echo n)" "y" "--apply conserva settings.json como enlace"
ck "$(readlink "$CLAUDE_HOME/settings.json")" "$tmp/repo-propio/settings.json" "--apply no cambia el destino del enlace"
ck "$(jq -r '.model + "|" + .env.MIA' "$tmp/repo-propio/settings.json")" "mi-modelo|1" "el destino del enlace conserva lo tuyo (model, env)"
ck "$(jq '.hooks | length > 0' "$tmp/repo-propio/settings.json")" "true" "el destino del enlace lleva los hooks del kit"
ck "$(find "$CLAUDE_HOME/backups" -name settings.json | wc -l | tr -d ' ')" "1" "--apply con enlace deja backup del settings.json"

# --- El plan ensena lo que haria --apply: partia de un arbol vacio y daba por borrado lo tuyo ---
# (env, model, permisos, hooks propios, tu CLAUDE.md). Se compara con --apply sobre una copia.
export CLAUDE_HOME="$tmp/dot-planfus"
mkdir -p "$CLAUDE_HOME" "$tmp/tmpd2"
# Con sangria, como lo guarda Claude Code: en una linea el diff da por borrado todo lo reformateado.
jq . > "$CLAUDE_HOME/settings.json" <<'EOF'
{"model":"mi-modelo","env":{"MIA":"1"},"permissions":{"allow":["Bash(mio:*)"]},
 "hooks":{"PostCompact":[{"hooks":[{"type":"command","command":"/opt/mio/sensor.sh"}]}]}}
EOF
echo "MIO CLAUDE" > "$CLAUDE_HOME/CLAUDE.md"
echo "MIO AGENTS" > "$CLAUDE_HOME/AGENTS.md"
cp -a "$CLAUDE_HOME" "$tmp/dot-planfus-apply"
set +e
out="$(TMPDIR="$tmp/tmpd2" HOME="$tmp/fakehome" MCHARNESS_OUT="$tmp/plan-fus" bash "$KIT/install.sh" --plan 2>&1)"; rc=$?
CLAUDE_HOME="$tmp/dot-planfus-apply" HOME="$tmp/fakehome" bash "$KIT/install.sh" --apply >/dev/null 2>&1
set -e
ck "$rc" "0" "--plan con settings.json, CLAUDE.md y AGENTS.md propios: exit 0"
ck "$(jq -S . "$tmp/plan-fus/settings.json")" "$(jq -S . "$tmp/dot-planfus-apply/settings.json")" "--plan: el settings.json del plan es el que deja --apply"
ck "$(jq -r '[.model, .env.MIA, (.permissions.allow | index("Bash(mio:*)") != null), ([.. | .command? // empty | select(. == "/opt/mio/sensor.sh")] | length)] | map(tostring) | join("|")' "$tmp/plan-fus/settings.json")" "mi-modelo|1|true|1" "--plan conserva tu model, env, permisos y hook propio"
ck "$(echo "$out" | grep -c '^-.*sensor\.sh' || true)" "0" "el diff del plan no da tu hook por borrado"
ck "$(cat "$tmp/plan-fus/CLAUDE.md")|$(cat "$tmp/plan-fus/AGENTS.md")" "MIO CLAUDE|MIO AGENTS" "--plan no pisa tu CLAUDE.md ni tu AGENTS.md, como --apply"
ck "$([ -f "$tmp/plan-fus/CLAUDE.kit.md" ] && [ -f "$tmp/plan-fus/AGENTS.kit.md" ] && echo y || echo n)" "y" "--plan deja la version del kit en *.kit.md, como --apply"
ck "$([ -e "$CLAUDE_HOME/backups" ] && echo y || echo n)" "n" "--plan no escribe backups en CLAUDE_HOME"
ck "$(find "$tmp/tmpd2" -mindepth 1 | wc -l | tr -d ' ')|$([ -e "$tmp/plan-fus/.mcharness-plan-bk" ] && echo y || echo n)" "0|n" "--plan no deja temporales en TMPDIR ni backups en su arbol"
ck "$(echo "$out" | grep -c 'Añade @AGENTS.md a tu CLAUDE.md' || true)" "1" "--plan avisa, como --apply, de que tu CLAUDE.md no importa AGENTS.md"
# Sembrar con un enlace haria que la fusion escribiese a traves de el, en tu repo.
export CLAUDE_HOME="$tmp/dot-planlink"
mkdir -p "$CLAUDE_HOME" "$tmp/repo-plan"
echo '{"model":"mi-modelo"}' > "$tmp/repo-plan/settings.json"
ln -s "$tmp/repo-plan/settings.json" "$CLAUDE_HOME/settings.json"
set +e; HOME="$tmp/fakehome" MCHARNESS_OUT="$tmp/plan-link" bash "$KIT/install.sh" --plan >/dev/null 2>&1; set -e
ck "$(cat "$tmp/repo-plan/settings.json")" '{"model":"mi-modelo"}' "--plan no escribe a traves de un settings.json enlazado"
ck "$([ -L "$tmp/plan-link/settings.json" ] && echo y || echo n)|$(jq -r .model "$tmp/plan-link/settings.json")" "n|mi-modelo" "--plan siembra el enlazado como copia y lo fusiona"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
