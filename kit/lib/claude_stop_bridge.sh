#!/usr/bin/env bash
# claude_stop_bridge.sh — el puente Stop ENDURECIDO del perfil de referencia de
# Claude (todo 20).
#
# QUE ES: el nativo Stop de Claude que consulta al productor REAL del gate v2 de
# M (`mch task gate --json`, contrato del todo 9) y traduce su veredicto al
# contrato del evento Stop de Claude Code. Es SEPARADO de .claude/hooks/verify-
# gate.sh (que no se toca): aquel es el hook instalado que resuelve `mch` por
# PATH y opera en modo aviso; este da las garantias que el todo 20 exige y que
# verify-gate.sh no da, precisamente porque es un PERFIL DE REFERENCIA -- la vara
# de medir, no la comodidad.
#
# CONTRATO (cada clausula la fija un caso de test_claude_stop_bridge.sh):
#   - RUTA ABSOLUTA DE CONFIANZA a M. NUNCA `mch` del PATH. `--mch RUTA` existe
#     SOLO para que el test inyecte productores de mentira; el perfil de
#     referencia jamas lo pasa.
#   - VERSION MINIMA del productor: `mch --version` < MIN => BLOQUEA.
#   - UNA sola invocacion de `mch task gate --json`.
#   - TIMEOUT y TOPE DE SALIDA: si el gate tarda mas de GATE_TIMEOUT o su stdout
#     suprea GATE_MAX_BYTES => BLOQUEA (no se confia en una respuesta truncada).
#   - ESQUEMA DE EVIDENCIA fijado + version compatible: el cuerpo debe declarar
#     evidencia.schema == EVID_SCHEMA en rc0/rc1; un esquema ausente/futuro
#     BLOQUEA.
#   - TABLA rc CERRADA del gate v2: 0=verified/ALLOW, 1=BLOCK, 2=usage/BLOCK,
#     3=not_governed/ALLOW, cualquier otro (timeout 124, crash, desconocido) =>
#     BLOQUEA.
#
# "Never weaken Claude behavior": este puente es ADITIVO. No sustituye a
# verify-gate.sh; el perfil de referencia lo declara como el Stop nativo
# ENDURECIDO cuando M gobierna de verdad. Ante ausencia de autoridad (M no
# gobierna: rc3) PERMITE, igual que verify-gate.sh, para no secuestrar sesiones
# en repos que no usan M.
#
# Salida: contrato del evento Stop (code.claude.com/docs/en/hooks).
#   ALLOW -> stdout {"decision":"allow",...}, exit 0
#   BLOCK -> stdout {"decision":"block","reason":...}, exit 2 (stderr al modelo)
# Se emite SIEMPRE el JSON por stdout para que el consumidor lea el veredicto sin
# depender solo del rc; el rc es el canal que el runtime honra.
set -uo pipefail

# ── Constantes del contrato (fijadas; el test las ancla) ──────────────────────
# Version minima compatible del productor (gate v2 aparecio en 0.2.0).
MIN_MAJOR=0; MIN_MINOR=2; MIN_PATCH=0
# Esquema de evidencia que el gate v2 debe declarar (todo 9).
EVID_SCHEMA="mch-gate-evidence-v2"
# Tope de salida del gate: un cuerpo mayor es sospechoso y se rechaza en cerrado.
GATE_MAX_BYTES=65536
# Timeout de la unica invocacion del gate. El gate solo lee ficheros sellados.
GATE_TIMEOUT=10

# ── Ruta absoluta de CONFIANZA al productor de M ──────────────────────────────
# El todo 20 exige "trusted absolute M path". "De confianza" NO significa
# literal en el arbol: la ruta al binario real es especifica de la maquina de
# instalacion (el nombre de la cuenta local no puede versionarse -- lo prohibe
# kit/scan-secrets.sh, y con razon). Se resuelve, en este orden:
#   1. --mch RUTA           -> SOLO para inyectar fakes en el test.
#   2. $CCKIT_MCH_BRIDGE_PATH -> la que el wiring de instalacion fija, ya validada.
# Ausencia de ambas => BLOQUEA (autoridad esperada que no se puede localizar);
# NUNCA se cae a un `mch` del PATH. Y sea cual sea el origen, la ruta pasa por
# _ruta_de_confianza(): absoluta, existe, ejecutable, y NI grupo NI otros pueden
# escribirla (un binario que un tercero puede reescribir no es de confianza).
MCH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --mch) MCH="${2:-}"; shift 2 ;;
    --mch=*) MCH="${1#--mch=}"; shift ;;
    -h|--help)
      printf 'uso: claude_stop_bridge.sh [--mch RUTA_ABSOLUTA]\n' >&2
      printf '  Sin --mch usa CCKIT_MCH_BRIDGE_PATH, la ruta de confianza que fija la instalacion.\n' >&2
      exit 0 ;;
    *) shift ;;   # el payload del evento Stop llega por stdin, no por argv
  esac
done
[ -n "$MCH" ] || MCH="${CCKIT_MCH_BRIDGE_PATH:-}"

# ── Lector JSON sin depender de jq (jq -> python3 -> fallo cerrado) ────────────
# Mismo criterio que verify-gate.sh: un control de seguridad no se parsea con
# grep/sed. Si no hay ni jq ni python3, se bloquea (fallo cerrado), porque sin
# parser no se puede confirmar el esquema de evidencia ni el veredicto.
if command -v jq >/dev/null 2>&1; then HK_JSON=jq
elif command -v python3 >/dev/null 2>&1; then HK_JSON=py
else HK_JSON=no; fi

json_get() {  # $1=json $2=ruta.punteada ; stdout=valor o vacio
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

# ── Emisores del veredicto (contrato Stop) ────────────────────────────────────
allow() {  # $1=motivo
  if [ "$HK_JSON" = jq ]; then printf '%s' "$1" >/dev/null
    jq -n --arg r "${1:-ok}" '{decision:"allow", reason:$r}'
  elif [ "$HK_JSON" = py ]; then
    python3 -c 'import json,sys; print(json.dumps({"decision":"allow","reason":sys.argv[1]}, ensure_ascii=False))' "${1:-ok}"
  else printf '{"decision":"allow"}\n'; fi
  exit 0
}
block() {  # $1=motivo
  if [ "$HK_JSON" = jq ]; then
    jq -n --arg r "$1" '{decision:"block", reason:$r}'
  elif [ "$HK_JSON" = py ]; then
    python3 -c 'import json,sys; print(json.dumps({"decision":"block","reason":sys.argv[1]}, ensure_ascii=False))' "$1"
  else printf '%s\n' "$1"; fi
  printf '%s\n' "$1" >&2
  exit 2
}

# ── 1. El binario de M tiene que existir por su ruta de CONFIANZA ─────────────
# NUNCA se busca en el PATH. Ademas de existir y ser ejecutable, la ruta tiene
# que ser ABSOLUTA y NO escribible por grupo ni por otros: un binario que un
# tercero puede reescribir no es de confianza, aunque exista.
[ -n "$MCH" ] || block "Puente Stop: no hay ruta de confianza al productor de M (ni --mch ni \$CCKIT_MCH_BRIDGE_PATH). No consulto un gate que no puedo localizar."
case "$MCH" in
  /*) : ;;
  *) block "Puente Stop: la ruta al productor de M no es absoluta ($MCH). Solo confio en una ruta absoluta." ;;
esac
[ -x "$MCH" ] || block "Puente Stop: el productor de M no esta en su ruta de confianza ($MCH). No termino el turno sin poder consultar al gate."
perms="$(stat -c '%a' "$MCH" 2>/dev/null)" || perms=""
# El ultimo digito octal (otros) y el del medio (grupo): si alguno lleva bit 2
# (escritura), un tercero puede reescribir el binario -> no es de confianza.
if [ -n "$perms" ]; then
  grp="${perms: -2:1}"; oth="${perms: -1}"
  if [ $(( grp & 2 )) -ne 0 ] || [ $(( oth & 2 )) -ne 0 ] 2>/dev/null; then
    block "Puente Stop: el productor de M en $MCH es escribible por grupo/otros (permisos $perms). Un binario que un tercero puede reescribir no es de confianza."
  fi
fi

# ── 2. Version minima del productor ───────────────────────────────────────────
ver_raw="$("$MCH" --version 2>/dev/null)" || block "Puente Stop: no pude leer la version de M ($MCH --version fallo)."
# Formato esperado: 'mch X.Y.Z'. Se extrae la terna sin regex-en-shell fragil.
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
[ "$compat" -eq 0 ] || block "Puente Stop: el productor de M declara version '$ver_raw', por debajo del minimo compatible ${MIN_MAJOR}.${MIN_MINOR}.${MIN_PATCH}. No confio en un gate incompatible."

# ── 3. cwd del payload Stop (para preguntar por el proyecto correcto) ──────────
payload="$(cat 2>/dev/null)" || payload=""
cwd=""
[ -n "$payload" ] && [ "$HK_JSON" != no ] && cwd="$(json_get "$payload" cwd)"
[ -n "$cwd" ] || cwd="$PWD"
# El cap de 8 de Claude Code: si el runtime ya reintento, apartarse.
active=""
[ -n "$payload" ] && [ "$HK_JSON" != no ] && active="$(json_get "$payload" stop_hook_active)"
[ "$active" = "true" ] && exit 0

# ── 4. UNA sola invocacion del gate, con timeout y tope de salida ─────────────
gate_out="$(cd "$cwd" && timeout "$GATE_TIMEOUT" "$MCH" task gate --json 2>/dev/null)"
gate_rc=$?

# Tope de salida: un cuerpo mayor que el tope se rechaza (respuesta sospechosa o
# truncada; no se decide a partir de ella).
nbytes=$(printf '%s' "$gate_out" | wc -c | tr -d ' ')
if [ "$nbytes" -gt "$GATE_MAX_BYTES" ] 2>/dev/null; then
  block "Puente Stop: la salida del gate ($nbytes bytes) supera el tope de $GATE_MAX_BYTES. No decido sobre una respuesta sospechosa."
fi

# ── 5. Tabla rc cerrada del gate v2 ───────────────────────────────────────────
case "$gate_rc" in
  0|1|3) : ;;                              # ramas gobernadas/no-gobernadas, abajo
  2) block "Puente Stop: el gate salio con rc=2 (error de uso). No confirmo cierre sobre un gate que no pudo evaluar." ;;
  124) block "Puente Stop: el gate no respondio en ${GATE_TIMEOUT}s (timeout). No termino el turno dando por bueno lo que no se comprobo." ;;
  *) block "Puente Stop: el gate salio con rc=$gate_rc, fuera de la tabla del contrato v2 (0/1/2/3). Fallo cerrado." ;;
esac

# rc0 y rc1 traen cuerpo JSON; rc3 tambien, pero not_governed. En rc0/rc1 se
# EXIGE que el parser este y que el esquema de evidencia sea el fijado: sin eso
# no se puede confiar en el veredicto.
if [ "$gate_rc" = 0 ] || [ "$gate_rc" = 1 ]; then
  [ "$HK_JSON" != no ] || block "Puente Stop: gate gobernado (rc=$gate_rc) pero sin jq ni python3 para verificar el esquema de evidencia. Fallo cerrado."
  [ -n "$gate_out" ] || block "Puente Stop: gate gobernado (rc=$gate_rc) con stdout vacio. Fallo cerrado."
  schema="$(json_get "$gate_out" evidencia.schema)"
  [ "$schema" = "$EVID_SCHEMA" ] || block "Puente Stop: el gate declara evidencia.schema='$schema', no el fijado '$EVID_SCHEMA' (esquema ausente/futuro/incompatible). No confio en un contrato que no reconozco."
fi

# ── 6. Veredicto final ────────────────────────────────────────────────────────
case "$gate_rc" in
  3)
    allow "M no gobierna este proyecto (rc3/not_governed): el puente permite, como en ausencia de autoridad." ;;
  0)
    allow "El gate v2 de M verifico el turno (rc0/verified)." ;;
  1)
    motivo="$(json_get "$gate_out" motivo)"; [ -n "$motivo" ] || motivo="sin motivo"
    tarea="$(json_get "$gate_out" tarea)"; [ -n "$tarea" ] || tarea="?"
    codigo="$(json_get "$gate_out" motivo_codigo)"; [ -n "$codigo" ] || codigo="?"
    block "Puente Stop: el gate v2 de M BLOQUEA (rc1/$codigo) la tarea $tarea. No termines el turno.

Motivo: $motivo

Repara la causa, no el sensor. Cuando el oraculo pase, cierra la tarea en mch." ;;
esac
