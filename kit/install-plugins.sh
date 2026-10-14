#!/usr/bin/env bash
# install-plugins.sh — Instala por referencia (marketplace de Claude Code) los plugins de
# terceros recomendados. Opt-in y diff-first: sin --apply solo imprime los comandos.
# Nada se copia a este repo; licencias y riesgos en THIRD-PARTY.md y kit/docs/08-plugins-mcp-y-skills.md.
# Uso: bash install-plugins.sh [--apply] [--with-optional]
set -euo pipefail

apply=0; optional=0
for a in "$@"; do
  case "$a" in
    --apply) apply=1 ;;
    --with-optional) optional=1 ;;
    *) echo "uso: bash install-plugins.sh [--apply] [--with-optional]" >&2; exit 2 ;;
  esac
done

# "<repo del marketplace> <plugin>@<marketplace>"; el marketplace oficial ya viene registrado.
RECOMMENDED=(
  "- superpowers@claude-plugins-official"
  "- frontend-design@claude-plugins-official"
  "DietrichGebert/ponytail ponytail@ponytail"
  "nextlevelbuilder/ui-ux-pro-max-skill ui-ux-pro-max@ui-ux-pro-max-skill"
)
# impeccable descarga un binario y lo ejecuta desde hooks en cada edicion: solo a peticion.
OPTIONAL=(
  "pbakaus/impeccable impeccable@impeccable"
)

entries=("${RECOMMENDED[@]}")
[ "$optional" = 1 ] && entries+=("${OPTIONAL[@]}")

cmds=()
for e in "${entries[@]}"; do
  read -r repo plugin <<<"$e"
  [ "$repo" != "-" ] && cmds+=("claude plugin marketplace add $repo --scope user")
  cmds+=("claude plugin install $plugin --scope user --yes")
done
if [ "$optional" = 1 ]; then
  runner=npx; command -v pnpm >/dev/null 2>&1 && runner="pnpm dlx"
  cmds+=("$runner skills add vercel-labs/skills --skill find-skills -g -a claude-code -y")
fi

if [ "$apply" = 0 ]; then
  echo "# Modo diff: se ejecutarian estos comandos (repite con --apply):"
  printf '%s\n' "${cmds[@]}"
  exit 0
fi

command -v claude >/dev/null 2>&1 || { echo "ERROR: no se encuentra el CLI 'claude' en PATH" >&2; exit 1; }
for c in "${cmds[@]}"; do
  echo "+ $c"
  # shellcheck disable=SC2086  # los comandos son literales de este script, sin entrada externa
  $c
done
echo "Plugins instalados. Reinicia Claude Code para cargarlos."
