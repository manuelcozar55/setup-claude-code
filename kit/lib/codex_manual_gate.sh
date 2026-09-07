#!/usr/bin/env bash
# codex_manual_gate.sh — el gate MANUAL explicito pre/post del perfil nativo de
# Codex (todo 21).
#
# QUE ES: Codex NO expone un hard-stop nativo probado en esta rama. El plan exige
# literal "native hard-stop degraded unless proven" y "Never ... equate manual
# gate to lifecycle enforcement". Asi que la puerta de gobierno de Codex es este
# gate MANUAL: se invoca de forma explicita antes/despues de un turno, consulta
# al productor REAL del gate v2 de M (`mch task gate --json`, contrato del todo 9)
# y traduce su veredicto a un rc de puerta manual. NUNCA se equipara a enforcement
# de ciclo de vida: por eso ambas superficies de Codex son profile-certified con
# lifecycle degradado, jamas lifecycle-enforced.
#
# CONTRATO (cada clausula la fija un caso de test_codex_profile.sh):
#   - RUTA ABSOLUTA DE CONFIANZA a M. NUNCA `mch` del PATH. `--mch RUTA` existe
#     SOLO para que el test inyecte productores de mentira; el perfil jamas lo pasa.
#   - VERSION MINIMA del productor: `mch --version` < MIN => BLOQUEA.
#   - UNA sola invocacion de `mch task gate --json`.
#   - TIMEOUT y TOPE DE SALIDA: mas de GATE_TIMEOUT o mas de GATE_MAX_BYTES => BLOQUEA.
#   - ESQUEMA DE EVIDENCIA fijado + version compatible: en rc0/rc1 el cuerpo debe
#     declarar evidencia.schema == EVID_SCHEMA; ausente/futuro BLOQUEA.
#   - TABLA rc CERRADA del gate v2: 0=ALLOW, 1=BLOCK, 2=BLOCK, 3=ALLOW, otro=BLOCK.
#
# Ante ausencia de autoridad (M no gobierna: rc3) PERMITE, para no secuestrar la
# sesion en repos que no usan M.
#
# Salida: JSON por stdout {"decision":"allow"|"block","reason":...}; rc 0=ALLOW,
# rc 2=BLOCK (con el motivo tambien por stderr).
set -uo pipefail

MIN_MAJOR=0; MIN_MINOR=2; MIN_PATCH=0
EVID_SCHEMA="mch-gate-evidence-v2"
GATE_MAX_BYTES=65536
GATE_TIMEOUT=10

MCH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --mch) MCH="${2:-}"; shift 2 ;;
    --mch=*) MCH="${1#--mch=}"; shift ;;
    -h|--help)
      printf 'uso: codex_manual_gate.sh [--mch RUTA_ABSOLUTA]\n' >&2
      printf '  Sin --mch usa CCKIT_MCH_BRIDGE_PATH, la ruta de confianza que fija la instalacion.\n' >&2
      exit 0 ;;
    *) shift ;;
  esac
done
[ -n "$MCH" ] || MCH="${CCKIT_MCH_BRIDGE_PATH:-}"

if command -v jq >/dev/null 2>&1; then HK_JSON=jq
elif command -v python3 >/dev/null 2>&1; then HK_JSON=py
else HK_JSON=no; fi

json_get() {
  case "$HK_JSON" in
    jq) printf '%s' "$1" | jq -r ".$2 // empty" 2>/dev/null ;;
    py) printf '%s' "$1" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(5)
for k in sys.argv[1].split("."):
    if not isinstance(d,dict): sys.exit(0)
    d=d.get(k)
    if d is None: sys.exit(0)
print(d if isinstance(d,str) else json.dumps(d))' "$2" 2>/dev/null ;;
    *)  return 127 ;;
  esac
}

allow() {
  if [ "$HK_JSON" = jq ]; then
    jq -n --arg r "${1:-ok}" '{decision:"allow", reason:$r}'
  elif [ "$HK_JSON" = py ]; then
    python3 -c 'import json,sys; print(json.dumps({"decision":"allow","reason":sys.argv[1]}, ensure_ascii=False))' "${1:-ok}"
  else printf '{"decision":"allow"}\n'; fi
  exit 0
}
block() {
  if [ "$HK_JSON" = jq ]; then
    jq -n --arg r "$1" '{decision:"block", reason:$r}'
  elif [ "$HK_JSON" = py ]; then
    python3 -c 'import json,sys; print(json.dumps({"decision":"block","reason":sys.argv[1]}, ensure_ascii=False))' "$1"
  else printf '%s\n' "$1"; fi
  printf '%s\n' "$1" >&2
  exit 2
}

[ -n "$MCH" ] || block "Gate manual Codex: no hay ruta de confianza al productor de M (ni --mch ni \$CCKIT_MCH_BRIDGE_PATH). No consulto un gate que no puedo localizar."
case "$MCH" in
  /*) : ;;
  *) block "Gate manual Codex: la ruta al productor de M no es absoluta ($MCH). Solo confio en una ruta absoluta." ;;
esac
[ -x "$MCH" ] || block "Gate manual Codex: el productor de M no esta en su ruta de confianza ($MCH)."
perms="$(stat -c '%a' "$MCH" 2>/dev/null)" || perms=""
if [ -n "$perms" ]; then
  grp="${perms: -2:1}"; oth="${perms: -1}"
  if [ $(( grp & 2 )) -ne 0 ] || [ $(( oth & 2 )) -ne 0 ] 2>/dev/null; then
    block "Gate manual Codex: el productor de M en $MCH es escribible por grupo/otros (permisos $perms). No es de confianza."
  fi
fi

ver_raw="$("$MCH" --version 2>/dev/null)" || block "Gate manual Codex: no pude leer la version de M ($MCH --version fallo)."
ver_num="$(printf '%s' "$ver_raw" | tr -cd '0-9.' )"
IFS='.' read -r vM vm vp _ <<EOF
$ver_num
EOF
vM="${vM:-0}"; vm="${vm:-0}"; vp="${vp:-0}"
compat=1
if   [ "$vM" -gt "$MIN_MAJOR" ] 2>/dev/null; then compat=0
elif [ "$vM" -eq "$MIN_MAJOR" ] 2>/dev/null; then
  if   [ "$vm" -gt "$MIN_MINOR" ] 2>/dev/null; then compat=0
  elif [ "$vm" -eq "$MIN_MINOR" ] 2>/dev/null; then
    [ "$vp" -ge "$MIN_PATCH" ] 2>/dev/null && compat=0
  fi
fi
[ "$compat" -eq 0 ] || block "Gate manual Codex: el productor de M declara version '$ver_raw', por debajo del minimo compatible ${MIN_MAJOR}.${MIN_MINOR}.${MIN_PATCH}. No confio en un gate incompatible."

payload="$(cat 2>/dev/null)" || payload=""
cwd=""
[ -n "$payload" ] && [ "$HK_JSON" != no ] && cwd="$(json_get "$payload" cwd)"
[ -n "$cwd" ] || cwd="$PWD"

gate_out="$(cd "$cwd" && timeout "$GATE_TIMEOUT" "$MCH" task gate --json 2>/dev/null)"
gate_rc=$?

nbytes=$(printf '%s' "$gate_out" | wc -c | tr -d ' ')
if [ "$nbytes" -gt "$GATE_MAX_BYTES" ] 2>/dev/null; then
  block "Gate manual Codex: la salida del gate ($nbytes bytes) supera el tope de $GATE_MAX_BYTES. No decido sobre una respuesta sospechosa."
fi

case "$gate_rc" in
  0|1|3) : ;;
  2) block "Gate manual Codex: el gate salio con rc=2 (error de uso). No confirmo cierre sobre un gate que no pudo evaluar." ;;
  124) block "Gate manual Codex: el gate no respondio en ${GATE_TIMEOUT}s (timeout). Fallo cerrado." ;;
  *) block "Gate manual Codex: el gate salio con rc=$gate_rc, fuera de la tabla del contrato v2 (0/1/2/3). Fallo cerrado." ;;
esac

if [ "$gate_rc" = 0 ] || [ "$gate_rc" = 1 ]; then
  [ "$HK_JSON" != no ] || block "Gate manual Codex: gate gobernado (rc=$gate_rc) pero sin jq ni python3 para verificar el esquema de evidencia. Fallo cerrado."
  [ -n "$gate_out" ] || block "Gate manual Codex: gate gobernado (rc=$gate_rc) con stdout vacio. Fallo cerrado."
  schema="$(json_get "$gate_out" evidencia.schema)"
  [ "$schema" = "$EVID_SCHEMA" ] || block "Gate manual Codex: el gate declara evidencia.schema='$schema', no el fijado '$EVID_SCHEMA' (ausente/futuro/incompatible). No confio en un contrato que no reconozco."
fi

case "$gate_rc" in
  3)
    allow "M no gobierna este proyecto (rc3/not_governed): la puerta manual permite, como en ausencia de autoridad." ;;
  0)
    allow "El gate v2 de M verifico el turno (rc0/verified). Puerta manual: ALLOW." ;;
  1)
    motivo="$(json_get "$gate_out" motivo)"; [ -n "$motivo" ] || motivo="sin motivo"
    tarea="$(json_get "$gate_out" tarea)"; [ -n "$tarea" ] || tarea="?"
    codigo="$(json_get "$gate_out" motivo_codigo)"; [ -n "$codigo" ] || codigo="?"
    block "Gate manual Codex: el gate v2 de M BLOQUEA (rc1/$codigo) la tarea $tarea. Puerta manual: BLOCK.

Motivo: $motivo

Repara la causa, no el sensor. Cuando el oraculo pase, cierra la tarea en mch." ;;
esac
