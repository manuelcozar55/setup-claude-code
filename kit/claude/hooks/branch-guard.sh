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

for seg in "${CMDN_SEGS[@]}"; do
  cmdn_fields "$seg"
  cmdn_track_cd
  [[ ${T[1]:-} == git && ${T[2]:-} == push ]] || continue

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

exit 0
