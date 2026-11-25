#!/bin/bash
# secret-guard.sh — Blocks git add of .env, credentials, private keys
# QUE-HACE: Deniega leer por Bash (cat, base64, cp, tar, scp, openssl, curl -F f=@) las claves de ~/.ssh, ~/.aws/credentials, .env, ~/.netrc, ~/.git-credentials y ~/.gnupg; deniega git add de .env,credenciales y claves privadas (por nombre, patron o comodin) y git add -A/. con un .env sin ignorar; deja pasar el resto de git add; el contenido de lo que se commitea lo mira el pre-commit con gitleaks (Capa 2).
# Source: yurukusa/claude-code-hooks (MIT)
# Protocol: exit 2 = block
#
# Capa 1 (name-only) of the two-layer secrets architecture: this hook decides
# from the shell command text alone, before the tool runs. Guessing what a
# shell command will do from PreToolUse text would require a real shell
# tokenizer + pathspec resolver + secret scanner, all in bash, within a hook
# time budget — and it would still only see the working tree, not what
# actually gets committed. That's why real content scanning lives in Capa 2
# instead: a `pre-commit` hook (hooks/git/pre-commit) that runs gitleaks over
# the staged index. See docs/05-security.md for the full rationale, and
# kit/test/test_guards.sh + kit/test/test_secret_content_gitleaks.sh for the
# regression coverage of both layers.
#
# No bare "secret" token: it used to match "secreto" as a substring (a false
# positive). Extensions are anchored to end-of-token, not end-of-string.

INPUT=$(cat)

# Fail-closed: sin jq no hay decision posible, y permitir en silencio apagaba toda la
# Capa 1 sin un mensaje. Denegar puede frenar trabajo legitimo, y por eso install.sh
# exige jq en una puerta de dependencia: llegar aqui sin el es una instalacion incompleta.
if ! command -v jq >/dev/null 2>&1; then
  echo "BLOCKED (fail-closed): falta jq en el PATH, asi que secret-guard no puede leer el comando." >&2
  echo "Instala jq (apt install jq) y reintenta." >&2
  echo "Que hacer: instala jq (sudo apt install jq / brew install jq) y reintenta." >&2
  exit 2
fi
if ! COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); then
  echo "BLOCKED (fail-closed): el payload de PreToolUse no es JSON parseable; secret-guard no puede leer el comando." >&2
  echo "Que hacer: reintenta; si se repite es un fallo de Claude Code, no de tu comando." >&2
  exit 2
fi
[[ -z "$COMMAND" ]] && exit 0

# Se decide por los OPERANDOS de cada `git add`, sobre el comando normalizado (lib/cmdnorm.sh): tokens
# descomillados, sin prefijos (sudo, env...) ni opciones globales de git. Antes eran regex sobre el texto
# entero, y fallaban en tres sitios: `git -C . add .env` no llegaba al filtro, la exencion del fichero
# de ejemplo se evaluaba sobre TODO el comando (`git add .env.example .env` pasaba) y `--all` no existia.
# shellcheck source=SCRIPTDIR/lib/cmdnorm.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/cmdnorm.sh" || { echo "BLOCKED (fail-closed): falta lib/cmdnorm.sh; reinstala el kit. Que hacer: reinstala el kit (./install.sh --apply)." >&2; exit 2; }
cmdn_oversize "$COMMAND" && exit 0
if ! cmdn_parse "$COMMAND"; then
  echo "BLOCKED (fail-closed): awk no pudo normalizar el comando; secret-guard no puede evaluarlo." >&2
  echo "Que hacer: comprueba que awk (mawk o gawk) esta instalado y reintenta con un comando mas corto." >&2
  exit 2
fi

# Un componente que nombra un fichero de entorno. `.envrc` se deniega a proposito (direnv).
env_name() {
  local n=$1 c
  if [[ $n == *[*?[]* ]]; then
    [[ $n =~ ^\*+$ ]] && return 1
    # Un glob casa con un fichero de entorno si casa con alguno de estos nombres tipicos. Acepta el falso
    # positivo de `*.bak`, `*~` o `*.local`: no se puede saber que ficheros hay detras.
    for c in .env .env.local .env.production .envrc x.env x.env.local production.env.bak config.env~ .env.bak .env-prod .env_local; do
      # shellcheck disable=SC2053  # el glob es justo lo que se compara
      [[ $c == $n ]] && return 0
    done
    return 1
  fi
  # Plantilla: el ULTIMO sufijo es example|sample|template|dist (`.env.local.example`, `.envrc.example`). Codigo: `x.env.ts`, `jest.env.js` no
  # son entornos; sin `.env.<codigo>` a secas ni `.json` (un `.env.json` puede llevar secretos).
  [[ $n =~ \.env.*\.(example|template|sample|dist)$ ]] && return 1
  [[ $n =~ .\.env\.(d\.ts|ts|mts|cts|js|mjs|cjs|py|rb|go)$ ]] && return 1
  [[ $n =~ (\.env($|[.~_-])|\.envrc) ]]
}
# Expande las llaves `{a,b}` de un operando (una por pasada); las variantes quedan en el array BEX. Sin subshell ni fork: cada operando
# pasa por aqui y un fork por operando hacia superar el timeout del hook con una orden larga.
brace_expand() {
  local w=$1 pre alt post a
  if [[ $w == *\{*,*\}* && $w =~ ^([^{]*)\{([^{}]*,[^{}]*)\}(.*)$ ]]; then
    pre=${BASH_REMATCH[1]} alt=${BASH_REMATCH[2]} post=${BASH_REMATCH[3]}
    alt+=,
    while [[ -n $alt ]]; do
      a=${alt%%,*}; alt=${alt#*,}
      brace_expand "$pre$a$post"
    done
  else
    BEX+=("$w")
  fi
}

# --- Leer material de credenciales por Bash (espejo en Bash de los deny de Read). Sin Sentinel (opcional) `permissions.deny` solo cubre la
# herramienta Read: `cat ~/.ssh/id_rsa` no tenia barrera. Se deniega cuando una de estas rutas es OPERANDO de una orden de una lista
# CERRADA de las que leen o copian (cat, head, base64, cp, tar, scp, openssl, curl -F f=@...): ~/.ssh (salvo config, known_hosts,
# authorized_keys y *.pub), ~/.aws (salvo config), ~/.gnupg (salvo *.conf), .env*, ~/.netrc, ~/.git-credentials y ~/.config/gh/hosts.yml.
# Lo que tumbo a Sentinel fueron los falsos positivos, asi que se mira el OPERANDO y no el texto: el literal como patron de grep/sed/awk,
# en un commit, un echo, un heredoc o un comentario no es operando; ls, chmod, ssh, ssh-keygen, ssh-add, test y git no estan en la lista;
# de cp/scp/rsync el ultimo operando es el destino y no se lee; las opciones de identidad (-i, -F, -o, -e) no se leen. Ante un caso que no
# se distingue del benigno gana el benigno (SECURITY.md: sin barrera por defecto, `--con sentinel`).
# Tope duro de trabajo (el guard corre con un timeout de 10 s y, pasado, la herramienta se ejecuta): operandos que llegan al analisis de
# ruta y segmentos. Pasado cualquiera, misma salida que cmdn_oversize (ask; deny en un asiento desatendido), nunca allow silencioso.
CRED_W=0 CRED_MAX_W=1500 CRED_MAX_SEGS=3000
cred_overwork() {
  local d=ask r="Confirm: la orden tiene demasiados operandos o segmentos para analizarla dentro del timeout del guard (tope: $CRED_MAX_W operandos con nombre sensible, $CRED_MAX_SEGS segmentos), y un guard que se pasa de tiempo deja ejecutar la herramienta. Dividela en ordenes mas cortas o usa un fichero con la lista."
  cmdn_desatendido && { d=deny; r+=$CMDN_DESATENDIDO; }
  jq -n --arg r "$r" --arg d "$d" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  exit 0
}
# cred_path "$operando" dir: rc 0 si nombra material de credenciales; dir=1 si la orden recorre directorios (cp -r, tar, grep -r).
cred_path() {
  local v n i c b d k
  local -a comps
  # Atajo de coste: sin glob, llave ni un trozo de los nombres sensibles no puede casar (todo lo de abajo exige uno de estos trozos).
  # shellcheck disable=SC1083  # la { va literal dentro del corchete: es uno de los caracteres que se buscan
  case $1 in *.ssh*|*.aws*|*.gnupg*|*.env*|*.netrc*|*_netrc*|*.git-credentials*|*id_*|*hosts.yml*|*[*?[{]*) ;; *) return 1 ;; esac
  # Tope de trabajo: cada operando que llega aqui cuesta un analisis de ruta; pasado el tope el guard pide confirmacion (nunca allow en silencio).
  (( ++CRED_W <= CRED_MAX_W )) || cred_overwork
  BEX=(); brace_expand "$1"
  for v in "${BEX[@]}"; do
    cmdn_path_norm "$v"; v=$REPLY
    IFS=/ read -r -a comps <<<"$v"
    n=${#comps[@]}; (( n )) || continue
    b=${comps[n-1]}
    env_name "$b" && return 0
    case $b in
      id_rsa|id_dsa|id_ecdsa|id_ed25519|id_ecdsa_sk|id_ed25519_sk|.netrc|_netrc|.git-credentials) return 0 ;;
      hosts.yml) (( n >= 2 )) && [[ ${comps[n-2]} == gh ]] && return 0 ;;
    esac
    for (( i = 0; i < n; i++ )); do
      c=${comps[i]}; k=
      for d in .ssh .aws .gnupg; do
        [[ $c == "$d" ]] && { k=$d; continue; }
        [[ $c == *[*?[]* && ! $c =~ ^[*?]+$ ]] || continue
        # shellcheck disable=SC2053  # un componente con comodin (`.s*`) es justo un glob contra el nombre del directorio
        [[ $d == $c ]] && k=$d
      done
      [[ -n $k ]] || continue
      if (( i == n - 1 )); then (( ${2:-0} )) && return 0; continue; fi
      case $k in
        .ssh) case $b in config|known_hosts|known_hosts.old|authorized_keys|authorized_keys2|*.pub) ;; *) return 0 ;; esac ;;
        .aws) [[ $b == config ]] || return 0 ;;
        .gnupg) [[ $b == *.conf ]] || return 0 ;;
      esac
    done
  done
  return 1
}
cred_deny() {
  echo "BLOCKED: lectura de material de credenciales por Bash ($1)." >&2
  echo "Command: $COMMAND" >&2
  echo "Que hacer: comprueba la clave sin leerla (ssh-keygen -l -f para la huella, ls -l para el modo, la .pub para la publica); si de verdad tienes que leerla, ejecutalo tu con ! en la sesion." >&2
  exit 2
}
# cred_check "$operando" dir: lo deniega si es una credencial, tambien relativa al directorio de credenciales en el que se hizo `cd`.
cred_check() {
  if cred_path "$1" "${2:-0}"; then cred_deny "$1"; fi
  if [[ -n $CDCRED && $1 != /* && $1 != '~'* && $1 != '$'* ]] && cred_path "$CDCRED/$1" "${2:-0}"; then cred_deny "$1"; fi
}
cred_in() { [[ " $2 " == *" $1 "* ]]; }
CRED_N=0
# cred_seg depth: la orden ya troceada en T. Un `sh -c "..."` o `eval "..."` a la vista se vuelve a mirar (3 niveles); `xargs`, `find -exec`,
# `ssh host '...'`, un script, `python -c` o una variable quedan fuera (SECURITY.md).
cred_seg() {
  local depth=$1 c=${T[1]:-} n=${#T[@]} i a inner='' vals='' pat=0 dir=0 dest=0 first=0 tflag=0 given=0 skip=0 chk=0 dat=0
  local -a pos=() inn
  # `< fichero` hacia CUALQUIER orden (tr, nc, ssh, `done < f` de un while read, mapfile): el shell abre el fichero y se lo da por la entrada.
  # Solo echo, printf y test no leen su entrada (`[ a \< b ]` es una comparacion). `<<` y `<<<` son texto, no ficheros.
  # Se mira desde T[1]: `< f cat`, `<f cat` y `0<f cat` abren el fichero igual aunque la redireccion vaya delante de la orden.
  if [[ ${T[*]:1} == *'<'* ]]; then
    case $c in echo|printf|test|\[|\[\[) ;; *)
      for (( i = 1; i < n; i++ )); do
        a=${T[i]}
        case $a in '<<'*|'<(') ;; '<') cred_check "${T[i+1]:-}" 0 ;; '<'?*) cred_check "${a#<}" 0 ;;
          *) if [[ $a =~ ^[0-9]+\<$ ]]; then cred_check "${T[i+1]:-}" 0; elif [[ $a =~ ^[0-9]+\<([^\<\(\&].*)$ ]]; then cred_check "${BASH_REMATCH[1]}" 0; fi ;;
        esac
      done ;;
    esac
  fi
  # `busybox cat f` es `cat f`: se quita el envoltorio y se mira la orden de dentro.
  if [[ $c == busybox && -n ${T[2]:-} ]]; then T=("${T[0]}" "${T[@]:2}"); c=${T[1]}; n=${#T[@]}; fi
  # Atajo de coste: las ordenes mas frecuentes que ninguna clase de abajo mira ni se declaran ni se trocean.
  case $c in git|ls|cd|echo|printf|test|\[|\[\[|true|false|pwd|mkdir|rm|mv|touch|chmod|ssh|ssh-keygen|ssh-add|make|npm|pnpm|node|python|python3|pytest|docker|sleep|export|set) return 0 ;; esac
  case $c in
    sh|bash|zsh|dash|ksh)
      for (( i = 2; i < n; i++ )); do
        [[ ${T[i]} == -* && ${T[i]} != --* && ${T[i]} == *c* ]] && { inner=${T[i+1]:-}; [[ $inner == -- ]] && inner=${T[i+2]:-}; break; }
      done
      [[ -n $inner ]] || return 0 ;;
    eval) inner="${T[*]:2}"; [[ ${T[2]:-} == -- ]] && inner="${T[*]:3}"; [[ -n $inner ]] || return 0 ;;
    cat|tac|head|tail|less|more|most|bat|batcat|nl|xxd|od|hexdump|hd|base64|base32|basenc|strings|cut|sort|uniq|paste|diff|cmp|comm|dd|gzip|bzip2|xz|zstd|zcat|split|fold|rev|shuf|column|fmt|source|.) ;;
    openssl) vals='-out -keyout -passin -passout -pass -rand -CAfile -CApath -config -name' ;;
    awk|gawk|mawk) pat=1; vals='-v -F' ;;
    sed) pat=1 ;;
    jq|yq) pat=1; vals='--arg --argjson --slurpfile --rawfile' ;;
    grep|egrep|fgrep|rg|ag) pat=1; dir=1; vals='-A -B -C -m -d -D -g -t -T -M -j --max-count --glob --type --type-not --include --exclude --exclude-dir --context --after-context --before-context --max-depth --threads --color --colour' ;;
    cp|install) dest=1; dir=1; vals='-S -m -o -g --suffix --mode --owner --group' ;;
    scp) dest=1; dir=1; vals='-i -F -o -J -S -l -P -c' ;;
    rsync) dest=1; dir=1; vals='-e --rsh --rsync-path -M --exclude --include --exclude-from --include-from --port --bwlimit --log-file --password-file --partial-dir --temp-dir -T --files-from' ;;
    tar) dir=1; vals='-C -f --directory --file -X --exclude -T --files-from' ;;
    zip|7z|7za|rar) dir=1; first=1; vals='-x -P -i' ;;
    curl|wget) dat=1 ;;
    *) return 0 ;;
  esac
  if [[ -n $inner ]]; then
    # Cada texto anidado cuesta un awk: el tope de profundidad y el de textos protegen el timeout del guard (pasado, se ejecuta todo).
    [[ -n $CDCRED || $inner == *[.@/~]* ]] || return 0
    (( depth < 3 && ++CRED_N <= 100 )) || cred_deny "mas de 3 niveles de bash -c/eval, o mas de 100 textos"
    inn=("${CMDN_SEGS[@]}")
    if cmdn_parse "$inner"; then cred_segs $(( depth + 1 )); fi
    CMDN_SEGS=("${inn[@]}")
    return 0
  fi
  for (( i = 2; i < n; i++ )); do
    a=${T[i]}
    if (( skip )); then skip=0; continue; fi
    if (( chk )); then chk=0; cred_check "$a" 0; continue; fi
    # Camino corto (coste): un operando sin redireccion, sin `-` ni `=` va directo a la lista.
    if (( ! dat )) && [[ $a != -* && $a != *[\<\>=]* ]]; then pos+=("$a"); continue; fi
    # Redireccion: el destino de `>` no se lee; `<` fichero si, y el texto de `<<` y `<<<` no es un fichero.
    if [[ $a =~ ^[0-9\&]*\>+\|?$ ]]; then skip=1; continue; fi
    [[ $a =~ ^[0-9\&]*\> ]] && continue
    [[ $a == '<<'* ]] && continue
    a=${a#<}; [[ -n $a ]] || continue
    if (( dat )); then
      # curl y wget solo leen un fichero que se les nombra aparte: `-T f`, `--post-file f` o un valor `@f`, `name=@f`, `name=<f`.
      case $a in
        -T|--upload-file|--post-file|--body-file) chk=1; continue ;;
        --upload-file=*|--post-file=*|--body-file=*) cred_check "${a#*=}" 0; continue ;;
        -d|--data|--data-binary|--data-raw|--data-urlencode|--json|-F|--form|--form-string) given=1; continue ;;
      esac
      if (( given )) || [[ $a == @* || $a == -[dF]* ]]; then
        given=0
        [[ $a =~ ^(-[dF])?([^=@\<]*=)?[@\<](.+)$ ]] && cred_check "${BASH_REMATCH[3]}" 0
      fi
      continue
    fi
    case $a in
      --) continue ;;
      -t|--target-directory) tflag=1; skip=1; continue ;;
      -e|-f|--regexp|--file) if (( pat )); then given=1; [[ $a == -f || $a == --file ]] && chk=1 || skip=1; continue; fi ;;
      --file=*|--input=*|--pattern-file=*|--files-from=*|--from-file=*) cred_check "${a#*=}" 0; continue ;;
      --regexp=*) given=1; continue ;;
      of=*) continue ;;
      if=*) cred_check "${a#*=}" 0; continue ;;
    esac
    if [[ $a == -* ]]; then
      if cred_in "$a" "$vals"; then skip=1
      elif [[ $c == tar && $a =~ ^-[a-zA-Z]+f$ ]]; then skip=1
      elif (( pat )) && [[ $a =~ ^-[a-zA-Z]+e$ ]]; then given=1; skip=1
      fi
      continue
    fi
    pos+=("$a")
  done
  (( ${#pos[@]} )) || return 0
  (( pat && ! given && ! CRED_CONT || first && ! CRED_CONT )) && pos=("${pos[@]:1}")
  (( dest && ! tflag && ${#pos[@]} >= 2 )) && unset 'pos[-1]'
  for a in "${pos[@]}"; do cred_check "$a" "$dir"; done
  return 0
}
# cred_ctx: tras cmdn_fields. cmdnorm parte la orden en el `)` (o el acento grave) de una sustitucion: en `cat $(echo x) K` la K llega como
# una orden nueva, sin lector, y con el directorio quitado. Se lleva una pila con la orden de fuera de cada sustitucion abierta; el
# segmento que la cierra (T_SEP `)`, `))` o `` ` ``) se reescribe como operandos de esa orden (T_RAW es su primera palabra intacta).
CRED_STK=() CRED_PC='' CRED_CONT=0
cred_ctx() {
  local c
  CRED_CONT=0
  case $T_SEP in
    ')'*|'`'*)
      if [[ $T_SEP == ')'* || $T_KIND == P ]] && (( ${#CRED_STK[@]} )); then
        c=${CRED_STK[-1]}; unset 'CRED_STK[-1]'
        if [[ $T_SEP == ')' || $T_SEP == '))' || $T_SEP == '`' ]]; then
          T=("${T[0]}" "$c" "$T_RAW" "${T[@]:2}"); CRED_CONT=1
        fi
        CRED_PC=$c
        return
      fi ;;
  esac
  [[ $T_KIND == S && ( $T_SEP == '(' || $T_SEP == '((' || $T_SEP == '`' ) ]] && CRED_STK+=("$CRED_PC")
  CRED_PC=${T[1]:-}
}
cred_segs() {
  local seg stk=("${CRED_STK[@]}") pc=$CRED_PC
  local -a T segs
  segs=("${CMDN_SEGS[@]}")
  CRED_STK=() CRED_PC=''
  for seg in "${segs[@]}"; do
    cmdn_fields "$seg"
    cred_ctx
    cred_seg "$1"
  done
  CRED_STK=("${stk[@]}") CRED_PC=$pc
}

shopt -s nocasematch
(( ${#CMDN_SEGS[@]} <= CRED_MAX_SEGS )) || cred_overwork
# El directorio de trabajo de la sesion cuenta: tras un `cd ~/.ssh` en una orden anterior, `cat id_rsa` es la clave.
CDCRED=
CWD0=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[[ -n $CWD0 ]] && cred_path "$CWD0" 1 && CDCRED=$CWD0
for seg in "${CMDN_SEGS[@]}"; do
  cmdn_fields "$seg"
  cred_ctx
  cmdn_track_cd
  if [[ ${T[1]:-} == cd ]]; then
    CDCRED=
    [[ -n ${T[2]:-} ]] && cred_path "${T[2]}" 1 && CDCRED=${T[2]}
  fi
  cred_seg 0
  [[ ${T[1]:-} == git && ${T[2]:-} == add ]] || continue

  all=0; dot=0; dd=0
  for op in "${T[@]:3}"; do
    if (( ! dd )) && [[ $op == -- ]]; then dd=1; continue; fi
    if (( ! dd )) && [[ $op == -* ]]; then
      [[ $op == --all || ( $op != --* && $op == -*A* ) ]] && all=1
      continue
    fi
    # .env files (allow known-safe template variants: .env.example, .env.template, .env.sample, .env.dist)
    # `.env` solo cuenta seguido de fin de nombre o de un separador (`.`, `~`, `-`, `_`): `.environment.md` no es un
    # .env, pero `production.env.bak`, `config.env~` y `.env_local` si. Se mira cada componente de la ruta (`.env.d/x`)
    # y los globs y llaves, que los interpreta git (o la shell) y no pasan por un nombre literal.
    BEX=(); brace_expand "$op"; variants=("${BEX[@]}")
    for expanded in "${variants[@]}"; do
      IFS=/ read -r -a comps <<<"$expanded"
      for comp in "${comps[@]}"; do
        if env_name "$comp"; then
          echo "BLOCKED: Staging .env file — add to .gitignore instead." >&2
          echo "Que hacer: anade .env a .gitignore y haz git add de los ficheros concretos." >&2
          exit 2
        fi
      done
    done
    # Credential/key files by name. Con los tokens ya descomillados la extension se ancla al final del
    # operando: `bundle.p12/data` no casa, igual que antes. No hay un "secret" suelto: casaba dentro de
    # palabras ajenas como "secreto".
    if [[ $op =~ (\.pem|\.p12|\.pfx|\.jks|\.keystore|\.key|credentials\.json)$ ]]; then
      echo "BLOCKED: Staging potential credential file." >&2
      echo "Command: $COMMAND" >&2
      echo "Que hacer: no subas la clave al repo; guardala fuera de el, o ejecuta tu el git add con ! en la sesion si es una clave de prueba." >&2
      exit 2
    fi
    [[ $op == . || $op == ./ || $op == '*' ]] && dot=1
  done

  # git add -A / --all / . only when .env is NOT gitignored
  if (( all || dot )); then
    # Del juicio a git solo pasa el directorio de cada `-C` (un dato). Reenviarle el resto de las opciones globales de la orden juzgada
    # (`-c core.fsmonitor='cmd'`, `--exec-path`...) hacia que git EJECUTARA `cmd` mientras el hook juzga, antes de que la orden se lance.
    IFS=$CMDN_GS read -r -a gopts <<<"${T[0]}"
    gc=()
    for (( gi = 0; gi < ${#gopts[@]}; gi++ )); do
      case ${gopts[gi]} in
        -C) gc+=(-C "${gopts[gi+1]:-.}"); (( gi++ )) ;;
        -c|--git-dir|--work-tree|--namespace|--super-prefix|--config-env|--attr-source) (( gi++ )) ;;
      esac
    done
    # git del hook: sin la config de sistema ni la global, sin heredar GIT_CONFIG_COUNT/PARAMETERS, y con fsmonitor y hooks apagados por
    # linea de ordenes (que pisa tambien el `.git/config` del propio repo, donde `core.fsmonitor` tambien ejecuta una orden).
    safe_git() {
      env -u GIT_CONFIG_COUNT -u GIT_CONFIG_PARAMETERS GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
        git -c core.fsmonitor=false -c core.hooksPath=/dev/null ${CMDN_CWD:+-C "$CMDN_CWD"} "${gc[@]}" "$@"
    }
    top=$(safe_git rev-parse --show-toplevel 2>/dev/null) || top=""
    if [[ -n $top ]]; then
      base=$top
      (( all )) || base="$top/$(safe_git rev-parse --show-prefix 2>/dev/null)"
      if [ -f "$base/.env" ] && ! safe_git check-ignore -q "$base/.env" 2>/dev/null; then
        echo "BLOCKED: git add -A/. with untracked .env present — add to .gitignore first." >&2
        echo "Que hacer: anade .env a .gitignore, o haz git add de ficheros concretos en vez de -A o ." >&2
        exit 2
      fi
    fi
  fi
done

exit 0
