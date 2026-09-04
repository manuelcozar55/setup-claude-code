#!/usr/bin/env bash
# test_install_settings_merge.sh — falsea la fusion de settings.json (install_settings).
#
# El incidente que cierra esta suite, medido el 2026-09-02 a las 11:34:24: install.sh
# instalaba settings.json con install_file() -- un `cp` del fichero entero -- y la plantilla
# publica del kit NO puede llevar `statusLine`, porque la ruta del script es de cada maquina.
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
#   hooks                                                   -> del KIT, reemplazan los tuyos
# Lo de `hooks` es la unica clave que el kit posee en bloque (la cadena de guards es lo que
# aporta) y esta declarado en el aviso que imprime la funcion: se fija aqui para que un
# cambio accidental de ese contrato salte, en un sentido o en el otro.
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
run(){ set +e; bash "$KIT/install.sh" >/dev/null 2>&1; set -e; }
backups(){ find "$CLAUDE_HOME/backups" -name settings.json 2>/dev/null | wc -l | tr -d ' '; }

# --- Caso a: statusLine sobrevive intacta (EL incidente) -------------------
seed a <<'EOF'
{ "statusLine": { "type": "command", "command": "/home/usuario/.claude/statusline.sh", "padding": 0 },
  "model": "opus[1m]" }
EOF
antes="$(jq -Sc .statusLine "$S")"
run
ck "$(jq -r 'has("statusLine")' "$KIT/claude/settings.json")" "false" "la plantilla del kit NO lleva statusLine (por eso el cp la borraba: falsabilidad del caso)"
ck "$(jq -Sc '.statusLine // "AUSENTE"' "$S")" "$antes" "statusLine sigue ahi y byte-identica tras reinstalar"
ck "$(jq -r '.model' "$S")" "opus[1m]" "tu model sigue ahi"
ck "$(stat -c %a "$S")" "644" "la escritura atomica preserva el modo del original (el mktemp nace en 600)"

# --- Caso b: una clave que el kit NO conoce -------------------------------
seed b <<'EOF'
{ "tui": "fullscreen" }
EOF
run
ck "$(jq -r '.tui // "AUSENTE"' "$S")" "fullscreen" "una clave que el kit no conoce (tui) sobrevive"

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

# --- Caso e: hooks -> los del kit REEMPLAZAN los tuyos --------------------
seed e <<'EOF'
{ "hooks": { "PreToolUse": [ { "matcher": "Bash",
              "hooks": [ { "type": "command", "command": "mi-hook-viejo.sh" } ] } ] } }
EOF
run
ck "$(jq '[.. | strings | select(test("mi-hook-viejo"))] | length' "$S")" "0" "hooks: los tuyos NO sobreviven -- el kit los posee en bloque"
ck "$(jq '[.hooks.PreToolUse[].hooks[].command | select(test("block-dangerous"))] | length' "$S")" "1" "hooks: los pone el kit"

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

# --- Caso h: idempotencia (se reusa el HOME del caso a, ya fusionado) -----
export CLAUDE_HOME="$tmp/a"; S="$CLAUDE_HOME/settings.json"
sha="$(sha256sum "$S" | cut -d' ' -f1)"; n="$(backups)"
run
ck "$(sha256sum "$S" | cut -d' ' -f1)" "$sha" "idempotencia: fusionar dos veces no cambia el fichero"
ck "$(backups)" "$n" "idempotencia: la segunda fusion no genera un backup nuevo (no hubo cambio)"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
