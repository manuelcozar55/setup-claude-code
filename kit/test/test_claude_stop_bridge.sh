#!/usr/bin/env bash
# test_claude_stop_bridge.sh — el puente Stop ENDURECIDO del perfil de referencia
# de Claude contra el productor real de M (`mch task gate --json`, gate v2 del
# todo 9).
#
# QUE lo distingue de test_verify_gate.sh (que NO se toca): aquel mide el hook
# INSTALADO que resuelve `mch` por PATH y opera en modo aviso. Este mide un
# puente NUEVO y separado (kit/lib/claude_stop_bridge.sh) cuyo contrato es el que
# el todo 20 exige y verify-gate.sh no da:
#
#   - RUTA ABSOLUTA DE CONFIANZA al binario de M: NUNCA `mch` del PATH. Un `mch`
#     de mentira primero en el PATH tiene que ser IGNORADO.
#   - VERSION MINIMA del productor: por debajo del minimo, BLOQUEA.
#   - UNA sola invocacion del gate.
#   - TIMEOUT y TOPE DE SALIDA (overflow): ambos BLOQUEAN.
#   - ESQUEMA DE EVIDENCIA fijado (mch-gate-evidence-v2) + version compatible:
#     un esquema/version futuros o ausentes BLOQUEAN.
#   - TABLA rc CERRADA: 0=ALLOW, 1=BLOCK, 2=BLOCK, 3=ALLOW, cualquier otro=BLOCK.
#
# El puente se invoca con `--mch RUTA` SOLO para inyectar productores de mentira
# en los casos de fallo (overflow/timeout/malformed/version). En produccion el
# perfil de referencia NO pasa `--mch`: usa la ruta absoluta de confianza que el
# puente lleva embebida. Un caso mide justo eso: sin `--mch`, un `mch` de mentira
# en el PATH no cambia el veredicto.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; RAIZ="$(cd "$HERE/../.." && pwd)"
BRIDGE="$RAIZ/kit/lib/claude_stop_bridge.sh"
# Binario real de M, derivado de la raiz del worktree SIN literal de la cuenta
# (kit/scan-secrets.sh prohibe versionar el nombre de la cuenta local). La raiz
# de este repo es .../<slug>/setup-claude-code; el repo M es su hermano
# .../<slug>/mcharness. El contrato entre repos solo se prueba hablando con el otro.
MCH_REAL="$(cd "$RAIZ/../mcharness" 2>/dev/null && pwd)/bin/mch"
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

if ! command -v jq >/dev/null 2>&1; then
  echo "skip - jq ausente: esta suite decodifica con jq la decision JSON del puente"
  echo "== 0 passed, 0 failed, 1 skipped =="; exit 0
fi
if [ ! -x "$MCH_REAL" ]; then
  echo "skip - el binario real de M no esta junto a este worktree (contrato entre repos no verificable aqui)"
  echo "== 0 passed, 0 failed, 1 skipped =="; exit 0
fi

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/ungoverned"

# El puente decide con un codigo de salida (contrato Stop): 0=ALLOW (el turno
# puede terminar), 2=BLOCK (stderr al modelo). El motivo/veredicto detallado va
# por stdout como JSON {"decision":"allow"|"block","reason":...} para que el test
# lo lea sin depender del rc en los caminos que ambos comparten.
decision(){ if [ -n "$1" ]; then printf '%s' "$1" | jq -r '.decision // "ninguna"' 2>/dev/null
            else echo "ninguna"; fi; }

# Un `mch` de MENTIRA que, si se ejecutara, escribiria un centinela y emitiria un
# BLOQUEO. Si el puente lo respetara (en vez de usar la ruta absoluta), el
# centinela apareceria y/o el veredicto seria block.
fabrica_mch_trampa(){
  cat > "$T/bin/mch" <<EOF
#!/usr/bin/env bash
touch "$T/centinela_trampa"
printf '%s\n' '{"contrato":2,"gobierna":true,"veredicto":"BLOCK","motivo_codigo":"governed_red","motivo":"TRAMPA: este mch de PATH no deberia ejecutarse","tarea":"T-999","evidencia":{"schema":"mch-gate-evidence-v2","state_sha256":null,"journal_sha256":null,"oracle_sha256":null}}'
exit 1
EOF
  chmod +x "$T/bin/mch"
}

# ─────────────────────────────────────────────────────────────────────────────
# RED PRINCIPAL (la asercion esperada, no un error de sintaxis):
# proyecto NO gobernado por M -> el productor REAL devuelve rc3/not_governed y el
# puente debe PERMITIR; y un `mch` de mentira primero en el PATH NO se ejecuta
# porque el puente usa la ruta absoluta de confianza embebida.
# ─────────────────────────────────────────────────────────────────────────────
fabrica_mch_trampa
rm -f "$T/centinela_trampa"
# Sin --mch: el puente usa $CCKIT_MCH_BRIDGE_PATH (la ruta de confianza que fija
# la instalacion). PATH lleva el mch trampa delante: no debe ejecutarse.
out_rc3="$( (cd "$T/ungoverned" && env PATH="$T/bin:$PATH" CCKIT_MCH_BRIDGE_PATH="$MCH_REAL" bash "$BRIDGE") 2>/dev/null )"
ck "$(decision "$out_rc3")" "allow" "rc3 (M no gobierna): el puente PERMITE via productor real"
ck "$([ -e "$T/centinela_trampa" ] && echo si || echo no)" "no" \
   "el mch de mentira del PATH NO se ejecuto (ruta absoluta de confianza)"

# El rc del contrato Stop tambien: rc3 => exit 0 (ALLOW).
( cd "$T/ungoverned" && bash "$BRIDGE" --mch "$MCH_REAL" >/dev/null 2>&1 )
ck "$?" "0" "rc3 real: el puente sale con exit 0 (ALLOW por contrato Stop)"

# --- sin ruta de confianza (ni --mch ni CCKIT_MCH_BRIDGE_PATH) -> BLOCK ------
# El mch trampa esta en el PATH; el puente NO debe caer a el.
rm -f "$T/centinela_trampa"
sin_ruta="$( (cd "$T/ungoverned" && env PATH="$T/bin:$PATH" bash "$BRIDGE") 2>/dev/null )"
ck "$(decision "$sin_ruta")" "block" "sin ruta de confianza: BLOQUEA (no cae al mch del PATH)"
ck "$([ -e "$T/centinela_trampa" ] && echo si || echo no)" "no" "sin ruta: el mch del PATH sigue sin ejecutarse"

# --- ruta de confianza NO absoluta -> BLOCK ---------------------------------
ck "$(decision "$( (cd "$T/ungoverned" && CCKIT_MCH_BRIDGE_PATH="bin/mch" env PATH="$T/bin:$PATH" bash "$BRIDGE") 2>/dev/null )")" "block" \
   "ruta de confianza relativa: BLOQUEA (solo absoluta)"

# --- ruta de confianza escribible por otros -> BLOCK ------------------------
cp "$MCH_REAL" "$T/mch_ww" 2>/dev/null || printf '#!/usr/bin/env bash\necho "mch 0.2.0"\n' > "$T/mch_ww"
chmod 0757 "$T/mch_ww"
ck "$(decision "$( (cd "$T/ungoverned" && bash "$BRIDGE" --mch "$T/mch_ww") 2>/dev/null )")" "block" \
   "productor escribible por otros (0757): BLOQUEA (no es de confianza)"

# ─────────────────────────────────────────────────────────────────────────────
# Productores de MENTIRA por --mch: SOLO para los caminos de fallo. Cada uno
# emula una desviacion concreta del contrato y el puente debe BLOQUEAR (exit 2),
# salvo el caso VERDE (rc0) que debe PERMITIR.
# ─────────────────────────────────────────────────────────────────────────────
# $1=nombre $2=version($ 'mch --version') $3=rc-del-gate $4=stdout-del-gate $5=sleep-opcional
fabrica_fake(){
  local nom="$1" ver="$2" grc="$3" body="$4" slp="${5:-}"
  cat > "$T/bin/$nom" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "--version" ]; then printf '%s\n' "$ver"; exit 0; fi
# el gate es: mch task gate --json
${slp:+sleep $slp}
printf '%s\n' '$body'
exit $grc
EOF
  chmod +x "$T/bin/$nom"
}

EVOK='{"contrato":2,"gobierna":true,"veredicto":"ALLOW","motivo_codigo":"verified","motivo":"ok","tarea":"T-1","evidencia":{"schema":"mch-gate-evidence-v2","state_sha256":null,"journal_sha256":null,"oracle_sha256":null}}'
ROJO='{"contrato":2,"gobierna":true,"veredicto":"BLOCK","motivo_codigo":"governed_red","motivo":"no hay VERDE registrado","tarea":"T-7","evidencia":{"schema":"mch-gate-evidence-v2","state_sha256":null,"journal_sha256":null,"oracle_sha256":null}}'
FUTURO='{"contrato":9,"gobierna":true,"veredicto":"ALLOW","motivo_codigo":"verified","motivo":"ok","tarea":"T-1","evidencia":{"schema":"mch-gate-evidence-v99","state_sha256":null,"journal_sha256":null,"oracle_sha256":null}}'

corre(){ printf '{"cwd":"%s","stop_hook_active":false}' "$T/ungoverned" | bash "$BRIDGE" --mch "$1" 2>/dev/null; }
rc_de(){ printf '{"cwd":"%s","stop_hook_active":false}' "$T/ungoverned" | bash "$BRIDGE" --mch "$1" >/dev/null 2>&1; echo $?; }

# --- rc0 verified -> ALLOW ---------------------------------------------------
fabrica_fake mch_ok "mch 0.2.0" 0 "$EVOK"
ck "$(decision "$(corre "$T/bin/mch_ok")")" "allow" "rc0 (verified) con esquema fijado: PERMITE"

# --- rc1 governed_red -> BLOCK ----------------------------------------------
fabrica_fake mch_rojo "mch 0.2.0" 1 "$ROJO"
ck "$(decision "$(corre "$T/bin/mch_rojo")")" "block" "rc1 (governed_red): BLOQUEA"
ck "$(rc_de "$T/bin/mch_rojo")" "2" "rc1: exit 2 (contrato Stop, stderr al modelo)"
razon="$(corre "$T/bin/mch_rojo" | jq -r '.reason // ""')"
ck "$(printf '%s' "$razon" | grep -qE '\bT-7\b' && echo y || echo n)" "y" "rc1: el bloqueo nombra la tarea"

# --- version por debajo del minimo -> BLOCK ---------------------------------
fabrica_fake mch_viejo "mch 0.1.9" 0 "$EVOK"
ck "$(decision "$(corre "$T/bin/mch_viejo")")" "block" "version 0.1.9 < 0.2.0: BLOQUEA"
razon="$(corre "$T/bin/mch_viejo" | jq -r '.reason // ""')"
ck "$(printf '%s' "$razon" | grep -qi 'version' && echo y || echo n)" "y" "version vieja: el motivo lo dice"
# Falsabilidad: una version por ENCIMA del minimo NO bloquea por version.
fabrica_fake mch_nuevo "mch 1.4.0" 0 "$EVOK"
ck "$(decision "$(corre "$T/bin/mch_nuevo")")" "allow" "version 1.4.0 >= 0.2.0: PERMITE (falsabilidad del chequeo de version)"

# --- rc2 usage -> BLOCK ------------------------------------------------------
fabrica_fake mch_usage "mch 0.2.0" 2 ""
ck "$(decision "$(corre "$T/bin/mch_usage")")" "block" "rc2 (usage): BLOQUEA (no se confia en un gate que no evaluo)"

# --- rc desconocido -> BLOCK -------------------------------------------------
fabrica_fake mch_raro "mch 0.2.0" 7 ""
ck "$(decision "$(corre "$T/bin/mch_raro")")" "block" "rc desconocido (7): fuera de la tabla v2, BLOQUEA"

# --- esquema de evidencia futuro/incompatible en rc0 -> BLOCK ---------------
fabrica_fake mch_futuro "mch 0.2.0" 0 "$FUTURO"
ck "$(decision "$(corre "$T/bin/mch_futuro")")" "block" "esquema evidencia v99 en rc0: BLOQUEA (no reconozco el contrato)"

# --- rc0 con stdout vacio (gobernado sin cuerpo) -> BLOCK -------------------
fabrica_fake mch_vacio "mch 0.2.0" 0 ""
ck "$(decision "$(corre "$T/bin/mch_vacio")")" "block" "rc0 gobernado con stdout vacio: BLOQUEA (fallo cerrado)"

# --- malformado (rc0 con JSON roto) -> BLOCK --------------------------------
fabrica_fake mch_malo "mch 0.2.0" 0 '{"contrato":2,"evidencia":{"schema":'
ck "$(decision "$(corre "$T/bin/mch_malo")")" "block" "rc0 con JSON malformado: BLOQUEA (no se puede confirmar el esquema)"

# --- overflow (salida por encima del tope) -> BLOCK -------------------------
# Un gate que emite mas de GATE_MAX_BYTES (65536) es sospechoso. Se fabrica un
# cuerpo gigante con el esquema correcto: el tope tiene que morder ANTES.
big="$(head -c 70000 /dev/zero | tr '\0' 'x')"
fabrica_fake mch_grande "mch 0.2.0" 0 "{\"contrato\":2,\"pad\":\"$big\",\"evidencia\":{\"schema\":\"mch-gate-evidence-v2\"}}"
ck "$(decision "$(corre "$T/bin/mch_grande")")" "block" "overflow (>64KiB): BLOQUEA aunque el esquema sea correcto"

# --- timeout -> BLOCK --------------------------------------------------------
# El gate duerme mas que GATE_TIMEOUT (10s). Para no colgar el test 10s, se
# fabrica un fake que duerme 12s pero se mide con el propio timeout del puente.
# Se acota el propio caso con un timeout externo de 20s de guardia.
fabrica_fake mch_lento "mch 0.2.0" 0 "$EVOK" 12
rc_to="$(timeout 20 bash -c 'printf "{\"cwd\":\"'"$T/ungoverned"'\",\"stop_hook_active\":false}" | bash "'"$BRIDGE"'" --mch "'"$T/bin/mch_lento"'" >/dev/null 2>&1; echo $?')"
ck "$rc_to" "2" "timeout del gate (>10s): BLOQUEA (exit 2)"

# --- stop_hook_active=true -> el puente se aparta (cap de 8 de Claude Code) --
fabrica_fake mch_rojo2 "mch 0.2.0" 1 "$ROJO"
rc_cap="$(printf '{"cwd":"%s","stop_hook_active":true}' "$T/ungoverned" | bash "$BRIDGE" --mch "$T/bin/mch_rojo2" >/dev/null 2>&1; echo $?)"
ck "$rc_cap" "0" "stop_hook_active=true: el puente se aparta (respeta el cap de 8)"

# --- ruta de M ausente -> BLOCK (autoridad esperada que no responde) --------
ck "$(decision "$(printf '{"cwd":"%s"}' "$T/ungoverned" | bash "$BRIDGE" --mch "$T/no_existe_mch" 2>/dev/null)")" "block" \
   "productor de M ausente en su ruta: BLOQUEA (no cae a un mch del PATH)"

# ─────────────────────────────────────────────────────────────────────────────
# PRODUCTOR REAL, ESTADO GOBERNADO (hallazgo 2): hasta aqui las clausulas
# gobernadas (rc0 verde, rc1 rojo) se probaban solo con fakes. Ahora se ejerce el
# puente contra el PRODUCTOR REAL de M en un proyecto GOBERNADO de verdad, llevado
# a VERDE y a ROJO por el propio `mch`. Cierra el bucle productor↔consumidor entre
# repos: el fake y el real deben coincidir. Respeta la rama de skip: si M no esta
# al lado, esta seccion ni siquiera se alcanza (el skip de arriba ya salio).
# ─────────────────────────────────────────────────────────────────────────────
# shellcheck source=/dev/null
. "$RAIZ/kit/lib/verify/mch_real_governed.sh"
G_DIR="$T/real_governed_green"; R_DIR="$T/real_governed_red"
if mrg_build_green "$G_DIR"; then
  ck "$(mrg_real_gate_rc "$G_DIR")" "0" "productor REAL: proyecto gobernado en VERDE devuelve gate rc0"
  dg="$(printf '{"cwd":"%s","stop_hook_active":false}' "$G_DIR" | bash "$BRIDGE" --mch "$MCH_REAL" 2>/dev/null)"
  ck "$(decision "$dg")" "allow" "rc0 REAL (verified): el puente PERMITE contra el productor real (no un fake)"
  rc_g="$(printf '{"cwd":"%s","stop_hook_active":false}' "$G_DIR" | bash "$BRIDGE" --mch "$MCH_REAL" >/dev/null 2>&1; echo $?)"
  ck "$rc_g" "0" "rc0 REAL: exit 0 (ALLOW por contrato Stop) contra el productor real"
else
  ck "no" "si" "no se pudo construir el proyecto gobernado VERDE con el productor real (git/mch ausente)"
fi
if mrg_build_red "$R_DIR"; then
  ck "$(mrg_real_gate_rc "$R_DIR")" "1" "productor REAL: proyecto gobernado en ROJO devuelve gate rc1"
  dr="$(printf '{"cwd":"%s","stop_hook_active":false}' "$R_DIR" | bash "$BRIDGE" --mch "$MCH_REAL" 2>/dev/null)"
  ck "$(decision "$dr")" "block" "rc1 REAL (governed_red): el puente BLOQUEA contra el productor real (no un fake)"
  rc_r="$(printf '{"cwd":"%s","stop_hook_active":false}' "$R_DIR" | bash "$BRIDGE" --mch "$MCH_REAL" >/dev/null 2>&1; echo $?)"
  ck "$rc_r" "2" "rc1 REAL: exit 2 (BLOCK por contrato Stop) contra el productor real"
  razon_r="$(printf '%s' "$dr" | jq -r '.reason // ""')"
  ck "$(printf '%s' "$razon_r" | grep -qE '\bT-001\b' && echo y || echo n)" "y" "rc1 REAL: el bloqueo nombra la tarea real gobernada (T-001)"
else
  ck "no" "si" "no se pudo construir el proyecto gobernado ROJO con el productor real (git/mch ausente)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# PERFIL DE REFERENCIA (declarativo) + su consumo por installer_core.
# ─────────────────────────────────────────────────────────────────────────────
PC="$RAIZ/kit/lib/profile_coordinator.py"
IC="$RAIZ/kit/lib/installer_core.py"
CAP_I="$RAIZ/kit/lib/profiles/claude-reference-interactive.runtime-capability-v1.json"
CAP_N="$RAIZ/kit/lib/profiles/claude-reference-noninteractive.runtime-capability-v1.json"
PLAN="$RAIZ/kit/lib/profiles/claude-reference.installer-core-plan-v1.json"
CONTRACT="$RAIZ/kit/lib/profiles/claude-stop-bridge.consumed-contract-v1.json"

# --- las dos capacidades validan contra el schema v1 real -------------------
ck "$(python3 "$PC" validate --capability "$CAP_I" >/dev/null 2>&1 && echo ok || echo no)" "ok" \
   "capacidad interactive valida (lifecycle-enforced, native_stop)"
ck "$(python3 "$PC" validate --capability "$CAP_N" >/dev/null 2>&1 && echo ok || echo no)" "ok" \
   "capacidad non-interactive valida (profile-certified, degradada)"
# tier/modo explicitos y coherentes con la matriz normativa
ck "$(jq -r '.tier' "$CAP_I")" "lifecycle-enforced" "interactive: tier lifecycle-enforced"
ck "$(jq -r '.modes[0]' "$CAP_I")" "interactive" "interactive: modo explicito"
ck "$(jq -r '.lifecycle.native_stop' "$CAP_I")" "true" "interactive: native_stop true"
ck "$(jq -r '.tier' "$CAP_N")" "profile-certified" "non-interactive: tier profile-certified (nunca lifecycle-enforced)"
ck "$(jq -r '.lifecycle.enforcement' "$CAP_N")" "degraded" "non-interactive: enforcement degradado, honesto"

# --- digest estable: delata cambios silenciosos -----------------------------
d1="$(python3 "$PC" digest --capability "$CAP_I")"
d2="$(python3 "$PC" digest --capability "$CAP_I")"
ck "$d1" "$d2" "digest de la capacidad interactive es estable"
ck "$([ -n "$d1" ] && echo y || echo n)" "y" "digest no vacio"

# --- el contrato consumido fija esquema + version minima --------------------
ck "$(jq -r '.evidence_schema' "$CONTRACT")" "mch-gate-evidence-v2" "contrato consumido fija el evidence_schema del gate v2"
ck "$(jq -r '.min_producer_version' "$CONTRACT")" "0.2.0" "contrato consumido fija la version minima del productor"
# y el puente embebe EXACTAMENTE ese esquema y esa version (no derivan)
ck "$(grep -c 'mch-gate-evidence-v2' "$BRIDGE")" "1" "el puente embebe el evidence_schema fijado"
ck "$(grep -cE 'MIN_MAJOR=0; MIN_MINOR=2; MIN_PATCH=0' "$BRIDGE")" "1" "el puente embebe la version minima 0.2.0"

# --- consumo del perfil: settings por MERGE (txnwrite), owned por installer_core
# Se materializa un CLAUDE_HOME temporal con settings.json y hooks MANUALES del
# usuario. El merge de settings.json lo hace su primitiva duena (txnwrite
# json-merge-owned-keys) porque installer_core reclama propiedad TOTAL de cada
# target de escritura y rechaza en cerrado pisar el settings manual del usuario:
# eso es correcto para un OWNED, no para un MERGE. Los ficheros OWNED (puente +
# capacidades) si van por installer_core, con su ledger de propiedad.
TXN="$RAIZ/kit/lib/txnwrite.py"
HOME_T="$T/claude_home"; mkdir -p "$HOME_T/hooks" "$HOME_T/profiles"
cat > "$HOME_T/settings.json" <<'EOF'
{"env":{"MI_VAR_PERSONAL":"no-me-toques"},"hooks":{"PreToolUse":[{"matcher":"","hooks":[{"type":"command","command":"mi-hook-manual.sh"}]}]},"permissions":{"allow":["Bash(mio *)"]}}
EOF
cat > "$HOME_T/hooks/mi-hook-manual.sh" <<'EOF'
#!/usr/bin/env bash
echo "hook manual del usuario, intocable"
EOF
manual_hook_sha="$(sha256sum "$HOME_T/hooks/mi-hook-manual.sh" | cut -d' ' -f1)"

# Resolver el plan OWNED: kit-relativo -> absoluto; content_ref -> content inline.
PLAN_ABS="$T/plan.abs.json"
python3 - "$PLAN" "$RAIZ" "$PLAN_ABS" <<'PY'
import json,sys,os
plan_path, raiz, out = sys.argv[1], sys.argv[2], sys.argv[3]
plan = json.load(open(plan_path))
for op in plan["operations"]:
    for k in ("src","kit_json"):
        if k in op and not os.path.isabs(op[k]):
            op[k] = os.path.join(raiz, op[k])
    if "content_ref" in op:
        ref = op.pop("content_ref")
        if not os.path.isabs(ref): ref = os.path.join(raiz, ref)
        op["content"] = open(ref, encoding="utf-8").read()
json.dump(plan, open(out,"w"))
PY
ck "$([ -s "$PLAN_ABS" ] && echo y || echo n)" "y" "plan OWNED resuelto a rutas absolutas + content inline"
ck "$(jq -r '[.operations[].op] | index("json-merge-owned-keys") // "no"' "$PLAN")" "no" \
   "el plan OWNED NO lleva el merge de settings (va por su primitiva duena)"

# MERGE de settings.json via su primitiva duena (declarada en settings_merge del plan).
SETTINGS_KIT="$RAIZ/$(jq -r '.settings_merge.kit_json' "$PLAN")"
python3 "$TXN" json-merge-owned-keys --root "$HOME_T" --dst settings.json \
        --kit-json "$SETTINGS_KIT" --policy claude-settings >/dev/null 2>&1
ck "$?" "0" "merge de settings.json (txnwrite json-merge-owned-keys) rc0"
ck "$(jq -r '.env.MI_VAR_PERSONAL' "$HOME_T/settings.json")" "no-me-toques" "el merge conserva env personal del usuario"
ck "$(jq -r '.env.CCKIT_CLAUDE_REFERENCE_PROFILE' "$HOME_T/settings.json")" "1" "el merge aporta la marca del perfil de referencia sin pisar el env del usuario"
ck "$(jq -r '.permissions.allow | index("Bash(mio *)") != null' "$HOME_T/settings.json")" "true" "el merge conserva el permiso propio del usuario"
ck "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$HOME_T/settings.json")" "mi-hook-manual.sh" \
   "el merge conserva los hooks manuales del usuario (el fragmento del perfil NO declara hooks, para no huerfanizarlos)"

# install de los ficheros OWNED via installer_core, preservando lo manual.
python3 "$IC" install --root "$HOME_T" --plan "$PLAN_ABS" >/dev/null 2>&1
ck "$?" "0" "installer_core instala los ficheros OWNED del perfil (install rc0)"
ck "$(sha256sum "$HOME_T/hooks/mi-hook-manual.sh" | cut -d' ' -f1)" "$manual_hook_sha" "el hook manual del usuario queda intacto"
ck "$([ -f "$HOME_T/hooks/claude_stop_bridge.sh" ] && echo y || echo n)" "y" "el puente Stop de referencia queda instalado"
ck "$([ -f "$HOME_T/profiles/claude-reference-interactive.runtime-capability-v1.json" ] && echo y || echo n)" "y" \
   "la capacidad interactive queda instalada como fichero propio"
ck "$(stat -c '%a' "$HOME_T/hooks/claude_stop_bridge.sh")" "755" "el puente queda ejecutable (0755)"

# --- update (reinstall) idempotente: no huerfaniza ni pisa lo manual --------
python3 "$IC" install --root "$HOME_T" --plan "$PLAN_ABS" >/dev/null 2>&1
ck "$?" "0" "reinstall (update) idempotente (rc0)"
ck "$(sha256sum "$HOME_T/hooks/mi-hook-manual.sh" | cut -d' ' -f1)" "$manual_hook_sha" "update: el hook manual sigue intacto"

# --- uninstall: retira SOLO lo propio, preserva lo manual -------------------
python3 "$IC" uninstall --root "$HOME_T" --plan "$PLAN_ABS" >/dev/null 2>&1
ck "$?" "0" "uninstall rc0"
ck "$([ -f "$HOME_T/hooks/claude_stop_bridge.sh" ] && echo si || echo no)" "no" "uninstall retira el puente propio"
ck "$([ -f "$HOME_T/hooks/mi-hook-manual.sh" ] && echo si || echo no)" "si" "uninstall PRESERVA el hook manual del usuario"
ck "$(sha256sum "$HOME_T/hooks/mi-hook-manual.sh" | cut -d' ' -f1)" "$manual_hook_sha" "uninstall: el hook manual queda byte-identico"

# --- ownership: un target ajeno preexistente NO se pisa (conflicto) ---------
# Se coloca a mano un fichero en la ruta de una capacidad propia ANTES de instalar
# en un home limpio: installer_core debe RECHAZAR pre-escritura.
HOME_C="$T/home_conflicto"; mkdir -p "$HOME_C/profiles"
echo "fichero ajeno preexistente" > "$HOME_C/profiles/claude-reference-interactive.runtime-capability-v1.json"
ajeno_sha="$(sha256sum "$HOME_C/profiles/claude-reference-interactive.runtime-capability-v1.json" | cut -d' ' -f1)"
python3 "$IC" install --root "$HOME_C" --plan "$PLAN_ABS" >/dev/null 2>&1
ck "$?" "1" "conflicto de propiedad: install rechaza pisar un target ajeno (rc1)"
ck "$(sha256sum "$HOME_C/profiles/claude-reference-interactive.runtime-capability-v1.json" | cut -d' ' -f1)" "$ajeno_sha" \
   "el fichero ajeno queda intacto (no se piso)"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
