#!/bin/bash
# shellcheck disable=SC2015  # «cond && pass=$((pass+1)) || bad»: la rama del medio es una asignacion y nunca falla.
# test_guards_mensajes.sh — todo bloqueo de todo guard acaba con la salida que funciona: la ultima parte del mensaje
# es «Que hacer: ...» (que cambiar en el comando o quien lo ejecuta). Un bloqueo sin salida es una pared: la
# sesion no sabe que hacer y acaba pidiendo ampliar la allowlist. Cubre los cinco guards de Bash, Sentinel y
# write-guard.py, tanto los bloqueos de contenido (fixtures/guards-mensajes.tsv) como los fail-closed
# (sin jq, JSON roto, escritura con secreto).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
H="${MENSAJES_HOOKS_DIR:-$KIT/claude/hooks}"
SEN="${MENSAJES_SENTINEL:-$KIT/sentinel/sentinel_preflight.py}"
PY="${PYTHON3:-python3}"
pass=0; fail=0

T=$(mktemp -d); trap 'rm -rf -- "$T"' EXIT
mkdir -p "$T/home/.claude" "$T/repo" "$T/nojq"
cp "$KIT/claude/sentinel-allowlist.json" "$T/home/.claude/"
(
  cd "$T/repo" && git init -q -b feat/demo \
    && git config user.email t@example.com && git config user.name t \
    && printf 'x\n' > README.md && git add README.md && git commit -qm init \
    && printf 'KEY=changeme\n' > .env
) >/dev/null 2>&1
AWS="AKI""A""Q3WJ5ZK7P2M9X4TB"

# Un PATH sin jq: solo las utilidades que los guards usan antes de comprobar jq.
for b in bash env dirname cat mkdir date git awk sed grep tr head tail printf python3 uname; do
  p=$(command -v "$b") && ln -sf "$p" "$T/nojq/$b"
done

# mensaje <rc> <stdout> <stderr> -> el texto que ve la sesion, o vacio si el hook no bloquea
mensaje() {
  local rc=$1 out=$2 err=$3 r
  if (( rc == 2 )); then printf '%s' "$err"; return; fi
  r=$(jq -r 'select(.hookSpecificOutput.permissionDecision == "deny") | .hookSpecificOutput.permissionDecisionReason' <<<"$out" 2>/dev/null)
  printf '%s' "$r"
}

# acaba_con_salida <texto>: hay un «Que hacer:» y despues de el no vuelve a empezar un bloqueo
acaba_con_salida() {
  local m=$1 tail
  [[ $m == *"Que hacer:"* ]] || return 1
  tail=${m##*Que hacer:}
  [[ $tail != *BLOCKED* && $tail != *"Command:"* ]]
}

comprobar() { # etiqueta rc stdout stderr
  local m
  m=$(mensaje "$2" "$3" "$4")
  if [[ -z $m ]]; then
    fail=$((fail+1)); echo "FAIL: [$1] no bloqueo (rc=$2): nada que comprobar"
  elif acaba_con_salida "$m"; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); echo "FAIL: [$1] el mensaje no acaba con «Que hacer:» :: ${m: -160}"
  fi
}

payload() { jq -nc --arg c "$1" --arg cwd "$T/repo" '{session_id:"t",transcript_path:"/dev/null",cwd:$cwd,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'; }

run_hook() { # guard payload [PATH]
  local g=$1 pl=$2 pth=${3:-$PATH} out err rc
  if [[ $g == sentinel ]]; then
    out=$(cd "$T/repo" && HOME="$T/home" PATH=$pth "$PY" -I -S "$SEN" <<<"$pl" 2>"$T/err"); rc=$?
  else
    out=$(cd "$T/repo" && HOME="$T/home" PATH=$pth CC_BLOCK_LOG="$T/blocked.log" bash "$H/$g.sh" <<<"$pl" 2>"$T/err"); rc=$?
  fi
  err=$(<"$T/err")
  R_RC=$rc; R_OUT=$out; R_ERR=$err
}

# 1. bloqueos de contenido
n=0
while IFS=$'\t' read -r g cmd; do
  [[ -z $g || $g == '#'* ]] && continue
  cmd=${cmd//@@AWSKEY@@/$AWS}
  n=$((n+1))
  run_hook "$g" "$(payload "$cmd")"
  comprobar "$g :: ${cmd:0:50}" "$R_RC" "$R_OUT" "$R_ERR"
done < "$HERE/fixtures/guards-mensajes.tsv"
echo "bloqueos de contenido comprobados: $n"

# 2. fail-closed: sin jq y con JSON roto, los cinco guards de Bash
for g in block-dangerous-commands branch-guard destructive-guard secret-guard bash-write-guard; do
  run_hook "$g" "$(payload 'echo hola > x.txt')" "$T/nojq"
  comprobar "$g sin jq" "$R_RC" "$R_OUT" "$R_ERR"
  run_hook "$g" 'esto no es json {{{ >' 
  # bash-write-guard y block-dangerous leen el payload sin parsearlo primero cuando no hay nada que escribir
  m=$(mensaje "$R_RC" "$R_OUT" "$R_ERR")
  if [[ -z $m ]]; then pass=$((pass+1)); else comprobar "$g con JSON roto" "$R_RC" "$R_OUT" "$R_ERR"; fi
done
run_hook sentinel 'esto no es json {{{'
comprobar "sentinel con JSON roto" "$R_RC" "$R_OUT" "$R_ERR"

# 3. write-guard.py: escribir un secreto con la herramienta Write
wp=$(jq -nc --arg f "$T/repo/cfg.txt" --arg c "token = $AWS" '{session_id:"t",transcript_path:"/dev/null",cwd:"/tmp",hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:$f,content:$c}}')
out=$(HOME="$T/home" "$PY" -I -S "$H/write-guard.py" <<<"$wp" 2>"$T/err"); rc=$?
comprobar "write-guard secreto" "$rc" "$out" "$(<"$T/err")"

echo "PASS=$pass FAIL=$fail"; [ $fail -eq 0 ]
