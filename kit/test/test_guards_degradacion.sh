#!/bin/bash
# shellcheck disable=SC2015  # «cond && pass=$((pass+1)) || bad»: la rama del medio es una asignacion y nunca falla.
# test_guards_degradacion.sh — la tabla de fallos de SECURITY.md y docs/05-security.md, ejecutada: que hace cada
# guard cuando le falta jq, le falta python3, le falta su script o su libreria, recibe JSON roto, se cae o recibe un
# comando mas grande de lo que puede analizar. Lo decidido es lo escrito: si esta suite y la tabla discrepan, manda
# esta suite y hay que corregir la tabla.
#
#   fallo                  guards bash (5)            Sentinel / write-guard
#   sin jq                 bloquean (exit 2/deny)     no usan jq: siguen funcionando
#   sin python3            no lo usan                 NO bloquean; avisan UNA vez por sesion (additionalContext)
#   falta su script        (falta la lib: exit 2)     exit 2
#   JSON roto              bloquean                   exit 2
#   caida interna          exit 2 (falta la lib)      exit 2
#   comando enorme         preguntan o bloquean       preguntan o bloquean
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
H="${DEGRADACION_HOOKS_DIR:-$KIT/claude/hooks}"
SEN="${DEGRADACION_SENTINEL:-$KIT/sentinel/sentinel_preflight.py}"
W="$H/optional-hook.sh"
PY="${PYTHON3:-python3}"
BASH_GUARDS="block-dangerous-commands branch-guard destructive-guard secret-guard bash-write-guard"
pass=0; fail=0
ok() { pass=$((pass+1)); }
ko() { fail=$((fail+1)); echo "FAIL: $1"; }

T=$(mktemp -d); trap 'rm -rf -- "$T"' EXIT
mkdir -p "$T/home/.claude" "$T/repo" "$T/nojq" "$T/warn" "$T/sinlib"
cp "$KIT/claude/sentinel-allowlist.json" "$T/home/.claude/"
(cd "$T/repo" && git init -q -b feat/demo && git config user.email t@example.com && git config user.name t \
  && printf 'x\n' > README.md && git add README.md && git commit -qm init) >/dev/null 2>&1
for b in bash env dirname cat mkdir date git awk sed grep tr head tail printf python3 uname id; do
  p=$(command -v "$b") && ln -sf "$p" "$T/nojq/$b"
done

payload() { jq -nc --arg c "$1" --arg cwd "$T/repo" --arg sid "${2:-s1}" '{session_id:$sid,transcript_path:"/dev/null",cwd:$cwd,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'; }

# bloquea <rc> <stdout>: exit 2 o deny JSON
bloquea() { [[ $1 == 2 ]] || [[ $2 == *'"permissionDecision": "deny"'* || $2 == *'"permissionDecision":"deny"'* ]]; }
pregunta_o_bloquea() { bloquea "$1" "$2" || [[ $2 == *'"permissionDecision": "ask"'* || $2 == *'"permissionDecision":"ask"'* ]]; }

run_guard() { # guard stdin [PATH] [directorio de hooks]
  local g=$1 in=$2 pth=${3:-$PATH} dir=${4:-$H}
  if [[ $g == sentinel ]]; then
    R_OUT=$(cd "$T/repo" && HOME="$T/home" PATH=$pth "$PY" -I -S "$SEN" <<<"$in" 2>"$T/err"); R_RC=$?
  else
    R_OUT=$(cd "$T/repo" && HOME="$T/home" PATH=$pth CC_BLOCK_LOG="$T/blocked.log" bash "$dir/$g.sh" <<<"$in" 2>"$T/err"); R_RC=$?
  fi
}

# 1. sin jq: los cinco guards de Bash bloquean (un guard que no puede leer el comando no deja pasar a ciegas)
for g in $BASH_GUARDS; do
  run_guard "$g" "$(payload 'echo hola > x.txt')" "$T/nojq"
  if bloquea "$R_RC" "$R_OUT"; then ok; else ko "$g sin jq deberia bloquear (rc=$R_RC)"; fi
done

# 2. JSON roto: bloquean los guards que leen el payload; bash-write-guard solo mira escrituras (prefiltro por texto)
for g in block-dangerous-commands branch-guard destructive-guard secret-guard bash-write-guard; do
  run_guard "$g" '{"tool_input":{"command":"echo x > f.txt"'
  if bloquea "$R_RC" "$R_OUT"; then ok; else ko "$g con JSON roto deberia bloquear (rc=$R_RC)"; fi
done
run_guard sentinel 'esto no es json {{{'
if (( R_RC == 2 )); then ok; else ko "sentinel con JSON roto deberia salir 2 (rc=$R_RC)"; fi
R_OUT=$(HOME="$T/home" "$PY" -I -S "$H/write-guard.py" <<<'esto no es json' 2>/dev/null); R_RC=$?
if (( R_RC == 2 )); then ok; else ko "write-guard con JSON roto deberia salir 2 (rc=$R_RC)"; fi

# 3. caida interna: sin su libreria los guards bash salen 2; write-guard sin su tabla de patrones tambien
for g in block-dangerous-commands branch-guard destructive-guard secret-guard; do
  mkdir -p "$T/sinlib/$g"; cp "$H/$g.sh" "$T/sinlib/$g/"
  run_guard "$g" "$(payload 'git status')" "$PATH" "$T/sinlib/$g"
  if (( R_RC == 2 )) || bloquea "$R_RC" "$R_OUT"; then ok; else ko "$g sin lib/cmdnorm.sh deberia bloquear (rc=$R_RC)"; fi
done
mkdir -p "$T/wg"; cp "$H/write-guard.py" "$T/wg/"
wp=$(jq -nc --arg f "$T/repo/a.txt" '{session_id:"t",transcript_path:"/dev/null",cwd:"/tmp",hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:$f,content:"hola"}}')
HOME="$T/home" "$PY" -I -S "$T/wg/write-guard.py" <<<"$wp" >/dev/null 2>&1; rc=$?
if (( rc == 2 )); then ok; else ko "write-guard sin lib/secret-patterns deberia salir 2 (rc=$rc)"; fi

# 4. sin python3: Sentinel y write-guard no bloquean pero avisan UNA vez por sesion
for spec in "sentinel_preflight.py:Sentinel" "write-guard.py:write-guard"; do
  s=${spec%%:*}; k=${spec##*:}
  out1=$(echo '{"session_id":"sesA"}' | CC_WARN_DIR="$T/warn" PYTHON_HOOK_BIN=/no/existe/python3 "$W" --python "/x/$s" 2>/dev/null); rc1=$?
  out2=$(echo '{"session_id":"sesA"}' | CC_WARN_DIR="$T/warn" PYTHON_HOOK_BIN=/no/existe/python3 "$W" --python "/x/$s" 2>/dev/null); rc2=$?
  out3=$(echo '{"session_id":"sesB"}' | CC_WARN_DIR="$T/warn" PYTHON_HOOK_BIN=/no/existe/python3 "$W" --python "/x/$s" 2>/dev/null)
  (( rc1 == 0 && rc2 == 0 )) && ok || ko "$k sin python3 no debe bloquear (rc=$rc1/$rc2)"
  [[ $out1 == *additionalContext*"$k"*"Que hacer:"* ]] && ok || ko "$k sin python3 debe avisar con additionalContext y Que hacer (salio: ${out1:0:100})"
  [[ -z $out2 ]] && ok || ko "$k sin python3 debe avisar UNA sola vez por sesion (2.a vez: ${out2:0:80})"
  [[ $out3 == *additionalContext* ]] && ok || ko "$k sin python3 debe avisar tambien en otra sesion"
done
out=$(echo '{"session_id":"sesC"}' | CC_WARN_DIR="$T/warn" PYTHON_HOOK_BIN=/no/existe/python3 "$W" --python /x/otro-hook.py 2>&1)
[[ -z $out ]] && ok || ko "un hook opcional sin python3 sigue en silencio (salio: ${out:0:80})"

# 5. falta el script del guard (con python3 presente): exit 2, como un guard que dice no
for s in sentinel_preflight.py write-guard.py; do
  out=$(echo '{}' | "$W" --python "/no/existe/$s" 2>&1); rc=$?
  (( rc == 2 )) && ok || ko "$s ausente deberia salir 2 (rc=$rc)"
  [[ $out == *"Que hacer:"* ]] && ok || ko "$s ausente debe decir que hacer (salio: ${out:0:80})"
done

# 6. comando mas grande de lo que se puede analizar: se pregunta o se bloquea, nunca se deja pasar
# (jq no admite un argumento de 200 KB: el comando va por fichero)
{ printf 'echo '; head -c 200000 /dev/zero | tr '\0' 'a'; } > "$T/big.txt"
jq -Rs --arg cwd "$T/repo" '{session_id:"s1",transcript_path:"/dev/null",cwd:$cwd,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:.}}' < "$T/big.txt" > "$T/big.json"
for g in block-dangerous-commands sentinel; do
  run_guard "$g" "$(<"$T/big.json")"
  if pregunta_o_bloquea "$R_RC" "$R_OUT"; then ok; else ko "$g con un comando de 200 KB deberia preguntar o bloquear (rc=$R_RC)"; fi
done

echo "PASS=$pass FAIL=$fail"; [ $fail -eq 0 ]
