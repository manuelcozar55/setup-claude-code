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

HOME="$tmp/home" bash "$KIT/install.sh" >/dev/null 2>&1
set +e; run_doctor; rc=$?; set -e
ck "$rc" "0" "doctor PASS sobre instalación limpia"

# El inventario obligatorio incluye instrucciones y skills aunque settings.json
# no las referencie. Un symlink personalizado que resuelve a fichero sigue
# estando presente y solo puede producir WARN de deriva, nunca FAIL.
rm "$CLAUDE_HOME/AGENTS.md"
set +e; run_doctor; rc=$?; set -e
ck "$rc" "1" "doctor FAIL si falta AGENTS.md"
HOME="$tmp/home" bash "$KIT/install.sh" >/dev/null 2>&1
# B-08: un agente personal no se cuenta como del kit
printf -- '---\nname: planner\n---\n' > "$CLAUDE_HOME/agents/planner.md"
ag="$(env -u ANTHROPIC_BASE_URL HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" bash "$KIT/doctor.sh" 2>&1 | grep 'agentes instalados' || true)"
ck "$(grep -c '1 ajeno(s) al kit: planner.md' <<<"$ag")" "1" "doctor distingue un agente personal de los del kit"
rm "$CLAUDE_HOME/agents/planner.md"
printf '# skill personalizada\n' > "$tmp/skill-personalizada.md"
rm "$CLAUDE_HOME/skills/deep-change/SKILL.md"
set +e; run_doctor; rc=$?; set -e
ck "$rc" "1" "doctor FAIL si falta una skill instalada"
ln -s "$tmp/skill-personalizada.md" "$CLAUDE_HOME/skills/deep-change/SKILL.md"
set +e; run_doctor; rc=$?; set -e
ck "$rc" "0" "doctor acepta una skill personalizada mediante symlink"
rm "$CLAUDE_HOME/skills/deep-change/SKILL.md"
HOME="$tmp/home" bash "$KIT/install.sh" >/dev/null 2>&1

# Rompe un hook referenciado -> FAIL
rm -f "$CLAUDE_HOME/hooks/branch-guard.sh"
set +e; run_doctor; rc=$?; set -e
ck "$rc" "1" "doctor FAIL con hook ausente"

# Hook presente pero NO ejecutable -> FAIL
HOME="$tmp/home" bash "$KIT/install.sh" >/dev/null 2>&1
chmod -x "$CLAUDE_HOME/hooks/branch-guard.sh"
set +e; run_doctor; rc=$?; set -e
ck "$rc" "1" "doctor FAIL con hook no ejecutable"

# Deriva entre el kit y lo desplegado -> WARN (no FAIL: personalizar es legitimo).
# El defecto que lo motiva: dos guards llevaban meses distintos entre el kit y su copia de
# origen, la version endurecida en un lado y la antigua en el otro, sin que nadie lo notara.
HOME="$tmp/home" bash "$KIT/install.sh" >/dev/null 2>&1
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
HOME="$tmp/home" bash "$KIT/install.sh" >/dev/null 2>&1
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
HOME="$tmp/home" bash "$KIT/install.sh" >/dev/null 2>&1
jq '.personal = true' "$CLAUDE_HOME/sentinel/iocs.json" > "$tmp/iocs.mio" && cp "$tmp/iocs.mio" "$CLAUDE_HOME/sentinel/iocs.json"
out="$(env -u ANTHROPIC_BASE_URL HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" \
       bash "$KIT/doctor.sh" 2>&1)"
if echo "$out" | grep -qE '^WARN .*difieren de los del kit.*iocs'; then
  ck n y "un iocs.json personalizado no produce WARN de deriva"
else
  ck y y "un iocs.json personalizado no produce WARN de deriva"
fi

# settings.json, CLAUDE.md y AGENTS.md son de la persona: install.sh fusiona el primero y no pisa
# los otros dos, asi que difieren del kit en toda instalacion real. Compararlos daba un WARN de
# deriva permanente, y un aviso que siempre esta ahi enseña a ignorar los verdaderos.
HOME="$tmp/home" bash "$KIT/install.sh" >/dev/null 2>&1
for f in settings.json CLAUDE.md AGENTS.md; do cp "$CLAUDE_HOME/$f" "$tmp/$f.guardado"; done
jq '.env.DERIVA_TEST = "1"' "$CLAUDE_HOME/settings.json" > "$tmp/settings.mio" && cp "$tmp/settings.mio" "$CLAUDE_HOME/settings.json"
echo "# mio" >> "$CLAUDE_HOME/CLAUDE.md"
echo "# mio" >> "$CLAUDE_HOME/AGENTS.md"
out="$(env -u ANTHROPIC_BASE_URL HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" \
       bash "$KIT/doctor.sh" 2>&1)"
n="$(echo "$out" | grep -cE '^WARN .*difieren de los del kit.*(settings\.json|CLAUDE\.md|AGENTS\.md)' || true)"
ck "$n" "0" "settings.json, CLAUDE.md y AGENTS.md personalizados no producen WARN de deriva"
for f in settings.json CLAUDE.md AGENTS.md; do cp "$tmp/$f.guardado" "$CLAUDE_HOME/$f"; done

# La capa de IOCs se busca donde la busca el hook, no en una sola ruta fija.
# El defecto: en una instalacion donde sentinel vive FUERA de CLAUDE_HOME, doctor avisaba de
# que la capa estaba inactiva cuando en realidad cargaba 31 patrones de ruta. Un aviso falso
# gasta la credibilidad de los verdaderos.
HOME="$tmp/home" bash "$KIT/install.sh" >/dev/null 2>&1
# El kit SI distribuye iocs.json (la capa activa de fabrica), asi que para probar el aviso
# hay que quitarlo. La capa sigue siendo opcional en una instalacion personalizada.
mv "$CLAUDE_HOME/sentinel/iocs.json" "$tmp/iocs.json.guardado"
set +e
out="$(env -u ANTHROPIC_BASE_URL HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" \
       bash "$KIT/doctor.sh" 2>&1)"
rc=$?
set -e
if echo "$out" | grep -qE '^WARN .*IOC layer inactiva'; then
  ck y y "si quitas iocs.json, doctor avisa que la capa esta inactiva"
else
  ck n y "si quitas iocs.json, doctor avisa que la capa esta inactiva"
fi
ck "$rc" "0" "si quitas iocs.json, doctor conserva el contrato opcional sin FAIL"
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

# CLIs del flujo de estado: sin bin/handoff, bin/oraculo o templates/nucleo.md el flujo v3 no arranca -> FAIL.
# En PATH ausente -> WARN; CLAUDE.md sin @AGENTS.md -> WARN. (Antes doctor daba OK con bin/ borrado.)
HOME="$tmp/home" bash "$KIT/install.sh" >/dev/null 2>&1
mv "$CLAUDE_HOME/bin/handoff" "$tmp/handoff.bak"
set +e; out="$(dr)"; rc=$?; set -e
ck "$(echo "$out" | grep -c '^FAIL .*bin/handoff')" "1" "doctor FAIL si falta bin/handoff"
set +e; dr >/dev/null; rc=$?; set -e
ck "$rc" "1" "doctor sale 1 si falta bin/handoff"
mv "$tmp/handoff.bak" "$CLAUDE_HOME/bin/handoff"
mv "$CLAUDE_HOME/bin/oraculo" "$tmp/oraculo.bak"
set +e; out="$(dr)"; set -e
ck "$(echo "$out" | grep -c '^FAIL .*bin/oraculo')" "1" "doctor FAIL si falta bin/oraculo"
mv "$tmp/oraculo.bak" "$CLAUDE_HOME/bin/oraculo"
mv "$CLAUDE_HOME/templates/nucleo.md" "$tmp/nucleo.bak"
set +e; out="$(dr)"; set -e
ck "$(echo "$out" | grep -c '^FAIL .*templates/nucleo.md')" "1" "doctor FAIL si falta templates/nucleo.md"
mv "$tmp/nucleo.bak" "$CLAUDE_HOME/templates/nucleo.md"
set +e; out="$(PATH="$tmp/home/.local/bin:$PATH" dr)"; set -e
ck "$(echo "$out" | grep -c '^PASS .*handoff se resuelve en el PATH')" "1" "doctor PASS si handoff esta en el PATH"
set +e; out="$(PATH="$(dirname "$(command -v jq)"):/usr/bin:/bin" dr)"; rc=$?; set -e
ck "$(echo "$out" | grep -cE '^WARN .*handoff no se resuelve en tu PATH')" "1" "doctor WARN si handoff no esta en el PATH"
ck "$rc" "0" "handoff fuera del PATH es WARN: doctor sigue en rc 0"
ck "$(echo "$out" | grep -c 'ln -sf')" "0" "la sugerencia usa ln -s, nunca ln -sf (pisaria un hueco ajeno)"
# Un handoff ajeno primero en el PATH no es el del kit, y command -v daba PASS igual: se compara readlink -f.
mkdir -p "$tmp/ajeno-bin"; printf '#!/bin/sh\necho otro\n' > "$tmp/ajeno-bin/handoff"; chmod +x "$tmp/ajeno-bin/handoff"
set +e; out="$(PATH="$tmp/ajeno-bin:$tmp/home/.local/bin:$PATH" dr)"; rc=$?; set -e
ck "$(echo "$out" | grep -cF "WARN · handoff del PATH es $tmp/ajeno-bin/handoff")" "1" "doctor WARN, con la ruta, si el handoff del PATH es ajeno"
ck "$(echo "$out" | grep -c '^PASS .*handoff se resuelve en el PATH')" "0" "un handoff ajeno en el PATH no da PASS"
ck "$(echo "$out" | grep -c '^PASS .*oraculo se resuelve en el PATH')" "1" "el oraculo enlazado al kit sigue en PASS (falsabilidad del caso)"
ck "$(echo "$out" | grep -c 'ln -sf')" "0" "con un handoff ajeno tampoco se sugiere ln -sf"
ck "$rc" "0" "un handoff ajeno en el PATH es WARN: doctor sigue en rc 0"
printf '# mis cosas\n' > "$CLAUDE_HOME/CLAUDE.md"
set +e; out="$(dr)"; set -e
ck "$(echo "$out" | grep -c '^WARN .*@AGENTS.md')" "1" "doctor WARN si CLAUDE.md no importa @AGENTS.md"
printf '# mis cosas\n%s\n' '@AGENTS.md' > "$CLAUDE_HOME/CLAUDE.md"
set +e; out="$(dr)"; set -e
ck "$(echo "$out" | grep -c '^WARN .*@AGENTS.md')" "0" "doctor sin WARN si CLAUDE.md importa @AGENTS.md"

# disableAllHooks: true apaga todos los hooks, guards incluidos, con cada fichero en su sitio: la fusion
# de install.sh lo respeta (es tuyo) y avisa, y doctor no puede dar OK sobre eso.
jq '.disableAllHooks = true' "$CLAUDE_HOME/settings.json" > "$tmp/s.json" && cp "$tmp/s.json" "$CLAUDE_HOME/settings.json"
set +e; out="$(dr)"; rc=$?; set -e
ck "$(echo "$out" | grep -c '^FAIL .*disableAllHooks')" "1" "doctor FAIL con disableAllHooks: true"
ck "$rc" "1" "doctor sale 1 con disableAllHooks: true"
jq '.disableAllHooks = false' "$CLAUDE_HOME/settings.json" > "$tmp/s.json" && cp "$tmp/s.json" "$CLAUDE_HOME/settings.json"
set +e; out="$(dr)"; set -e
ck "$(echo "$out" | grep -c '^FAIL .*disableAllHooks')" "0" "disableAllHooks: false no es FAIL"

# Estado del proyecto actual (ADR 016): WARN si .claude/estado/ no esta ignorado y tiene ficheros sin
# rastrear; sin WARN si esta ignorado; WARN si informes/ pasa del tope (DOCTOR_INFORMES_MB).
mkdir -p "$tmp/p-estado/.claude/estado/informes"; git -C "$tmp/p-estado" init -q
echo x > "$tmp/p-estado/.claude/estado/nucleo.md"
set +e; out="$(cd "$tmp/p-estado" && dr)"; set -e
ck "$(echo "$out" | grep -c '^WARN .*estado/ no esta ignorado')" "1" "doctor WARN si .claude/estado/ no esta ignorado y tiene ficheros sin rastrear"
printf '*\n' > "$tmp/p-estado/.claude/estado/.gitignore"
set +e; out="$(cd "$tmp/p-estado" && dr)"; set -e
ck "$(echo "$out" | grep -c '^WARN .*estado/ no esta ignorado')" "0" "doctor sin WARN de estado con .claude/estado/ ignorado"
ck "$(echo "$out" | grep -c '^WARN .*informes/ pesa')" "0" "doctor sin WARN de informes bajo el tope"
dd if=/dev/zero of="$tmp/p-estado/.claude/estado/informes/grande.bin" bs=1024 count=2048 2>/dev/null
set +e; out="$(cd "$tmp/p-estado" && DOCTOR_INFORMES_MB=1 dr)"; set -e
ck "$(echo "$out" | grep -c '^WARN .*informes/ pesa')" "1" "doctor WARN si informes/ pasa del tope"

# M5 residuo: env.CC_ALLOW_DESTRUCTIVE=1 apaga destructive-guard.sh y sobrevive a la fusion de install.sh.
cp "$CLAUDE_HOME/settings.json" "$tmp/s.bak"
jq '.env.CC_ALLOW_DESTRUCTIVE = "1"' "$tmp/s.bak" > "$CLAUDE_HOME/settings.json"
set +e; out="$(dr)"; set -e
ck "$(echo "$out" | grep -c '^WARN .*CC_ALLOW_DESTRUCTIVE')" "1" "doctor WARN con env.CC_ALLOW_DESTRUCTIVE=1"
jq '.env.CC_ALLOW_DESTRUCTIVE = "0"' "$tmp/s.bak" > "$CLAUDE_HOME/settings.json"
set +e; out="$(dr)"; set -e
ck "$(echo "$out" | grep -c '^WARN .*CC_ALLOW_DESTRUCTIVE')" "0" "CC_ALLOW_DESTRUCTIVE=0 no es WARN"
cp "$tmp/s.bak" "$CLAUDE_HOME/settings.json"

# Hooks ajenos: install.sh los conserva (fusion por propietario) y doctor los lista, para que un sensor tuyo
# muerto o duplicado se vea. En una instalacion limpia no hay ninguno.
set +e; out="$(dr)"; set -e
ck "$(echo "$out" | grep -c 'hooks ajenos al kit')" "0" "doctor no lista hooks ajenos en una instalacion limpia"
jq '.hooks.PostCompact = [{"hooks":[{"type":"command","command":"mi-sensor.sh"}]}]' "$tmp/s.bak" > "$CLAUDE_HOME/settings.json"
set +e; out="$(dr)"; set -e
ck "$(echo "$out" | grep -c '^PASS .*hooks ajenos al kit.*: 1 (PostCompact mi-sensor.sh)')" "1" "doctor lista un hook ajeno con su evento"
cp "$tmp/s.bak" "$CLAUDE_HOME/settings.json"

# Version de claude (rev-B IMPORTANTE 6): WARN si falta o es anterior a la version con la que se probo el kit.
# Es la que cita docs/10-onboarding.md, no la de ninguna politica gestionada: las dos no pueden divergir.
ck "$(grep -cF "se probó con la versión $(sed -n 's/^CLAUDE_PROBADA="\(.*\)"$/\1/p' "$KIT/doctor.sh")." "$KIT/docs/10-onboarding.md")" "1" "doctor.sh y docs/10-onboarding.md citan la misma version probada"
fake_claude() {  # $1 = version que imprime
  mkdir -p "$tmp/fk-$1"; printf '#!/bin/sh\necho "%s (Claude Code)"\n' "$1" > "$tmp/fk-$1/claude"; chmod +x "$tmp/fk-$1/claude"
}
fake_claude 2.1.100; fake_claude 2.1.292; fake_claude 2.2.0
set +e; out="$(PATH="$tmp/fk-2.1.100:$PATH" dr)"; set -e
ck "$(echo "$out" | grep -c '^WARN .*claude.*2\.1\.100.*2\.1\.292')" "1" "doctor WARN con claude 2.1.100 (< 2.1.292)"
set +e; out="$(PATH="$tmp/fk-2.1.292:$PATH" dr)"; set -e
ck "$(echo "$out" | grep -c '^PASS .*claude 2\.1\.292')" "1" "claude 2.1.292 (la probada justa) es PASS"
set +e; out="$(PATH="$tmp/fk-2.2.0:$PATH" dr)"; set -e
ck "$(echo "$out" | grep -c '^PASS .*claude 2\.2\.0')" "1" "claude 2.2.0 es PASS (comparacion por version, no por texto)"
# C-02: los guards de Bash llevan onFailure:"block" (claude >= 2.1.295); con uno anterior el doctor avisa.
ck "$(jq '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.onFailure == "block")] | length' "$CLAUDE_HOME/settings.json")" "5" "los 5 guards de Bash de settings.json llevan onFailure:block"
set +e; out="$(PATH="$tmp/fk-2.1.292:$PATH" dr)"; set -e
ck "$(echo "$out" | grep -c '^WARN .*2\.1\.292.*2\.1\.295.*onFailure')" "1" "doctor WARN con claude 2.1.292 (< 2.1.295) porque settings.json usa onFailure:block"
ck "$(echo "$out" | grep -c 'onFailure')" "1" "el aviso de onFailure sale una sola vez"
set +e; out="$(PATH="$tmp/fk-2.2.0:$PATH" dr)"; set -e
ck "$(echo "$out" | grep -c 'onFailure')" "0" "claude 2.2.0 no da el aviso de onFailure"
farm="$tmp/sinclaude"; mkdir -p "$farm"
IFS=: read -ra dirs <<< "$PATH"
for d in "${dirs[@]}"; do
  [ -d "$d" ] || continue
  for f in "$d"/*; do
    b="${f##*/}"
    [ -e "$f" ] && [ "$b" != claude ] && [ ! -e "$farm/$b" ] && ln -s "$f" "$farm/$b"
  done
done
ck "$(PATH="$farm" bash -c 'command -v claude >/dev/null 2>&1 && echo y || echo n')" "n" "el PATH de la granja no tiene claude (falsabilidad del caso)"
set +e; out="$(PATH="$farm" dr)"; set -e
ck "$(echo "$out" | grep -c '^WARN .*claude.*no se encuentra')" "1" "doctor WARN si claude no esta en el PATH"
cp "$CLAUDE_HOME/hooks/lib/nucleo.sh" "$tmp/nucleo-original"
rm "$CLAUDE_HOME/hooks/lib/nucleo.sh"
set +e; out="$(dr)"; rc=$?; set -e
ck "$rc" "1" "doctor FAIL si falta la biblioteca de continuidad"
ck "$(echo "$out" | grep -c '^FAIL .*lib/nucleo.sh')" "1" "doctor identifica la biblioteca ausente"
cp "$tmp/nucleo-original" "$CLAUDE_HOME/hooks/lib/nucleo.sh"
printf '\n# version distinta\n' >> "$CLAUDE_HOME/bin/handoff"
set +e; out="$(dr)"; set -e
ck "$(echo "$out" | grep -c '^WARN .*difieren de los del kit.*bin/handoff')" "1" "doctor detecta CLI de otra version aunque siga siendo ejecutable"

# K10: CLAUDE_CONFIG_DIR definida pero vacia no equivale a no definirla: claude auth status da loggedIn:false.
set +e; out="$(CLAUDE_CONFIG_DIR="" dr)"; set -e
ck "$(echo "$out" | grep -c '^WARN .*CLAUDE_CONFIG_DIR.*vac')" "1" "K10: doctor avisa si CLAUDE_CONFIG_DIR esta definida pero vacia"
set +e; out="$(env -u CLAUDE_CONFIG_DIR HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" bash "$KIT/doctor.sh" 2>&1)"; set -e
ck "$(echo "$out" | grep -c 'CLAUDE_CONFIG_DIR')" "0" "K10: sin definir no dice nada"
set +e; out="$(CLAUDE_CONFIG_DIR="$tmp/cfg" dr)"; set -e
ck "$(echo "$out" | grep -c 'CLAUDE_CONFIG_DIR.*vac')" "0" "K10: con valor no avisa"
ck "$(grep -c 'claude auth login --email' "$KIT/docs/02-install.md")" "1" "K10: la guia documenta el login sin TUI y por config dir"
# K11: pgrep -f "claude -p" se encuentra a si mismo dentro de bash -c. Nada del kit lo recomienda y la guia lo explica.
ck "$(grep -c '\[c\]laude -p' "$KIT/docs/06-routine.md")" "1" "K11: la guia de autonomia da el patron ps|grep [c]laude -p"
# Solo lo versionado: un .out ignorado (p. ej. en .claude/estado/) no es una recomendacion del repo.
K11F="$KIT/../.claude/estado/k11-prueba.out"; mkdir -p "${K11F%/*}"; echo 'pgrep -f claude' >"$K11F"
ck "$(git -C "$KIT/.." grep -lE 'pgrep +-f +.?claude' -- . ':(exclude,glob)**/archive/**' ':(exclude,glob)**/06-routine.md' ':(exclude,glob)**/test_doctor.sh' 2>/dev/null | wc -l)" "0" "K11: ningun fichero versionado del repo recomienda pgrep -f claude (los ignorados no cuentan)"
rm -f "$K11F"
# K6: la ventana de 250 K se queda (freno de coste), con su porque, y cambiarla en una ejecucion va por --settings.
ck "$(grep -c -- "--settings '{\"env\":{\"CLAUDE_CODE_AUTO_COMPACT_WINDOW\"" "$KIT/docs/02-install.md")" "1" "K6: la guia documenta --settings con env para cambiar la ventana en una ejecucion"
ck "$(grep -c 'freno de coste' "$KIT/docs/02-install.md")" "1" "K6: la guia explica por que se queda en 250 K"
# K13: el numero de suites que da la documentacion cuadra con el real (los ficheros de kit/test y las lineas de `make test`).
ROOT="$KIT/.."
real_suites="$(find "$KIT/test" -maxdepth 1 -name 'test_*.sh' | wc -l | tr -d ' ')"
make_suites="$(sed -n '/^test:/,/^[a-z-]*:/p' "$ROOT/Makefile" | grep -c 'bash kit/test/test_')"
ck "$make_suites" "$real_suites" "K13: make test corre todas las suites de kit/test ($real_suites)"
for doc in README.md AGENTS.md CLAUDE.md CONTRIBUTING.md kit/README.md kit/docs/10-onboarding.md; do
  [ -f "$ROOT/$doc" ] || continue
  dichos="$(grep -oE '[0-9]+ suites' "$ROOT/$doc" | grep -oE '[0-9]+' | sort -u | tr '\n' ' ')"
  ck "${dichos% }" "$real_suites" "K13: $doc dice $real_suites suites"
done
# v1.6.0: cuatro WARN nuevos, todos reproducibles con fixtures en el HOME temporal y nunca FAIL.
HOME="$tmp/home" bash "$KIT/install.sh" >/dev/null 2>&1
dr_en() { (cd "$1" && dr); }   # git worktree list y nucleo.md miran el repo del cwd
rp="$tmp/repo-v160"; mkdir -p "$rp"
git -C "$rp" init -q -b main; git -C "$rp" -c user.name=t -c user.email=t@x commit -q --allow-empty -m i
set +e; out="$(dr_en "$rp")"; set -e
ck "$(echo "$out" | grep -cE '^WARN .*(memoria |worktrees prunable|NUCLEO_TOPE)')" "0" "v1.6: caso limpio, ninguno de los cuatro WARN nuevos"
# 1. memoria: un .md sin linea en el indice y un enlace roto
mem="$CLAUDE_HOME/projects/-p/memory"; mkdir -p "$mem"
printf -- '- [Uno](uno.md) — ok\n- [Roto](roto.md) — no existe\n' > "$mem/MEMORY.md"
printf 'x\n' > "$mem/uno.md"; printf 'x\n' > "$mem/huerfana.md"
set +e; out="$(dr_en "$rp")"; rc=$?; set -e
ck "$(echo "$out" | grep -c '^WARN · memoria -p: 1 .md sin linea en MEMORY.md (p. ej. huerfana.md)')" "1" "v1.6: WARN por memoria sin linea en el indice"
ck "$(echo "$out" | grep -c '^WARN · memoria -p: MEMORY.md enlaza a ficheros que no existen (1; p. ej. roto.md)')" "1" "v1.6: WARN por enlace roto en MEMORY.md"
ck "$rc" "0" "v1.6: los WARN de memoria no son FAIL"
rm "$mem/huerfana.md"; printf -- '- [Uno](uno.md) — ok\n' > "$mem/MEMORY.md"
set +e; out="$(dr_en "$rp")"; set -e
ck "$(echo "$out" | grep -c '^WARN · memoria ')" "0" "v1.6: memoria coherente no avisa"
printf 'x\n' > "$mem/dos.md"; printf -- '- [Uno](uno.md) — ok\n- [dos] indexada por slug, sin .md\n' > "$mem/MEMORY.md"
set +e; out="$(dr_en "$rp")"; set -e
ck "$(echo "$out" | grep -c '^WARN · memoria ')" "0" "v1.6: una entrada [slug] sin .md cuenta como indexada"
rm "$mem/dos.md"; printf -- '- [Uno](uno.md) — ok\n' > "$mem/MEMORY.md"
# 2. MEMORY.md por encima del 75 % de lo que Claude Code carga (150 lineas o 20 KB)
{ printf -- '- [Uno](uno.md) — ok\n'; for i in $(seq 1 150); do printf -- '- nota %s\n' "$i"; done; } > "$mem/MEMORY.md"
set +e; out="$(dr_en "$rp")"; set -e
ck "$(echo "$out" | grep -c '^WARN · memoria -p: MEMORY.md tiene 151 lineas')" "1" "v1.6: WARN si MEMORY.md pasa de 150 lineas"
printf -- '- [Uno](uno.md) — ok\n' > "$mem/MEMORY.md"
# 3. worktrees: uno prunable y otro en detached bajo /tmp
wtp="$tmp/wt-prunable"; git -C "$rp" worktree add -q "$wtp" -b ramap
rm -r "$wtp"
wtd="$(mktemp -d /tmp/doctor-wt.XXXXXX)"; rmdir "$wtd"; git -C "$rp" worktree add -q --detach "$wtd"
set +e; out="$(dr_en "$rp")"; rc=$?; set -e
ck "$(echo "$out" | grep -c "^WARN · worktrees prunable o en detached bajo /tmp:.*wt-prunable")" "1" "v1.6: WARN por worktree prunable"
ck "$(echo "$out" | grep -c "^WARN · worktrees prunable.*$wtd")" "1" "v1.6: WARN por worktree en detached bajo /tmp"
ck "$rc" "0" "v1.6: los WARN de worktrees no son FAIL"
git -C "$rp" worktree remove --force "$wtd"; git -C "$rp" worktree prune
set +e; out="$(dr_en "$rp")"; set -e
ck "$(echo "$out" | grep -c '^WARN · worktrees')" "0" "v1.6: sin worktrees sobrantes no avisa"
# 4. nucleo.md mayor que NUCLEO_TOPE (el tope sale de la lib de hooks)
mkdir -p "$rp/.claude/estado"; printf '*\n' > "$rp/.claude/estado/.gitignore"
head -c 3000 /dev/zero | tr '\0' 'n' > "$rp/.claude/estado/nucleo.md"
set +e; out="$(dr_en "$rp")"; set -e
ck "$(echo "$out" | grep -c 'NUCLEO_TOPE')" "0" "v1.6: nucleo.md bajo el tope no avisa"
head -c 7000 /dev/zero | tr '\0' 'n' > "$rp/.claude/estado/nucleo.md"
set +e; out="$(dr_en "$rp")"; rc=$?; set -e
ck "$(echo "$out" | grep -c '^WARN · .*nucleo.md pesa 7000 B (> NUCLEO_TOPE 6500)')" "1" "v1.6: WARN si nucleo.md pasa de NUCLEO_TOPE"
ck "$rc" "0" "v1.6: el WARN de nucleo.md no es FAIL"
rm -r "$CLAUDE_HOME/projects"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
