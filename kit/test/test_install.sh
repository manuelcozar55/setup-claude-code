#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

export CLAUDE_HOME="$tmp/dot"
bash "$KIT/install.sh" >/dev/null 2>&1
ck "$([ -f "$CLAUDE_HOME/CLAUDE.md" ] && echo y)" "y" "instala CLAUDE.md"
ck "$([ -f "$CLAUDE_HOME/settings.json" ] && echo y)" "y" "instala settings.json"
ck "$([ -x "$CLAUDE_HOME/hooks/branch-guard.sh" ] && echo y)" "y" "hook ejecutable"
ck "$([ -f "$CLAUDE_HOME/sentinel/sentinel_preflight.py" ] && echo y)" "y" "instala sentinel"

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

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
