#!/bin/bash
# destructive-guard.sh — Blocks rm-rf on sensitive paths, git reset --hard, git clean
# Source: yurukusa/claude-code-hooks (MIT)
# WSL2 note: rm -rf follows NTFS junctions — can delete far beyond target directory
# Protocol: exit 2 = block

INPUT=$(cat)
# El escape hatch declarado se atiende ANTES del fail-closed de abajo: quien pone
# CC_ALLOW_DESTRUCTIVE=1 ya ha apagado este guard a proposito, y no necesita jq para eso.
[[ "${CC_ALLOW_DESTRUCTIVE:-0}" == "1" ]] && exit 0

# Fail-closed: sin jq no hay decision posible, y permitir en silencio apagaba toda la
# Capa 1 sin un mensaje. Denegar puede frenar trabajo legitimo, y por eso install.sh
# exige jq en una puerta de dependencia: llegar aqui sin el es una instalacion incompleta.
if ! command -v jq >/dev/null 2>&1; then
  echo "BLOCKED (fail-closed): falta jq en el PATH, asi que destructive-guard no puede leer el comando." >&2
  echo "Instala jq (apt install jq) y reintenta." >&2
  exit 2
fi
if ! COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); then
  echo "BLOCKED (fail-closed): el payload de PreToolUse no es JSON parseable; destructive-guard no puede leer el comando." >&2
  exit 2
fi
[[ -z "$COMMAND" ]] && exit 0

log_block() {
  local logfile="${CC_BLOCK_LOG:-$HOME/.claude/audit-logs/blocked-commands.log}"
  mkdir -p "$(dirname "$logfile")" 2>/dev/null
  echo "[$(date -Iseconds)] BLOCKED: $1 | cmd: $COMMAND" >> "$logfile" 2>/dev/null
}

SAFE_DIRS="${CC_SAFE_DELETE_DIRS:-node_modules:dist:build:.cache:__pycache__:coverage:.next:.nuxt:tmp}"

# El texto se normaliza con la lib comun: continuaciones unidas y comentarios quitados SOLO fuera
# de comillas (el sed anterior cortaba en el `#` de `git commit -m "fix #12" && git reset --hard`).
# Un comentario de verdad sigue sin poder voltear la exencion de directorio seguro ni esconderse
# tras un ancla de final (un decoy `... # tmp` tras un rm sobre /etc).
# shellcheck source=SCRIPTDIR/lib/cmdnorm.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/cmdnorm.sh" || { echo "BLOCKED (fail-closed): falta lib/cmdnorm.sh; reinstala el kit." >&2; exit 2; }
cmdn_oversize "$COMMAND" && exit 0
if ! cmdn_parse "$COMMAND"; then
  echo "BLOCKED (fail-closed): awk no pudo normalizar el comando; destructive-guard no puede evaluarlo." >&2
  exit 2
fi
COMMAND_SCAN=$CMDN_TEXT

# Check 1: rm -rf on sensitive paths. ~ and .. are matched even when followed by
# more text (previously end-anchored, so a trailing token defeated detection).
# Las formas largas (--recursive/--force) van en la clase de opciones: solo se aceptaban
# grupos de flags cortos, asi que `rm --recursive --force /home/usuario/docs` no
# emparejaba la ruta sensible y salia limpio de los cinco guards.
if echo "$COMMAND_SCAN" | grep -qE 'rm\s+((-[rf]+|--recursive|--force)\s+)*(\/$|\/\s|\/[^a-z]|\/home|\/etc|\/usr|\/var|\/root|\/boot|~($|[/[:space:]])|\.\.($|[/[:space:]]))'; then
  SAFE=0
  IFS=':' read -ra DIRS <<< "$SAFE_DIRS"
  for dir in "${DIRS[@]}"; do
    # Exempt only when a safe dir is a real path token of the target AND the
    # command is not also touching an absolute sensitive path. Un `..` tras el directorio seguro
    # (`~/dist/../Documents`) escapa de el: no cuenta como exencion.
    if echo "$COMMAND_SCAN" | grep -qE "(^|[[:space:]/])${dir}(/|[[:space:]]|$)" \
       && ! echo "$COMMAND_SCAN" | grep -qE "(^|[[:space:]/])${dir}/([^[:space:]]*/)?\.\.(/|[[:space:]]|$)" \
       && ! echo "$COMMAND_SCAN" | grep -qE '(^|[[:space:]])(/home|/etc|/usr|/var|/root|/boot|/lib|/bin|/sbin)'; then
      SAFE=1; break
    fi
  done
  if (( SAFE == 0 )); then
    log_block "rm on sensitive path"
    echo "BLOCKED: rm on sensitive path (WSL2 risk: NTFS junctions can delete beyond target)." >&2
    echo "Command: $COMMAND" >&2
    exit 2
  fi
fi

# Check 2: git reset --hard
if echo "$COMMAND_SCAN" | grep -qE '^\s*git\s+reset\s+--hard|[;&|]\s*git\s+reset\s+--hard'; then
  log_block "git reset --hard"
  echo "BLOCKED: git reset --hard discards all uncommitted changes." >&2
  echo "Consider: git stash, or git reset --soft" >&2
  exit 2
fi

# Check 3: git clean -fd
if echo "$COMMAND_SCAN" | grep -qE '(^|[;&|])\s*git\s+clean\s+-[a-z]*[fd]'; then
  log_block "git clean"
  echo "BLOCKED: git clean removes untracked files permanently." >&2
  echo "Run: git clean -n (dry run) first to verify what would be deleted." >&2
  exit 2
fi

# Check 4: find -delete on broad paths (WSL2 junction risk). Va sobre tokens, no sobre el texto: la
# regex se evitaba con `find -L .`, `find '.'`, `find ../..` o `find /etc`, y a la vez bloqueaba
# `find . -name '*.pyc' -delete` y hasta un `echo` o un mensaje de commit que lo citara. La ruta son
# los operandos entre las opciones iniciales de find (-H -L -P -O<n> -D x --) y el primer token de
# expresion (-..., `(`, `!`); sin ruta, `.`. Tres familias, con la ruta normalizada (`./.` es `.`):
#   - cwd (`.`, y `*`, `.*`, `{a,b}`... o `./*`, que son su contenido): bloquea salvo que la expresion filtre por nombre
#     o ruta (-name, -path, -regex...).
#   - amplia (`..` y lo que sube de el, `~`, `$HOME`, `/`, `/*`, un solo componente absoluto como
#     /etc, y todo /home/... y /mnt/...): bloquea siempre, con filtro o sin el.
#   - resto (`build`, `./build`, `/tmp/x`): pasa, decision ya declarada.
# Como en branch-guard.sh, la cadena de un `bash -c`, `ssh`, `xargs`... se vuelve a normalizar, hasta
# 3 niveles (un cuarto con -delete se bloquea); git y lo que solo muestra texto (echo, grep...) no cuentan: ahi `find` es prosa.
# shellcheck disable=SC2088,SC2016  # `~` y `$HOME` son el TEXTO del operando, no se expanden.
find_path_class() {
  local c abs=0
  local -a parts out=()
  case $1 in '~'*|'$HOME'|'$HOME/'*|'${HOME}'|'${HOME}/'*) FCLASS=amplia; return ;; esac
  [[ $1 == /* ]] && abs=1
  IFS=/ read -ra parts <<<"$1"
  for c in "${parts[@]}"; do
    case $c in
      ''|.) ;;
      ..) if (( ${#out[@]} )) && [[ ${out[-1]} != .. ]]; then unset 'out[-1]'; elif (( ! abs )); then out+=(..); fi ;;
      *) out+=("$c") ;;
    esac
  done
  if (( abs )); then
    if (( ${#out[@]} <= 1 )) || [[ ${out[0]} == home || ${out[0]} == mnt ]]; then FCLASS=amplia; else FCLASS=resto; fi
  elif (( ${#out[@]} == 0 )) || [[ ${#out[@]} == 1 && ${out[0]} == *['*?[{']* ]]; then FCLASS=cwd
  elif [[ ${out[0]} == .. ]]; then FCLASS=amplia
  else FCLASS=resto
  fi
}
# Cada cadena anidada cuesta un awk (~3 ms): sin tope, 14 KB de `x find;` eran 7 s de CPU, y un guard
# que pasa de su timeout deja ejecutar el comando ENTERO. Solo se vuelve a normalizar la cadena que
# lleva -delete, y pasadas 16 se bloquea: fallar cerrado.
NEST=0
# `find ... | xargs rm` borra lo que find lista sin llevar -delete: la salida de find es el operando.
destructive_name() {
  case ${1##*/} in rm|unlink|shred) return 0 ;; esac
  return 1
}
shell_rm() {
  local depth=$1 seg i inner rc
  local -a T segs saved
  segs=("${CMDN_SEGS[@]}")
  for seg in "${segs[@]}"; do
    cmdn_fields "$seg"
    destructive_name "${T[1]:-}" && return 0
    case ${T[1]:-} in sh|bash) ;; *) continue ;; esac
    inner=
    for (( i = 2; i < ${#T[@]}; i++ )); do
      if [[ ${T[i]} == -*c* ]]; then inner=${T[i+1]:-}; break; fi
    done
    [[ -n $inner ]] || continue
    (( depth < 3 && ++NEST <= 16 )) || return 2
    saved=("${CMDN_SEGS[@]}")
    cmdn_parse "$inner" || { CMDN_SEGS=("${saved[@]}"); continue; }
    shell_rm $(( depth + 1 )); rc=$?
    CMDN_SEGS=("${saved[@]}")
    (( rc == 1 )) || return $rc
  done
  return 1
}
xargs_rm() {
  local seg a i k inner rc
  local -a T saved
  for seg in "${CMDN_SEGS[@]}"; do
    [[ $seg == *xargs* ]] || continue
    cmdn_fields "$seg"
    [[ ${T[1]:-} == xargs ]] || continue
    for (( i = 2; i < ${#T[@]}; i++ )); do
      a=${T[i]}
      destructive_name "$a" && return 0
      case ${a##*/} in sh|bash) ;; *) continue ;; esac
      inner=
      for (( k = i + 1; k < ${#T[@]}; k++ )); do
        if [[ ${T[k]} == -*c* ]]; then inner=${T[k+1]:-}; break; fi
      done
      [[ -n $inner ]] || continue
      (( ++NEST <= 16 )) || return 2
      saved=("${CMDN_SEGS[@]}")
      cmdn_parse "$inner" || { CMDN_SEGS=("${saved[@]}"); continue; }
      shell_rm 1; rc=$?
      CMDN_SEGS=("${saved[@]}")
      (( rc == 1 )) || return $rc
    done
  done
  return 1
}
PIPED=0; XRM=0
find_delete() {
  local depth=$1 seg a i k inner del filt unf rc
  local -a T segs paths
  segs=("${CMDN_SEGS[@]}")
  for seg in "${segs[@]}"; do
    [[ $seg == *find* && ( $seg == *-delete* || $seg == *-exec* || $XRM == 1 ) ]] || continue
    cmdn_fields "$seg"
    if [[ ${T[1]:-} != find ]]; then
      # Un echo/printf que va a `| bash` no es prosa: su texto es la orden.
      case ${T[1]:-} in
        git) continue ;;
        echo|printf|grep|egrep|fgrep|rg|sed|awk|cat|man|type|which|less|head|tail|test|'[') (( PIPED )) || continue ;;
      esac
      for (( i = 2; i < ${#T[@]}; i++ )); do
        a=${T[i]}
        [[ $a == *find* ]] || continue
        inner=$a
        [[ $a == find || $a == */find ]] && printf -v inner '%s ' "${T[@]:i}"
        case ${T[1]:-} in
          python*|perl|ruby|node|php) cmdn_code_inner "$a" find && inner=$REPLY ;;
          echo|printf) inner=${inner//\\n/$'\n'} ;;
        esac
        [[ $inner == *-delete* || $inner == *-exec* ]] || continue
        (( depth < 3 && ++NEST <= 16 )) || return 2
        cmdn_parse "$inner" || continue
        find_delete $(( depth + 1 )); rc=$?
        (( rc == 1 )) || return $rc
      done
      continue
    fi
    k=2
    while (( k < ${#T[@]} )); do
      case ${T[k]} in
        -H|-L|-P|-O*) k=$(( k + 1 )) ;;
        -D) k=$(( k + 2 )) ;;
        --) k=$(( k + 1 )); break ;;
        *) break ;;
      esac
    done
    paths=()
    while (( k < ${#T[@]} )); do
      case ${T[k]} in -*|'('|'!') break ;; esac
      paths+=("${T[k]}"); k=$(( k + 1 ))
    done
    # El filtro solo acota el borrado si va ANTES de -delete (find evalua de izquierda a derecha) y la
    # expresion no lo invierte ni lo puentea: `-o`, `,`, `!`, `-not` y `-prune` hacen que -delete alcance
    # justo lo que el filtro excluia o a todo; `-name '*'` filtra nada.
    del=0; filt=0; unf=0
    for (( i = k; i < ${#T[@]}; i++ )); do
      case ${T[i]} in
        -delete) del=1; (( filt )) || unf=1 ;;
        -exec|-execdir)
          destructive_name "${T[i+1]:-}" && { del=1; (( filt )) || unf=1; }
          ;;
        -o|-or|,|'!'|-not|-prune) unf=1 ;;
        -name|-iname|-path|-ipath|-wholename|-iwholename|-regex|-iregex)
          [[ ${T[i+1]:-} == '*' ]] || filt=1
          i=$(( i + 1 )) ;;
      esac
    done
    (( del || XRM )) || continue
    (( filt && ! unf )) || filt=0
    (( ${#paths[@]} )) || paths=(.)
    for a in "${paths[@]}"; do
      find_path_class "$a"
      [[ $FCLASS == amplia ]] && return 0
      [[ $FCLASS == cwd ]] && (( ! filt )) && return 0
    done
  done
  return 1
}
# La vuelta a normalizar pisa CMDN_SEGS, y el Check 5 lo necesita intacto.
xargs_rm; rc_xrm=$?
if (( rc_xrm == 0 )); then
  XRM=1
elif (( rc_xrm == 2 )); then
  log_block "find deletion nested too deep"
  echo "BLOCKED: mas de 3 niveles o 16 comandos anidados (bash -c, ssh, xargs...) con find -delete: no caben en el timeout del guard; dividelo en comandos cortos." >&2
  exit 2
fi
if [[ $COMMAND_SCAN == *find* && ( $COMMAND_SCAN == *-delete* || $COMMAND_SCAN == *-exec* || $XRM == 1 ) ]]; then
  segs0=("${CMDN_SEGS[@]}")
  cmdn_pipes_to_shell && PIPED=1
  find_delete 0; rc_find=$?
  if (( rc_find == 0 )); then
    log_block "find -delete on broad path"
    echo "BLOCKED: find -delete on broad path (WSL2 junction risk)." >&2
    exit 2
  fi
  if (( rc_find == 2 )); then
    log_block "find -delete nested too deep"
    echo "BLOCKED: mas de 3 niveles o 16 comandos anidados (bash -c, ssh, xargs...) con find -delete: no caben en el timeout del guard; dividelo en comandos cortos." >&2
    exit 2
  fi
  CMDN_SEGS=("${segs0[@]}")
fi

# Check 5: el mismo conjunto sobre cada comando simple ya normalizado (tokens descomillados, sin
# prefijos sudo/env/command/nice/timeout ni ruta de ejecutable, sin opciones globales de git).
# Los checks de arriba siguen mirando el texto porque su patron no esta anclado y por eso ven
# tambien lo que va dentro de un `bash -c "..."`; este cubre las grafias que sacaban el comando del
# patron: `git -C dir reset --hard`, `sudo git clean --force -d`, `rm -rv`, `rm -R`, `rm -rf --`.
# shellcheck disable=SC2088,SC2016  # `~` y `$HOME` son el TEXTO del operando, no se expanden.
sensitive_operand() {
  case $1 in
    /|/[!a-z]*|/home*|/etc*|/usr*|/var*|/root*|/boot*|'~'|'~/'*|..|../*|'$HOME'|'$HOME/'*|'${HOME}'|'${HOME}/'*|*/..|*/../*) return 0 ;;
  esac
  return 1
}
safe_operand() {
  local d p tail
  case $1 in /home*|/etc*|/usr*|/var*|/root*|/boot*|/lib*|/bin*|/sbin*) return 1 ;; esac
  p="/$1/"
  for d in "${DIRS[@]}"; do
    [[ $p == *"/$d/"* ]] || continue
    tail="/${p#*"/$d/"}"
    [[ $tail == *"/../"* ]] || return 0
  done
  return 1
}
IFS=':' read -ra DIRS <<< "$SAFE_DIRS"
for seg in "${CMDN_SEGS[@]}"; do
  cmdn_fields "$seg"
  case ${T[1]:-} in
    rm)
      dd=0
      for a in "${T[@]:2}"; do
        if (( ! dd )) && [[ $a == -- ]]; then dd=1; continue; fi
        if (( ! dd )) && [[ $a == -* ]]; then continue; fi
        if sensitive_operand "$a" && ! safe_operand "$a"; then
          log_block "rm on sensitive path"
          echo "BLOCKED: rm on sensitive path (WSL2 risk: NTFS junctions can delete beyond target)." >&2
          echo "Command: $COMMAND" >&2
          exit 2
        fi
      done ;;
    git)
      case ${T[2]:-} in
        reset)
          for a in "${T[@]:3}"; do
            if [[ $a == --hard ]]; then
              log_block "git reset --hard"
              echo "BLOCKED: git reset --hard discards all uncommitted changes." >&2
              echo "Consider: git stash, or git reset --soft" >&2
              exit 2
            fi
          done ;;
        clean)
          force=0; dry=0
          for a in "${T[@]:3}"; do
            case $a in
              --force) force=1 ;;
              --dry-run) dry=1 ;;
              --*) ;;
              -*) [[ $a == -*[fd]* ]] && force=1; [[ $a == -*n* ]] && dry=1 ;;
            esac
          done
          if (( force && ! dry )); then
            log_block "git clean"
            echo "BLOCKED: git clean removes untracked files permanently." >&2
            echo "Run: git clean -n (dry run) first to verify what would be deleted." >&2
            exit 2
          fi ;;
      esac ;;
  esac
done

exit 0
