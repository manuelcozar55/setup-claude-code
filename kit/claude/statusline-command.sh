#!/bin/bash
# Statusline en dos lineas, sin node:
#   1: modelo | cwd completa | repo | rama | cambios
#   2: contexto (gris) | limites 5h y 7d (azul)
# Sustituye a ccstatusline (~300 ms por refresco: arranca node con un bundle de
# 3,3 MB y relee el transcript entero para sacar el contexto, que Claude Code ya
# manda en context_window.current_usage con la misma formula).

# UTF-8 para que ${#s} cuente caracteres y no bytes; C para que git no traduzca
# "insertions"/"deletions" del --shortstat. Sin locks opcionales: el refresco no
# debe pelear por index.lock con el git de la sesion.
# core.fsmonitor=false en cada diff: el fsmonitor de un .git/config ajeno es un ejecutable, y la
# barra corre git en cualquier directorio en el que entres.
export LC_ALL=C.UTF-8 GIT_OPTIONAL_LOCKS=0

mapfile -t f < <(jq -r '
  def dec($u): (. / $u * 10 | round) as $d | "\($d / 10 | floor).\($d % 10)";
  def tok: if . >= 999950 then "\(dec(1e6))M" elif . >= 1000 then "\(dec(1e3))k" else tostring end;
  def left: . - now | if . < 0 then 0 else floor end;
  def lim($n; $l; fmt): if $l.used_percentage != null and $l.resets_at != null
    then ($l.resets_at | left) as $d | "\($n):\($l.used_percentage | round)% (resets in \($d | fmt))"
    else "" end;
  (.context_window.current_usage // {}) as $u |
  (.model.display_name // .model.id // "" | sub(" *\\([^)]*\\)$"; "")),
  (.workspace.current_dir // .cwd // ""),
  "Ctx: \(($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.cache_read_input_tokens // 0) | tok)",
  lim("5h"; .rate_limits.five_hour // {}; "\(. / 3600 | floor)h\(. % 3600 / 60 | floor)m"),
  lim("7d"; .rate_limits.seven_day // {}; "\(. / 86400 | floor)d\(. % 86400 / 3600 | floor)h")
')
model=${f[0]} cwd=${f[1]} ctx=${f[2]} five=${f[3]} week=${f[4]}

repo="" branch="" changes=""
if top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null); then
  repo=${top##*/}
  branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
  [ -n "$branch" ] || branch=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  branch="⎇ $branch"
  ins=0 del=0
  while read -r l; do
    [[ $l =~ ([0-9]+)\ insertion ]] && ins=$(( ins + BASH_REMATCH[1] ))
    [[ $l =~ ([0-9]+)\ deletion ]] && del=$(( del + BASH_REMATCH[1] ))
  done < <(git -c core.fsmonitor=false -C "$cwd" diff --shortstat 2>/dev/null; git -c core.fsmonitor=false -C "$cwd" diff --cached --shortstat 2>/dev/null)
  changes="(+$ins,-$del)"
else
  repo="no git"
fi

# Ancho real: el script no tiene terminal propio, asi que se sube por los padres
# hasta el TTY de claude (el mismo truco que usaba ccstatusline). COLUMNS manda.
cols=${COLUMNS:-}
pid=$PPID
while [ -z "$cols" ] && [ "${pid:-0}" -gt 1 ]; do
  read -r tty pid < <(ps -o tty=,ppid= -p "$pid" 2>/dev/null) || break
  case $tty in ''|'?') ;; *) read -r _ cols < <(stty -F "/dev/$tty" size 2>/dev/null) ;; esac
done
# margen de 6 como el flexMode "full" de ccstatusline; sin ancho, nunca se parte
max=$(( ${cols:-0} > 6 ? cols - 6 : 1 << 30 ))

# render COLOR TEXTO [COLOR TEXTO ...]: une con " | " gris, omite los vacios y,
# si no cabe en $max, salta de linea en un separador; nunca corta un texto.
render() {
  local line="" w=0
  while [ $# -gt 1 ]; do
    if [ -n "$2" ]; then
      if (( w > 0 && w + 3 + ${#2} > max )); then
        printf '%s\n' "$line"; line="" w=0
      fi
      (( w > 0 )) && { line+=$'\e[38;5;59m | \e[0m'; (( w += 3 )); }
      line+=$'\e['"$1m$2"$'\e[0m'; (( w += ${#2} ))
    fi
    shift 2
  done
  printf '%s\n' "$line"
}

render "38;5;30" "$model" "38;5;188" "$cwd" "38;5;70" "$repo" "38;5;96" "$branch" "38;5;178" "$changes"
render "38;5;59" "$ctx" "34" "$five" "34" "$week"
