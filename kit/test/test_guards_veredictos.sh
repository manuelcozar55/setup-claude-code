#!/bin/bash
# shellcheck disable=SC2015  # «cond && pass=$((pass+1)) || bad»: la rama del medio es una asignacion y nunca falla.
# test_guards_veredictos.sh — los cuatro corpus de la auditoria A (2026-11-12) como suite ejecutable:
# legitimos (34), peligrosos (25), bypasses (12), extra (18) y prosa (15: formas que parecen prosa y no lo son). Cada caso pasa por la CADENA completa de
# PreToolUse de Bash (los cinco guards mas Sentinel) y el veredicto de la cadena es el peor de los seis:
# BLOCK (deny JSON o exit 2) > ASK > ALLOW. Cada fila lleva su veredicto esperado en `exp`:
#   ALLOW, BLOCK, ASK, o `BLOCK|ASK` cuando valen las dos salidas seguras (frena o pide confirmacion).
# Una fila con `limite` es un limite CONOCIDO y documentado (SECURITY.md): el hook no puede verlo.
#
# Los comandos peligrosos NUNCA se ejecutan: solo se dan como texto a los guards. Los literales de
# credenciales van como marcadores (@@AWSKEY@@, @@GHPAT@@) y se montan aqui por concatenacion, para que
# scan-secrets.sh no vea un secreto en el fixture.
#
# VEREDICTOS_HOOKS_DIR / VEREDICTOS_SENTINEL permiten apuntar la suite a otra copia de los guards
# (test_guards_falsifiability.sh los muta). Con VEREDICTOS_TABLA=1 imprime la tabla por corpus.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
H="${VEREDICTOS_HOOKS_DIR:-$KIT/claude/hooks}"
SEN="${VEREDICTOS_SENTINEL:-$KIT/sentinel/sentinel_preflight.py}"
PY="${PYTHON3:-python3}"
FIX="$HERE/fixtures"
pass=0; fail=0

T=$(mktemp -d); trap 'rm -rf -- "$T"' EXIT
mkdir -p "$T/home/.claude" "$T/repo"
cp "$KIT/claude/sentinel-allowlist.json" "$T/home/.claude/"
(
  cd "$T/repo" && git init -q -b feat/demo \
    && git config user.email t@example.com && git config user.name t \
    && mkdir -p docs src build node_modules config \
    && printf 'x\n' > README.md && printf 'KEY=changeme\n' > .env.example \
    && printf '.env\n' > .gitignore && git add README.md .env.example .gitignore \
    && git commit -qm init
) >/dev/null 2>&1

AWS="AKI""A""Q3WJ5ZK7P2M9X4TB"
GHP="gh""p_$(printf 'a%.0s' {1..36})"

# code <rc> <salida> -> A | D | K | X2 | E<n>
code() {
  local rc=$1 out=$2
  (( rc == 2 )) && { echo X2; return; }
  (( rc != 0 )) && { echo "E$rc"; return; }
  case $out in
    *'"permissionDecision": "deny"'*|*'"permissionDecision":"deny"'*) echo D ;;
    *'"permissionDecision": "ask"'*|*'"permissionDecision":"ask"'*) echo K ;;
    *) echo A ;;
  esac
}

# veredicto <comando> -> BLOCK | ASK | ALLOW, y VERDICT_ROW con los seis codigos
veredicto() {
  local payload out rc c worst=ALLOW g
  payload=$(jq -nc --arg c "$1" --arg cwd "$T/repo" '{session_id:"t",transcript_path:"/dev/null",cwd:$cwd,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}')
  VERDICT_ROW=""
  for g in block-dangerous-commands branch-guard destructive-guard secret-guard bash-write-guard sentinel; do
    if [[ $g == sentinel ]]; then
      out=$(cd "$T/repo" && HOME="$T/home" "$PY" -I -S "$SEN" <<<"$payload" 2>/dev/null); rc=$?
    else
      out=$(cd "$T/repo" && HOME="$T/home" CC_BLOCK_LOG="$T/blocked.log" bash "$H/$g.sh" <<<"$payload" 2>/dev/null); rc=$?
    fi
    c=$(code "$rc" "$out")
    VERDICT_ROW+="${g:0:3}=$c "
    case $c in
      D|X2|E*) worst=BLOCK ;;
      K) [[ $worst == BLOCK ]] || worst=ASK ;;
    esac
  done
  VERDICT=$worst
}

run_corpus() { # nombre fichero
  local name=$1 file=$2 total=0 ok=0 line id cmd exp lim
  while IFS= read -r line; do
    [[ -z $line ]] && continue
    id=$(jq -r .id <<<"$line"); cmd=$(jq -r .cmd <<<"$line"); exp=$(jq -r .exp <<<"$line")
    cmd=${cmd//@@AWSKEY@@/$AWS}; cmd=${cmd//@@GHPAT@@/$GHP}
    total=$((total+1))
    veredicto "$cmd"
    if [[ "|$exp|" == *"|$VERDICT|"* ]]; then
      ok=$((ok+1)); pass=$((pass+1))
    else
      fail=$((fail+1)); echo "FAIL: [$name $id] esperado $exp, obtenido $VERDICT ($VERDICT_ROW) :: ${cmd:0:90}"
    fi
    [[ ${VEREDICTOS_TABLA:-0} == 1 ]] && printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$id" "$exp" "$VERDICT" "$VERDICT_ROW"
  done < "$file"
  lim=$(jq -r 'select(.limite != null) | .id' "$file" | wc -l)
  echo "corpus $name: $ok/$total con el veredicto esperado ($lim limites documentados)"
}

run_corpus legit  "$FIX/guards-legit.jsonl"
run_corpus danger "$FIX/guards-danger.jsonl"
run_corpus bypass "$FIX/guards-bypass.jsonl"
run_corpus extra  "$FIX/guards-extra.jsonl"
run_corpus prosa  "$FIX/guards-prosa.jsonl"

echo "PASS=$pass FAIL=$fail"; [ $fail -eq 0 ]
