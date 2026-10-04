#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

# Esta suite no llama a jq, pero lo que ejerce si: kit/doctor.sh lo usa en 12 sitios.
# Sin jq el primer check ("doctor PASS sobre instalacion limpia") daba 1 != 0 y, con el
# `set -e` de arriba, la suite moria ANTES de imprimir su resumen: kit/sumar-tests.sh la
# listaba como "sin resumen parseable", que es ruido y no un hallazgo. Se omite
# declarandolo, como ya hacen otras diez suites de este repo.
if ! command -v jq >/dev/null 2>&1; then
  echo "skip - jq ausente: esta suite ejerce doctor.sh, que lee settings.json con jq"
  echo "== 0 passed, 0 failed, 1 skipped =="; exit 0
fi

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
if echo "$out" | grep -qE '^WARN .*branch-guard.*personalizacion local'; then
  ck y y "un hook desplegado modificado a mano produce WARN de deriva"
else
  ck n y "un hook desplegado modificado a mano produce WARN de deriva"
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

# Sensores de maquina (seccion 7 de doctor). Cada uno se prueba en rojo Y en verde: un
# sensor que solo se ha visto callar no ha demostrado que sepa hablar. Se fabrican /proc
# y /tmp falsos, asi el resultado no depende de la maquina que corre la suite.
fproc="$tmp/proc"; ftmp="$tmp/faketmp"; mkdir -p "$fproc/sys/fs/binfmt_misc" "$ftmp"
doc(){ env -u ANTHROPIC_BASE_URL HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" \
       DOCTOR_PROC="$fproc" DOCTOR_TMP="$ftmp" "$@" bash "$KIT/doctor.sh" 2>&1; }
tiene(){ if echo "$out" | grep -qE "$1"; then ck y "$2" "$3"; else ck n "$2" "$3"; fi; }

set +e; out="$(doc DOCTOR_TMP_INODOS="980 1000")"; rc=$?; set -e
tiene '^WARN .*al 98% de inodos' y "inodos de /tmp al 98%: WARN"
ck "$rc" "0" "los sensores de maquina avisan, no suspenden (rc=0)"
out="$(doc DOCTOR_TMP_INODOS="100 1000")"
tiene '^PASS .*al 10% de inodos' y "inodos de /tmp al 10%: PASS"

echo 'tmpfs /tmp tmpfs rw,nosuid,nr_inodes=4194304 0 0' > "$fproc/mounts"
out="$(doc DOCTOR_TMPMOUNT_OPTS='Options=mode=1777,size=50%%,nr_inodes=1m')"
tiene '^WARN .*nr_inodes=4194304 pero tmp.mount dice 1m' y "remount sin drop-in (vivo 4m, unidad 1m): WARN"
out="$(doc DOCTOR_TMPMOUNT_OPTS='Options=mode=1777,size=50%%,nr_inodes=4m')"
tiene 'pero tmp.mount dice' n "drop-in persistente (4m = 4194304): sin aviso"
rm -f "$fproc/mounts"

echo 'Linux version 6.6 (microsoft-standard-WSL2)' > "$fproc/version"
out="$(doc)"
tiene '^WARN .*WSL sin interop' y "WSL sin WSLInterop en binfmt_misc: WARN"
: > "$fproc/sys/fs/binfmt_misc/WSLInterop-late"
out="$(doc)"
tiene '^PASS .*interop con Windows registrado' y "WSL con WSLInterop-late registrado: PASS"
echo 'Linux version 6.6 (generic)' > "$fproc/version"
out="$(doc)"
tiene 'interop' n "fuera de WSL el sensor de interop calla"

mkdir -p "$tmp/fbin" "$tmp/nvm/.nvm/versions/node/v24/bin"
printf '#!/bin/sh\n' > "$tmp/nvm/.nvm/versions/node/v24/bin/pnpm"; chmod +x "$tmp/nvm/.nvm/versions/node/v24/bin/pnpm"
ln -sf "$tmp/nvm/.nvm/versions/node/v24/bin/pnpm" "$tmp/fbin/pnpm"
out="$(doc PATH="$tmp/fbin:$PATH")"
tiene '^WARN .*pnpm depende de una version concreta de Node' y "pnpm resuelto dentro de nvm: WARN"
rm -f "$tmp/fbin/pnpm"; printf '#!/bin/sh\n' > "$tmp/fbin/pnpm"; chmod +x "$tmp/fbin/pnpm"
out="$(doc PATH="$tmp/fbin:$PATH")"
tiene '^PASS .*pnpm no depende' y "pnpm independiente de nvm: PASS"

mkdir -p "$CLAUDE_HOME/projects/-mnt-c-Users-x-repo"
: > "$CLAUDE_HOME/projects/-mnt-c-Users-x-repo/s.jsonl"
out="$(doc)"
tiene '^WARN .*1 proyecto\(s\) con sesiones .* /mnt/' y "proyecto activo en /mnt/c: WARN"
touch -d '30 days ago' "$CLAUDE_HOME/projects/-mnt-c-Users-x-repo/s.jsonl"
out="$(doc)"
tiene 'viven en /mnt/' n "proyecto en /mnt/c sin sesiones en 14 dias: sin aviso"

for i in $(seq 1 20); do mkdir "$ftmp/tmp.$i"; touch -d '2 days ago' "$ftmp/tmp.$i"; done
out="$(doc)"
tiene '^WARN .*restos en .*20 dirs tmp' y "20 dirs tmp.* de mas de un dia: WARN"
touch "$ftmp"/tmp.*
out="$(doc)"
tiene 'restos en' n "los mismos dirs recien creados (un test en curso): sin aviso"
for i in $(seq 1 10); do : > "$ftmp/.ab$i-00000000.so"; done
out="$(doc)"
tiene '^WARN .*restos en .*10 \.so' y "10 .so extraidos por binarios Bun: WARN"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
