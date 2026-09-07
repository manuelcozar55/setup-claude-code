#!/usr/bin/env bash
# test_codex_profile.sh — el perfil nativo de Codex con LIMITES DE CICLO DE VIDA
# HONESTOS (todo 21).
#
# QUE lo distingue del perfil de Claude (test_claude_stop_bridge.sh, que NO se
# toca): Claude interactivo es lifecycle-enforced (Stop nativo). Codex NO tiene
# un hard-stop nativo probado en esta rama, asi que el plan exige literalmente
# "native hard-stop degraded unless proven": el tier de ambas superficies de
# Codex (interactive y `exec`) es profile-certified y su lifecycle va DEGRADADO,
# con la puerta de gobierno resuelta por un gate MANUAL explicito pre/post. Este
# test ancla, caso por caso, cada clausula del "What/Must NOT" y del
# "Acceptance/QA" del todo 21:
#
#   - AGENTS: la instruccion de Codex es un fichero OWNED por M (proyectado); S
#     no lo escribe ni puede huerfanizarlo.
#   - MANAGED TOML FRAGMENT/DIFF: el config.toml de Codex se toca por FRAGMENTO
#     via diff-only (NUNCA escribe) -> preserva byte a byte lo no gestionado.
#     Jamas se pisa el TOML.
#   - GATE MANUAL: script explicito que consulta al productor REAL del gate v2 de
#     M y traduce ALLOW/BLOCK a un rc de puerta manual; nunca se equipara a
#     enforcement de ciclo de vida.
#   - CERT SCRIPT OFFLINE: valida el perfil sin red y con matriz de fakes.
#   - LIGADURA AL TODO 9: el contrato consumido fija evidence_schema y version
#     minima del productor; ausente/futuro BLOQUEA.
#   - AISLAMIENTO: todo va contra un CODEX_HOME temporal; el ~/.codex real nunca
#     se toca.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; RAIZ="$(cd "$HERE/../.." && pwd)"
GATE="$RAIZ/kit/lib/codex_manual_gate.sh"
CERT="$RAIZ/kit/lib/codex_profile_cert.sh"
# Binario real de M, derivado de la raiz del worktree SIN literal de la cuenta
# (kit/scan-secrets.sh prohibe versionar el nombre de la cuenta local). El repo M
# es hermano de este: .../<slug>/mcharness.
MCH_REAL="$(cd "$RAIZ/../mcharness" 2>/dev/null && pwd)/bin/mch"
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

if ! command -v jq >/dev/null 2>&1; then
  echo "skip - jq ausente: esta suite decodifica con jq la decision JSON del gate"
  echo "== 0 passed, 0 failed, 1 skipped =="; exit 0
fi
if [ ! -x "$MCH_REAL" ]; then
  echo "skip - el binario real de M no esta junto a este worktree (contrato entre repos no verificable aqui)"
  echo "== 0 passed, 0 failed, 1 skipped =="; exit 0
fi

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/ungoverned"

decision(){ if [ -n "$1" ]; then printf '%s' "$1" | jq -r '.decision // "ninguna"' 2>/dev/null
            else echo "ninguna"; fi; }

PC="$RAIZ/kit/lib/profile_coordinator.py"
IC="$RAIZ/kit/lib/installer_core.py"
CAP_I="$RAIZ/kit/lib/profiles/codex-interactive.runtime-capability-v1.json"
CAP_E="$RAIZ/kit/lib/profiles/codex-exec.runtime-capability-v1.json"
PLAN="$RAIZ/kit/lib/profiles/codex.installer-core-plan-v1.json"
CONTRACT="$RAIZ/kit/lib/profiles/codex-manual-gate.consumed-contract-v1.json"
AGENTS_SRC="$RAIZ/kit/lib/profiles/codex-AGENTS.md"
TOML_FRAG="$RAIZ/kit/lib/profiles/codex-config.fragment.toml"
HEADROOM_OPT="$RAIZ/kit/lib/profiles/codex-headroom-wave0.declared-not-certified-v1.json"

# ─────────────────────────────────────────────────────────────────────────────
# 1. LAS DOS CAPACIDADES: tier profile-certified, lifecycle DEGRADADO (honesto).
#    El plan dice literal "native hard-stop degraded unless proven". No probado
#    aqui -> degraded, nunca lifecycle-enforced.
# ─────────────────────────────────────────────────────────────────────────────
ck "$(python3 "$PC" validate --capability "$CAP_I" >/dev/null 2>&1 && echo ok || echo no)" "ok" \
   "capacidad codex interactive valida contra el schema v1 real"
ck "$(python3 "$PC" validate --capability "$CAP_E" >/dev/null 2>&1 && echo ok || echo no)" "ok" \
   "capacidad codex exec valida contra el schema v1 real"
ck "$(jq -r '.provider' "$CAP_I")" "codex" "interactive: provider codex"
ck "$(jq -r '.surface' "$CAP_I")" "interactive" "interactive: surface interactive"
ck "$(jq -r '.tier' "$CAP_I")" "profile-certified" "interactive: tier profile-certified (NUNCA lifecycle-enforced)"
ck "$(jq -r '.lifecycle.native_stop' "$CAP_I")" "false" "interactive: sin hard-stop nativo (no probado)"
ck "$(jq -r '.lifecycle.enforcement' "$CAP_I")" "degraded" "interactive: enforcement DEGRADADO, honesto"
ck "$(jq -r '.surface' "$CAP_E")" "exec" "exec: surface exec"
ck "$(jq -r '.tier' "$CAP_E")" "profile-certified" "exec: tier profile-certified"
ck "$(jq -r '.lifecycle.enforcement' "$CAP_E")" "degraded" "exec: enforcement DEGRADADO (gate manual pre/post)"
# Falsabilidad: NINGUNA de las dos declara lifecycle-enforced.
ck "$(jq -r 'select(.tier=="lifecycle-enforced") | .surface' "$CAP_I" "$CAP_E" 2>/dev/null | wc -l | tr -d ' ')" "0" \
   "falsabilidad: ninguna superficie de Codex se declara lifecycle-enforced"
# El motivo del degradado queda ESCRITO (no es un valor mudo). El schema v1 de M
# (todo 18) es CERRADO -- no admite un campo extra en la capacidad --, asi que el
# motivo vive en el contrato consumido de S, junto a la razon del gate manual.
ck "$(jq -r '.degraded_reason | length > 0' "$CONTRACT")" "true" "el degradado de Codex lleva motivo escrito (en el contrato consumido de S)"

# ─────────────────────────────────────────────────────────────────────────────
# 2. GATE MANUAL contra el productor REAL de M: proyecto NO gobernado -> rc3 ->
#    la puerta manual PERMITE (como en ausencia de autoridad). Y NUNCA cae a un
#    `mch` del PATH.
# ─────────────────────────────────────────────────────────────────────────────
# mch trampa en el PATH: si el gate lo ejecutara escribiria un centinela.
cat > "$T/bin/mch" <<EOF
#!/usr/bin/env bash
touch "$T/centinela_trampa"
printf '%s\n' '{"contrato":2,"gobierna":true,"veredicto":"BLOCK","motivo_codigo":"governed_red","motivo":"TRAMPA","tarea":"T-999","evidencia":{"schema":"mch-gate-evidence-v2","state_sha256":null,"journal_sha256":null,"oracle_sha256":null}}'
exit 1
EOF
chmod +x "$T/bin/mch"
rm -f "$T/centinela_trampa"
out_rc3="$( (cd "$T/ungoverned" && env PATH="$T/bin:$PATH" CCKIT_MCH_BRIDGE_PATH="$MCH_REAL" bash "$GATE") 2>/dev/null )"
ck "$(decision "$out_rc3")" "allow" "gate manual rc3 (M no gobierna): PERMITE via productor real"
ck "$([ -e "$T/centinela_trampa" ] && echo si || echo no)" "no" "el mch de mentira del PATH NO se ejecuto (ruta absoluta de confianza)"

# sin ruta de confianza -> BLOCK (no cae al PATH)
rm -f "$T/centinela_trampa"
sin_ruta="$( (cd "$T/ungoverned" && env PATH="$T/bin:$PATH" bash "$GATE") 2>/dev/null )"
ck "$(decision "$sin_ruta")" "block" "gate manual sin ruta de confianza: BLOQUEA"
ck "$([ -e "$T/centinela_trampa" ] && echo si || echo no)" "no" "sin ruta: el mch del PATH sigue sin ejecutarse"

# ruta relativa -> BLOCK
ck "$(decision "$( (cd "$T/ungoverned" && CCKIT_MCH_BRIDGE_PATH="bin/mch" env PATH="$T/bin:$PATH" bash "$GATE") 2>/dev/null )")" "block" \
   "gate manual ruta relativa: BLOQUEA (solo absoluta)"

# ─────────────────────────────────────────────────────────────────────────────
# 3. Matriz de fakes del gate manual (SOLO caminos de fallo via --mch).
# ─────────────────────────────────────────────────────────────────────────────
fabrica_fake(){
  local nom="$1" ver="$2" grc="$3" body="$4" slp="${5:-}"
  cat > "$T/bin/$nom" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "--version" ]; then printf '%s\n' "$ver"; exit 0; fi
${slp:+sleep $slp}
printf '%s\n' '$body'
exit $grc
EOF
  chmod +x "$T/bin/$nom"
}
EVOK='{"contrato":2,"gobierna":true,"veredicto":"ALLOW","motivo_codigo":"verified","motivo":"ok","tarea":"T-1","evidencia":{"schema":"mch-gate-evidence-v2","state_sha256":null,"journal_sha256":null,"oracle_sha256":null}}'
ROJO='{"contrato":2,"gobierna":true,"veredicto":"BLOCK","motivo_codigo":"governed_red","motivo":"no hay VERDE","tarea":"T-7","evidencia":{"schema":"mch-gate-evidence-v2","state_sha256":null,"journal_sha256":null,"oracle_sha256":null}}'
FUTURO='{"contrato":9,"gobierna":true,"veredicto":"ALLOW","motivo_codigo":"verified","motivo":"ok","tarea":"T-1","evidencia":{"schema":"mch-gate-evidence-v99","state_sha256":null,"journal_sha256":null,"oracle_sha256":null}}'
corre(){ printf '{"cwd":"%s"}' "$T/ungoverned" | bash "$GATE" --mch "$1" 2>/dev/null; }
rc_de(){ printf '{"cwd":"%s"}' "$T/ungoverned" | bash "$GATE" --mch "$1" >/dev/null 2>&1; echo $?; }

fabrica_fake mch_ok "mch 0.2.0" 0 "$EVOK"
ck "$(decision "$(corre "$T/bin/mch_ok")")" "allow" "gate manual rc0 (verified) esquema fijado: PERMITE"
fabrica_fake mch_rojo "mch 0.2.0" 1 "$ROJO"
ck "$(decision "$(corre "$T/bin/mch_rojo")")" "block" "gate manual rc1 (governed_red): BLOQUEA"
ck "$(rc_de "$T/bin/mch_rojo")" "2" "gate manual rc1: exit 2"
fabrica_fake mch_viejo "mch 0.1.9" 0 "$EVOK"
ck "$(decision "$(corre "$T/bin/mch_viejo")")" "block" "gate manual version 0.1.9 < 0.2.0: BLOQUEA"
fabrica_fake mch_nuevo "mch 1.4.0" 0 "$EVOK"
ck "$(decision "$(corre "$T/bin/mch_nuevo")")" "allow" "gate manual version 1.4.0 >= 0.2.0: PERMITE (falsabilidad)"
fabrica_fake mch_usage "mch 0.2.0" 2 ""
ck "$(decision "$(corre "$T/bin/mch_usage")")" "block" "gate manual rc2 (usage): BLOQUEA"
fabrica_fake mch_raro "mch 0.2.0" 7 ""
ck "$(decision "$(corre "$T/bin/mch_raro")")" "block" "gate manual rc desconocido: BLOQUEA"
fabrica_fake mch_futuro "mch 0.2.0" 0 "$FUTURO"
ck "$(decision "$(corre "$T/bin/mch_futuro")")" "block" "gate manual esquema v99 en rc0: BLOQUEA"
fabrica_fake mch_vacio "mch 0.2.0" 0 ""
ck "$(decision "$(corre "$T/bin/mch_vacio")")" "block" "gate manual rc0 gobernado con stdout vacio: BLOQUEA"
fabrica_fake mch_malo "mch 0.2.0" 0 '{"contrato":2,"evidencia":{"schema":'
ck "$(decision "$(corre "$T/bin/mch_malo")")" "block" "gate manual rc0 malformado: BLOQUEA"
big="$(head -c 70000 /dev/zero | tr '\0' 'x')"
fabrica_fake mch_grande "mch 0.2.0" 0 "{\"contrato\":2,\"pad\":\"$big\",\"evidencia\":{\"schema\":\"mch-gate-evidence-v2\"}}"
ck "$(decision "$(corre "$T/bin/mch_grande")")" "block" "gate manual overflow (>64KiB): BLOQUEA"
fabrica_fake mch_lento "mch 0.2.0" 0 "$EVOK" 12
rc_to="$(timeout 20 bash -c 'printf "{\"cwd\":\"'"$T/ungoverned"'\"}" | bash "'"$GATE"'" --mch "'"$T/bin/mch_lento"'" >/dev/null 2>&1; echo $?')"
ck "$rc_to" "2" "gate manual timeout (>10s): BLOQUEA"

# stdin ABIERTO: este gate es MANUAL -- se invoca a mano antes/despues de un
# turno, no lo alimenta el runtime como a un hook. Si se queda leyendo stdin
# hasta EOF, una invocacion desde una terminal no vuelve nunca y la puerta de
# gobierno de Codex es inusable justo como esta documentada. Debe decidir en
# tiempo acotado con el cwd del proceso.
rc_stdin="$( (cd "$T/ungoverned" && timeout 8 bash "$GATE" --mch "$MCH_REAL" >/dev/null 2>&1 < <(sleep 25); echo $?) )"
ck "$rc_stdin" "0" "gate manual con stdin abierto: decide sin colgarse"

# ─────────────────────────────────────────────────────────────────────────────
# PRODUCTOR REAL, ESTADO GOBERNADO (hallazgo 2): las clausulas gobernadas (rc0
# verde, rc1 rojo) se probaban solo con fakes. Aqui el gate manual se ejerce
# contra el PRODUCTOR REAL de M en un proyecto GOBERNADO llevado a VERDE y ROJO
# por el propio `mch`. El fake y el real deben coincidir.
# ─────────────────────────────────────────────────────────────────────────────
# shellcheck source=/dev/null
. "$RAIZ/kit/lib/verify/mch_real_governed.sh"
G_DIR="$T/real_governed_green"; R_DIR="$T/real_governed_red"
if mrg_build_green "$G_DIR"; then
  ck "$(mrg_real_gate_rc "$G_DIR")" "0" "productor REAL: proyecto gobernado en VERDE devuelve gate rc0"
  dg="$(printf '{"cwd":"%s"}' "$G_DIR" | bash "$GATE" --mch "$MCH_REAL" 2>/dev/null)"
  ck "$(decision "$dg")" "allow" "gate manual rc0 REAL (verified): PERMITE contra el productor real (no un fake)"
else
  ck "no" "si" "no se pudo construir el proyecto gobernado VERDE con el productor real (git/mch ausente)"
fi
if mrg_build_red "$R_DIR"; then
  ck "$(mrg_real_gate_rc "$R_DIR")" "1" "productor REAL: proyecto gobernado en ROJO devuelve gate rc1"
  dr="$(printf '{"cwd":"%s"}' "$R_DIR" | bash "$GATE" --mch "$MCH_REAL" 2>/dev/null)"
  ck "$(decision "$dr")" "block" "gate manual rc1 REAL (governed_red): BLOQUEA contra el productor real (no un fake)"
  rc_r="$(printf '{"cwd":"%s"}' "$R_DIR" | bash "$GATE" --mch "$MCH_REAL" >/dev/null 2>&1; echo $?)"
  ck "$rc_r" "2" "gate manual rc1 REAL: exit 2 contra el productor real"
else
  ck "no" "si" "no se pudo construir el proyecto gobernado ROJO con el productor real (git/mch ausente)"
fi
# AUTORIDAD ROTA (mutantes M2/M3): el productor real da rc1 tambien con la AUTORIDAD
# del gate rota. Sin estos estados reales, suprimir authority_incompatible o
# authority_untrusted en M sobrevive. Aqui el gate manual debe BLOQUEAR en ambos.
AI_DIR="$T/real_authority_incompatible"; AU_DIR="$T/real_authority_untrusted"
if mrg_build_authbreak "$AI_DIR"; then
  ck "$(mrg_real_gate_rc "$AI_DIR")" "1" "productor REAL: autoridad incompatible devuelve gate rc1"
  dai="$(printf '{"cwd":"%s"}' "$AI_DIR" | bash "$GATE" --mch "$MCH_REAL" 2>/dev/null)"
  ck "$(decision "$dai")" "block" "gate manual rc1 REAL (authority_incompatible): BLOQUEA contra el productor real"
  rc_ai="$(printf '{"cwd":"%s"}' "$AI_DIR" | bash "$GATE" --mch "$MCH_REAL" >/dev/null 2>&1; echo $?)"
  ck "$rc_ai" "2" "gate manual rc1 REAL (authority_incompatible): exit 2 contra el productor real"
else
  ck "no" "si" "no se pudo construir el proyecto con autoridad incompatible con el productor real (git/mch ausente)"
fi
if mrg_build_untrusted "$AU_DIR"; then
  ck "$(mrg_real_gate_rc "$AU_DIR")" "1" "productor REAL: autoridad no confiable devuelve gate rc1"
  dau="$(printf '{"cwd":"%s"}' "$AU_DIR" | bash "$GATE" --mch "$MCH_REAL" 2>/dev/null)"
  ck "$(decision "$dau")" "block" "gate manual rc1 REAL (authority_untrusted): BLOQUEA contra el productor real"
  rc_au="$(printf '{"cwd":"%s"}' "$AU_DIR" | bash "$GATE" --mch "$MCH_REAL" >/dev/null 2>&1; echo $?)"
  ck "$rc_au" "2" "gate manual rc1 REAL (authority_untrusted): exit 2 contra el productor real"
else
  ck "no" "si" "no se pudo construir el proyecto con autoridad no confiable con el productor real (git/mch ausente)"
fi
# ESTADO INVALIDO (M5) y AUTORIDAD AUSENTE (M7): el productor real da rc1 tambien
# con mas de una tarea en-curso (invalid_state) y con la en-curso sin oraculo
# (authority_missing). Sin estos estados reales, suprimir invalid_state o
# authority_missing en M sobrevive. El gate manual debe BLOQUEAR en ambos.
IS_DIR="$T/real_invalid_state"; AM_DIR="$T/real_authority_missing"
if mrg_build_invalid_state "$IS_DIR"; then
  ck "$(mrg_real_gate_rc "$IS_DIR")" "1" "productor REAL: estado invalido (2 en-curso) devuelve gate rc1"
  dis="$(printf '{"cwd":"%s"}' "$IS_DIR" | bash "$GATE" --mch "$MCH_REAL" 2>/dev/null)"
  ck "$(decision "$dis")" "block" "gate manual rc1 REAL (invalid_state): BLOQUEA contra el productor real"
  rc_is="$(printf '{"cwd":"%s"}' "$IS_DIR" | bash "$GATE" --mch "$MCH_REAL" >/dev/null 2>&1; echo $?)"
  ck "$rc_is" "2" "gate manual rc1 REAL (invalid_state): exit 2 contra el productor real"
else
  ck "no" "si" "no se pudo construir el proyecto en estado invalido con el productor real (git/mch ausente)"
fi
if mrg_build_authority_missing "$AM_DIR"; then
  ck "$(mrg_real_gate_rc "$AM_DIR")" "1" "productor REAL: autoridad ausente (en-curso sin oraculo) devuelve gate rc1"
  dam="$(printf '{"cwd":"%s"}' "$AM_DIR" | bash "$GATE" --mch "$MCH_REAL" 2>/dev/null)"
  ck "$(decision "$dam")" "block" "gate manual rc1 REAL (authority_missing): BLOQUEA contra el productor real"
  rc_am="$(printf '{"cwd":"%s"}' "$AM_DIR" | bash "$GATE" --mch "$MCH_REAL" >/dev/null 2>&1; echo $?)"
  ck "$rc_am" "2" "gate manual rc1 REAL (authority_missing): exit 2 contra el productor real"
else
  ck "no" "si" "no se pudo construir el proyecto con autoridad ausente con el productor real (git/mch ausente)"
fi

# El contrato consumido fija esquema + version minima (ligadura al todo 9), y el
# gate embebe EXACTAMENTE esos valores (no derivan).
ck "$(jq -r '.evidence_schema' "$CONTRACT")" "mch-gate-evidence-v2" "contrato consumido fija el evidence_schema del gate v2"
ck "$(jq -r '.min_producer_version' "$CONTRACT")" "0.2.0" "contrato consumido fija la version minima del productor"
ck "$(grep -c 'mch-gate-evidence-v2' "$GATE")" "1" "el gate embebe el evidence_schema fijado"
ck "$(grep -cE 'MIN_MAJOR=0; MIN_MINOR=2; MIN_PATCH=0' "$GATE")" "1" "el gate embebe la version minima 0.2.0"

# ─────────────────────────────────────────────────────────────────────────────
# 4. AISLAMIENTO: install/diff/uninstall contra un CODEX_HOME temporal, con
#    bytes AJENOS en el config.toml -> deben sobrevivir byte a byte tras cada
#    operacion. El TOML NUNCA se pisa (fragmento via diff-only).
# ─────────────────────────────────────────────────────────────────────────────
CODEX_HOME_T="$T/codex_home"; mkdir -p "$CODEX_HOME_T"
# bytes AJENOS del usuario en el TOML (config no gestionado)
cat > "$CODEX_HOME_T/config.toml" <<'EOF'
# config personal del usuario, intocable
model = "o3"
[mcp_servers.mio]
command = "mi-server"
EOF
toml_ajeno_sha="$(sha256sum "$CODEX_HOME_T/config.toml" | cut -d' ' -f1)"

# Resolver el plan: kit-relativo -> absoluto; content_ref -> content inline.
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
ck "$([ -s "$PLAN_ABS" ] && echo y || echo n)" "y" "plan de Codex resuelto a rutas absolutas + content inline"

# El plan del TOML NO escribe: solo diff-only (nunca pisa el TOML).
ck "$(jq -r '[.operations[] | select(.dst=="config.toml") | .op] | .[0] // "no"' "$PLAN")" "diff-only" \
   "el config.toml de Codex va por diff-only (fragmento/diff, NUNCA se pisa)"

# install de los ficheros OWNED (AGENTS + capacidades) preservando lo ajeno.
python3 "$IC" install --root "$CODEX_HOME_T" --plan "$PLAN_ABS" >/dev/null 2>&1
ck "$?" "0" "installer_core instala los OWNED del perfil Codex (install rc0)"
ck "$(sha256sum "$CODEX_HOME_T/config.toml" | cut -d' ' -f1)" "$toml_ajeno_sha" "install: el config.toml AJENO queda byte-identico (no se piso)"
ck "$([ -f "$CODEX_HOME_T/AGENTS.md" ] && echo y || echo n)" "y" "el AGENTS de Codex queda instalado (OWNED)"
ck "$([ -f "$CODEX_HOME_T/profiles/codex-interactive.runtime-capability-v1.json" ] && echo y || echo n)" "y" \
   "la capacidad interactive queda instalada como fichero propio"

# diff del fragmento TOML: NUNCA escribe -> el TOML ajeno queda intacto.
python3 "$IC" diff --root "$CODEX_HOME_T" --plan "$PLAN_ABS" >/dev/null 2>&1
ck "$?" "0" "installer_core diff del perfil Codex (rc0)"
ck "$(sha256sum "$CODEX_HOME_T/config.toml" | cut -d' ' -f1)" "$toml_ajeno_sha" "diff: el config.toml AJENO sigue byte-identico"

# update (reinstall) idempotente: no huerfaniza ni pisa lo ajeno.
python3 "$IC" install --root "$CODEX_HOME_T" --plan "$PLAN_ABS" >/dev/null 2>&1
ck "$?" "0" "reinstall (update) idempotente (rc0)"
ck "$(sha256sum "$CODEX_HOME_T/config.toml" | cut -d' ' -f1)" "$toml_ajeno_sha" "update: el config.toml AJENO sigue byte-identico"

# uninstall: retira SOLO lo propio, preserva el TOML ajeno.
python3 "$IC" uninstall --root "$CODEX_HOME_T" --plan "$PLAN_ABS" >/dev/null 2>&1
ck "$?" "0" "uninstall rc0"
ck "$([ -f "$CODEX_HOME_T/AGENTS.md" ] && echo si || echo no)" "no" "uninstall retira el AGENTS propio"
ck "$([ -f "$CODEX_HOME_T/config.toml" ] && echo si || echo no)" "si" "uninstall PRESERVA el config.toml ajeno del usuario"
ck "$(sha256sum "$CODEX_HOME_T/config.toml" | cut -d' ' -f1)" "$toml_ajeno_sha" "uninstall: el config.toml ajeno queda byte-identico"

# ─────────────────────────────────────────────────────────────────────────────
# 5. M ALONE OWNS AGENTS y S no puede huerfanizarlo: un target ajeno preexistente
#    en la ruta del AGENTS propio NO se pisa (conflicto de propiedad).
# ─────────────────────────────────────────────────────────────────────────────
HOME_C="$T/home_conflicto"; mkdir -p "$HOME_C"
echo "AGENTS ajeno preexistente" > "$HOME_C/AGENTS.md"
ajeno_sha="$(sha256sum "$HOME_C/AGENTS.md" | cut -d' ' -f1)"
python3 "$IC" install --root "$HOME_C" --plan "$PLAN_ABS" >/dev/null 2>&1
ck "$?" "1" "conflicto de propiedad: install rechaza pisar un AGENTS ajeno (rc1)"
ck "$(sha256sum "$HOME_C/AGENTS.md" | cut -d' ' -f1)" "$ajeno_sha" "el AGENTS ajeno queda intacto (no se piso)"

# ─────────────────────────────────────────────────────────────────────────────
# 6. CERT SCRIPT OFFLINE + matriz de fakes: valida el perfil sin red.
# ─────────────────────────────────────────────────────────────────────────────
ck "$([ -x "$CERT" ] && echo y || echo n)" "y" "el script de certificacion offline existe y es ejecutable"
cert_out="$(bash "$CERT" --profile-dir "$RAIZ/kit/lib/profiles" 2>&1)"; cert_rc=$?
ck "$cert_rc" "0" "cert offline pasa sobre el perfil Codex del repo (rc0)"
ck "$(printf '%s' "$cert_out" | grep -c 'profile-certified')" "2" "cert offline reporta las dos superficies profile-certified"
# Fake: un perfil que MIENTE (lifecycle-enforced) DEBE ser rechazado por el cert.
FAKE_DIR="$T/fake_profiles"; mkdir -p "$FAKE_DIR"
cp "$RAIZ/kit/lib/profiles"/codex-*.runtime-capability-v1.json "$FAKE_DIR/" 2>/dev/null
jq '.tier="lifecycle-enforced" | .lifecycle.enforcement="enforced" | .lifecycle.native_stop=true' \
   "$CAP_I" > "$FAKE_DIR/codex-interactive.runtime-capability-v1.json"
cert_fake_rc=0
bash "$CERT" --profile-dir "$FAKE_DIR" >/dev/null 2>&1 || cert_fake_rc=$?
ck "$([ "$cert_fake_rc" -ne 0 ] && echo y || echo n)" "y" \
   "cert offline RECHAZA un perfil Codex que miente (lifecycle-enforced): no se certifica de mas"

# ─────────────────────────────────────────────────────────────────────────────
# 7. AGENTS payload + fragmento TOML son coherentes con Codex (Responses/sandbox).
# ─────────────────────────────────────────────────────────────────────────────
ck "$([ -f "$AGENTS_SRC" ] && echo y || echo n)" "y" "el payload AGENTS.md de Codex existe"
ck "$(grep -qi 'sandbox' "$AGENTS_SRC" && echo y || echo n)" "y" "AGENTS.md menciona el sandbox (read-only)"
ck "$([ -f "$TOML_FRAG" ] && echo y || echo n)" "y" "el fragmento config.toml de Codex existe"
ck "$(grep -qi 'responses\|model_provider\|base_url' "$TOML_FRAG" && echo y || echo n)" "y" \
   "el fragmento TOML declara el provider Responses/base_url (Wave 0 Headroom, opcional)"

# ─────────────────────────────────────────────────────────────────────────────
# 8. Perfil opcional Wave-0 Headroom: DECLARADO y NO CERTIFICADO (no hay login de
#    Codex en esta rama; el plan prohibe simularlo). Debe existir y marcarse como
#    no certificado, honesto.
# ─────────────────────────────────────────────────────────────────────────────
ck "$([ -f "$HEADROOM_OPT" ] && echo y || echo n)" "y" "el perfil opcional Wave-0 Headroom existe (declarado)"
ck "$(jq -r '.certification' "$HEADROOM_OPT")" "not-certified" \
   "el perfil Wave-0 Headroom queda NO CERTIFICADO (sin login de Codex en esta rama)"
ck "$(jq -r '.certification_blocker | length > 0' "$HEADROOM_OPT")" "true" \
   "el perfil Wave-0 Headroom lleva escrito por que no esta certificado"

# ─────────────────────────────────────────────────────────────────────────────
# 9. CERTIFICACION REAL (todo 25) — kit/real-certify-profiles.sh.
#    A diferencia del cert OFFLINE de arriba (que valida los JSON de capacidad
#    sin CLI), este arnes produce el veredicto REAL por modo/tier: congela la
#    identidad del binario (realpath+version+sha256), resuelve el home efimero
#    PROVISTO POR EL DUENO bajo el attemptDir, limpia el proxy Headroom en el
#    HIJO, y solo con un smoke real (canario + flujo) emite PASS. Sin home ->
#    BLOCKED/missing_auth_home. NUNCA PASS sin smoke. Todo con binarios de
#    mentira: el todo 25 prohibe aprovisionar/inspeccionar credenciales reales.
# ─────────────────────────────────────────────────────────────────────────────
RCERT="$RAIZ/kit/real-certify-profiles.sh"
ck "$([ -x "$RCERT" ] && echo y || echo n)" "y" "el arnes de certificacion REAL existe y es ejecutable"

# 9a. Binarios de mentira + attemptDir SIN homes -> todo BLOCKED/missing_auth_home,
#     con identidad congelada, rc 2, y CERO PASS. Es el estado real de esta rama.
RC_T="$T/rcert"; mkdir -p "$RC_T/bin"
cat > "$RC_T/bin/claude"  <<'FAKE'
#!/usr/bin/env bash
echo "PROXY_ANTHROPIC=${ANTHROPIC_BASE_URL:-CLEAN}" >> "${RCERT_CHILD_ENV:-/dev/null}"
echo "9.9.9 (Fake Claude)"
FAKE
cat > "$RC_T/bin/codex"   <<'FAKE'
#!/usr/bin/env bash
echo "codex-cli 9.9.9"
FAKE
cat > "$RC_T/bin/copilot" <<'FAKE'
#!/usr/bin/env bash
echo "GitHub Copilot CLI 9.9.9"
FAKE
chmod +x "$RC_T/bin/claude" "$RC_T/bin/codex" "$RC_T/bin/copilot"

RCERT_CHILD_ENV="$RC_T/childenv.txt"
: > "$RCERT_CHILD_ENV"
# Simula el proxy Headroom en el ENTORNO del test; el arnes debe limpiarlo en el hijo.
out_block="$(RCERT_CHILD_ENV="$RCERT_CHILD_ENV" \
  ANTHROPIC_BASE_URL="http://localhost:8787" \
  COPILOT_PROVIDER_BASE_URL="http://localhost:8787" \
  COPILOT_PROVIDER_TYPE="headroom" \
  bash "$RCERT" --attempt-dir "$RC_T" --bin-dir "$RC_T/bin" --json 2>/dev/null)"
rc_block=$?
ck "$rc_block" "2" "sin home efimero: rc=2 (BLOCKED, cierre global bloqueado honesto)"
n_rows="$(printf '%s' "$out_block" | jq 'length' 2>/dev/null)"
ck "$n_rows" "6" "la matriz normativa produce 6 filas (una por modo/superficie)"
n_blocked="$(printf '%s' "$out_block" | jq '[.[]|select(.verdict=="BLOCKED" and .reason=="missing_auth_home")]|length' 2>/dev/null)"
ck "$n_blocked" "6" "los 6 modos son BLOCKED/missing_auth_home (home efimero ausente)"
n_pass="$(printf '%s' "$out_block" | jq '[.[]|select(.verdict=="PASS")]|length' 2>/dev/null)"
ck "$n_pass" "0" "CERO PASS sin smoke real (nunca se certifica de mas)"
# Identidad congelada: realpath + version + sha256 no vacios en cada fila.
n_frozen="$(printf '%s' "$out_block" | jq '[.[]|select(.binary_realpath!="" and .binary_version!="" and .binary_sha256!="")]|length' 2>/dev/null)"
ck "$n_frozen" "6" "cada fila congela realpath+version+sha256 del binario"
# El proxy Headroom NO debe filtrarse al hijo: la version se leyo con el env limpio.
proxy_leak="$(grep -c 'PROXY_ANTHROPIC=http' "$RCERT_CHILD_ENV" 2>/dev/null)"; proxy_leak="${proxy_leak:-0}"
ck "$proxy_leak" "0" "el proxy Headroom se limpia en el HIJO (identidad = proveedor, no proxy)"

# 9b. DISCRIMINACION: con home efimero provisto + recibo de smoke valido -> PASS;
#     recibo con canario fallido -> FAIL; home poblado sin recibo -> BLOCKED.
#     Prueba que el arnes distingue "certificable" de "certificado" de verdad.
mkdir -p "$RC_T/codex-home" "$RC_T/copilot-home" "$RC_T/claude-home"
# Recibos LIGADOS: el binary_sha256 coincide con el binario de mentira congelado.
sha_codex="$(sha256sum "$(realpath "$RC_T/bin/codex")" | cut -d' ' -f1)"
sha_copilot="$(sha256sum "$(realpath "$RC_T/bin/copilot")" | cut -d' ' -f1)"
printf '{"canary_observed":true,"complete_flow":true,"binary_sha256":"%s"}\n'  "$sha_codex"   > "$RC_T/codex-home/.smoke-receipt.json"
printf '{"canary_observed":false,"complete_flow":true,"binary_sha256":"%s"}\n' "$sha_copilot" > "$RC_T/copilot-home/.smoke-receipt.json"
echo 'auth-placeholder' > "$RC_T/claude-home/config"   # poblado pero sin recibo
out_mix="$(bash "$RCERT" --attempt-dir "$RC_T" --bin-dir "$RC_T/bin" --json 2>/dev/null)"
codex_pass="$(printf '%s' "$out_mix" | jq -r '[.[]|select(.provider=="codex" and .verdict=="PASS")]|length')"
ck "$codex_pass" "2" "con home efimero + recibo canario OK: codex/exec y codex/interactive PASS (smoke real)"
copilot_fail="$(printf '%s' "$out_mix" | jq -r '[.[]|select(.provider=="copilot" and .verdict=="FAIL")]|length')"
ck "$copilot_fail" "2" "recibo con canario fallido: copilot FAIL (no se maquilla a PASS)"
claude_block="$(printf '%s' "$out_mix" | jq -r '[.[]|select(.provider=="claude" and .verdict=="BLOCKED" and .reason=="smoke_not_run")]|length')"
ck "$claude_block" "2" "home poblado sin recibo de smoke: claude BLOCKED/smoke_not_run (nunca PASS por tener home)"

# 9c. Binario ausente -> BLOCKED/missing_binary (motivo EXACTO, no generico).
RC_NB="$T/rcert_nobin"; mkdir -p "$RC_NB/bin"   # bin-dir vacio y PATH minimo sin las CLIs
out_nb="$(PATH=/usr/bin bash "$RCERT" --attempt-dir "$RC_NB" --bin-dir "$RC_NB/bin" --json 2>/dev/null)"
nb_missing="$(printf '%s' "$out_nb" | jq -r '[.[]|select(.verdict=="BLOCKED" and .reason=="missing_binary")]|length' 2>/dev/null)"
ck "$nb_missing" "6" "binario ausente: BLOCKED/missing_binary en los 6 modos (motivo exacto)"

# 9d. LIGADURA DE IDENTIDAD (todo 25 cierre): el recibo de smoke debe ir LIGADO
#     al binario con el que se ejecuto el smoke. Un recibo con canario OK pero un
#     binary_sha256 que NO coincide con la identidad que el arnes acaba de congelar
#     es un recibo FALSIFICADO: NO puede salir PASS. Debe salir
#     BLOCKED/receipt_identity_mismatch. Sin esto, cualquiera certifica los 6 modos
#     escribiendo un JSON a mano, que es justo el fraude que este repo persigue.
RC_ID="$T/rcert_ident"; mkdir -p "$RC_ID/bin" "$RC_ID/codex-home"
cat > "$RC_ID/bin/codex"   <<'FAKE'
#!/usr/bin/env bash
echo "codex-cli 9.9.9"
FAKE
cat > "$RC_ID/bin/claude"  <<'FAKE'
#!/usr/bin/env bash
echo "9.9.9 (Fake Claude)"
FAKE
cat > "$RC_ID/bin/copilot" <<'FAKE'
#!/usr/bin/env bash
echo "GitHub Copilot CLI 9.9.9"
FAKE
chmod +x "$RC_ID/bin/codex" "$RC_ID/bin/claude" "$RC_ID/bin/copilot"
# Recibo con canario OK pero sha256 FORJADO (no es el del binario codex real).
echo '{"canary_observed":true,"complete_flow":true,"binary_sha256":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"}' \
  > "$RC_ID/codex-home/.smoke-receipt.json"
out_id="$(bash "$RCERT" --attempt-dir "$RC_ID" --bin-dir "$RC_ID/bin" --json 2>/dev/null)"
id_pass="$(printf '%s' "$out_id" | jq -r '[.[]|select(.provider=="codex" and .verdict=="PASS")]|length')"
ck "$id_pass" "0" "recibo con sha256 forjado: NUNCA PASS (recibo ligado a la identidad congelada)"
id_mism="$(printf '%s' "$out_id" | jq -r '[.[]|select(.provider=="codex" and .verdict=="BLOCKED" and .reason=="receipt_identity_mismatch")]|length')"
ck "$id_mism" "2" "recibo con sha256 forjado: BLOCKED/receipt_identity_mismatch en codex/exec e interactive"

# 9e. El recibo LEGITIMO (sha256 == el que el arnes congela para ese binario) sigue
#     dando PASS: la ligadura no rompe el camino honesto, solo el falsificado.
RC_OK="$T/rcert_ident_ok"; mkdir -p "$RC_OK/bin" "$RC_OK/codex-home"
cp "$RC_ID/bin/codex" "$RC_OK/bin/codex"
cp "$RC_ID/bin/claude" "$RC_OK/bin/claude"
cp "$RC_ID/bin/copilot" "$RC_OK/bin/copilot"
chmod +x "$RC_OK/bin"/*
real_codex_sha="$(sha256sum "$(realpath "$RC_OK/bin/codex")" | cut -d' ' -f1)"
printf '{"canary_observed":true,"complete_flow":true,"binary_sha256":"%s"}\n' "$real_codex_sha" \
  > "$RC_OK/codex-home/.smoke-receipt.json"
out_ok="$(bash "$RCERT" --attempt-dir "$RC_OK" --bin-dir "$RC_OK/bin" --json 2>/dev/null)"
ok_pass="$(printf '%s' "$out_ok" | jq -r '[.[]|select(.provider=="codex" and .verdict=="PASS")]|length')"
ck "$ok_pass" "2" "recibo con sha256 correcto + canario OK: codex PASS (la ligadura no rompe el camino honesto)"

# 9f. PRODUCTOR: el ejecutor del smoke (kit/smoke-executor.sh) escribe un recibo
#     LIGADO a la identidad del binario, con binarios de mentira y CERO coste. Es el
#     lado productor que faltaba: hoy nadie ESCRIBE un recibo genuino.
SEXEC="$RAIZ/kit/smoke-executor.sh"
ck "$([ -x "$SEXEC" ] && echo y || echo n)" "y" "el ejecutor del smoke (productor del recibo) existe y es ejecutable"
RC_PROD="$T/rcert_prod"; mkdir -p "$RC_PROD/bin" "$RC_PROD/codex-home"
# Binario codex de mentira que emite el canario esperado por su STDOUT (ruta exec).
cat > "$RC_PROD/bin/codex" <<'FAKE'
#!/usr/bin/env bash
# emula `codex exec`: devuelve el token canario que se le pasa en el prompt
for a in "$@"; do :; done
echo "CANARY-OK-$SMOKE_CANARY"
FAKE
chmod +x "$RC_PROD/bin/codex"
# El productor ejecuta el smoke (canario+flujo) y ESCRIBE el recibo ligado.
bash "$SEXEC" --provider codex --surface exec \
  --bin "$RC_PROD/bin/codex" --home "$RC_PROD/codex-home" \
  --timeout 10 --max-turns 1 --max-cost 0 --json >/dev/null 2>&1
prod_rc=$?
ck "$prod_rc" "0" "el productor ejecuta canario+flujo con topes y sale 0 (binario de mentira, coste 0)"
ck "$([ -f "$RC_PROD/codex-home/.smoke-receipt.json" ] && echo y || echo n)" "y" \
   "el productor ESCRIBE el recibo de smoke en el home efimero"
prod_sha="$(jq -r '.binary_sha256' "$RC_PROD/codex-home/.smoke-receipt.json" 2>/dev/null)"
frozen_sha="$(sha256sum "$(realpath "$RC_PROD/bin/codex")" | cut -d' ' -f1)"
ck "$prod_sha" "$frozen_sha" "el recibo LIGA binary_sha256 al binario con el que se ejecuto el smoke"
prod_canary="$(jq -r '.canary_observed' "$RC_PROD/codex-home/.smoke-receipt.json" 2>/dev/null)"
ck "$prod_canary" "true" "el productor sella canary_observed=true solo tras observar el canario"
# El recibo que ESCRIBE el productor es aceptado por el consumidor como PASS.
out_e2e="$(bash "$RCERT" --attempt-dir "$RC_PROD" --bin-dir "$RC_PROD/bin" --json 2>/dev/null)"
e2e_pass="$(printf '%s' "$out_e2e" | jq -r '[.[]|select(.provider=="codex" and .surface=="exec" and .verdict=="PASS")]|length')"
ck "$e2e_pass" "1" "recibo producido por el ejecutor -> consumidor lo certifica PASS (contrato productor-consumidor cerrado)"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
