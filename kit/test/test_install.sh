#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

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

# N2: con CLAUDE_HOME no estandar no se enlaza nada; el aviso de PATH no puede decir que
# handoff y oraculo "no se encontraran" (no estan enlazados) y debe orientar a lo que si hay que hacer.
rm -f "$tmp/home/.local/bin/handoff" "$tmp/home/.local/bin/oraculo"
set +e; CLAUDE_HOME="$tmp/otro" bash "$KIT/install.sh" >"$tmp/otro.log" 2>&1; set -e
ck "$(grep -c 'no se encontraran' "$tmp/otro.log" || true)" "0" "CLAUDE_HOME no estandar: el aviso de PATH no da por enlazados handoff y oraculo"
ck "$(grep -c "ln -s \"$tmp/otro/bin/handoff\"" "$tmp/otro.log" || true)" "1" "CLAUDE_HOME no estandar: imprime la orden ln -s"
ck "$([ -e "$HOME/.local/bin/handoff" ] && echo y || echo n)" "n" "CLAUDE_HOME no estandar: no crea enlaces"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
