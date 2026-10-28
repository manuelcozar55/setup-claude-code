#!/bin/bash
# secret-guard.sh — Blocks git add of .env, credentials, private keys
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
  exit 2
fi
if ! COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); then
  echo "BLOCKED (fail-closed): el payload de PreToolUse no es JSON parseable; secret-guard no puede leer el comando." >&2
  exit 2
fi
[[ -z "$COMMAND" ]] && exit 0

# Se decide por los OPERANDOS de cada `git add`, sobre el comando normalizado (lib/cmdnorm.sh): tokens
# descomillados, sin prefijos (sudo, env...) ni opciones globales de git. Antes eran regex sobre el texto
# entero, y fallaban en tres sitios: `git -C . add .env` no llegaba al filtro, la exencion del fichero
# de ejemplo se evaluaba sobre TODO el comando (`git add .env.example .env` pasaba) y `--all` no existia.
# shellcheck source=SCRIPTDIR/lib/cmdnorm.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/cmdnorm.sh" || { echo "BLOCKED (fail-closed): falta lib/cmdnorm.sh; reinstala el kit." >&2; exit 2; }
cmdn_oversize "$COMMAND" && exit 0
if ! cmdn_parse "$COMMAND"; then
  echo "BLOCKED (fail-closed): awk no pudo normalizar el comando; secret-guard no puede evaluarlo." >&2
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
  [[ $n =~ \.env\.(example|template|sample|dist)$ ]] && return 1
  [[ $n =~ (\.env($|[.~_-])|\.envrc) ]]
}
# Expande las llaves `{a,b}` de un operando (una por pasada), una variante por linea.
brace_expand() {
  local w=$1 pre alt post a
  if [[ $w =~ ^([^{]*)\{([^{}]*,[^{}]*)\}(.*)$ ]]; then
    pre=${BASH_REMATCH[1]} alt=${BASH_REMATCH[2]} post=${BASH_REMATCH[3]}
    alt+=,
    while [[ -n $alt ]]; do
      a=${alt%%,*}; alt=${alt#*,}
      brace_expand "$pre$a$post"
    done
  else
    printf '%s\n' "$w"
  fi
}

shopt -s nocasematch
for seg in "${CMDN_SEGS[@]}"; do
  cmdn_fields "$seg"
  cmdn_track_cd
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
    mapfile -t variants < <(brace_expand "$op")
    for expanded in "${variants[@]}"; do
      IFS=/ read -r -a comps <<<"$expanded"
      for comp in "${comps[@]}"; do
        if env_name "$comp"; then
          echo "BLOCKED: Staging .env file — add to .gitignore instead." >&2
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
      exit 2
    fi
    [[ $op == . || $op == ./ || $op == '*' ]] && dot=1
  done

  # git add -A / --all / . only when .env is NOT gitignored
  if (( all || dot )); then
    IFS=$CMDN_GS read -r -a gopts <<<"${T[0]}"
    top=$(git ${CMDN_CWD:+-C "$CMDN_CWD"} "${gopts[@]}" rev-parse --show-toplevel 2>/dev/null) || top=""
    if [[ -n $top ]]; then
      base=$top
      (( all )) || base="$top/$(git ${CMDN_CWD:+-C "$CMDN_CWD"} "${gopts[@]}" rev-parse --show-prefix 2>/dev/null)"
      if [ -f "$base/.env" ] && ! git ${CMDN_CWD:+-C "$CMDN_CWD"} "${gopts[@]}" check-ignore -q "$base/.env" 2>/dev/null; then
        echo "BLOCKED: git add -A/. with untracked .env present — add to .gitignore first." >&2
        exit 2
      fi
    fi
  fi
done

exit 0
