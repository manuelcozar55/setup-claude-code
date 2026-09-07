#!/usr/bin/env bash
# copilot_profile_cert.sh — certificacion OFFLINE del perfil nativo de Copilot
# (todo 22). Sin red, sin CLI de Copilot, sin credenciales de GitHub.
#
# QUE HACE: valida que las capacidades de Copilot del perfil son ESTRUCTURALMENTE
# coherentes con lo que el plan exige y con la matriz normativa:
#   - las dos superficies (interactive PTY, prompt -p) validan contra el schema v1
#     real de M (profile_coordinator validate);
#   - ambas son profile-certified (NUNCA lifecycle-enforced) con lifecycle
#     degradado y block_cap=8 -> RECHAZA cualquier perfil de Copilot que mienta
#     declarandose lifecycle-enforced o borrando el tope de 8;
#   - reporta por stdout las dos superficies certificadas con su block_cap.
#
# NO es la certificacion REAL (esa exige el smoke autenticado del todo 25, con
# PTY+`-p` reales). Es la conformidad estructural offline que el todo 22 pide.
# rc0 si todas las capacidades de Copilot del directorio pasan; rc!=0 si alguna
# miente o no valida.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PC="$HERE/profile_coordinator.py"
PROFILE_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --profile-dir) PROFILE_DIR="${2:-}"; shift 2 ;;
    --profile-dir=*) PROFILE_DIR="${1#--profile-dir=}"; shift ;;
    -h|--help) printf 'uso: copilot_profile_cert.sh --profile-dir DIR\n' >&2; exit 0 ;;
    *) shift ;;
  esac
done
[ -n "$PROFILE_DIR" ] || { echo "copilot_profile_cert: falta --profile-dir" >&2; exit 2; }
[ -d "$PROFILE_DIR" ] || { echo "copilot_profile_cert: no es un directorio: $PROFILE_DIR" >&2; exit 2; }
if ! command -v jq >/dev/null 2>&1; then
  echo "copilot_profile_cert: jq ausente" >&2; exit 2
fi

rc=0
found=0
for cap in "$PROFILE_DIR"/copilot-interactive.runtime-capability-v1.json \
           "$PROFILE_DIR"/copilot-prompt.runtime-capability-v1.json; do
  [ -f "$cap" ] || { echo "FAIL: falta la capacidad $(basename "$cap")"; rc=1; continue; }
  if ! python3 "$PC" validate --capability "$cap" >/dev/null 2>&1; then
    echo "FAIL: $(basename "$cap") no valida contra el schema v1"; rc=1; continue
  fi
  tier="$(jq -r '.tier' "$cap")"
  enforce="$(jq -r '.lifecycle.enforcement' "$cap")"
  cap8="$(jq -r '.lifecycle.block_cap' "$cap")"
  surface="$(jq -r '.surface' "$cap")"
  if [ "$tier" = "lifecycle-enforced" ] || [ "$enforce" = "enforced" ]; then
    echo "FAIL: $(basename "$cap") MIENTE: declara ciclo de vida enforced; Copilot es ACOTADO (tope de 8) -> degradado"
    rc=1; continue
  fi
  if [ "$cap8" != "8" ]; then
    echo "FAIL: $(basename "$cap") no declara block_cap=8; el tope de 8 bloqueos es obligatorio (bounded enforcement)"
    rc=1; continue
  fi
  if [ "$tier" != "profile-certified" ]; then
    echo "FAIL: $(basename "$cap") tier=$tier; se exige profile-certified"; rc=1; continue
  fi
  echo "PASS: copilot/$surface profile-certified (lifecycle degradado, block_cap=8, honesto)"
  found=$((found+1))
done

if [ "$found" -lt 2 ]; then rc=1; fi
exit "$rc"
