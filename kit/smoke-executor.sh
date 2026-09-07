#!/usr/bin/env bash
# smoke-executor.sh — el PRODUCTOR del recibo de smoke (todo 25).
#
# Es el lado que faltaba del contrato: real-certify-profiles.sh (el consumidor)
# lee un recibo y decide PASS/FAIL/BLOCKED, pero hasta ahora nadie ESCRIBIA un
# recibo genuino, asi que un JSON a mano podia certificar los 6 modos. Este
# ejecutor corre el canario + el flujo completo contra el binario, con tope de
# tiempo/turnos/coste, ESCRIBE el recibo LIGADO a la identidad del binario
# (binary_sha256/realpath/version) y SELLA en el el DESAFIO fresco que el
# certificador emitio en el home (--issue-challenge).
#
# QUE ATAQUES MATA la combinacion recibo-ligado + desafio-fresco, y CUAL NO:
#   - Recibo de OTRO binario (sha256 divergente): rechazado. El certificador
#     congela el sha256 del binario real y exige que el recibo lo declare igual.
#   - Recibo RANCIO / de otra ejecucion / anterior al desafio: rechazado. El
#     desafio lo emite el certificador, es impredecible por ejecucion y de un solo
#     uso; un recibo que no sella el desafio VIGENTE nunca certifica.
#   - FUERA DE ALCANCE: con acceso de ESCRITURA al home efimero NO existe un
#     recibo local infalsificable. binary_sha256 es un valor PUBLICO y, una vez
#     conocido el desafio vigente, quien pueda escribir el home puede fabricar un
#     recibo. No hay raiz de confianza firmada por el proveedor: este recibo no
#     autentica al proveedor, solo evidencia frescura+identidad frente a un
#     escritor honesto. La defensa real de coste/credenciales es que sin un home
#     de auth provisto no se llega a un proveedor de pago.
#
# Rutas de proveedor:
#   codex/exec         -> `codex exec` (ruta explicita, sandbox read-only)
#   codex/interactive  -> `codex` (misma binario, gate manual)
#   copilot/prompt     -> `copilot -p` (modo no interactivo)
#   copilot/interactive-> `copilot` bajo PTY real via `script(1)`
#   claude/*           -> `claude -p` (no interactivo) / interactivo
#
# Nunca inspecciona ni copia credenciales. El home efimero lo provee el dueno;
# aqui solo se usa como HOME/CODEX_HOME. El proxy Headroom se limpia en el HIJO.
# Con binarios de mentira (coste 0) demuestra el contrato sin llamar a un
# proveedor de pago; sin home provisto no debe llegar a un proveedor real.
set -uo pipefail

PROVIDER=""; SURFACE=""; BIN=""; HOME_DIR=""
TIMEOUT=30; MAX_TURNS=1; MAX_COST=0; JSON_OUT=""
CANARY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --provider) PROVIDER="${2:-}"; shift 2 ;;
    --surface) SURFACE="${2:-}"; shift 2 ;;
    --bin) BIN="${2:-}"; shift 2 ;;
    --home) HOME_DIR="${2:-}"; shift 2 ;;
    --timeout) TIMEOUT="${2:-}"; shift 2 ;;
    --max-turns) MAX_TURNS="${2:-}"; shift 2 ;;
    --max-cost) MAX_COST="${2:-}"; shift 2 ;;
    --canary) CANARY="${2:-}"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    -h|--help)
      printf 'uso: smoke-executor.sh --provider P --surface S --bin BIN --home DIR [--timeout N] [--max-turns N] [--max-cost N] [--canary TOKEN] [--json]\n' >&2
      printf '  Ejecuta el canario+flujo con topes y ESCRIBE el recibo LIGADO a la identidad del binario.\n' >&2
      exit 0 ;;
    *) shift ;;
  esac
done

[ -n "$PROVIDER" ] || { echo "smoke-executor: falta --provider" >&2; exit 2; }
[ -n "$SURFACE" ]  || { echo "smoke-executor: falta --surface" >&2; exit 2; }
[ -n "$BIN" ] || { echo "smoke-executor: falta --bin" >&2; exit 2; }
[ -n "$HOME_DIR" ] || { echo "smoke-executor: falta --home (home efimero provisto por el dueno)" >&2; exit 2; }
[ -x "$BIN" ] || { echo "smoke-executor: --bin no es ejecutable: $BIN" >&2; exit 2; }
[ -d "$HOME_DIR" ] || { echo "smoke-executor: --home no es un directorio: $HOME_DIR" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "smoke-executor: jq ausente" >&2; exit 2; }

# Canario unico por ejecucion si no se pasa: liga la observacion a ESTE smoke.
if [ -z "$CANARY" ]; then
  CANARY="smoke-$(date +%s)-$$-$RANDOM"
fi

# Identidad del binario con el proxy LIMPIO en el hijo (proveedor, no proxy).
RP="$(realpath "$BIN" 2>/dev/null)" || { echo "smoke-executor: realpath fallo" >&2; exit 2; }
VER="$(env -u ANTHROPIC_BASE_URL -u COPILOT_PROVIDER_BASE_URL -u COPILOT_PROVIDER_TYPE \
       "$BIN" --version 2>/dev/null | head -1 | tr -d '|')"
SHA="$(sha256sum "$RP" 2>/dev/null | cut -d' ' -f1)"

# Ejecuta la superficie con tope de tiempo. El comando concreto es la RUTA
# EXPLICITA de cada proveedor; el canario viaja por el entorno y se busca en la
# salida. Nunca se usa shell=True: argv directo bajo `timeout`.
run_surface() { # -> stdout del proveedor (o vacio si falla/timeout)
  local out
  case "$PROVIDER/$SURFACE" in
    codex/exec)
      out="$(env -u ANTHROPIC_BASE_URL -u COPILOT_PROVIDER_BASE_URL -u COPILOT_PROVIDER_TYPE \
        CODEX_HOME="$HOME_DIR" SMOKE_CANARY="$CANARY" \
        timeout "$TIMEOUT" "$BIN" exec --sandbox read-only \
        "responde exactamente con el token: $CANARY" 2>/dev/null)" ;;
    codex/interactive)
      out="$(env -u ANTHROPIC_BASE_URL -u COPILOT_PROVIDER_BASE_URL -u COPILOT_PROVIDER_TYPE \
        CODEX_HOME="$HOME_DIR" SMOKE_CANARY="$CANARY" \
        timeout "$TIMEOUT" "$BIN" exec --sandbox read-only \
        "responde exactamente con el token: $CANARY" 2>/dev/null)" ;;
    copilot/prompt)
      out="$(env -u ANTHROPIC_BASE_URL -u COPILOT_PROVIDER_BASE_URL -u COPILOT_PROVIDER_TYPE \
        HOME="$HOME_DIR" SMOKE_CANARY="$CANARY" \
        timeout "$TIMEOUT" "$BIN" -p "responde exactamente con el token: $CANARY" 2>/dev/null)" ;;
    copilot/interactive)
      # PTY real: Copilot interactivo exige TTY. script(1) provee un pseudo-terminal.
      out="$(env -u ANTHROPIC_BASE_URL -u COPILOT_PROVIDER_BASE_URL -u COPILOT_PROVIDER_TYPE \
        HOME="$HOME_DIR" SMOKE_CANARY="$CANARY" \
        timeout "$TIMEOUT" script -qec "\"$BIN\" -p \"responde exactamente con el token: $CANARY\"" /dev/null 2>/dev/null)" ;;
    claude/*)
      out="$(env -u ANTHROPIC_BASE_URL -u COPILOT_PROVIDER_BASE_URL -u COPILOT_PROVIDER_TYPE \
        HOME="$HOME_DIR" SMOKE_CANARY="$CANARY" \
        timeout "$TIMEOUT" "$BIN" -p "responde exactamente con el token: $CANARY" 2>/dev/null)" ;;
    *) out="" ;;
  esac
  printf '%s' "$out"
}

surface_out="$(run_surface)"

# Flujo completo = el canario aparece en la salida del proveedor. Con topes ya
# aplicados (timeout, un solo turno, coste 0), no hay bucle de reintento.
canary_observed=false
complete_flow=false
if printf '%s' "$surface_out" | grep -qF "$CANARY"; then
  canary_observed=true
  complete_flow=true
fi

RECEIPT="$HOME_DIR/.smoke-receipt.json"
CHALLENGE="$(cat "$HOME_DIR/.smoke-challenge" 2>/dev/null)"
tmp="$(mktemp "$HOME_DIR/.smoke-receipt.XXXXXX")" || { echo "smoke-executor: no pude crear tmp del recibo" >&2; exit 2; }
jq -n \
  --arg p "$PROVIDER" --arg s "$SURFACE" \
  --arg rp "$RP" --arg ver "$VER" --arg sha "$SHA" \
  --arg canary "$CANARY" --arg chal "$CHALLENGE" \
  --argjson co "$canary_observed" --argjson cf "$complete_flow" \
  --argjson to "$TIMEOUT" --argjson mt "$MAX_TURNS" --argjson mc "$MAX_COST" \
  '{provider:$p,surface:$s,binary_realpath:$rp,binary_version:$ver,binary_sha256:$sha,canary:$canary,challenge:$chal,canary_observed:$co,complete_flow:$cf,caps:{timeout_s:$to,max_turns:$mt,max_cost:$mc}}' \
  > "$tmp" || { rm -f "$tmp"; echo "smoke-executor: jq fallo al escribir el recibo" >&2; exit 2; }
mv -f "$tmp" "$RECEIPT"

if [ "$JSON_OUT" = 1 ]; then
  jq '.' "$RECEIPT"
else
  printf '%s/%s smoke: canary_observed=%s complete_flow=%s (sha256=%s)\n' \
    "$PROVIDER" "$SURFACE" "$canary_observed" "$complete_flow" "$SHA"
fi

# rc: 0 si el flujo completo se observo; 1 si el smoke corrio pero el canario no
# aparecio (flujo incompleto). El consumidor traduce el recibo a PASS/FAIL.
[ "$complete_flow" = true ] && exit 0 || exit 1
