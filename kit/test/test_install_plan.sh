#!/usr/bin/env bash
# test_install_plan.sh — lo que install.sh --plan ensena y dice (W4: I3, M1, M2, M3):
#   - el plan MUESTRA que claves de settings.json anadiria o cambiaria (antes solo el diff en bruto);
#   - su arbol temporal se borra al salir y lleva nombres scc-*, no mcharness-*;
#   - «Commitea esos cambios en TU repo» solo si CLAUDE_HOME es un repo git;
#   - el aviso de CLAUDE.md/AGENTS.md no se queda en «CLAUDE no se han actualizado»;
#   - el mensaje final ya no manda copiar una plantilla de credenciales: el kit no usa claves;
#   - la plantilla no impone model/effortLevel/theme/tui ni deny de un MCP ajeno: tras instalar en limpio no estan.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

H="$tmp/h"; mkdir -p "$H" "$tmp/t"
out="$(HOME="$H" CLAUDE_HOME="$H/.claude" TMPDIR="$tmp/t" bash "$KIT/install.sh" --plan 2>&1)"
ck "$(echo "$out" | grep -c 'settings.json: claves que --apply')" "1" "--plan muestra la seccion de claves de settings.json"
ck "$(echo "$out" | grep -c '+ env: CLAUDE_CODE_AUTO_COMPACT_WINDOW, DISABLE_TELEMETRY')" "1" "--plan nombra las claves de env que anadiria"
ck "$(echo "$out" | grep -c '+ hooks: ')" "1" "--plan dice que eventos de hooks anadiria"
ck "$(echo "$out" | grep -cE '^ +\+ (model|effortLevel|theme|tui)')" "0" "la plantilla no anade model, effortLevel, theme ni tui"
ck "$(find "$tmp/t" -mindepth 1 | wc -l | tr -d ' ')" "0" "el arbol temporal del plan se borra al salir"
ck "$(echo "$out" | grep -c 'mcharness')" "0" "ningun texto del plan nombra mcharness"
ck "$(echo "$out" | grep -c 'Commitea esos cambios')" "0" "sin repo git en CLAUDE_HOME no habla de commitear en TU repo"
ck "$(find "$H" -mindepth 1 | wc -l | tr -d ' ')" "0" "--plan no escribe en el HOME"

# Con claves previas: ~ para lo cambiado, y lo del usuario no se propone cambiar.
H2="$tmp/h2"; mkdir -p "$H2/.claude"
echo '{"env":{"DISABLE_TELEMETRY":"0","MIA":"1"},"model":"sonnet"}' > "$H2/.claude/settings.json"
out="$(HOME="$H2" CLAUDE_HOME="$H2/.claude" TMPDIR="$tmp/t" bash "$KIT/install.sh" --plan 2>&1)"
ck "$(echo "$out" | grep -c '+ env.CLAUDE_CODE_AUTO_COMPACT_WINDOW')" "1" "con env previo: anade la ventana de compactacion"
ck "$(echo "$out" | grep -c '~ env.DISABLE_TELEMETRY')" "0" "tu DISABLE_TELEMETRY gana: el plan no propone cambiarlo"
ck "$(echo "$out" | grep -cE '[+~] model')" "0" "tu model no se toca"

# En un repo git propio (sin remoto) si habla de commitear.
H3="$tmp/h3"; mkdir -p "$H3/.claude"; git -C "$H3/.claude" init -q 2>/dev/null
out="$(HOME="$H3" CLAUDE_HOME="$H3/.claude" TMPDIR="$tmp/t" bash "$KIT/install.sh" --plan 2>&1)"
ck "$(echo "$out" | grep -c 'Commitea esos cambios')" "1" "con CLAUDE_HOME repo git: si dice commitear"

# SCC_OUT conserva el arbol; MCHARNESS_OUT sigue valiendo como alias.
HOME="$H" CLAUDE_HOME="$H/.claude" SCC_OUT="$tmp/o1" bash "$KIT/install.sh" --plan >/dev/null 2>&1
ck "$([ -f "$tmp/o1/settings.json" ] && [ -f "$tmp/o1/.scc-out-marker" ] && echo y)" "y" "SCC_OUT conserva el arbol, con marcador scc"
HOME="$H" CLAUDE_HOME="$H/.claude" MCHARNESS_OUT="$tmp/o2" bash "$KIT/install.sh" --plan >/dev/null 2>&1
ck "$([ -f "$tmp/o2/settings.json" ] && echo y)" "y" "MCHARNESS_OUT sigue funcionando como alias"

# M2: el aviso nombra los ficheros completos.
H4="$tmp/h4"; mkdir -p "$H4/.claude"; echo "mio" > "$H4/.claude/CLAUDE.md"; echo "mio" > "$H4/.claude/AGENTS.md"
out="$(HOME="$H4" CLAUDE_HOME="$H4/.claude" bash "$KIT/install.sh" --apply 2>&1)"
ck "$(echo "$out" | grep -c 'AVISO: CLAUDE.md AGENTS.md no se han actualizado')" "1" "el aviso dice CLAUDE.md AGENTS.md, no «CLAUDE no se han actualizado»"
ck "$(echo "$out" | grep -c 'cp .*env')" "0" "el mensaje final no manda copiar una plantilla de credenciales"
ck "$(echo "$out" | grep -c 'no usa claves')" "1" "y dice que el kit no usa claves"

# Instalar en limpio no fija los gustos del autor.
H5="$tmp/h5"; mkdir -p "$H5"
HOME="$H5" CLAUDE_HOME="$H5/.claude" bash "$KIT/install.sh" --apply >/dev/null 2>&1
ck "$(jq -c '[has("model"), has("effortLevel"), has("theme"), has("tui")]' "$H5/.claude/settings.json")" "[false,false,false,false]" "settings.json instalado en limpio sin model/effortLevel/theme/tui"
ck "$(jq '[.permissions.deny[] | select(test("linkedin"))] | length' "$H5/.claude/settings.json")" "0" "sin deny de linkedin"

# M3: el WARN de Capa 2 fuera de un repo trae la orden.
out="$(cd "$tmp" && HOME="$H5" CLAUDE_HOME="$H5/.claude" bash "$KIT/doctor.sh" 2>&1)"
ck "$(echo "$out" | grep -c 'WARN · no estas dentro de un repo git.*install.sh --enable-secrets-layer2')" "1" "doctor: el WARN de Capa 2 dice la orden"

echo "== $pass ok, $fail fallos =="
[ "$fail" -eq 0 ]
