#!/bin/bash
# test_optional_hook.sh — contrato de kit/claude/hooks/optional-hook.sh.
#
# El wrapper existe por un fallo real: settings.json invocaba `rtk hook claude` y
# el python3 del venv de tools directamente, y ninguno de los dos los instala
# install.sh (son terceros). En una instalación limpia eso da exit 127 en cada
# llamada a tool -- en el caso del preflight de Sentinel, con matcher "", en
# TODAS. El contrato que se prueba aquí: dependencia ausente = no-op silencioso;
# dependencia presente = se ejecuta y su código de salida se propaga TAL CUAL,
# incluido el 2 que Claude Code interpreta como bloqueo. Un wrapper que se
# comiera el 2 convertiría los guards en decorativos, que es peor que el 127.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
W="$KIT/claude/hooks/optional-hook.sh"
pass=0; fail=0
ok(){ pass=$((pass+1)); }
ko(){ fail=$((fail+1)); echo "FAIL: $1"; }

check(){ # desc, expected_rc, actual_rc
  if [ "$2" = "$3" ]; then ok; else ko "$1 (esperaba rc=$2, fue rc=$3)"; fi
}

if [ ! -x "$W" ]; then
  echo "FAIL: $W no existe o no es ejecutable"
  echo "PASS=0 FAIL=1"
  exit 1
fi

# --- (a) ejecutable inexistente -> no-op, exit 0, sin ruido ------------------
out="$("$W" definitivamente-no-existe-$$ arg1 2>&1)"; rc=$?
check "comando ausente sale 0" 0 "$rc"
if [ -z "$out" ]; then ok; else ko "comando ausente no debe imprimir nada (imprimió: $out)"; fi

# --- (b) --python con intérprete ausente -> no-op ---------------------------
out="$(PYTHON_HOOK_BIN=/no/existe/python3 "$W" --python /tmp/da-igual.py 2>&1)"; rc=$?
check "--python sin intérprete sale 0" 0 "$rc"
if [ -z "$out" ]; then ok; else ko "--python sin intérprete no debe imprimir nada (imprimió: $out)"; fi

# --- (c) --python con intérprete presente pero script ausente -> no-op ------
out="$(PYTHON_HOOK_BIN="$(command -v python3)" "$W" --python /no/existe/script.py 2>&1)"; rc=$?
check "--python sin script sale 0" 0 "$rc"

# --- (d) comando presente que bloquea (exit 2) -> el 2 se propaga -----------
blocker="$(mktemp)"; printf '#!/bin/sh\necho "BLOCKED: motivo" >&2\nexit 2\n' > "$blocker"; chmod +x "$blocker"
out="$("$W" "$blocker" 2>&1)"; rc=$?
check "exit 2 se propaga (el guard sigue bloqueando)" 2 "$rc"
if echo "$out" | grep -q "BLOCKED: motivo"; then ok; else ko "el stderr del guard debe llegar intacto"; fi

# --- (e) comando presente que permite (exit 0) ------------------------------
allower="$(mktemp)"; printf '#!/bin/sh\nexit 0\n' > "$allower"; chmod +x "$allower"
"$W" "$allower" >/dev/null 2>&1; rc=$?
check "exit 0 se propaga" 0 "$rc"

# --- (f) el stdin llega al comando envuelto ---------------------------------
# Los hooks de Claude Code reciben el payload JSON por stdin: si el wrapper no
# lo pasa, los guards quedan ciegos y aprueban todo.
echoer="$(mktemp)"; printf '#!/bin/sh\ncat\n' > "$echoer"; chmod +x "$echoer"
got="$(printf '{"tool_name":"Bash"}' | "$W" "$echoer" 2>/dev/null)"
if [ "$got" = '{"tool_name":"Bash"}' ]; then ok; else ko "stdin no llega al comando envuelto (got: $got)"; fi

rm -f "$blocker" "$allower" "$echoer"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
