#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

export CLAUDE_HOME="$tmp/dot"

# doctor.sh mira estado de MAQUINA, no solo de CLAUDE_HOME: la unidad systemd en
# XDG_CONFIG_HOME y ~/.headroom/logs/proxy.jsonl. Sin aislar HOME, este test aprueba o
# suspende segun lo que tenga la maquina de quien lo corre -- y de hecho suspendia en la
# del autor, que tiene conversaciones en claro en ese log (un hallazgo verdadero de
# doctor, pero ajeno a "instalacion limpia"). Tambien se limpia ANTHROPIC_BASE_URL: con
# un proxy muerto en el entorno, el caso "instalacion limpia" fallaria por otro motivo.
# Misma leccion que 628dfaa "fix(test): hace hermetico test_guards.sh".
mkdir -p "$tmp/home/.headroom/logs" "$tmp/home/.config"
run_doctor(){ env -u ANTHROPIC_BASE_URL HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" \
  bash "$KIT/doctor.sh" >/dev/null 2>&1; }

bash "$KIT/install.sh" >/dev/null 2>&1
set +e; run_doctor; rc=$?; set -e
ck "$rc" "0" "doctor PASS sobre instalación limpia"

# Rompe un hook referenciado -> FAIL
rm -f "$CLAUDE_HOME/hooks/branch-guard.sh"
set +e; run_doctor; rc=$?; set -e
ck "$rc" "1" "doctor FAIL con hook ausente"

# Hook presente pero NO ejecutable -> FAIL
bash "$KIT/install.sh" >/dev/null 2>&1
chmod -x "$CLAUDE_HOME/hooks/branch-guard.sh"
set +e; run_doctor; rc=$?; set -e
ck "$rc" "1" "doctor FAIL con hook no ejecutable"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
