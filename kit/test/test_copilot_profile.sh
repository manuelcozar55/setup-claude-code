#!/usr/bin/env bash
# test_copilot_profile.sh — el perfil nativo de Copilot para modo INTERACTIVO
# (PTY) y modo PROMPT (`-p`), con LIMITES DE CICLO DE VIDA HONESTOS acotados por
# el TOPE DE 8 BLOQUEOS (todo 22).
#
# QUE lo distingue del perfil de Codex (test_codex_profile.sh, que NO se toca):
# Codex no expone hard-stop nativo, asi que va degradado sin tope. Copilot SI
# tiene un enforcement nativo de `agentStop`/`subagentStop` — pero ACOTADO: tras
# OCHO respuestas de bloqueo consecutivas Copilot FUERZA la parada pase lo que
# pase. Por eso el ciclo de vida de Copilot se declara `degraded` con `block_cap`
# = 8, y NUNCA lifecycle-enforced (el plan solo lo permitiria con un "separately
# approved outer runner" que aqui NO existe). Este test ancla, caso por caso,
# cada clausula del "What/Must NOT" y del "Acceptance/QA" del todo 22:
#
#   - DOS SUPERFICIES SEPARADAS: interactive (PTY) y `-p` (prompt), con arneses
#     distintos. Nunca se asume que el binario `copilot` exista.
#   - CUATRO COMPORTAMIENTOS del gate acotado, no tres: (1) verde -> allow;
#     (2) bloqueos 1..8; (3) el ciclo siguiente AGOTA el tope y se observa la
#     parada forzada; (4) el contador se RESETEA.
#   - GATE MANUAL explicito pre/post ademas del gate nativo: bloquea y permite
#     por su cuenta contra el productor REAL del gate v2 de M.
#   - AGENTS/instruccion nativa OWNED por M; S no la huerfaniza.
#   - hooks/extensions/MCP con trust-gate.
#   - SIN BINARIO/AUTH: missing_binary / BLOCKED_CERTIFICATION, jamas un salto ni
#     un verde. Prohibido copiar credenciales de GitHub.
#   - CERT SCRIPT OFFLINE que RECHAZA un perfil que mienta lifecycle-enforced.
#   - LIGADURA AL TODO 9: contrato consumido fija evidence_schema y version
#     minima del productor; ausente/futuro BLOQUEA.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; RAIZ="$(cd "$HERE/../.." && pwd)"
GATE="$RAIZ/kit/lib/copilot_manual_gate.sh"
CAP_GATE="$RAIZ/kit/lib/copilot_lifecycle_gate.sh"
CERT="$RAIZ/kit/lib/copilot_profile_cert.sh"
HARNESS="$RAIZ/kit/lib/copilot_stop_harness.sh"
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
CAP_I="$RAIZ/kit/lib/profiles/copilot-interactive.runtime-capability-v1.json"
CAP_P="$RAIZ/kit/lib/profiles/copilot-prompt.runtime-capability-v1.json"
PLAN="$RAIZ/kit/lib/profiles/copilot.installer-core-plan-v1.json"
CONTRACT="$RAIZ/kit/lib/profiles/copilot-manual-gate.consumed-contract-v1.json"
INSTR_SRC="$RAIZ/kit/lib/profiles/copilot-instructions.md"
HOOKS_SRC="$RAIZ/kit/lib/profiles/copilot-hooks.json"

# ─────────────────────────────────────────────────────────────────────────────
# 1. LAS DOS CAPACIDADES: tier profile-certified, lifecycle DEGRADADO con
#    block_cap=8. El plan obliga a modelar el tope de 8 como bounded enforcement:
#    degraded, NUNCA lifecycle-enforced.
# ─────────────────────────────────────────────────────────────────────────────
ck "$(python3 "$PC" validate --capability "$CAP_I" >/dev/null 2>&1 && echo ok || echo no)" "ok" \
   "capacidad copilot interactive valida contra el schema v1 real"
ck "$(python3 "$PC" validate --capability "$CAP_P" >/dev/null 2>&1 && echo ok || echo no)" "ok" \
   "capacidad copilot prompt (-p) valida contra el schema v1 real"
ck "$(jq -r '.provider' "$CAP_I")" "copilot" "interactive: provider copilot"
ck "$(jq -r '.surface' "$CAP_I")" "interactive" "interactive: surface interactive (PTY)"
ck "$(jq -r '.tier' "$CAP_I")" "profile-certified" "interactive: tier profile-certified (NUNCA lifecycle-enforced)"
ck "$(jq -r '.modes[]' "$CAP_I")" "interactive" "interactive: modo interactive"
ck "$(jq -r '.lifecycle.native_stop' "$CAP_I")" "true" "interactive: agentStop nativo existe (pero acotado)"
ck "$(jq -r '.lifecycle.enforcement' "$CAP_I")" "degraded" "interactive: enforcement DEGRADADO por el tope de 8"
ck "$(jq -r '.lifecycle.block_cap' "$CAP_I")" "8" "interactive: block_cap=8 (bounded enforcement escrito)"
ck "$(jq -r '.surface' "$CAP_P")" "prompt" "prompt: surface prompt (-p)"
ck "$(jq -r '.modes[]' "$CAP_P")" "non-interactive" "prompt: modo non-interactive"
ck "$(jq -r '.tier' "$CAP_P")" "profile-certified" "prompt: tier profile-certified"
ck "$(jq -r '.lifecycle.enforcement' "$CAP_P")" "degraded" "prompt: enforcement DEGRADADO por el tope de 8"
ck "$(jq -r '.lifecycle.block_cap' "$CAP_P")" "8" "prompt: block_cap=8"
# Falsabilidad: NINGUNA de las dos declara lifecycle-enforced.
ck "$(jq -r 'select(.tier=="lifecycle-enforced") | .surface' "$CAP_I" "$CAP_P" 2>/dev/null | wc -l | tr -d ' ')" "0" \
   "falsabilidad: ninguna superficie de Copilot se declara lifecycle-enforced"
ck "$(jq -r '.degraded_reason | test("8")' "$CONTRACT")" "true" "el degradado de Copilot cita el tope de 8 (motivo escrito)"

# ─────────────────────────────────────────────────────────────────────────────
# 2. GATE DE CICLO DE VIDA ACOTADO — CUATRO comportamientos, no tres. El arnes
#    (copilot_lifecycle_gate.sh) modela agentStop/subagentStop: emite block hasta
#    el tope y a partir de ahi FUERZA la parada. Contador persistente por sesion.
# ─────────────────────────────────────────────────────────────────────────────
CNT="$T/blockcount"
# (1) VERDE -> allow y RESET del contador (el turno cerro limpio).
printf '5' > "$CNT"   # habia 5 bloqueos acumulados
out_v="$(COPILOT_BLOCK_STATE="$CNT" bash "$CAP_GATE" --verdict green 2>/dev/null)"
ck "$(printf '%s' "$out_v" | jq -r '.decision')" "allow" "cap gate: verdict verde -> allow"
ck "$(cat "$CNT")" "0" "cap gate: verde RESETEA el contador a 0 (comportamiento 4)"

# (2) BLOQUEOS 1..8: cada rojo incrementa y emite block mientras no se agote.
printf '0' > "$CNT"
for i in $(seq 1 8); do
  o="$(COPILOT_BLOCK_STATE="$CNT" bash "$CAP_GATE" --verdict red 2>/dev/null)"
  d="$(printf '%s' "$o" | jq -r '.decision')"
  ck "$d" "block" "cap gate: bloqueo $i/8 -> block (enforcement activo)"
done
ck "$(cat "$CNT")" "8" "cap gate: tras 8 rojos el contador esta en el tope"

# (3) EL CICLO SIGUIENTE AGOTA EL TOPE -> parada forzada (ya no bloquea: 'stop').
o9="$(COPILOT_BLOCK_STATE="$CNT" bash "$CAP_GATE" --verdict red 2>/dev/null)"
ck "$(printf '%s' "$o9" | jq -r '.decision')" "stop" "cap gate: 9.o ciclo AGOTA el tope y FUERZA la parada (comportamiento 3)"
ck "$(printf '%s' "$o9" | jq -r '.forced')" "true" "cap gate: la parada del 9.o ciclo se marca forzada (degradado, honesto)"

# (4) RESET explicito: tras la parada forzada, un verde vuelve a 0.
o_reset="$(COPILOT_BLOCK_STATE="$CNT" bash "$CAP_GATE" --verdict green 2>/dev/null)"
ck "$(printf '%s' "$o_reset" | jq -r '.decision')" "allow" "cap gate: verde tras la parada forzada -> allow"
ck "$(cat "$CNT")" "0" "cap gate: el contador se RESETEA tras el verde (comportamiento 4, tras agotar)"

# ─────────────────────────────────────────────────────────────────────────────
# 3. ARNES PTY (interactivo) y `-p` (prompt): dos superficies distintas. El arnes
#    ejerce el gate de ciclo de vida en cada modo con un `copilot` de MENTIRA
#    (nunca el real: "No binary/auth assumption").
# ─────────────────────────────────────────────────────────────────────────────
# fake copilot: en -p imprime una respuesta; el arnes NO le pasa el binario real.
cat > "$T/bin/copilot" <<'EOF'
#!/usr/bin/env bash
# fake copilot para el arnes: jamas toca red ni credenciales.
echo '{"role":"assistant","content":"fake turn"}'
exit 0
EOF
chmod +x "$T/bin/copilot"

ck "$([ -x "$HARNESS" ] && echo y || echo n)" "y" "el arnes de parada de Copilot existe y es ejecutable"
# -p (prompt): un turno con veredicto verde -> allow.
hp_green="$(COPILOT_BLOCK_STATE="$T/hp1" COPILOT_FAKE_VERDICT=green bash "$HARNESS" --mode prompt --copilot "$T/bin/copilot" 2>/dev/null)"
ck "$(decision "$hp_green")" "allow" "arnes -p: turno verde -> allow"
# -p: rojo -> block (dentro del tope).
hp_red="$(COPILOT_BLOCK_STATE="$T/hp2" COPILOT_FAKE_VERDICT=red bash "$HARNESS" --mode prompt --copilot "$T/bin/copilot" 2>/dev/null)"
ck "$(decision "$hp_red")" "block" "arnes -p: turno rojo -> block (bloqueo 1/8)"
# PTY (interactive): mismo gate, superficie distinta. Debe existir la rama pty.
hi_green="$(COPILOT_BLOCK_STATE="$T/hi1" COPILOT_FAKE_VERDICT=green bash "$HARNESS" --mode interactive --copilot "$T/bin/copilot" 2>/dev/null)"
ck "$(decision "$hi_green")" "allow" "arnes PTY interactivo: turno verde -> allow"
# PTY: cap-exhaustion observable tambien por el arnes.
printf '8' > "$T/hi_cap"
hi_forced="$(COPILOT_BLOCK_STATE="$T/hi_cap" COPILOT_FAKE_VERDICT=red bash "$HARNESS" --mode interactive --copilot "$T/bin/copilot" 2>/dev/null)"
ck "$(decision "$hi_forced")" "stop" "arnes PTY: con el contador en 8, el rojo AGOTA el tope y fuerza la parada"

# SIN BINARIO: el arnes debe reportar missing_binary / BLOCKED, jamas allow ni skip.
hmiss="$(COPILOT_BLOCK_STATE="$T/hm" bash "$HARNESS" --mode prompt --copilot "$T/bin/no_existe_copilot" 2>/dev/null)"
ck "$(printf '%s' "$hmiss" | jq -r '.decision')" "block" "arnes sin binario copilot -> block (nunca allow ni skip)"
ck "$(printf '%s' "$hmiss" | jq -r '.reason')" "missing_binary" "arnes sin binario -> reason=missing_binary (honesto)"

# ─────────────────────────────────────────────────────────────────────────────
# 4. GATE MANUAL contra el productor REAL de M: proyecto NO gobernado -> rc3 ->
#    la puerta manual PERMITE. Y NUNCA cae a un `mch` del PATH.
# ─────────────────────────────────────────────────────────────────────────────
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

rm -f "$T/centinela_trampa"
sin_ruta="$( (cd "$T/ungoverned" && env PATH="$T/bin:$PATH" bash "$GATE") 2>/dev/null )"
ck "$(decision "$sin_ruta")" "block" "gate manual sin ruta de confianza: BLOQUEA"
ck "$(decision "$( (cd "$T/ungoverned" && CCKIT_MCH_BRIDGE_PATH="bin/mch" env PATH="$T/bin:$PATH" bash "$GATE") 2>/dev/null )")" "block" \
   "gate manual ruta relativa: BLOQUEA (solo absoluta)"

# ─────────────────────────────────────────────────────────────────────────────
# 5. Matriz de fakes del gate manual (SOLO caminos de fallo via --mch).
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

# stdin ABIERTO: gate MANUAL, invocado a mano -> debe decidir en tiempo acotado.
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

# Ligadura al todo 9: esquema + version minima embebidos EXACTOS.
ck "$(jq -r '.evidence_schema' "$CONTRACT")" "mch-gate-evidence-v2" "contrato consumido fija el evidence_schema del gate v2"
ck "$(jq -r '.min_producer_version' "$CONTRACT")" "0.2.0" "contrato consumido fija la version minima del productor"
ck "$(grep -c 'mch-gate-evidence-v2' "$GATE")" "1" "el gate embebe el evidence_schema fijado"
ck "$(grep -cE 'MIN_MAJOR=0; MIN_MINOR=2; MIN_PATCH=0' "$GATE")" "1" "el gate embebe la version minima 0.2.0"

# ─────────────────────────────────────────────────────────────────────────────
# 6. AISLAMIENTO: install/diff/uninstall contra un COPILOT_HOME temporal, con
#    bytes AJENOS -> deben sobrevivir byte a byte. La instruccion nativa es OWNED.
# ─────────────────────────────────────────────────────────────────────────────
COPILOT_HOME_T="$T/copilot_home"; mkdir -p "$COPILOT_HOME_T"
cat > "$COPILOT_HOME_T/config.json" <<'EOF'
{ "personal": "intocable", "theme": "dark" }
EOF
config_ajeno_sha="$(sha256sum "$COPILOT_HOME_T/config.json" | cut -d' ' -f1)"

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
ck "$([ -s "$PLAN_ABS" ] && echo y || echo n)" "y" "plan de Copilot resuelto a rutas absolutas + content inline"

python3 "$IC" install --root "$COPILOT_HOME_T" --plan "$PLAN_ABS" >/dev/null 2>&1
ck "$?" "0" "installer_core instala los OWNED del perfil Copilot (install rc0)"
ck "$(sha256sum "$COPILOT_HOME_T/config.json" | cut -d' ' -f1)" "$config_ajeno_sha" "install: el config.json AJENO queda byte-identico (no se piso)"
ck "$([ -f "$COPILOT_HOME_T/copilot-instructions.md" ] && echo y || echo n)" "y" "la instruccion nativa de Copilot queda instalada (OWNED)"
ck "$([ -f "$COPILOT_HOME_T/profiles/copilot-interactive.runtime-capability-v1.json" ] && echo y || echo n)" "y" \
   "la capacidad interactive queda instalada como fichero propio"

python3 "$IC" install --root "$COPILOT_HOME_T" --plan "$PLAN_ABS" >/dev/null 2>&1
ck "$?" "0" "reinstall (update) idempotente (rc0)"
ck "$(sha256sum "$COPILOT_HOME_T/config.json" | cut -d' ' -f1)" "$config_ajeno_sha" "update: el config.json AJENO sigue byte-identico"

python3 "$IC" uninstall --root "$COPILOT_HOME_T" --plan "$PLAN_ABS" >/dev/null 2>&1
ck "$?" "0" "uninstall rc0"
ck "$([ -f "$COPILOT_HOME_T/copilot-instructions.md" ] && echo si || echo no)" "no" "uninstall retira la instruccion propia"
ck "$([ -f "$COPILOT_HOME_T/config.json" ] && echo si || echo no)" "si" "uninstall PRESERVA el config.json ajeno del usuario"
ck "$(sha256sum "$COPILOT_HOME_T/config.json" | cut -d' ' -f1)" "$config_ajeno_sha" "uninstall: el config.json ajeno queda byte-identico"

# ─────────────────────────────────────────────────────────────────────────────
# 7. M ALONE OWNS la instruccion: S no puede huerfanizarla. Target ajeno
#    preexistente NO se pisa (conflicto de propiedad).
# ─────────────────────────────────────────────────────────────────────────────
HOME_C="$T/home_conflicto"; mkdir -p "$HOME_C"
echo "instruccion ajena preexistente" > "$HOME_C/copilot-instructions.md"
ajeno_sha="$(sha256sum "$HOME_C/copilot-instructions.md" | cut -d' ' -f1)"
python3 "$IC" install --root "$HOME_C" --plan "$PLAN_ABS" >/dev/null 2>&1
ck "$?" "1" "conflicto de propiedad: install rechaza pisar una instruccion ajena (rc1)"
ck "$(sha256sum "$HOME_C/copilot-instructions.md" | cut -d' ' -f1)" "$ajeno_sha" "la instruccion ajena queda intacta (no se piso)"

# ─────────────────────────────────────────────────────────────────────────────
# 8. CERT SCRIPT OFFLINE + matriz de fakes: valida el perfil sin red. RECHAZA un
#    perfil que MIENTA declarandose lifecycle-enforced.
# ─────────────────────────────────────────────────────────────────────────────
ck "$([ -x "$CERT" ] && echo y || echo n)" "y" "el script de certificacion offline existe y es ejecutable"
cert_out="$(bash "$CERT" --profile-dir "$RAIZ/kit/lib/profiles" 2>&1)"; cert_rc=$?
ck "$cert_rc" "0" "cert offline pasa sobre el perfil Copilot del repo (rc0)"
ck "$(printf '%s' "$cert_out" | grep -c 'profile-certified')" "2" "cert offline reporta las dos superficies profile-certified"
ck "$(printf '%s' "$cert_out" | grep -c 'block_cap=8')" "2" "cert offline confirma el tope de 8 en ambas superficies"
FAKE_DIR="$T/fake_profiles"; mkdir -p "$FAKE_DIR"
cp "$RAIZ/kit/lib/profiles"/copilot-*.runtime-capability-v1.json "$FAKE_DIR/" 2>/dev/null
jq '.tier="lifecycle-enforced" | .lifecycle.enforcement="enforced" | .lifecycle.block_cap=null' \
   "$CAP_I" > "$FAKE_DIR/copilot-interactive.runtime-capability-v1.json"
cert_fake_rc=0
bash "$CERT" --profile-dir "$FAKE_DIR" >/dev/null 2>&1 || cert_fake_rc=$?
ck "$([ "$cert_fake_rc" -ne 0 ] && echo y || echo n)" "y" \
   "cert offline RECHAZA un perfil Copilot que miente (lifecycle-enforced): no se certifica de mas"

# ─────────────────────────────────────────────────────────────────────────────
# 9. INSTRUCCION nativa + hooks/extensions/MCP trust-gated coherentes.
# ─────────────────────────────────────────────────────────────────────────────
ck "$([ -f "$INSTR_SRC" ] && echo y || echo n)" "y" "el payload de instruccion nativa de Copilot existe"
ck "$(grep -qi 'trust\|confian' "$INSTR_SRC" && echo y || echo n)" "y" "la instruccion menciona el trust-gate de hooks/extensions/MCP"
ck "$(grep -qi '8 ' "$INSTR_SRC" && echo y || echo n)" "y" "la instruccion documenta el tope de 8 bloqueos (ciclo de vida degradado)"
ck "$([ -f "$HOOKS_SRC" ] && echo y || echo n)" "y" "el fichero de hooks trust-gated de Copilot existe"
ck "$(jq -r '.version' "$HOOKS_SRC")" "1" "los hooks declaran version 1 (formato oficial de Copilot)"
ck "$(jq -e '.hooks.agentStop' "$HOOKS_SRC" >/dev/null 2>&1 && echo y || echo n)" "y" "los hooks cablean agentStop (ciclo de vida acotado)"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
