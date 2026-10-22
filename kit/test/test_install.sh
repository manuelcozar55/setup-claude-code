#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

args_case() {
  local name=$1 expected=$2 path=$3 rc probe
  shift 3
  probe="$tmp/args-$name"
  mkdir -p "$probe"
  set +e
  HOME="$probe" CLAUDE_HOME="$probe/.claude" PATH="$path" /bin/bash "$KIT/install.sh" "$@" > "$tmp/args-$name.log" 2>&1
  rc=$?
  set -e
  ck "$rc" "$expected" "argumentos $name: codigo esperado"
  ck "$(find "$probe" -mindepth 1 -print -quit)" "" "argumentos $name: HOME intacto, sin instalacion ni enlaces"
  ck "$(grep -c '^Uso:' "$tmp/args-$name.log" || true)" "1" "argumentos $name: muestra uso"
}
args_case help 0 "$PATH" --help
args_case short-help 0 "$PATH" -h
args_case help-no-tools 0 "$tmp/empty-path" --help
args_case short-help-no-tools 0 "$tmp/empty-path" -h
args_case unknown 64 "$PATH" --unknown
args_case extra 64 "$PATH" --apply extra
args_case combined 64 "$PATH" --plan --apply
args_case help-extra 64 "$tmp/empty-path" --help extra
args_case unknown-no-tools 64 "$tmp/empty-path" --unknown
args_case layer-extra 64 "$PATH" --enable-secrets-layer2 extra

# HOME falso: install.sh enlaza handoff y oraculo en $HOME/.local/bin y no debe tocar el de quien corre el test.
# CLAUDE_HOME es $HOME/.claude porque solo ahi se enlaza (con otro, install.sh imprime las ordenes; ver abajo).
export HOME="$tmp/home"; mkdir -p "$HOME"
export CLAUDE_HOME="$HOME/.claude"
# Con `set -e` y la salida a /dev/null, un fallo aqui mataba la suite con rc=1 y CERO salida:
# rojo correcto pero imposible de diagnosticar. Se captura para que el rojo diga por que.
set +e; bash "$KIT/install.sh" >"$tmp/install.log" 2>&1; irc=$?; set -e
ck "$irc" "0" "install.sh sale 0 en un CLAUDE_HOME limpio$([ "$irc" -eq 0 ] || printf ' -- %s' "$(tail -1 "$tmp/install.log")")"
ck "$([ -f "$CLAUDE_HOME/CLAUDE.md" ] && echo y)" "y" "instala CLAUDE.md"
ck "$([ -f "$CLAUDE_HOME/AGENTS.md" ] && echo y)" "y" "instala AGENTS.md junto a CLAUDE.md (su @AGENTS.md lo importa)"
ck "$([ -f "$CLAUDE_HOME/settings.json" ] && echo y)" "y" "instala settings.json"
ck "$([ -x "$CLAUDE_HOME/hooks/branch-guard.sh" ] && echo y)" "y" "hook ejecutable"
ck "$([ -f "$CLAUDE_HOME/sentinel/sentinel_preflight.py" ] && echo y)" "y" "instala sentinel"
ck "$([ -f "$CLAUDE_HOME/hooks/lib/nucleo.sh" ] && echo y)" "y" "instala hooks/lib"
ck "$([ -f "$CLAUDE_HOME/templates/nucleo.md" ] && echo y)" "y" "instala templates"
ck "$([ -x "$CLAUDE_HOME/bin/handoff" ] && [ -x "$CLAUDE_HOME/bin/oraculo" ] && echo y)" "y" "instala bin/handoff y bin/oraculo ejecutables"

# Las post-condiciones deben cubrir el inventario completo y sus ejecutables,
# no solo los ficheros que settings.json referencia.
rm "$CLAUDE_HOME/skills/deep-change/SKILL.md"
set +e; bash "$HERE/../../.github/scripts/assert-install.sh" "$CLAUDE_HOME" >/dev/null 2>&1; arc=$?; set -e
ck "$arc" "1" "post-condiciones FAIL si falta una skill obligatoria"
bash "$KIT/install.sh" >/dev/null 2>&1
chmod -x "$CLAUDE_HOME/statusline-command.sh"
set +e; bash "$HERE/../../.github/scripts/assert-install.sh" "$CLAUDE_HOME" >/dev/null 2>&1; arc=$?; set -e
ck "$arc" "1" "post-condiciones FAIL si un ejecutable obligatorio pierde el permiso"
bash "$KIT/install.sh" >/dev/null 2>&1
printf '# skill personalizada\n' > "$tmp/skill-personalizada.md"
rm "$CLAUDE_HOME/skills/deep-change/SKILL.md"
ln -s "$tmp/skill-personalizada.md" "$CLAUDE_HOME/skills/deep-change/SKILL.md"
set +e; bash "$HERE/../../.github/scripts/assert-install.sh" "$CLAUDE_HOME" >/dev/null 2>&1; arc=$?; set -e
ck "$arc" "0" "post-condiciones aceptan una skill personalizada mediante symlink"
rm "$CLAUDE_HOME/skills/deep-change/SKILL.md"
bash "$KIT/install.sh" >/dev/null 2>&1

ck "$(readlink "$HOME/.local/bin/handoff")" "$CLAUDE_HOME/bin/handoff" "crea el enlace ~/.local/bin/handoff -> bin/handoff"
ck "$(readlink "$HOME/.local/bin/oraculo")" "$CLAUDE_HOME/bin/oraculo" "crea el enlace ~/.local/bin/oraculo -> bin/oraculo"
ck "$(grep -c 'no esta en tu PATH' "$tmp/install.log")" "1" "avisa si ~/.local/bin no esta en el PATH"
ck "$(grep -c 'CLAUDE.kit.md' "$tmp/install.log")" "0" "sin CLAUDE.md previo no hay aviso de @AGENTS.md"
set +e; PATH="$HOME/.local/bin:$PATH" bash "$KIT/install.sh" >"$tmp/install2.log" 2>&1; set -e
ck "$(grep -c 'no esta en tu PATH' "$tmp/install2.log")" "0" "con ~/.local/bin en el PATH no hay aviso"
ck "$(readlink "$HOME/.local/bin/handoff")" "$CLAUDE_HOME/bin/handoff" "reinstalar mantiene el enlace propio"
# Un fichero o un enlace ajeno no se pisa: se avisa.
rm "$HOME/.local/bin/handoff" "$HOME/.local/bin/oraculo"
printf 'mio\n' > "$HOME/.local/bin/handoff"; ln -s /bin/true "$HOME/.local/bin/oraculo"
set +e; bash "$KIT/install.sh" >"$tmp/install3.log" 2>&1; set -e
ck "$(cat "$HOME/.local/bin/handoff")" "mio" "no pisa un fichero ajeno en ~/.local/bin"
ck "$(readlink "$HOME/.local/bin/oraculo")" "/bin/true" "no pisa un enlace ajeno en ~/.local/bin"
ck "$(grep -c 'no se enlazo' "$tmp/install3.log")" "1" "avisa de los enlaces que no pudo crear"
rm "$HOME/.local/bin/handoff" "$HOME/.local/bin/oraculo"
# diff-first (--plan): no escribe en ~/.local/bin, lo pone en el plan.
set +e; MCHARNESS_OUT="$tmp/plan-ln" bash "$KIT/install.sh" --plan >"$tmp/plan-ln.log" 2>&1; set -e
ck "$([ -e "$HOME/.local/bin/handoff" ] && echo y || echo n)" "n" "--plan no crea enlaces"
ck "$(grep -c 'se enlazarian handoff y oraculo' "$tmp/plan-ln.log")" "1" "--plan lo dice en el plan"
# Un CLAUDE_HOME que no es $HOME/.claude (prueba, CI, sandbox) enlazaba en el ~/.local/bin real, y al
# borrar esa ruta los enlaces quedaban colgantes y ya no se reparaban (contaban como ajenos). Ahora no
# escribe nada ahi: imprime las ordenes ln -s.
H2="$tmp/home-otro"; mkdir -p "$H2"
set +e; HOME="$H2" CLAUDE_HOME="$tmp/otro" bash "$KIT/install.sh" >"$tmp/otro.log" 2>&1; orc=$?; set -e
ck "$orc" "0" "CLAUDE_HOME no estandar: install.sh sale 0"
ck "$(find "$H2/.local/bin" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')" "0" "CLAUDE_HOME no estandar: no aparece ningun enlace en ~/.local/bin"
ck "$(grep -cF "ln -s \"$tmp/otro/bin/handoff\" \"$H2/.local/bin/handoff\"" "$tmp/otro.log")" "1" "CLAUDE_HOME no estandar: imprime la orden ln -s de handoff"
ck "$(grep -cF "ln -s \"$tmp/otro/bin/oraculo\" \"$H2/.local/bin/oraculo\"" "$tmp/otro.log")" "1" "CLAUDE_HOME no estandar: imprime la orden ln -s de oraculo"
set +e; HOME="$H2" CLAUDE_HOME="$tmp/otro" MCHARNESS_OUT="$tmp/plan-otro" bash "$KIT/install.sh" --plan >"$tmp/plan-otro.log" 2>&1; set -e
ck "$(grep -c 'se enlazarian handoff y oraculo' "$tmp/plan-otro.log")" "0" "--plan con CLAUDE_HOME no estandar no promete enlaces"
bash "$KIT/install.sh" >/dev/null 2>&1
# En el plan diff-first los bin entran como cualquier otro fichero del kit (y con el modo ejecutable).
set +e; MCHARNESS_OUT="$tmp/plan-bin" bash "$KIT/install.sh" --plan >"$tmp/plan.log" 2>&1; set -e
ck "$([ -x "$tmp/plan-bin/bin/handoff" ] && grep -c 'bin/handoff' "$tmp/plan.log" | grep -qv '^0$' && echo y)" "y" "el plan diff-first incluye bin/handoff ejecutable"

# Idempotencia + backup: modifica un fichero que el KIT posee, reinstala, debe backupear.
# Se usa .gitleaks.toml y no CLAUDE.md: CLAUDE.md son TUS instrucciones y desde ahora no se
# pisa (ver abajo), asi que ya no genera backup -- genera CLAUDE.kit.md.
echo "# MOD" >> "$CLAUDE_HOME/.gitleaks.toml"
set +e; bash "$KIT/install.sh" >/dev/null 2>&1; rrc=$?; set -e
ck "$(find "$CLAUDE_HOME/backups" -mindepth 2 -maxdepth 2 -name .gitleaks.toml 2>/dev/null | wc -l | tr -d ' ')" "1" "backup creado al reinstalar"
ck "$rrc" "0" "reinstalar no falla"

# --- Reinstalar NO destruye tu configuracion personal -----------------------
# El fallo que esto cierra, medido en una maquina real: un `install.sh --apply` sobre una
# instalacion existente reemplazaba settings.json entero y se llevaba en silencio
# ENABLE_TOOL_SEARCH (~30k de contexto por sesion), el ANTHROPIC_MODEL con el sufijo de la
# ventana de 1M, CLAUDE_CODE_AUTO_COMPACT_WINDOW y tres limites mas. Y reemplazaba CLAUDE.md,
# que es prosa escrita a mano y no se puede fusionar.
if command -v jq >/dev/null 2>&1; then
  tmp2="$(mktemp)"
  jq '.env.MI_CLAVE = "mia" | .model = "fable[1m]" | .statusLine = {"command":"mi-statusline"}
      | .permissions.allow += ["Bash(mi-comando *)"]' \
     "$CLAUDE_HOME/settings.json" > "$tmp2" && mv "$tmp2" "$CLAUDE_HOME/settings.json"
  printf '# mis instrucciones a mano\nno me borres\n' > "$CLAUDE_HOME/CLAUDE.md"
  rm -f "$CLAUDE_HOME/CLAUDE.kit.md"
  set +e; bash "$KIT/install.sh" >"$tmp/prev.log" 2>&1; set -e
  ck "$(grep -c '@AGENTS.md' "$tmp/prev.log")" "1" "con CLAUDE.md previo sin import: aviso con @AGENTS.md"
  ck "$(grep -c 'CLAUDE.kit.md' "$tmp/prev.log" | awk '{print ($1>=1)}')" "1" "el aviso nombra CLAUDE.kit.md"
  printf '# mio\n%s\n' '@AGENTS.md' > "$CLAUDE_HOME/CLAUDE.md"
  set +e; bash "$KIT/install.sh" >"$tmp/prev2.log" 2>&1; set -e
  ck "$(grep -c 'Añade @AGENTS.md' "$tmp/prev2.log")" "0" "si tu CLAUDE.md ya importa @AGENTS.md no hay aviso"
  printf '# mis instrucciones a mano\nno me borres\n' > "$CLAUDE_HOME/CLAUDE.md"
  set +e; bash "$KIT/install.sh" >/dev/null 2>&1; set -e

  ck "$(jq -r '.env.MI_CLAVE // "AUSENTE"' "$CLAUDE_HOME/settings.json")" "mia" "reinstalar conserva tus claves de env"
  ck "$(jq -r '.model // "AUSENTE"' "$CLAUDE_HOME/settings.json")" "fable[1m]" "reinstalar conserva tu model"
  ck "$(jq -r '.statusLine.command // "AUSENTE"' "$CLAUDE_HOME/settings.json")" "mi-statusline" "reinstalar conserva claves que el kit no gestiona"
  ck "$(jq -r '[.permissions.allow[] | select(. == "Bash(mi-comando *)")] | length' "$CLAUDE_HOME/settings.json")" "1" "reinstalar conserva tus permisos allow"
  ck "$(jq -r '[.permissions.deny[] | select(. == "Bash(git push -*f *)")] | length' "$CLAUDE_HOME/settings.json")" "1" "reinstalar mantiene los deny del kit (union, no reemplazo)"
  ck "$(jq -r '[.hooks.PreToolUse[].hooks[].command | select(test("block-dangerous"))] | length' "$CLAUDE_HOME/settings.json")" "1" "los hooks los sigue poniendo el kit"
  ck "$(grep -c 'no me borres' "$CLAUDE_HOME/CLAUDE.md")" "1" "reinstalar NO pisa tu CLAUDE.md"
  ck "$([ -f "$CLAUDE_HOME/CLAUDE.kit.md" ] && echo y)" "y" "la version del kit queda al lado en CLAUDE.kit.md"
else
  echo "skip - jq ausente: no se prueba la fusion de settings.json"
fi

# El aviso de credenciales solo recomienda copiar la plantilla si existe.
cp -a "$KIT" "$tmp/kit-sin-env"; rm -f "$tmp/kit-sin-env/.env.example"
set +e; bash "$tmp/kit-sin-env/install.sh" >"$tmp/sin-env.log" 2>&1; set -e
ck "$(grep -c 'cp .*\.env\.example' "$tmp/sin-env.log")" "0" "sin plantilla de credenciales no manda copiarla"
ck "$(grep -c 'cp .*\.env\.example' "$tmp/install.log")" "$([ -f "$KIT/.env.example" ] && echo 1 || echo 0)" "con plantilla en el kit si manda copiarla"

# Regresion 2026-09-02: un __pycache__ dentro del kit rompia el bucle `cp` de install.sh
# ("cp: -r not specified; omitting directory"), el instalador salia rc=1 y dejaba la
# instalacion a medias -- y con ella test_doctor.sh en rojo por una causa ajena al doctor.
# Los bucles filtran con -f: un directorio se ignora en vez de matar la instalacion.
cp -a "$KIT" "$tmp/kitcopy"
mkdir -p "$tmp/kitcopy/sentinel/__pycache__" "$tmp/kitcopy/claude/agents/__pycache__"
: > "$tmp/kitcopy/sentinel/__pycache__/sentinel_preflight.cpython-314.pyc"
set +e; CLAUDE_HOME="$tmp/dot2" bash "$tmp/kitcopy/install.sh" >"$tmp/pyc.log" 2>&1; prc=$?; set -e
ck "$prc" "0" "un __pycache__ en el kit no rompe la instalacion"
ck "$(grep -c 'omitting directory' "$tmp/pyc.log" || true)" "0" "install.sh no intenta copiar directorios"
ck "$([ -f "$tmp/dot2/sentinel/sentinel_preflight.py" ] && echo y)" "y" "sentinel se instala con __pycache__ presente"
ck "$([ -d "$tmp/dot2/sentinel/__pycache__" ] && echo y || echo n)" "n" "el __pycache__ no viaja a CLAUDE_HOME"

# Los validadores tampoco deben exigir caches generadas en el fuente.
# Se compilan los hooks reales en la copia, no en el checkout que ejecuta la suite.
env -u PYTHONPYCACHEPREFIX python3 -m compileall -q "$tmp/kitcopy/claude/hooks" "$tmp/kitcopy/sentinel"
ck "$(find "$tmp/kitcopy/claude/hooks" -name '*.pyc' -print -quit | wc -l)" "1" "la regresion genera bytecode real en el fuente"
mkdir -p "$tmp/cache-check/.github/scripts"
cp "$HERE/../../.github/scripts/assert-install.sh" "$tmp/cache-check/.github/scripts/"
ln -s "$tmp/kitcopy" "$tmp/cache-check/kit"
cache_home="$tmp/cache-home"
HOME="$cache_home" CLAUDE_HOME="$cache_home/.claude" bash "$tmp/kitcopy/install.sh" >"$tmp/cache-install.log" 2>&1
set +e
HOME="$cache_home" CLAUDE_HOME="$cache_home/.claude" \
  bash "$tmp/cache-check/.github/scripts/assert-install.sh" "$cache_home/.claude" >"$tmp/cache-smoke.log" 2>&1
cache_smoke_rc=$?
env -u ANTHROPIC_BASE_URL HOME="$cache_home" CLAUDE_HOME="$cache_home/.claude" \
  XDG_CONFIG_HOME="$cache_home/.config" COLUMNS=140 \
  bash "$tmp/kitcopy/doctor.sh" >"$tmp/cache-doctor.log" 2>&1
cache_doctor_rc=$?
set -e
ck "$cache_smoke_rc" "0" "smoke acepta la instalacion sin exigir caches del fuente"
ck "$cache_doctor_rc" "0" "doctor acepta la instalacion sin exigir caches del fuente"

# N2: con CLAUDE_HOME no estandar no se enlaza nada; el aviso de PATH no puede decir que
# handoff y oraculo "no se encontraran" (no estan enlazados) y debe orientar a lo que si hay que hacer.
rm -f "$tmp/home/.local/bin/handoff" "$tmp/home/.local/bin/oraculo"
set +e; CLAUDE_HOME="$tmp/otro" bash "$KIT/install.sh" >"$tmp/otro.log" 2>&1; set -e
ck "$(grep -c 'no se encontraran' "$tmp/otro.log" || true)" "0" "CLAUDE_HOME no estandar: el aviso de PATH no da por enlazados handoff y oraculo"
ck "$(grep -c "ln -s \"$tmp/otro/bin/handoff\"" "$tmp/otro.log" || true)" "1" "CLAUDE_HOME no estandar: imprime la orden ln -s"
ck "$([ -e "$HOME/.local/bin/handoff" ] && echo y || echo n)" "n" "CLAUDE_HOME no estandar: no crea enlaces"


# --- L1 y M6 residuo: «nuestro» se decide por ruta canonica, no por prefijo de texto ---
# El prefijo "$CLAUDE_HOME/bin/"* aceptaba bin/../../x como nuestro y lo pisaba con ln -sfn.
H3="$tmp/home-l1"; mkdir -p "$H3/.local/bin"
export HOME="$H3" CLAUDE_HOME="$H3/.claude"
ln -s "$CLAUDE_HOME/bin/../../ajeno" "$HOME/.local/bin/handoff"
set +e; bash "$KIT/install.sh" >"$tmp/l1.log" 2>&1; set -e
ck "$(readlink "$HOME/.local/bin/handoff")" "$CLAUDE_HOME/bin/../../ajeno" "L1: un enlace con bin/../../x NO es nuestro y no se pisa"
ck "$(grep -c 'bin/handoff ya existe' "$tmp/l1.log")" "1" "L1: avisa del enlace ajeno"
ck "$(readlink "$HOME/.local/bin/oraculo")" "$CLAUDE_HOME/bin/oraculo" "L1: el hueco libre se enlaza"
# Un enlace nuestro con otra grafia (bin/../bin/x) se normaliza.
rm "$HOME/.local/bin/handoff"; ln -s "$CLAUDE_HOME/bin/../bin/handoff" "$HOME/.local/bin/handoff"
set +e; bash "$KIT/install.sh" >"$tmp/l1b.log" 2>&1; set -e
ck "$(readlink "$HOME/.local/bin/handoff")" "$CLAUDE_HOME/bin/handoff" "enlace nuestro con otra grafia: se deja con la ruta exacta"
# SCC-04: un enlace a OTRO fichero existente de nuestro bin/ (un wrapper de la persona) no es el CLI: ajeno, no se pisa.
rm "$HOME/.local/bin/handoff"; printf 'wrapper\n' > "$CLAUDE_HOME/bin/custom-wrapper"
ln -s "$CLAUDE_HOME/bin/custom-wrapper" "$HOME/.local/bin/handoff"
set +e; bash "$KIT/install.sh" >"$tmp/l1c.log" 2>&1; set -e
ck "$(readlink "$HOME/.local/bin/handoff")" "$CLAUDE_HOME/bin/custom-wrapper" "SCC-04: un enlace a otro fichero existente de nuestro bin/ no se pisa"
ck "$(grep -c 'bin/handoff ya existe' "$tmp/l1c.log")" "1" "SCC-04: y se avisa como ajeno"
rm "$HOME/.local/bin/handoff" "$CLAUDE_HOME/bin/custom-wrapper"
# M6 residuo: ~/.claude es un enlace a otro sitio y el enlace colgante apunta por la ruta real.
H4="$tmp/home-m6"; mkdir -p "$H4/.local/bin" "$H4/real"; ln -s "$H4/real" "$H4/.claude"
export HOME="$H4" CLAUDE_HOME="$H4/.claude"
ln -s "$H4/real/bin/viejo" "$HOME/.local/bin/handoff"
ck "$([ -e "$HOME/.local/bin/handoff" ] && echo y || echo n)" "n" "M6: el enlace de partida esta colgante (falsabilidad del caso)"
set +e; bash "$KIT/install.sh" >"$tmp/m6.log" 2>&1; set -e
ck "$(readlink "$HOME/.local/bin/handoff")" "$CLAUDE_HOME/bin/handoff" "M6: un enlace colgante hacia nuestro bin/ (ruta canonica) se repara"
rm "$HOME/.local/bin/oraculo"; ln -s "$H4/otro/bin/oraculo" "$HOME/.local/bin/oraculo"
set +e; bash "$KIT/install.sh" >"$tmp/m6b.log" 2>&1; set -e
ck "$(readlink "$HOME/.local/bin/oraculo")" "$H4/otro/bin/oraculo" "M6: un enlace colgante ajeno se deja"
ck "$(grep -c 'bin/oraculo ya existe' "$tmp/m6b.log")" "1" "M6: y se avisa"
# TOCTOU: crear el enlace no puede ser un `ln -f`, que pisaria lo que aparezca entre la comprobacion y el ln.
ck "$(sed -n '/^enlazar_clis()/,/^}/p' "$KIT/install.sh" | grep -cE 'ln -[a-z]*f')" "0" "TOCTOU: enlazar_clis no usa ln -f"
echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
