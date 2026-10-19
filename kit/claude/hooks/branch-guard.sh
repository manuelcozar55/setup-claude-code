#!/bin/bash
# branch-guard.sh — Blocks git push to protected branches
# Source: yurukusa/claude-code-hooks (MIT)
# Protocol: exit 2 = block with stderr reason

INPUT=$(cat)

# Fail-closed: sin jq no hay decision posible, y permitir en silencio apagaba toda la
# Capa 1 sin un mensaje. Denegar puede frenar trabajo legitimo, y por eso install.sh
# exige jq en una puerta de dependencia: llegar aqui sin el es una instalacion incompleta.
if ! command -v jq >/dev/null 2>&1; then
  echo "BLOCKED (fail-closed): falta jq en el PATH, asi que branch-guard no puede leer el comando." >&2
  echo "Instala jq (apt install jq) y reintenta." >&2
  exit 2
fi
if ! COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); then
  echo "BLOCKED (fail-closed): el payload de PreToolUse no es JSON parseable; branch-guard no puede leer el comando." >&2
  exit 2
fi
[[ -z "$COMMAND" ]] && exit 0

# El destino real del push se resuelve sobre el comando normalizado (lib/cmdnorm.sh): tokens
# descomillados, sin prefijos (sudo, env, timeout...) ni opciones globales de git. Antes se buscaba el
# nombre de la rama como SUBCADENA del texto, y eso fallaba en las dos direcciones: `git push origin
# "main"`, `git push` a secas y `git push origin HEAD` con main activa pasaban, y `main-menu` o un
# `echo main` posterior daban falso positivo. Ahora: refspec implicito o HEAD -> rama actual
# (`git symbolic-ref`, en el cwd del hook o en el que fijen `git -C` / `cd`), y igualdad de token.
# Fuera de un repo, o con HEAD suelto, la rama actual no existe y se conserva el comportamiento
# anterior: solo cuenta lo que el comando nombra.
# shellcheck source=SCRIPTDIR/lib/cmdnorm.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/cmdnorm.sh" || { echo "BLOCKED (fail-closed): falta lib/cmdnorm.sh; reinstala el kit." >&2; exit 2; }
cmdn_oversize "$COMMAND" && exit 0
if ! cmdn_parse "$COMMAND"; then
  echo "BLOCKED (fail-closed): awk no pudo normalizar el comando; branch-guard no puede evaluarlo." >&2
  exit 2
fi

PROTECTED="${CC_PROTECT_BRANCHES:-main:master:production}"
IFS=':' read -ra BRANCHES <<< "$PROTECTED"

is_protected() {
  local b
  for b in "${BRANCHES[@]}"; do [[ $1 == "$b" ]] && return 0; done
  return 1
}

block() {
  echo "BLOCKED: Attempted push to protected branch '$1'." >&2
  echo "Command: $COMMAND" >&2
  echo "Push to a feature/staging branch first, then open a PR." >&2
  exit 2
}

# Un segmento cuyo ejecutable no es git puede llevar un push dentro: `bash -c "git push ..."`, `eval`,
# `ssh host git push ...`, `xargs git push ...`, `find -exec git push ...`. El guard de texto de 3576d87
# los veia y la normalizacion los dejo pasar; ahora la cadena interior (un argumento con git, o los
# argumentos desde el token `git`) se vuelve a normalizar y se analiza igual, hasta 3 niveles. Los
# comandos que solo muestran texto (echo, grep...) no cuentan: `echo "git push origin main"` es prosa.
# La expansion de variables sigue fuera de alcance (docs/05-security.md).
# Cada cadena anidada cuesta un awk (~3 ms): sin tope, 12 KB de `x git;` eran 7 s de CPU y 128 KB pasaban
# de 20 s. Este guard corre con timeout 10 y sin envoltorio, y un hook que pasa de su timeout deja
# ejecutar el comando: fallaba en abierto. Solo se miran los segmentos con push (y los `cd`, que fijan el
# repo), solo se vuelve a normalizar la cadena que lleva push, y pasadas 16 se bloquea: fallar cerrado.
NEST=0
scan() {
  local depth=$1 seg a i inner cwd0 first ref dst t cur rc
  local skip dd tags repo
  local -a T segs ops targets gopts
  segs=("${CMDN_SEGS[@]}")
  for seg in "${segs[@]}"; do
  [[ $seg == *push* || $seg == "$CMDN_US"cd"$CMDN_US"* ]] || continue
  cmdn_fields "$seg"
  cmdn_track_cd
  if [[ ${T[1]:-} != git ]]; then
    [[ $seg == *git* && $depth -lt 3 ]] || continue
    case ${T[1]:-} in echo|printf|grep|egrep|fgrep|rg|sed|awk|cat|man|type|which|less|head|tail|test|'[') continue ;; esac
    for (( i = 2; i < ${#T[@]}; i++ )); do
      a=${T[i]}
      [[ $a == *git* ]] || continue
      inner=$a
      [[ $a == git || $a == */git ]] && printf -v inner '%s ' "${T[@]:i}"
      [[ $inner == *push* ]] || continue
      (( ++NEST > 16 )) && return 2
      cwd0=$CMDN_CWD; rc=0
      cmdn_parse "$inner" && { CMDN_CWD=$cwd0; scan $(( depth + 1 )); rc=$?; }
      CMDN_CWD=$cwd0
      (( rc == 2 )) && return 2
    done
    continue
  fi
  [[ ${T[2]:-} == push ]] || continue

  ops=(); skip=0; dd=0; tags=0; repo=0
  for a in "${T[@]:3}"; do
    if (( skip )); then skip=0; continue; fi
    if (( ! dd )) && [[ $a == -- ]]; then dd=1; continue; fi
    if (( ! dd )) && [[ $a == -* ]]; then
      case $a in
        --repo) skip=1; repo=1 ;;
        --repo=*) repo=1 ;;
        -o|--push-option|--receive-pack|--exec) skip=1 ;;
        --tags) tags=1 ;;
        --all|--branches|--mirror) block "$a (empuja todas las ramas, las protegidas incluidas)" ;;
      esac
      continue
    fi
    [[ $a =~ ^[0-9]*[\<\>] || $a == '&>'* ]] && continue
    ops+=("$a")
  done

  IFS=$CMDN_GS read -r -a gopts <<<"${T[0]}"
  cur=$(git ${CMDN_CWD:+-C "$CMDN_CWD"} "${gopts[@]}" symbolic-ref --short -q HEAD 2>/dev/null)

  # Con --repo el remoto ya viene dado y todos los posicionales son refspecs.
  first=1; (( repo )) && first=0
  targets=()
  if (( ${#ops[@]} <= first )); then
    (( tags )) || targets+=("$cur")
  else
    for ref in "${ops[@]:first}"; do
      ref=${ref#+}
      dst=$ref
      [[ $ref == *:* ]] && dst=${ref##*:}
      [[ $dst == HEAD ]] && dst=$cur
      targets+=("${dst#refs/heads/}")
    done
  fi
  for t in "${targets[@]}"; do
    [[ -n $t ]] && is_protected "$t" && block "$t"
  done
  done
  return 0
}

scan 0; rc=$?
if (( rc == 2 )); then
  echo "BLOCKED: mas de 16 comandos anidados (bash -c, ssh, xargs...) con git push: no caben en el timeout del guard; dividelo en comandos cortos." >&2
  exit 2
fi
exit 0
