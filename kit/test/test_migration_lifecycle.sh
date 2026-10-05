#!/usr/bin/env bash
# test_migration_lifecycle.sh — la prueba end-to-end del todo 26: MIGRACION,
# ACTUALIZACION (x2), CRASH/RECUPERACION, DESINSTALACION y ROLLBACK del ciclo de
# vida gobernado por kit/lib/installer_core.py, mas el rollback por backup de
# uninstall.sh/scripts/backup.sh.
#
# Los sensores previos cubren piezas sueltas (test_installer_core.sh: un install
# y un uninstall; test_uninstall.sh y test_backup_integrity.sh: el rollback por
# backup). Este sensor exige la HISTORIA COMPLETA que el todo 26 pide como una
# sola secuencia determinista, y mide lo que esos no miden:
#
#   1. MIGRACION a perfiles sobre DOS estados de partida distintos: un home
#      "endurecido" que ya trae ficheros (incluidos ficheros del USUARIO no
#      gestionados) y un home LIMPIO. Ambos convergen al mismo conjunto OWNED.
#   2. UPDATE TWICE: dos instalaciones encadenadas del perfil sobre el mismo
#      home. La 2a no debe derivar ni un byte (idempotencia real, no afirmada).
#   3. NO UNMANAGED LOSS: el fichero del usuario (no gestionado) SOBREVIVE a
#      migrar -> update -> update -> uninstall, byte a byte y con su modo.
#   4. UNINSTALL OWNED: uninstall retira EXACTAMENTE lo que el ledger posee y
#      cuyo sha sigue coincidiendo; un OWNED modificado a mano se PRESERVA.
#   5. EXACT ROLLBACK HASHES/MODES: el rollback por backup (uninstall.sh --apply)
#      devuelve los bytes Y el modo exactos del estado respaldado.
#   6. THIRD HASH / CRASH DETERMINISTIC: un WAL corrupto (tercer estado) bloquea
#      el update en cerrado, sin dejar el target a medias; y la MISMA entrada en
#      dos homes independientes produce un digest OWNED byte-identico (repetir y
#      comparar, no afirmar).
#   7. SEMANTIC CONFIG vs OWNED BYTES: doctor distingue owned-clean / owned-drifted
#      / unowned; el kit POSEE lo suyo y no reclama lo ajeno.
#
# Todo corre contra homes temporales que este test crea y borra (patron de
# test_clean_install_resilience.sh): NUNCA toca el ~/.claude real.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."; REPO="$(cd "$KIT/.." && pwd)"
CORE="$KIT/lib/installer_core.py"
UNINSTALL="$REPO/uninstall.sh"
PY=/usr/bin/python3
tmp="$(mktemp -d)"; trap 'chmod -R u+rwX "$tmp" 2>/dev/null; find "$tmp" -mindepth 0 -delete 2>/dev/null || true' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

core(){ "$PY" -I "$CORE" "$@"; }

# El perfil de referencia de Claude (task 20) trae 'src' KIT-relativo; el
# consumidor los resuelve a absoluto antes de invocar. Aqui construimos un plan
# equivalente de dos copy-owned con src absoluto, que es lo que installer_core
# consume. (managed-text-block del puente Stop lee de stdin y se prueba en
# test_installer_core.sh; aqui el foco es el ciclo de vida, no esa primitiva.)
make_profile_plan(){ # $1 = ruta del plan a escribir
  "$PY" - "$1" "$REPO" <<'PYEOF'
import json,sys,os
path, repo = sys.argv[1], sys.argv[2]
def a(rel): return os.path.join(repo, rel)
ops=[
 {"op":"copy-owned","dst":"profiles/claude-reference-interactive.runtime-capability-v1.json","mode":"0644",
  "src":a("kit/lib/profiles/claude-reference-interactive.runtime-capability-v1.json")},
 {"op":"copy-owned","dst":"profiles/claude-reference-noninteractive.runtime-capability-v1.json","mode":"0644",
  "src":a("kit/lib/profiles/claude-reference-noninteractive.runtime-capability-v1.json")},
]
json.dump({"schema":"installer-core-plan-v1","operations":ops}, open(path,"w"))
PYEOF
}

# Digest determinista de lo que el kit POSEE en un home: por cada entrada del
# ledger, (ruta relativa + bytes + modo). Excluye deliberadamente todo lo NO
# gestionado (ficheros del usuario), el propio ledger y el estado transaccional:
# es el "owned bytes" del todo 26, no un digest del arbol entero.
owned_digest(){ # $1 = root
  "$PY" - "$1" <<'PYEOF'
import json,sys,hashlib,os
r=sys.argv[1]
led=json.load(open(os.path.join(r,".cckit-owned.json")))
h=hashlib.sha256()
for dst in sorted(led["owned"]):
    p=os.path.join(r,dst)
    with open(p,"rb") as f: b=f.read()
    h.update(dst.encode("utf-8")+b"\0")
    h.update(hashlib.sha256(b).digest())
    h.update(oct(os.stat(p).st_mode & 0o777).encode("ascii"))
print(h.hexdigest())
PYEOF
}

PLAN="$tmp/profile-plan.json"; make_profile_plan "$PLAN"

# ============================================================================
# 1. MIGRACION sobre DOS estados de partida -> mismo conjunto OWNED
# ============================================================================
# Home A: "endurecido", ya trae ficheros del kit y un fichero del USUARIO.
A="$tmp/homeA"; mkdir -p "$A/hooks"; chmod 700 "$A"
printf 'instrucciones-endurecidas\n' > "$A/CLAUDE.md"; chmod 644 "$A/CLAUDE.md"
printf 'guard\n' > "$A/hooks/block-dangerous-commands.sh"; chmod 755 "$A/hooks/block-dangerous-commands.sh"
# fichero del usuario, NO gestionado: es el que no se puede perder.
USER_BYTES='mis-notas-personales-que-no-gestiona-el-kit'
printf '%s\n' "$USER_BYTES" > "$A/mis-notas.md"; chmod 600 "$A/mis-notas.md"
user_sha_before="$(sha256sum "$A/mis-notas.md" | cut -d' ' -f1)"
user_mode_before="$(stat -c '%a' "$A/mis-notas.md")"

# Home B: LIMPIO.
B="$tmp/homeB"; mkdir -p "$B"; chmod 700 "$B"

set +e; core install --root "$A" --plan "$PLAN" >/dev/null 2>&1; rcA=$?; set -e
set +e; core install --root "$B" --plan "$PLAN" >/dev/null 2>&1; rcB=$?; set -e
ck "$rcA" "0" "migracion sobre home endurecido: rc=0"
ck "$rcB" "0" "migracion sobre home limpio: rc=0"
ck "$([ -f "$A/profiles/claude-reference-interactive.runtime-capability-v1.json" ] && echo y || echo n)" "y" \
  "migracion escribio el perfil owned en el home endurecido"
ck "$([ -f "$B/profiles/claude-reference-interactive.runtime-capability-v1.json" ] && echo y || echo n)" "y" \
  "migracion escribio el perfil owned en el home limpio"
# Los dos convergen al MISMO owned-digest, pese a partir de estados distintos.
ck "$(owned_digest "$A")" "$(owned_digest "$B")" \
  "canonical owned output: endurecido y limpio convergen al mismo digest OWNED"

# ============================================================================
# 2. UPDATE TWICE: dos updates encadenados, sin deriva
# ============================================================================
dig_after_migrate="$(owned_digest "$A")"
set +e; core install --root "$A" --plan "$PLAN" >/dev/null 2>&1; rcU1=$?; set -e
dig_after_u1="$(owned_digest "$A")"
set +e; core install --root "$A" --plan "$PLAN" >/dev/null 2>&1; rcU2=$?; set -e
dig_after_u2="$(owned_digest "$A")"
ck "$rcU1" "0" "update #1 rc=0"
ck "$rcU2" "0" "update #2 rc=0"
ck "$dig_after_migrate" "$dig_after_u1" "update #1 no deriva (owned-digest identico)"
ck "$dig_after_u1" "$dig_after_u2" "update #2 no deriva (owned-digest identico) — update twice idempotente"

# ============================================================================
# 3+7. SEMANTIC CONFIG: doctor distingue owned-clean vs owned-drifted vs unowned
# ============================================================================
doc="$(core doctor --root "$A" --plan "$PLAN" 2>/dev/null)"
ck "$(printf '%s' "$doc" | "$PY" -c 'import json,sys; d=json.load(sys.stdin); print(all(t["state"]=="owned-clean" for t in d["targets"]))')" \
  "True" "doctor: tras update, todo OWNED esta owned-clean"
# Deriva un OWNED a mano -> doctor lo ve owned-drifted (config semantica != bytes owned).
prof="$A/profiles/claude-reference-interactive.runtime-capability-v1.json"
printf '\n// tocado a mano\n' >> "$prof"
doc2="$(core doctor --root "$A" --plan "$PLAN" 2>/dev/null)"
ck "$(printf '%s' "$doc2" | "$PY" -c 'import json,sys; d=json.load(sys.stdin); print(any(t["state"]=="owned-drifted" for t in d["targets"]))')" \
  "True" "doctor: un OWNED modificado a mano se reporta owned-drifted"

# ============================================================================
# 4. UNINSTALL OWNED: retira lo owned-clean, PRESERVA lo drifted y lo del usuario
# ============================================================================
# En este punto: 'prof' esta drifted (modificado a mano); el noninteractive
# sigue owned-clean; 'mis-notas.md' es del usuario (no gestionado).
set +e; core uninstall --root "$A" --plan "$PLAN" >/dev/null 2>&1; rcUn=$?; set -e
ck "$rcUn" "0" "uninstall rc=0"
ck "$([ -e "$A/profiles/claude-reference-noninteractive.runtime-capability-v1.json" ] && echo queda || echo retirado)" \
  "retirado" "uninstall retira el OWNED owned-clean"
ck "$([ -e "$prof" ] && echo queda || echo retirado)" "queda" \
  "uninstall PRESERVA el OWNED modificado a mano (owned-drifted), no lo pisa"
# NO UNMANAGED LOSS: el fichero del usuario sobrevive intacto, bytes y modo.
ck "$([ -f "$A/mis-notas.md" ] && echo y || echo n)" "y" "no unmanaged loss: el fichero del usuario sobrevive al ciclo completo"
ck "$(sha256sum "$A/mis-notas.md" | cut -d' ' -f1)" "$user_sha_before" "no unmanaged loss: bytes exactos del fichero del usuario"
ck "$(stat -c '%a' "$A/mis-notas.md")" "$user_mode_before" "no unmanaged loss: modo exacto del fichero del usuario"

# ============================================================================
# 5. EXACT ROLLBACK HASHES/MODES via backup (uninstall.sh --apply)
# ============================================================================
# Instala el kit real en un home, respalda, ensucia, y restaura: los bytes Y el
# modo del estado respaldado tienen que volver EXACTOS. Es el rollback del todo
# 26 por el origen "restore backup", complementario al ledger de installer_core.
if command -v zip >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1; then
  RH="$tmp/roll"; mkdir -p "$RH"
  export HOME="$RH" CLAUDE_HOME="$RH/.claude" BACKUP_DIR="$RH/backups"
  bash "$REPO/kit/install.sh" >/dev/null 2>&1
  chmod 640 "$CLAUDE_HOME/settings.json"
  set_sha="$(sha256sum "$CLAUDE_HOME/settings.json" | cut -d' ' -f1)"
  set_mode="$(stat -c '%a' "$CLAUDE_HOME/settings.json")"
  bash "$REPO/scripts/backup.sh" >/dev/null 2>&1
  # ensucia despues del backup: cambia bytes Y modo.
  printf 'ROTO\n' >> "$CLAUDE_HOME/settings.json"; chmod 600 "$CLAUDE_HOME/settings.json"
  sleep 1   # el ZIP de backup.sh tiene granularidad de 1s; evita choque de nombre
  bash "$UNINSTALL" --apply >/dev/null 2>&1
  ck "$(sha256sum "$CLAUDE_HOME/settings.json" | cut -d' ' -f1)" "$set_sha" "rollback por backup: bytes exactos restaurados"
  ck "$(stat -c '%a' "$CLAUDE_HOME/settings.json")" "$set_mode" "rollback por backup: modo exacto restaurado"
  unset HOME CLAUDE_HOME BACKUP_DIR
else
  # Sin zip/unzip el rollback por backup NO se puede probar. Antes esta rama
  # imprimia dos lineas "ok -" y sumaba dos a `pass`: el suite salia
  # "24 passed, 0 failed" habiendo saltado justo la clausula que el todo 26
  # exige ("restore backup", "exact rollback hashes/modes"), y el total no lo
  # delataba. Un salto no es un aprobado: se declara en ROJO.
  ck "no" "si" "zip/unzip presentes: sin ellos el rollback por backup no se ejecuta y no puede darse por pasado"
  ck "no" "si" "rollback por backup ejecutado (bytes y modo exactos)"
fi

# ============================================================================
# 6. THIRD HASH / CRASH DETERMINISTIC
# ============================================================================
# 6a. Un WAL corrupto (un "tercer hash": ni el estado previo ni el nuevo) bloquea
#     el update en cerrado y NO deja el target a medias.
C="$tmp/homeC"; mkdir -p "$C"; chmod 700 "$C"
core install --root "$C" --plan "$PLAN" >/dev/null 2>&1
crash_target="$C/profiles/claude-reference-interactive.runtime-capability-v1.json"
crash_sha_before="$(sha256sum "$crash_target" | cut -d' ' -f1)"
printf 'no-es-un-wal-valido\n' > "$C/.cckit-txn.wal"; chmod 600 "$C/.cckit-txn.wal"
set +e; core install --root "$C" --plan "$PLAN" >"$tmp/crash.out" 2>&1; rcCrash=$?; set -e
ck "$([ "$rcCrash" -ne 0 ] && echo y || echo n)" "y" "crash: WAL corrupto (tercer estado) bloquea el update en cerrado"
ck "$(sha256sum "$crash_target" | cut -d' ' -f1)" "$crash_sha_before" "crash: el target no queda a medias (bytes intactos)"
ck "$(grep -qic 'fsck\|corrupto\|corrupt' "$tmp/crash.out" && echo y || echo n)" "y" "crash: el bloqueo dice como recuperarse (fsck)"

# 6b. Determinismo por repeticion: la MISMA entrada en dos homes independientes
#     produce el mismo owned-digest (ya visto en el paso 1) Y el mismo ledger
#     canonico byte a byte. Se compara, no se afirma.
D1="$tmp/det1"; D2="$tmp/det2"; mkdir -p "$D1" "$D2"; chmod 700 "$D1" "$D2"
core install --root "$D1" --plan "$PLAN" >/dev/null 2>&1
core install --root "$D2" --plan "$PLAN" >/dev/null 2>&1
led1="$("$PY" -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])),sort_keys=True))' "$D1/.cckit-owned.json")"
led2="$("$PY" -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])),sort_keys=True))' "$D2/.cckit-owned.json")"
ck "$led1" "$led2" "determinista: la misma entrada produce el mismo ledger canonico en dos homes"
ck "$(owned_digest "$D1")" "$(owned_digest "$D2")" "determinista: mismo owned-digest en dos homes independientes"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
