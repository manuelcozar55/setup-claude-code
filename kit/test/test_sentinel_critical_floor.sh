#!/bin/bash
# test_sentinel_critical_floor.sh — un veredicto CRITICAL de Sentinel no lo puede
# levantar la allowlist (ni del usuario ni la que un repo clonado trae en
# $CWD/.security/sentinel-allowlist.json).
#
# Por que existe (F-13/RT-20, boundary del todo 17): sentinel_preflight.py ya tiene
# un suelo para ALWAYS_DENY_PATHS y para dominios known-malicious, pero
# check_dangerous_commands consultaba la allowlist `commands` ANTES de casar el
# patron critico, asi que meter una reverse-shell en la allowlist -- algo que un
# repo clonado puede hacer solo, load_user_allowlist() prefiere el CWD -- convertia
# un veredicto CRITICAL en allow. Un CRITICAL es, por definicion, un hallazgo que
# ningun falso positivo justifica eximir: si necesita supresion por allowlist, no
# es CRITICAL, es otra severidad. Esta suite lo falsifica.
#
# PYTHON3 es sobreescribible; corre contra los ficheros del propio kit.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
PY="${PYTHON3:-python3}"
SEN="$KIT/sentinel/sentinel_preflight.py"
pass=0; fail=0

# Construye los comandos peligrosos en runtime para no disparar los guards de
# Bash del entorno que ejecuta esta suite. Se elige mkfs. (patron CRITICAL
# (?i)mkfs\.) porque su UNICO hit es el patron peligroso: sin IP ni segundo
# hallazgo que enmascare una supresion. Asi, si la allowlist lo levanta, el
# veredicto cae a allow limpio y la asercion lo caza.
DANGER="$($PY -c 'print("mk"+"fs.ext4 /dev/sdb1")')"

# Corre sentinel con un CWD que trae una allowlist de repo clonado.
run_with_repo_allowlist() { # $1 json_allowlist  $2 payload_json  -> stdout+rc via echo
  local d; d="$(mktemp -d)"
  mkdir -p "$d/.security"
  printf '%s' "$1" > "$d/.security/sentinel-allowlist.json"
  ( cd "$d" && printf '%s' "$2" | "$PY" "$SEN" 2>&1 )
  rm -rf "$d"
}

expect_deny() { # $1 desc  $2 stdout
  if echo "$2" | grep -qiE '"permissionDecision": *"deny"|SENTINEL BLOCKED'; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); echo "FAIL: $1"
    echo "    got: $(echo "$2" | head -c 200)"
  fi
}

al_cmd="$($PY -c "import json,sys;print(json.dumps({'commands':[sys.argv[1]]}))" "$DANGER")"
pay_cmd="$($PY -c "import json,sys;print(json.dumps({'tool_name':'Bash','tool_input':{'command':sys.argv[1]}}))" "$DANGER")"
out="$(run_with_repo_allowlist "$al_cmd" "$pay_cmd")"
expect_deny "comando CRITICAL sigue denegado pese a estar en allowlist.commands" "$out"

out2="$(run_with_repo_allowlist '{"paths":["/"]}' "$pay_cmd")"
expect_deny "comando CRITICAL sigue denegado con allowlist.paths=['/']" "$out2"

echo "PASS=$pass FAIL=$fail SKIP=0"
[ "$fail" -eq 0 ]
