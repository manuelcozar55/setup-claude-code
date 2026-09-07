#!/usr/bin/env bash
# real-certify-profiles.sh — la CERTIFICACION REAL de proveedores (todo 25).
#
# QUE lo distingue de codex_profile_cert.sh / copilot_profile_cert.sh: aquellos
# son conformidad ESTRUCTURAL OFFLINE (validan los JSON de capacidad contra el
# schema, sin CLI real, sin red). ESTE arnes produce el veredicto REAL por
# modo/tier consumiendo la matriz normativa (los ficheros
# *.runtime-capability-v1.json, una fila por superficie) y, para cada uno:
#
#   1. CONGELA la identidad del binario: realpath + version + sha256. Si el
#      binario no esta -> BLOCKED/missing_binary.
#   2. RESUELVE el home de auth EFIMERO PROVISTO POR EL DUENO bajo el attemptDir
#      (claude-home / codex-home / copilot-home). El plan PROHIBE aprovisionar
#      credenciales o inspeccionarlas: si el home no existe -> BLOCKED con motivo
#      EXACTO (missing_auth_home). NUNCA se lee su contenido.
#   3. LIMPIA en el HIJO las tres variables del proxy Headroom
#      (ANTHROPIC_BASE_URL, COPILOT_PROVIDER_BASE_URL, COPILOT_PROVIDER_TYPE) para
#      que la "resolved provider identity" congelada sea el PROVEEDOR, no el
#      proxy. Nunca toca el entorno del padre ni el servicio del proxy.
#   4. Solo si hay home efimero usable ejecuta el SMOKE real (canary, sandbox
#      read-only, tope de tiempo/turnos/coste). PASS exige canario observado +
#      flujo completo; jamas se emite PASS sin smoke real.
#
# BLOCKED es un veredicto LEGITIMO (la aceptacion dice literal "each mode
# PASS/FAIL/BLOCKED with evidence"). La falta de home/auth/entitlement impide el
# cierre GLOBAL del programa, que es informacion, no un fallo del arnes.
#
# Codigos de salida:
#   0 = todos los modos requeridos PASS
#   1 = al menos un modo FAIL (y ninguno pendiente que lo tape)
#   2 = al menos un modo BLOCKED y ningun FAIL (sin auth/entitlement: cierre
#       global bloqueado, honesto)
#
# Nunca red salvo el smoke real; nunca shell=True; nunca inspecciona credenciales.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PROFILES_DIR="$HERE/lib/profiles"
ATTEMPT_DIR=""
JSON_OUT=""
ISSUE_CHALLENGE=""
# Permite al test inyectar binarios de mentira y un attemptDir temporal sin tocar
# el entorno real. El perfil de produccion no pasa --bin-dir.
BIN_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --attempt-dir) ATTEMPT_DIR="${2:-}"; shift 2 ;;
    --attempt-dir=*) ATTEMPT_DIR="${1#--attempt-dir=}"; shift ;;
    --profiles-dir) PROFILES_DIR="${2:-}"; shift 2 ;;
    --profiles-dir=*) PROFILES_DIR="${1#--profiles-dir=}"; shift ;;
    --bin-dir) BIN_DIR="${2:-}"; shift 2 ;;
    --bin-dir=*) BIN_DIR="${1#--bin-dir=}"; shift ;;
    --issue-challenge) ISSUE_CHALLENGE=1; shift ;;
    --json) JSON_OUT=1; shift ;;
    -h|--help)
      printf 'uso: real-certify-profiles.sh --attempt-dir DIR [--profiles-dir DIR] [--bin-dir DIR] [--issue-challenge] [--json]\n' >&2
      printf '  Certifica REALMENTE cada modo/tier de la matriz normativa. BLOCKED si falta el home efimero.\n' >&2
      printf '  --issue-challenge: emite un desafio fresco e impredecible en cada home efimero y NO certifica.\n' >&2
      exit 0 ;;
    *) shift ;;
  esac
done

[ -n "$ATTEMPT_DIR" ] || { echo "real-certify-profiles: falta --attempt-dir (donde viven los homes efimeros provistos por el dueno)" >&2; exit 2; }
[ -d "$PROFILES_DIR" ] || { echo "real-certify-profiles: --profiles-dir no es un directorio: $PROFILES_DIR" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "real-certify-profiles: jq ausente (se decodifica la matriz normativa con jq)" >&2; exit 2; }

# Mapea provider -> nombre del binario y nombre del home efimero bajo attemptDir.
bin_for() { case "$1" in
  claude) echo claude ;; codex) echo codex ;; copilot) echo copilot ;; *) echo "" ;; esac; }
home_for() { case "$1" in
  claude) echo claude-home ;; codex) echo codex-home ;; copilot) echo copilot-home ;; *) echo "" ;; esac; }

# FRESCURA: el desafio lo emite el CERTIFICADOR, no el productor. binary_sha256 es
# un valor PUBLICO; ligar el recibo a el impide servir el recibo de OTRO binario,
# pero NO prueba que el smoke ocurriera DESPUES de que alguien lo pidiera. El
# desafio es un valor fresco e impredecible por ejecucion que el productor debe
# consumir y sellar; la certificacion exige el desafio VIGENTE. Recibo sin
# desafio -> missing_challenge; recibo con un desafio que no es el vigente ->
# stale_challenge; y el desafio se consume al certificar en verde (un solo uso).
mint_challenge() { head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'; }

# GRANO POR SUPERFICIE: dos superficies del mismo proveedor comparten home
# efimero. Con un unico recibo/desafio por home, la ejecucion de UNA superficie
# certificaba a su hermana: tres ejecuciones del ejecutor devolvian seis PASS, y
# `copilot/interactive` (que exige PTY real) quedaba certificado por un recibo de
# `copilot -p`. El plan certifica *per mode/tier*, asi que recibo y desafio van
# por superficie y cada modo solo se certifica con SU propia evidencia.
chal_file_for()    { printf '%s/.smoke-challenge-%s' "$1" "$2"; }
receipt_file_for() { printf '%s/.smoke-receipt-%s.json' "$1" "$2"; }

if [ -n "$ISSUE_CHALLENGE" ]; then
  for cap in "$PROFILES_DIR"/*.runtime-capability-v1.json; do
    [ -f "$cap" ] || continue
    homename="$(home_for "$(jq -r '.provider' "$cap")")"
    [ -n "$homename" ] || continue
    capsurface="$(jq -r '.surface' "$cap")"
    home="$ATTEMPT_DIR/$homename"
    [ -d "$home" ] || continue
    ch="$(mint_challenge)"
    tmp="$(mktemp "$home/.smoke-challenge.XXXXXX")" || { echo "real-certify-profiles: no pude crear el desafio en $home" >&2; exit 2; }
    printf '%s' "$ch" > "$tmp" && mv -f "$tmp" "$(chal_file_for "$home" "$capsurface")"
  done
  exit 0
fi

# Localiza el binario: --bin-dir tiene prioridad (inyeccion del test), luego PATH.
resolve_bin() {
  local name="$1"
  if [ -n "$BIN_DIR" ] && [ -x "$BIN_DIR/$name" ]; then
    printf '%s' "$BIN_DIR/$name"; return 0
  fi
  command -v "$name" 2>/dev/null
}

# Congela realpath+version+sha256 con el entorno del proxy LIMPIO en el hijo.
freeze_identity() { # bin -> emite "realpath|version|sha256" o vacio si falla
  local bin="$1" rp ver sha
  rp="$(realpath "$bin" 2>/dev/null)" || return 1
  ver="$(env -u ANTHROPIC_BASE_URL -u COPILOT_PROVIDER_BASE_URL -u COPILOT_PROVIDER_TYPE \
         "$bin" --version 2>/dev/null | head -1 | tr -d '|')"
  sha="$(sha256sum "$rp" 2>/dev/null | cut -d' ' -f1)"
  printf '%s|%s|%s' "$rp" "$ver" "$sha"
}

results_json="[]"
any_fail=0; any_blocked=0
passed_challenges=""

emit_row() { # provider surface tier verdict reason realpath version sha256
  results_json="$(printf '%s' "$results_json" | jq \
    --arg p "$1" --arg s "$2" --arg t "$3" --arg v "$4" --arg r "$5" \
    --arg rp "$6" --arg ver "$7" --arg sha "$8" \
    '. + [{provider:$p,surface:$s,tier:$t,verdict:$v,reason:$r,binary_realpath:$rp,binary_version:$ver,binary_sha256:$sha}]')"
}

for cap in "$PROFILES_DIR"/*.runtime-capability-v1.json; do
  [ -f "$cap" ] || continue
  provider="$(jq -r '.provider' "$cap")"
  surface="$(jq -r '.surface' "$cap")"
  tier="$(jq -r '.tier' "$cap")"
  binname="$(bin_for "$provider")"
  homename="$(home_for "$provider")"
  [ -n "$binname" ] || { emit_row "$provider" "$surface" "$tier" "BLOCKED" "unknown_provider" "" "" ""; any_blocked=1; continue; }

  bin="$(resolve_bin "$binname")"
  if [ -z "$bin" ] || [ ! -x "$bin" ]; then
    emit_row "$provider" "$surface" "$tier" "BLOCKED" "missing_binary" "" "" ""
    any_blocked=1; continue
  fi

  ident="$(freeze_identity "$bin")" || ident="||"
  rp="${ident%%|*}"; rest="${ident#*|}"; ver="${rest%%|*}"; sha="${rest#*|}"

  # Home efimero PROVISTO POR EL DUENO. No lo creo yo (el plan lo prohibe).
  home="$ATTEMPT_DIR/$homename"
  if [ ! -d "$home" ]; then
    emit_row "$provider" "$surface" "$tier" "BLOCKED" "missing_auth_home" "$rp" "$ver" "$sha"
    any_blocked=1; continue
  fi

  # A partir de aqui HABRIA smoke real (canary + flujo completo, con el proxy
  # limpio en el hijo y el home efimero como HOME/CODEX_HOME/etc.). El plan
  # prohibe aprovisionar credenciales o inspeccionarlas, asi que sin un home
  # provisto NO se llega aqui. Un home vacio no autentica: el smoke real fallaria
  # el canario -> se traduce a BLOCKED/auth_incomplete, NUNCA a PASS silencioso.
  # No se emite PASS sin canario observado.
  # El propio arnes escribe .smoke-challenge-* en el home al emitir el desafio:
  # si contaran como contenido, su artefacto enmascararia un home sin autenticar.
  home_poblado=0
  for entry in "$home"/* "$home"/.[!.]*; do
    [ -e "$entry" ] || continue
    case "$entry" in *"/.smoke-challenge-"*) continue ;; esac
    home_poblado=1; break
  done
  if [ "$home_poblado" -eq 0 ]; then
    emit_row "$provider" "$surface" "$tier" "BLOCKED" "auth_incomplete" "$rp" "$ver" "$sha"
    any_blocked=1; continue
  fi

  # Home provisto y no vacio: el smoke real lo ejercita el flujo de QA con tope
  # de tiempo/turnos/coste. Este arnes no fabrica un PASS: si el smoke no se ha
  # ejecutado y sellado su canario, el modo queda BLOCKED/smoke_not_run.
  smoke_receipt="$(receipt_file_for "$home" "$surface")"
  if [ ! -f "$smoke_receipt" ]; then
    emit_row "$provider" "$surface" "$tier" "BLOCKED" "smoke_not_run" "$rp" "$ver" "$sha"
    any_blocked=1; continue
  fi
  # Ligadura de identidad: el recibo debe declarar el binary_sha256 del binario
  # con el que se ejecuto el smoke, y tiene que coincidir con la identidad que
  # ACABAMOS de congelar. Un recibo con sha256 divergente esta escrito para OTRO
  # binario (o a mano): es falsificable, y no puede certificar este. Sin esta
  # comprobacion, cualquiera certifica los 6 modos escribiendo un JSON a mano.
  receipt_sha="$(jq -r '.binary_sha256 // ""' "$smoke_receipt" 2>/dev/null)"
  if [ -z "$receipt_sha" ] || [ "$receipt_sha" != "$sha" ]; then
    emit_row "$provider" "$surface" "$tier" "BLOCKED" "receipt_identity_mismatch" "$rp" "$ver" "$sha"
    any_blocked=1; continue
  fi
  # SUPERFICIE: el recibo debe declarar la superficie que se ejecuto, y tiene que
  # ser la de esta fila. La ruta por superficie ya lo separa, pero un recibo
  # COPIADO al nombre de la hermana pasaria: solo la superficie sellada DENTRO lo
  # delata. Motivo propio, no se recicla missing_challenge.
  receipt_surface="$(jq -r '.surface // ""' "$smoke_receipt" 2>/dev/null)"
  if [ "$receipt_surface" != "$surface" ]; then
    emit_row "$provider" "$surface" "$tier" "BLOCKED" "receipt_surface_mismatch" "$rp" "$ver" "$sha"
    any_blocked=1; continue
  fi
  # FRESCURA: el recibo debe sellar el desafio VIGENTE emitido por el certificador
  # (--issue-challenge) en este home. Sin desafio en el recibo -> missing_challenge
  # (recibo de otra ejecucion o escrito a mano con el sha256 publico). Con un
  # desafio que no es el vigente -> stale_challenge (recibo rancio, o anterior al
  # desafio en curso). Ambos son BLOCKED con motivo PROPIO, nunca PASS.
  chal_file="$(chal_file_for "$home" "$surface")"
  current_chal="$(cat "$chal_file" 2>/dev/null)"
  receipt_chal="$(jq -r '.challenge // ""' "$smoke_receipt" 2>/dev/null)"
  if [ -z "$receipt_chal" ] || [ -z "$current_chal" ]; then
    emit_row "$provider" "$surface" "$tier" "BLOCKED" "missing_challenge" "$rp" "$ver" "$sha"
    any_blocked=1; continue
  fi
  if [ "$receipt_chal" != "$current_chal" ]; then
    emit_row "$provider" "$surface" "$tier" "BLOCKED" "stale_challenge" "$rp" "$ver" "$sha"
    any_blocked=1; continue
  fi
  # Recibo de smoke presente, LIGADO y FRESCO: exige canario observado y flujo.
  canary_ok="$(jq -r '.canary_observed // false' "$smoke_receipt" 2>/dev/null)"
  flow_ok="$(jq -r '.complete_flow // false' "$smoke_receipt" 2>/dev/null)"
  if [ "$canary_ok" = "true" ] && [ "$flow_ok" = "true" ]; then
    emit_row "$provider" "$surface" "$tier" "PASS" "real_smoke_ok" "$rp" "$ver" "$sha"
    passed_challenges="$passed_challenges $chal_file"
  else
    emit_row "$provider" "$surface" "$tier" "FAIL" "canary_or_flow_failed" "$rp" "$ver" "$sha"
    any_fail=1
  fi
done

# UN SOLO USO: el desafio que produjo un PASS se consume aqui, tras cerrar el
# bucle. Es el desafio de ESA superficie: gastar el de una no toca el de su
# hermana. Recertificar sin re-emitir y re-ejecutar el smoke vuelve a caer en
# missing_challenge, nunca en un segundo PASS.
for cf in $passed_challenges; do rm -f "$cf" 2>/dev/null; done

if [ "$JSON_OUT" = 1 ]; then
  printf '%s\n' "$results_json" | jq '.'
else
  printf '%s\n' "$results_json" | jq -r '.[] | "\(.provider)/\(.surface) [\(.tier)] -> \(.verdict) (\(.reason))"'
fi

# rc cerrado: FAIL manda sobre BLOCKED; BLOCKED sobre PASS-only.
if [ "$any_fail" = 1 ]; then exit 1; fi
if [ "$any_blocked" = 1 ]; then exit 2; fi
exit 0
