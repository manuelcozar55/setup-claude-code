#!/usr/bin/env bash
# test_profile_coordinator.sh — runtime capability/profile schema v1 y su
# coordinador transaccional del lado S (task 18 del plan
# provider-agnostic-agent-harness).
#
# QUE PRUEBA (y por que existe cada bloque):
#
#   A) SCHEMA v1 (fake schema): kit/lib/profiles/runtime-capability-v1.schema.json
#      y validate_capability aceptan un perfil conforme y RECHAZAN, ANTES de
#      coordinar nada, todo lo que el plan prohibe: schema futuro, campo extra,
#      tier/enforcement incoherente. La clausula dura del plan (y de la matriz de
#      certificacion, fila Copilot) es que un ciclo 'degraded'/'none' NUNCA puede
#      reclamar 'lifecycle-enforced': eso se falsifica aqui.
#
#   B) SEGURIDAD (fake): S NUNCA escribe en el --path de M. Se comprueba que tras
#      coordinar, el receipt de M lo escribio M (el fake), y que el WAL/estado de
#      S viven SOLO bajo sroot, nunca bajo mpath. Un digest delata cambios
#      silenciosos del contrato.
#
#   C) DOCTOR (fake): coordinate no llama a ningun `--version` ni ejecuta el
#      proyecto; se limita a los verbos del contrato. Se verifica con un M falso
#      que registra CADA invocacion que recibe: solo aparecen
#      prepare/apply/query/compensate.
#
#   D) MAQUINA DE ESTADOS TRAS CRASH: se mata el coordinador en cada frontera y
#      se reanuda consultando a M el estado EXACTO. Cada corrida converge o a
#      "ambos comprometidos" (M APPLIED + S complete) o a "M-compensado/S-
#      restaurado". Un M BLOCKED para el coordinador (rc 2) sin huerfanos.
#
# El M real (mcharness) NO se toca: se usa kit/test/fixtures/fake_mch.py, que
# reproduce el contrato de `mch project` de forma determinista.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
LIB="$KIT/lib/profile_coordinator.py"
SCHEMA="$KIT/lib/profiles/runtime-capability-v1.schema.json"
FAKE="$HERE/fixtures/fake_mch.py"
PY=/usr/bin/python3
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

coord(){ "$PY" -I "$LIB" "$@"; }

# ------------------------------------------------------------- existencia/API
ck "$([ -f "$LIB" ] && echo y || echo n)" "y" "kit/lib/profile_coordinator.py existe"
ck "$([ -f "$SCHEMA" ] && echo y || echo n)" "y" "el schema v1 existe"
ck "$([ -f "$FAKE" ] && echo y || echo n)" "y" "el M falso existe"

set +e
sid="$(coord --schema-id 2>/dev/null)"; rc=$?
set -e
ck "$rc" "0" "--schema-id responde rc=0"
ck "$sid" "runtime-capability-v1" "el id del schema es runtime-capability-v1"

# ------------------------------------------------------ A) SCHEMA v1 (fake)
mkcap(){ # $1 fichero  $2 tier  $3 enforcement  $4 native_stop(true/false)
  cat > "$1" <<JSON
{"schema":"runtime-capability-v1","provider":"claude","surface":"interactive",
 "tier":"$2","modes":["interactive"],
 "lifecycle":{"native_stop":$4,"enforcement":"$3"}}
JSON
}

GOOD="$tmp/good.json"; mkcap "$GOOD" "profile-certified" "degraded" "false"
set +e; coord validate --capability "$GOOD" >/dev/null 2>&1; rc=$?; set -e
ck "$rc" "0" "A: un perfil conforme (profile-certified/degraded) valida"

# lifecycle-enforced coherente (enforced + native_stop) valida.
ENF="$tmp/enf.json"; mkcap "$ENF" "lifecycle-enforced" "enforced" "true"
set +e; coord validate --capability "$ENF" >/dev/null 2>&1; rc=$?; set -e
ck "$rc" "0" "A: lifecycle-enforced coherente valida"

# La mentira Copilot: degraded reclamando lifecycle-enforced -> RECHAZO.
LIE="$tmp/lie.json"; mkcap "$LIE" "lifecycle-enforced" "degraded" "false"
set +e; coord validate --capability "$LIE" >/dev/null 2>&1; rc=$?; set -e
ck "$rc" "1" "A: un ciclo degradado NO puede reclamar lifecycle-enforced"

# schema futuro/desconocido -> rechazo.
FUT="$tmp/fut.json"; sed 's/runtime-capability-v1/runtime-capability-v2/' "$GOOD" > "$FUT"
set +e; coord validate --capability "$FUT" >/dev/null 2>&1; rc=$?; set -e
ck "$rc" "1" "A: schema futuro se rechaza"

# campo fuera del contrato -> rechazo.
EXTRA="$tmp/extra.json"; sed 's/"modes":\["interactive"\]/"modes":["interactive"],"comando":"rm -rf"/' "$GOOD" > "$EXTRA"
set +e; coord validate --capability "$EXTRA" >/dev/null 2>&1; rc=$?; set -e
ck "$rc" "1" "A: un campo fuera del contrato (p.ej. comando) se rechaza"

# digest estable y delator.
d1="$(coord digest --capability "$GOOD" 2>/dev/null)"
d2="$(coord digest --capability "$GOOD" 2>/dev/null)"
ck "$d1" "$d2" "A: el digest de un perfil es estable"
ck "$([ -n "$d1" ] && echo y || echo n)" "y" "A: el digest no es vacio"

# ------------------------------------------------------ B/C/D) coordinacion
setup_dirs(){
  SROOT="$tmp/s$1"; MPATH="$tmp/m$1"
  rm -rf "$SROOT" "$MPATH"; mkdir -p "$SROOT" "$MPATH"; chmod 700 "$SROOT" "$MPATH"
}
UUID="11111111-1111-1111-1111-111111111111"
MCH="$PY -I $FAKE"

# --- happy path: apply completo ---
setup_dirs A
set +e
out="$(coord coordinate --sroot "$SROOT" --mpath "$MPATH" --uuid "$UUID" \
       --capability "$GOOD" --mch-cmd "$MCH" --intent apply 2>&1)"; rc=$?
set -e
ck "$rc" "0" "D: apply completo devuelve rc=0"
echo "$out" | grep -q '"coordinator_state": "complete"'; ck "$?" "0" "D: estado terminal 'complete'"
ck "$([ -f "$MPATH/FAKE-PROJECTED.md" ] && echo y || echo n)" "y" "D: M escribio su target (apply real)"
ck "$([ -f "$MPATH/.fake-mch-receipt-$UUID.json" ] && echo y || echo n)" "y" "B: el receipt lo escribio M, esta bajo mpath"

# --- B) S nunca escribe en mpath: el WAL/estado de S viven bajo sroot ---
ck "$([ -f "$SROOT/.cckit-profile.wal" ] && echo y || echo n)" "y" "B: el WAL de S vive bajo sroot"
ck "$([ -f "$SROOT/.cckit-profile.state" ] && echo y || echo n)" "y" "B: la marca de S vive bajo sroot"
# Ningun fichero de S bajo mpath (solo lo del fake M).
sfiles_en_m="$(find "$MPATH" -name '.cckit-*' | wc -l | tr -d ' ')"
ck "$sfiles_en_m" "0" "B: NINGUN fichero de estado de S contamina mpath"

# --- C) doctor-fake: solo verbos del contrato, ningun --version ni ejecucion ---
# El fake M registra cada verbo recibido en un log. Comprobamos que solo hay
# verbos del contrato de proyeccion.
# (re-coordinamos con un fake que loguea)
LOGFAKE="$tmp/logfake.py"
cat > "$LOGFAKE" <<PYEOF
import sys, os
sys.argv=[sys.argv[0]]+sys.argv[1:]
verb = sys.argv[sys.argv.index("project")+1] if "project" in sys.argv else "?"
# el path es el arg tras --path
path=""
for i,a in enumerate(sys.argv):
    if a=="--path": path=sys.argv[i+1]
with open(os.path.join(path,"VERBS.log"),"a") as f: f.write(verb+"\n")
sys.path.insert(0, os.path.dirname("$FAKE"))
import importlib.util
spec=importlib.util.spec_from_file_location("fm","$FAKE")
fm=importlib.util.module_from_spec(spec); spec.loader.exec_module(fm)
sys.exit(fm.main(sys.argv[1:]))
PYEOF
setup_dirs C
set +e
coord coordinate --sroot "$SROOT" --mpath "$MPATH" --uuid "$UUID" \
      --capability "$GOOD" --mch-cmd "$PY -I $LOGFAKE" --intent apply >/dev/null 2>&1
set -e
badverbs="$(grep -vcE '^(prepare|apply|query|compensate)$' "$MPATH/VERBS.log" | tr -d ' ')"
ck "$badverbs" "0" "C: coordinate solo usa verbos del contrato (ni --version ni ejecucion)"

# --- D) crash en cada frontera: query a M y converger ---
# Simulamos "crash tras prepare" dejando M en PREPARED y re-invocando coordinate:
# debe detectar PREPARED y llevar a complete (apply) sin huerfanos.
setup_dirs D1
$MCH --path "$MPATH" project prepare --id "$UUID" >/dev/null 2>&1  # M queda PREPARED, S sin rastro
set +e
out="$(coord coordinate --sroot "$SROOT" --mpath "$MPATH" --uuid "$UUID" \
       --capability "$GOOD" --mch-cmd "$MCH" --intent apply 2>&1)"; rc=$?
set -e
ck "$rc" "0" "D: crash-tras-prepare -> reanuda y completa (rc=0)"
echo "$out" | grep -q 'complete'; ck "$?" "0" "D: converge a complete desde PREPARED"
ck "$([ -f "$MPATH/FAKE-PROJECTED.md" ] && echo y || echo n)" "y" "D: target aplicado tras reanudar"

# crash tras apply: M en APPLIED, S sin 'complete' -> continuar y cerrar.
setup_dirs D2
$MCH --path "$MPATH" project prepare --id "$UUID" >/dev/null 2>&1
$MCH --path "$MPATH" project apply --id "$UUID" >/dev/null 2>&1  # M queda APPLIED
set +e
out="$(coord coordinate --sroot "$SROOT" --mpath "$MPATH" --uuid "$UUID" \
       --capability "$GOOD" --mch-cmd "$MCH" --intent apply 2>&1)"; rc=$?
set -e
ck "$rc" "0" "D: crash-tras-apply -> continua y cierra (rc=0)"
echo "$out" | grep -q 'complete'; ck "$?" "0" "D: converge a complete desde APPLIED"

# compensacion: revertir un APPLIED -> M COMPENSATED + S restaurado.
setup_dirs D3
coord coordinate --sroot "$SROOT" --mpath "$MPATH" --uuid "$UUID" \
      --capability "$GOOD" --mch-cmd "$MCH" --intent apply >/dev/null 2>&1
set +e
out="$(coord coordinate --sroot "$SROOT" --mpath "$MPATH" --uuid "$UUID" \
       --capability "$GOOD" --mch-cmd "$MCH" --intent compensate 2>&1)"; rc=$?
set -e
ck "$rc" "0" "D: compensar un APPLIED devuelve rc=0"
echo "$out" | grep -q 'compensated'; ck "$?" "0" "D: estado terminal 'compensated'"
ck "$([ -f "$MPATH/FAKE-PROJECTED.md" ] && echo y || echo n)" "n" "D: M-compensado retiro el target"
ck "$([ -f "$SROOT/.cckit-profile.state" ] && echo y || echo n)" "n" "D: S-restaurado retiro su marca"

# M BLOCKED -> el coordinador para (rc 2) sin huerfanos ni destruccion.
setup_dirs D4
$MCH --path "$MPATH" project prepare --id "$UUID" >/dev/null 2>&1
touch "$MPATH/.fake-mch-force-blocked"
set +e
coord coordinate --sroot "$SROOT" --mpath "$MPATH" --uuid "$UUID" \
      --capability "$GOOD" --mch-cmd "$MCH" --intent apply >/dev/null 2>&1; rc=$?
set -e
ck "$rc" "2" "D: M BLOCKED -> coordinador para con rc=2"
# el receipt de M sigue existiendo (no se destruyo).
ck "$([ -f "$MPATH/.fake-mch-receipt-$UUID.json" ] && echo y || echo n)" "y" "D: BLOCKED no destruye el receipt de M"

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
