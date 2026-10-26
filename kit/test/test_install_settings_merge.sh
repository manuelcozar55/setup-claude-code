#!/usr/bin/env bash
# test_install_settings_merge.sh — falsea la fusion de settings.json (install_settings).
#
# El incidente que cierra esta suite, medido el 2026-09-02 a las 11:34:24: install.sh
# instalaba settings.json con install_file() -- un `cp` del fichero entero -- y la plantilla
# publica del kit no llevaba entonces `statusLine`.
# Al reinstalar, la clave desaparecio del settings.json de una maquina real y la statusline
# estuvo 15 minutos muerta sin un solo aviso. La fusion con jq lo arreglo el mismo dia, pero
# la garantia se quedo casi sin sensor: lo unico que la vigilaba era una linea de test_install.sh
# (`.statusLine.command` sobrevive). Fuera de esa clave y de ese camino no habia nada, asi que
# el proximo refactor la rompe igual de callado. Aqui se mide el resto: el objeto entero, las
# claves que el kit no conoce, el camino degradado (JSON invalido), la puerta que aborta sin
# jq sin tocar tu fichero, la idempotencia y el modo del fichero.
#
# El contrato que se fija aqui, clave por clave (kit/install.sh, install_settings):
#   statusLine y cualquier otra clave que el kit no conozca -> TUYAS, intactas
#   env, permissions.allow, permissions.deny                -> union, y gana tu valor
#   hooks                                                   -> por propietario: los del kit los
#                                                              pone el kit, los tuyos se quedan
#   permissions.disableBypassPermissionsMode                -> del KIT, siempre "disable"
# Hasta la 1.5.0 el kit poseia `hooks` en bloque y se llevaba los tuyos (caso e). El caso fija
# las dos mitades para que un cambio de contrato salte en un sentido o en el otro: lo tuyo
# sobrevive y lo del kit no se duplica.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

if ! command -v jq >/dev/null 2>&1; then
  echo "skip - jq ausente: esta suite mide la fusion, que solo existe con jq"
  echo "== 0 passed, 0 failed =="; exit 0
fi

# Todo ocurre en un HOME temporal: esta suite no puede acercarse al ~/.claude real.
export HOME="$tmp/home"; mkdir -p "$HOME"
S=""
seed(){  # $1 = caso; stdin = el settings.json que ya tenias. Deja $CLAUDE_HOME y $S puestos.
  export CLAUDE_HOME="$tmp/$1"; mkdir -p "$CLAUDE_HOME"
  S="$CLAUDE_HOME/settings.json"; cat > "$S"; chmod 644 "$S"
}
run(){ set +e; bash "$KIT/install.sh" "$@" >"$tmp/run.log" 2>&1; set -e; }
dice(){ grep -qE "$1" "$tmp/run.log" && echo y || echo n; }
backups(){ find "$CLAUDE_HOME/backups" -name settings.json 2>/dev/null | wc -l | tr -d ' '; }

# --- Caso a: statusLine sobrevive intacta (EL incidente) -------------------
seed a <<'EOF'
{ "statusLine": { "type": "command", "command": "/home/usuario/.claude/statusline.sh", "padding": 0 },
  "model": "opus[1m]", "theme": "light", "tui": "classic" }
EOF
antes="$(jq -Sc .statusLine "$S")"
run
ck "$([ "$(jq -Sc '.statusLine // "AUSENTE"' "$KIT/claude/settings.json")" != "$antes" ] && echo y || echo n)" "y" "la statusLine de la plantilla es otra (un cp pisaria la tuya: falsabilidad del caso)"
ck "$(jq -Sc '.statusLine // "AUSENTE"' "$S")" "$antes" "statusLine sigue ahi y byte-identica tras reinstalar"
ck "$(jq -r '.model' "$S")" "opus[1m]" "tu model sigue ahi"
ck "$(jq -r '.theme' "$S")" "light" "tu tema sigue ahi"
ck "$(jq -r '.tui' "$S")" "classic" "tu renderer sigue ahi"
ck "$(stat -c %a "$S")" "644" "la escritura atomica preserva el modo del original (el mktemp nace en 600)"

# --- Caso b: una clave que el kit NO conoce -------------------------------
seed b <<'EOF'
{ "editorMode": "vim" }
EOF
run
ck "$(jq -r '.editorMode // "AUSENTE"' "$S")" "vim" "una clave que el kit no conoce (editorMode) sobrevive"

# --- Caso c: env -> tu valor gana, y las claves nuevas del kit se anaden --
seed c <<'EOF'
{ "env": { "MAX_THINKING_TOKENS": "64000" } }
EOF
run
ck "$(jq -r '.env.MAX_THINKING_TOKENS' "$S")" "64000" "env: tu valor gana sobre el del kit (32000)"
ck "$(jq -r '.env.ANTHROPIC_DISABLE_TELEMETRY // "AUSENTE"' "$S")" "1" "env: una clave nueva del kit se anade"

# --- Caso d: permissions.allow/.deny -> union sin duplicados --------------
seed d <<'EOF'
{ "permissions": { "allow": ["Bash(mi-comando *)", "WebFetch(domain:doi.org)"],
                   "deny":  ["Bash(mi-peligro)"] } }
EOF
run
ck "$(jq '[.permissions.allow[] | select(. == "Bash(mi-comando *)")] | length' "$S")" "1" "allow: tu entrada sigue"
ck "$(jq '[.permissions.allow[] | select(. == "WebFetch(domain:doi.org)")] | length' "$S")" "1" "allow: la entrada que tenian kit y usuario no se duplica"
ck "$(jq '[.permissions.deny[] | select(. == "Bash(mi-peligro)")] | length' "$S")" "1" "deny: tu entrada sigue"
ck "$(jq '[.permissions.deny[] | select(. == "Bash(rm -rf /*)")] | length' "$S")" "1" "deny: los del kit siguen (union, no reemplazo)"
ck "$(jq '(.permissions.allow | length) == (.permissions.allow | unique | length)' "$S")" "true" "allow: sin duplicados"
ck "$(jq '(.permissions.deny  | length) == (.permissions.deny  | unique | length)' "$S")" "true" "deny: sin duplicados"

# --- Caso e: hooks -> el kit sustituye LOS SUYOS; los tuyos se quedan ------
# El 21-oct una reinstalacion borro `PostCompact -> post-compact-check.sh` y un PreCompact de otra
# capa: el kit poseia `hooks` en bloque. Ahora solo posee las entradas que nombran sus scripts
# (los que cablea la plantilla, mas los que retiro). La semilla mezcla de todo: un evento que el
# kit no usa, un ajeno colgado en un grupo junto a un guard del kit, un guard del kit con su forma
# antigua, un retirado y un hook sin `command`.
seed e <<'EOF'
{ "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/block-dangerous-commands.sh" },
          { "type": "command", "command": "~/.local/bin/mi-linter --hook" } ] },
      { "hooks": [ { "type": "command", "command": "~/.venvs/tools/bin/python3 ~/.claude/hooks/write-guard.py" } ] },
      { "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/optional-hook.sh --python $HOME/.claude/hooks/smart_approve.py" } ] },
      { "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/optional-hook.sh --python $HOME/.claude/hooks/mi-guard.py" } ] } ],
    "PreCompact": [ { "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/circe-pre-compact.sh" },
                                 { "type": "command", "command": "$HOME/.claude/hooks/preflight.sh" } ] } ],
    "PostCompact": [ { "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/post-compact-check.sh", "timeout": 5 } ] } ],
    "Stop": [ { "hooks": [ { "type": "prompt", "prompt": "mi revision" } ] } ] } }
EOF
run
cmds(){ jq -r "[.hooks.$1[]?.hooks[]? | .command // .prompt] | join(\"|\")" "$S"; }
# shellcheck disable=SC2016 # $HOME literal del settings, no del shell
ck "$(jq -c '.hooks.PostCompact' "$S")" '[{"hooks":[{"type":"command","command":"$HOME/.claude/hooks/post-compact-check.sh","timeout":5}]}]' \
   "hooks: un evento que el kit no usa sobrevive byte a byte (EL incidente)"
ck "$(cmds PreToolUse | tr '|' '\n' | grep -c -e 'mi-linter --hook' -e 'mi-guard.py')" "2" "hooks: tus PreToolUse se quedan, tambien el que va por optional-hook.sh"
ck "$(jq -c '[.hooks.PreToolUse[] | select(any(.hooks[]; .command // "" | test("mi-linter")))] | map(.matcher, (.hooks | length))' "$S")" '["Bash",1]' \
   "hooks: en un grupo mixto queda solo lo tuyo, con su matcher"
ck "$(cmds PreToolUse | tr '|' '\n' | grep -c -e 'block-dangerous' -e 'write-guard.py')" "2" "hooks: los guards del kit no se duplican (ni con su forma antigua)"
ck "$(jq '[.hooks | .. | strings | select(test("smart_approve|preflight\\.sh"))] | length' "$S")" "0" "hooks: los que el kit retiro se van"
# shellcheck disable=SC2016 # $HOME literal del settings, no del shell
ck "$(cmds PreCompact)" '$HOME/.claude/hooks/pre-compact.sh|$HOME/.claude/hooks/circe-pre-compact.sh' "hooks: en un evento compartido van los del kit y detras los tuyos"
ck "$(cmds Stop | tr '|' '\n' | grep -c 'mi revision')" "1" "hooks: uno sin command (type prompt) es tuyo"
ck "$(jq -c '[.hooks[][]? | select((.hooks | length) == 0)] | length' "$S")" "0" "hooks: no quedan grupos vacios"
plantilla="$(jq -c '[.hooks[][].hooks[].command] | sort' "$KIT/claude/settings.json")"
ck "$(jq -c --argjson p "$plantilla" '[.hooks[][].hooks[].command // empty] | map(select(IN($p[]))) | sort' "$S")" "$plantilla" "hooks: estan todos los de la plantilla, una vez cada uno"
antes="$(sha256sum < "$S")"; n="$(backups)"
run
ck "$(sha256sum < "$S")" "$antes" "hooks: reinstalar no cambia nada (idempotente)"
ck "$(backups)" "$n" "hooks: reinstalar no crea otro backup"

# --- Caso e2: lo que no es del todo del kit se queda; lo malformado no tumba la fusion --
# Un comando que nombra un guard pero hace algo mas es tuyo: borrarlo entero perderia tu parte. Y un
# evento que no es lista o un grupo sin `hooks` no pueden abortar la fusion: sin ella no llegan los guards.
seed e2 <<'EOF'
{ "hooks": {
    "Stop": { "no": "es una lista" },
    "PostCompact": [ { "matcher": "sin-hooks" }, { "hooks": [ { "type": "command", "command": "mio.sh" } ] } ] } }
EOF
run
ck "$(dice 'fusion de settings.json fallo')" "n" "hooks: un evento malformado no aborta la fusion"
ck "$(cmds PreToolUse | tr '|' '\n' | grep -c 'block-dangerous')" "1" "hooks: con un evento malformado los guards del kit llegan igual"
ck "$(cmds PostCompact)" "mio.sh" "hooks: el grupo sin hooks se descarta y el resto del evento se queda"
ck "$(jq -r '.hooks.Stop | "\(type) \(length)"' "$S")" "array 1" "hooks: un evento que no es lista se descarta y quedan los del kit"
seed e3 <<'EOF'
{ "hooks": { "PreToolUse": [ { "hooks": [ { "type": "command", "command": "/opt/mio/log.sh && $HOME/.claude/hooks/branch-guard.sh" } ] } ] } }
EOF
run
ck "$(cmds PreToolUse | tr '|' '\n' | grep -c '/opt/mio/log.sh')" "1" "hooks: un comando con algo mas que un guard del kit es tuyo y se queda"

# --- Caso f: settings.json con JSON invalido -> reemplazo con backup ------
seed f <<'EOF'
{ "statusLine": { "command": "mio" },
EOF
run
ck "$(cmp -s "$KIT/claude/settings.json" "$S" && echo y || echo n)" "y" "JSON invalido: se reemplaza con la plantilla del kit"
ck "$(backups)" "1" "JSON invalido: tu fichero queda en backup"
ck "$(grep -c mio "$(find "$CLAUDE_HOME/backups" -name settings.json)")" "1" "JSON invalido: el backup lleva tu contenido, no el del kit"

# --- Caso g: sin jq en el PATH -> install.sh aborta sin tocar tu fichero ---
# Este caso afirmaba lo contrario: sin jq, install.sh reemplazaba tu settings.json con la
# plantilla del kit y confiaba en el backup. Ya no hay tal degradacion, hay una puerta de
# dependencia: los cuatro guards de Bash leen el payload con jq y sin el fallan en CERRADO
# (deniegan), asi que instalar en esa maquina dejaria Claude Code bloqueado. La garantia
# nueva es mas fuerte que la vieja -- no se te toca el fichero, no hay backup que descubrir.
# Un PATH sin jq y con todo lo demas: una granja de symlinks a cada binario del PATH real,
# saltando jq. Es la unica forma de que `command -v jq` falle DE VERDAD dentro de install.sh
# (un jq no ejecutable, o una funcion exportada, no lo consiguen).
farm="$tmp/nojq"; mkdir -p "$farm"
IFS=: read -ra dirs <<< "$PATH"
for d in "${dirs[@]}"; do
  [ -d "$d" ] || continue
  for f in "$d"/*; do
    b="${f##*/}"
    [ -e "$f" ] && [ "$b" != jq ] && [ ! -e "$farm/$b" ] && ln -s "$f" "$farm/$b"
  done
done
seed g <<'EOF'
{ "statusLine": { "command": "mio" } }
EOF
ck "$(PATH="$farm" bash -c 'command -v jq >/dev/null 2>&1 && echo y || echo n')" "n" "el PATH de la granja no tiene jq (falsabilidad del caso)"
sha_g="$(sha256sum "$S" | cut -d' ' -f1)"
set +e; out_g="$(PATH="$farm" bash "$KIT/install.sh" 2>&1)"; rc_g=$?; set -e
ck "$([ "$rc_g" -ne 0 ] && echo y || echo n)" "y" "sin jq: install.sh aborta (rc=$rc_g)"
ck "$(echo "$out_g" | grep -qi 'falta jq' && echo y || echo n)" "y" "sin jq: el mensaje dice que falta jq"
ck "$(sha256sum "$S" | cut -d' ' -f1)" "$sha_g" "sin jq: tu settings.json queda intacto"
ck "$(backups)" "0" "sin jq: no hay backup que descubrir, porque no se toco nada"

# --- Caso i: claves de seguridad sueltas -> gana el KIT, y lo que no se fuerza se avisa ---
# La union de permissions dejaba ganar lo tuyo en las claves escalares: un previo con
# disableBypassPermissionsMode vacio, defaultMode bypassPermissions y disableAllHooks salia de
# la fusion igual, sin guards ni freno al bypass, y sin una linea de aviso.
seed i <<'EOF'
{ "disableAllHooks": true,
  "permissions": { "disableBypassPermissionsMode": "", "defaultMode": "bypassPermissions", "allow": ["Bash"] } }
EOF
run
ck "$(jq -r '.permissions.disableBypassPermissionsMode' "$S")" "disable" "disableBypassPermissionsMode: gana el kit sobre tu valor vacio"
ck "$(jq -r '.permissions.allow | index("Bash") != null' "$S")" "true" "allow: tu entrada sigue (la union no cambia)"
ck "$(dice 'AVISO.*disableAllHooks')" "y" "disableAllHooks: true previo -> aviso visible"
ck "$(dice 'AVISO.*bypassPermissions')" "y" "defaultMode bypassPermissions previo -> aviso"
seed i2 <<'EOF'
{ "permissions": { "defaultMode": "acceptEdits" } }
EOF
run
ck "$(dice 'AVISO.*(disableAllHooks|bypassPermissions)')" "n" "sin esas claves no hay aviso (falsabilidad del caso)"
# En el plan diff-first no se escribe en CLAUDE_HOME, pero el arbol del plan lleva "disable" y el
# aviso sale igual: es justo cuando la persona decide que copiar.
seed j <<'EOF'
{ "disableAllHooks": true,
  "permissions": { "disableBypassPermissionsMode": "", "defaultMode": "bypassPermissions" } }
EOF
sha_j="$(sha256sum "$S" | cut -d' ' -f1)"
MCHARNESS_OUT="$tmp/plan-j" run --plan
ck "$(jq -r '.permissions.disableBypassPermissionsMode' "$tmp/plan-j/settings.json")" "disable" "plan: el settings.json del plan lleva disable"
ck "$(sha256sum "$S" | cut -d' ' -f1)" "$sha_j" "plan: tu settings.json queda intacto"
ck "$(dice 'AVISO.*disableAllHooks')" "y" "plan: aviso de disableAllHooks"
ck "$(dice 'AVISO.*bypassPermissions')" "y" "plan: aviso de defaultMode bypassPermissions"

# --- Caso h: idempotencia (se reusa el HOME del caso a, ya fusionado) -----
export CLAUDE_HOME="$tmp/a"; S="$CLAUDE_HOME/settings.json"
sha="$(sha256sum "$S" | cut -d' ' -f1)"; n="$(backups)"
run
ck "$(sha256sum "$S" | cut -d' ' -f1)" "$sha" "idempotencia: fusionar dos veces no cambia el fichero"
ck "$(backups)" "$n" "idempotencia: la segunda fusion no genera un backup nuevo (no hubo cambio)"

# --- Caso j: env.CC_ALLOW_DESTRUCTIVE=1 previo (M5 residuo) -> la fusion lo respeta (es tuyo) y avisa ---
# CC_ALLOW_DESTRUCTIVE=1 apaga destructive-guard.sh (kit/claude/hooks/destructive-guard.sh:10): sobrevivia
# a la fusion sin una linea de aviso.
seed j <<'EOF'
{ "env": { "CC_ALLOW_DESTRUCTIVE": "1" } }
EOF
run
ck "$(jq -r '.env.CC_ALLOW_DESTRUCTIVE' "$S")" "1" "CC_ALLOW_DESTRUCTIVE previo: sigue (es tuyo, no se borra)"
ck "$(dice 'AVISO.*CC_ALLOW_DESTRUCTIVE')" "y" "CC_ALLOW_DESTRUCTIVE=1 previo -> aviso visible"
seed j2 <<'EOF'
{ "env": { "CC_ALLOW_DESTRUCTIVE": "0" } }
EOF
run
ck "$(dice 'AVISO.*CC_ALLOW_DESTRUCTIVE')" "n" "CC_ALLOW_DESTRUCTIVE=0 no avisa (falsabilidad del caso)"

# --- Caso k: marketplace del kit ya registrado sin ref (o con el de otra version) -> el ref sigue a VERSION ---
# Con la entrada vieja intacta, `marketplace add <repo>@v<VERSION>` de install-plugins.sh falla («its source
# doesn't match its extraKnownMarketplaces entry», medido con claude 2.1.304) y el cockpit sigue a main:
# se adelanta a ~/.claude/bin/handoff. Tus otros marketplaces no se tocan.
ref="v$(cat "$KIT/../VERSION")"
ck "$(jq -r '.extraKnownMarketplaces["setup-claude-code"].source.ref' "$KIT/claude/settings.json")" "$ref" "la plantilla fija el marketplace del kit a v<VERSION> (premisa del caso)"
for previo in '' '"ref": "v0.0.1",'; do
seed k <<EOF
{ "extraKnownMarketplaces": {
    "setup-claude-code": { "source": { $previo "source": "github", "repo": "manuelcozar55/setup-claude-code" } },
    "otro": { "source": { "source": "github", "repo": "alguien/otro", "ref": "main" } } } }
EOF
run
caso="${previo:+con ref viejo}"; caso="${caso:-sin ref}"
ck "$(jq -r '.extraKnownMarketplaces["setup-claude-code"].source.ref' "$S")" "$ref" "marketplace del kit $caso: queda en $ref"
ck "$(jq -c '.extraKnownMarketplaces.otro' "$S")" '{"source":{"source":"github","repo":"alguien/otro","ref":"main"}}' "otro marketplace tuyo: intacto"
done
# Por la misma razon, `plugin install cockpit --marketplace <repo>` sin ref falla con el marketplace ya fijado.
ck "$(grep -rl -- '--marketplace manuelcozar55' "$KIT/docs" "$KIT/../README.md" | wc -l)" "0" "ninguna doc instala el cockpit con --marketplace <repo> sin ref"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
