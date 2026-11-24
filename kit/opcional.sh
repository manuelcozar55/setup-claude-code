# opcional.sh — las piezas que el kit NO instala por defecto y se piden con `install.sh --con <pieza>[,<pieza>…]`.
# Una sola fuente para install.sh, doctor.sh, uninstall.sh y .github/scripts/assert-install.sh. Se lee con `.`.
# El código de cada pieza sigue en el repo; lo que cambia es que la instalación sin flags no lo copia ni lo cablea.
# Lo que cablean en settings.json va en opcional-settings.json (una clave por pieza).
PIEZAS_OPCIONALES="esenciales revisores skills-extra cockpit nudge sentinel"

opcional_globs() {  # pieza -> rutas relativas a CLAUDE_HOME (patron de case; `dir/*` = todo lo de dentro), una por linea
  case $1 in
    esenciales) printf '%s\n' 'scc/plugins/*' ;;
    revisores)  printf '%s\n' 'agents/silent-failure-hunter.md' 'agents/pr-test-analyzer.md' ;;
    skills-extra) printf '%s\n' 'skills/verification-before-completion/*' 'skills/retro/*' ;;
    cockpit)    printf '%s\n' 'scc/mods/cockpit/*' ;;
    nudge)      printf '%s\n' 'hooks/nucleo-nudge.sh' ;;
    sentinel)   printf '%s\n' 'sentinel/*' 'hooks/narthex-post-mcp.py' ;;
  esac
}

opcional_de() {  # ruta relativa a CLAUDE_HOME -> imprime su pieza (rc 0), o rc 1 si es del nucleo
  local p g
  for p in $PIEZAS_OPCIONALES; do
    while IFS= read -r g; do
      # shellcheck disable=SC2254 # $g es un patron a proposito
      case "$1" in $g) printf '%s' "$p"; return 0 ;; esac
    done < <(opcional_globs "$p")
  done
  return 1
}

pieza_instalada() {  # CLAUDE_HOME pieza: ¿hay algo suyo en disco?
  local g
  while IFS= read -r g; do
    case $g in
      */\*) [ -n "$(find "$1/${g%/\*}" -mindepth 1 \( -type f -o -type l \) -print -quit 2>/dev/null)" ] && return 0 ;;
      *) [ -e "$1/$g" ] && return 0 ;;
    esac
  done < <(opcional_globs "$2")
  return 1
}
