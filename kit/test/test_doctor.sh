#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

export CLAUDE_HOME="$tmp/home/.claude"  # = $HOME/.claude: la statusLine del kit apunta ahi

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

# La deriva tambien cubre hooks/lib/ (nucleo.sh, del que dependen los hooks de estado) y sentinel/
# (sentinel_preflight.py): antes solo se comparaba hooks/*, y esos dos podian divergir sin aviso.
bash "$KIT/install.sh" >/dev/null 2>&1
echo "# tocado a mano" >> "$CLAUDE_HOME/hooks/lib/nucleo.sh"
echo "# tocado a mano" >> "$CLAUDE_HOME/sentinel/sentinel_preflight.py"
out="$(env -u ANTHROPIC_BASE_URL HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" \
       bash "$KIT/doctor.sh" 2>&1)"
if echo "$out" | grep -qE '^WARN .*difieren de los del kit.*lib/nucleo\.sh'; then
  ck y y "un hooks/lib/nucleo.sh desplegado modificado a mano produce WARN de deriva"
else
  ck n y "un hooks/lib/nucleo.sh desplegado modificado a mano produce WARN de deriva"
fi
if echo "$out" | grep -qE '^WARN .*difieren de los del kit.*sentinel_preflight\.py'; then
  ck y y "un sentinel_preflight.py desplegado modificado a mano produce WARN de deriva"
else
  ck n y "un sentinel_preflight.py desplegado modificado a mano produce WARN de deriva"
fi

# iocs.json es dato que la persona personaliza por diseno: editarlo no es deriva de codigo y el
# consejo de reinstalar pisaria sus datos (E7.3 CR-10). Solo el codigo de sentinel/ entra en la deriva.
bash "$KIT/install.sh" >/dev/null 2>&1
jq '.personal = true' "$CLAUDE_HOME/sentinel/iocs.json" > "$tmp/iocs.mio" && cp "$tmp/iocs.mio" "$CLAUDE_HOME/sentinel/iocs.json"
out="$(env -u ANTHROPIC_BASE_URL HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" \
       bash "$KIT/doctor.sh" 2>&1)"
if echo "$out" | grep -qE '^WARN .*difieren de los del kit.*iocs'; then
  ck n y "un iocs.json personalizado no produce WARN de deriva"
else
  ck y y "un iocs.json personalizado no produce WARN de deriva"
fi

# La capa de IOCs se busca donde la busca el hook, no en una sola ruta fija.
# El defecto: en una instalacion donde sentinel vive FUERA de CLAUDE_HOME, doctor avisaba de
# que la capa estaba inactiva cuando en realidad cargaba 31 patrones de ruta. Un aviso falso
# gasta la credibilidad de los verdaderos.
bash "$KIT/install.sh" >/dev/null 2>&1
# El kit SI distribuye iocs.json (la capa activa de fabrica), asi que para probar el aviso
# hay que quitarlo. Antes solo venia iocs.example.json y cada instalacion arrancaba con la
# capa apagada y un WARN que nadie lee.
mv "$CLAUDE_HOME/sentinel/iocs.json" "$tmp/iocs.json.guardado"
out="$(env -u ANTHROPIC_BASE_URL HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" \
       bash "$KIT/doctor.sh" 2>&1)"
if echo "$out" | grep -qE '^WARN .*IOC layer inactiva'; then
  ck y y "si quitas iocs.json, doctor avisa (la capa es opcional, pero el kit la trae activa)"
else
  ck n y "si quitas iocs.json, doctor avisa (la capa es opcional, pero el kit la trae activa)"
fi
mv "$tmp/iocs.json.guardado" "$CLAUDE_HOME/sentinel/iocs.json"
out="$(env -u ANTHROPIC_BASE_URL HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" \
       bash "$KIT/doctor.sh" 2>&1)"
if echo "$out" | grep -qE '^PASS .*IOC layer activa'; then
  ck y y "con iocs.json junto al preflight, doctor lo encuentra y lo dice"
else
  ck n y "con iocs.json junto al preflight, doctor lo encuentra y lo dice"
fi

# Acoplamiento iocs.json/.py (E6 #27): el iocs declara la version minima del preflight y doctor avisa
# si el instalado es mas viejo. Antes un iocs nuevo con un .py viejo no fallaba: se quedaba a medias.
dr() { env -u ANTHROPIC_BASE_URL HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" bash "$KIT/doctor.sh" 2>&1; }
out="$(dr)"
if echo "$out" | grep -qE '^PASS .*sentinel_preflight\.py v[0-9]+ cubre lo que exige iocs\.json'; then
  ck y y "iocs.json y preflight alineados: doctor lo confirma"
else
  ck n y "iocs.json y preflight alineados: doctor lo confirma"
fi
jq '.min_preflight_version = 99' "$CLAUDE_HOME/sentinel/iocs.json" > "$tmp/iocs.alto" && cp "$tmp/iocs.alto" "$CLAUDE_HOME/sentinel/iocs.json"
out="$(dr)"
if echo "$out" | grep -qE '^WARN .*iocs\.json exige sentinel_preflight\.py v99'; then
  ck y y "un iocs.json que exige un preflight mas nuevo que el instalado produce WARN"
else
  ck n y "un iocs.json que exige un preflight mas nuevo que el instalado produce WARN"
fi
jq '.min_preflight_version = 2' "$CLAUDE_HOME/sentinel/iocs.json" > "$tmp/iocs.dos" && cp "$tmp/iocs.dos" "$CLAUDE_HOME/sentinel/iocs.json"
sed -i '/^PREFLIGHT_VERSION = /d' "$CLAUDE_HOME/sentinel/sentinel_preflight.py"
out="$(dr)"
if echo "$out" | grep -qE '^WARN .*iocs\.json exige sentinel_preflight\.py v2 y el instalado .* es v1'; then
  ck y y "un preflight sin constante de version cuenta como v1 y produce WARN"
else
  ck n y "un preflight sin constante de version cuenta como v1 y produce WARN"
fi

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
