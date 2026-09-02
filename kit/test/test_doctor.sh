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

# Deriva entre el kit y lo desplegado -> WARN (no FAIL: personalizar es legitimo).
# El defecto que lo motiva: dos guards llevaban meses distintos entre el kit y su copia de
# origen, la version endurecida en un lado y la antigua en el otro, sin que nadie lo notara.
bash "$KIT/install.sh" >/dev/null 2>&1
out="$(env -u ANTHROPIC_BASE_URL HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" \
       bash "$KIT/doctor.sh" 2>&1)"
if echo "$out" | grep -q 'coinciden byte a byte con los del kit'; then
  ck y y "sin tocar nada, doctor confirma que lo desplegado coincide con el kit"
else
  ck n y "sin tocar nada, doctor confirma que lo desplegado coincide con el kit"
fi
echo "# tocado a mano" >> "$CLAUDE_HOME/hooks/branch-guard.sh"
out="$(env -u ANTHROPIC_BASE_URL HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" \
       bash "$KIT/doctor.sh" 2>&1)"
if echo "$out" | grep -qE '^WARN .*difieren de los del kit.*branch-guard'; then
  ck y y "un hook desplegado modificado a mano produce WARN de deriva"
else
  ck n y "un hook desplegado modificado a mano produce WARN de deriva"
fi

# La capa de IOCs se busca donde la busca el hook, no en una sola ruta fija.
# El defecto: en una instalacion donde sentinel vive FUERA de CLAUDE_HOME, doctor avisaba de
# que la capa estaba inactiva cuando en realidad cargaba 31 patrones de ruta. Un aviso falso
# gasta la credibilidad de los verdaderos.
bash "$KIT/install.sh" >/dev/null 2>&1
out="$(env -u ANTHROPIC_BASE_URL HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" \
       bash "$KIT/doctor.sh" 2>&1)"
if echo "$out" | grep -qE '^WARN .*IOC layer inactiva'; then
  ck y y "sin iocs.json, doctor avisa (es opcional: el kit solo trae el .example)"
else
  ck n y "sin iocs.json, doctor avisa (es opcional: el kit solo trae el .example)"
fi
printf '{"schema_version":3,"sensitive_paths":{"patterns":[]}}\n' > "$CLAUDE_HOME/sentinel/iocs.json"
out="$(env -u ANTHROPIC_BASE_URL HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" \
       bash "$KIT/doctor.sh" 2>&1)"
if echo "$out" | grep -qE '^PASS .*IOC layer activa'; then
  ck y y "con iocs.json junto al preflight, doctor lo encuentra y lo dice"
else
  ck n y "con iocs.json junto al preflight, doctor lo encuentra y lo dice"
fi
rm -f "$CLAUDE_HOME/sentinel/iocs.json"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
