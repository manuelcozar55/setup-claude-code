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

# --- (g) el preflight de Sentinel es obligatorio: ausente -> exit 2, no no-op ---
out="$("$W" --python /no/existe/sentinel_preflight.py 2>&1)"; rc=$?
check "sentinel_preflight.py ausente deniega (exit 2)" 2 "$rc"
if echo "$out" | grep -q "fail-closed"; then ok; else ko "el aviso fail-closed debe llegar por stderr"; fi

# --- (h) --python arranca el intérprete aislado (-I -S) ---------------------
# Medido en la instalación real: el venv tardaba 22 ms por hook y 8 ms con -I -S, porque site
# cargaba apport y un .pth editable que apunta a /mnt/c, escribible desde Windows: código ajeno
# dentro de cada guard. Los hooks del kit solo importan stdlib (lo comprueba (i)).
fakepy="$(mktemp)"; printf '#!/bin/sh\nprintf "%%s\\n" "$*"\n' > "$fakepy"; chmod +x "$fakepy"
args="$(PYTHON_HOOK_BIN="$fakepy" "$W" --python "$fakepy" extra 2>&1)"
if [ "$args" = "-I -S $fakepy extra" ]; then ok; else ko "--python debe pasar -I -S antes del script (args: $args)"; fi

# --- (i) cada hook Python del kit arranca por la resolución real del wrapper y sale 0 con `{}` ---
# `--python` es lo que cablea settings.json (intérprete elegido por el wrapper, con -I -S): se mide
# esa ruta, no un python3 suelto. HOME desechable: lo que se mide es el arranque, no la decisión.
phome="$(mktemp -d)"
for hook in "$KIT"/claude/hooks/*.py "$KIT"/sentinel/*.py; do
  out="$(echo '{}' | HOME="$phome" "$W" --python "$hook" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then ok; else ko "$(basename "$hook") no arranca por optional-hook.sh --python (rc=$rc): $out"; fi
done
rm -r -- "$phome"

rm -f "$blocker" "$allower" "$echoer" "$fakepy"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
