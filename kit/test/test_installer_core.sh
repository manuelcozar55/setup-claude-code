#!/usr/bin/env bash
# test_installer_core.sh — el nucleo del instalador (task 19).
#
# kit/lib/installer_core.py es un INTERPRETE de operaciones cerradas: recibe un
# PLAN declarativo (JSON) donde cada operacion nombra UNA de las cuatro
# primitivas de task-16 (copy-owned, json-merge-owned-keys, managed-text-block,
# diff-only) y la enruta a kit/lib/txnwrite.py. Sobre ese interprete monta los
# cuatro verbos de ciclo de vida install/doctor/diff/uninstall.
#
# Lo que este sensor exige, y por que:
#   A. El interprete existe y declara EXACTAMENTE las cuatro primitivas cerradas
#      (ni una generalizacion especulativa mas). Un plan que nombre una operacion
#      DESCONOCIDA falla ANTES de escribir un solo byte.
#   B. `install` enruta las escrituras propias por las primitivas: el target
#      aparece con los bytes/modo pedidos, y es idempotente.
#   C. `diff` NUNCA escribe (hereda diff-only).
#   D. `doctor` es de solo lectura: reporta el estado de lo propio sin mutar.
#   E. `uninstall` revierte SOLO lo que el core posee, dejando intacto lo manual.
#   F. Confinamiento heredado: ruta con symlink o '..' se rechaza pre-escritura.
#   G. CONFLICTO DE PROPIEDAD: si el target existe y NO es nuestro (otra huella
#      de propiedad / preimage que no reconocemos), install falla ANTES de pisar.
#   H. RECUPERACION: un install interrumpido a mitad se recupera de forma
#      idempotente (o bloquea), nunca deja el target en un tercer estado.
#   I. "Sin cambiar a Claude": la caracterizacion (scripts/claude-characterization.sh)
#      sigue coincidiendo byte-a-byte con la baseline sellada. El core es ADITIVO.
#
# Falsabilidad: cada rechazo (A/F/G) comprueba ADEMAS que el target no se
# escribio; un interprete que "rechaza" pero ya escribio no protege nada.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."; REPO="$(cd "$KIT/.." && pwd)"
CORE="$KIT/lib/installer_core.py"
PY=/usr/bin/python3
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

core(){ "$PY" -I "$CORE" "$@"; }

# ── A. existencia y superficie de primitivas cerradas ───────────────────────
ck "$([ -f "$CORE" ] && echo y || echo n)" "y" "kit/lib/installer_core.py existe"

set +e
ops="$(core --list-operations 2>/dev/null)"; rc=$?
set -e
ck "$rc" "0" "--list-operations responde rc=0"
ck "$ops" "copy-owned
diff-only
json-merge-owned-keys
managed-text-block" "el interprete enruta EXACTAMENTE las cuatro primitivas cerradas"

# Utilidad: escribe un plan JSON en $1 con un solo op copy-owned de $2 a dst $3.
plan_copy(){ # $1=path plan  $2=src  $3=dst
  "$PY" - "$1" "$2" "$3" <<'PYEOF'
import json,sys
path,src,dst=sys.argv[1],sys.argv[2],sys.argv[3]
json.dump({"schema":"installer-core-plan-v1","operations":[
  {"op":"copy-owned","src":src,"dst":dst,"mode":"0644"}]}, open(path,"w"))
PYEOF
}

# ── B. install enruta la escritura propia por copy-owned ────────────────────
ROOT="$tmp/hh"; mkdir -p "$ROOT"; chmod 700 "$ROOT"
SRC="$tmp/src.txt"; printf 'nucleo-uno\n' > "$SRC"
PLAN="$tmp/plan.json"; plan_copy "$PLAN" "$SRC" "a/b/c.txt"

set +e
core install --root "$ROOT" --plan "$PLAN" >/dev/null 2>&1; rc=$?
set -e
ck "$rc" "0" "install ejecuta el plan (rc=0)"
ck "$([ -f "$ROOT/a/b/c.txt" ] && echo y || echo n)" "y" "install escribio el target propio"
ck "$(cat "$ROOT/a/b/c.txt" 2>/dev/null)" "nucleo-uno" "install: bytes exactos"
ck "$(stat -c '%a' "$ROOT/a/b/c.txt" 2>/dev/null)" "644" "install: modo pedido"

# Idempotencia: mismo plan, mismo estado.
set +e; core install --root "$ROOT" --plan "$PLAN" >/dev/null 2>&1; rc=$?; set -e
ck "$rc" "0" "install idempotente (rc=0)"
ck "$(cat "$ROOT/a/b/c.txt" 2>/dev/null)" "nucleo-uno" "install idempotente: sin deriva"

# ── C. diff NUNCA escribe ───────────────────────────────────────────────────
printf 'nucleo-DOS\n' > "$SRC"           # el plan ahora propondria cambiar bytes
before="$(cat "$ROOT/a/b/c.txt" 2>/dev/null)"
set +e
core diff --root "$ROOT" --plan "$PLAN" >/dev/null 2>&1; rc=$?
set -e
ck "$rc" "0" "diff responde rc=0"
ck "$(cat "$ROOT/a/b/c.txt" 2>/dev/null)" "$before" "diff NO escribe (target intacto)"
printf 'nucleo-uno\n' > "$SRC"           # restaura el src para el resto

# ── D. doctor es solo lectura ───────────────────────────────────────────────
snap="$(find "$ROOT" -type f -exec sha256sum {} + | LC_ALL=C sort | sha256sum)"
set +e
core doctor --root "$ROOT" --plan "$PLAN" >/dev/null 2>&1; rc=$?
set -e
ck "$([ "$rc" -eq 0 ] && echo y || echo n)" "y" "doctor responde rc=0 sobre estado consistente"
snap2="$(find "$ROOT" -type f -exec sha256sum {} + | LC_ALL=C sort | sha256sum)"
ck "$snap" "$snap2" "doctor no muta el arbol"

# ── E. uninstall revierte SOLO lo propio, respeta lo manual ─────────────────
printf 'a-mano\n' > "$ROOT/manual.txt"; chmod 644 "$ROOT/manual.txt"
set +e
core uninstall --root "$ROOT" --plan "$PLAN" >/dev/null 2>&1; rc=$?
set -e
ck "$rc" "0" "uninstall responde rc=0"
ck "$([ -e "$ROOT/a/b/c.txt" ] && echo queda || echo retirado)" "retirado" "uninstall retira el target propio"
ck "$([ -f "$ROOT/manual.txt" ] && echo y || echo n)" "y" "uninstall PRESERVA el fichero manual"
ck "$(cat "$ROOT/manual.txt")" "a-mano" "uninstall no toca los bytes manuales"

# ── F. confinamiento: symlink y '..' se rechazan pre-escritura ──────────────
ROOTF="$tmp/hhF"; mkdir -p "$ROOTF"; chmod 700 "$ROOTF"
mkdir -p "$tmp/afuera"; ln -s "$tmp/afuera" "$ROOTF/enlace"
PLANF="$tmp/planF.json"; plan_copy "$PLANF" "$SRC" "enlace/x.txt"
set +e
core install --root "$ROOTF" --plan "$PLANF" >/dev/null 2>&1; rc=$?
set -e
ck "$([ "$rc" -ne 0 ] && echo y || echo n)" "y" "install rechaza symlink en la ruta (rc!=0)"
ck "$([ -e "$tmp/afuera/x.txt" ] && echo escapo || echo confinado)" "confinado" "no escribio fuera por el symlink"

PLANE="$tmp/planE.json"; plan_copy "$PLANE" "$SRC" "../fuera.txt"
set +e
core install --root "$ROOTF" --plan "$PLANE" >/dev/null 2>&1; rc=$?
set -e
ck "$([ "$rc" -ne 0 ] && echo y || echo n)" "y" "install rechaza '..' en dst (rc!=0)"
ck "$([ -e "$tmp/fuera.txt" ] && echo escapo || echo confinado)" "confinado" "no escribio via '..'"

# ── A(bis). operacion DESCONOCIDA falla pre-escritura ───────────────────────
ROOTU="$tmp/hhU"; mkdir -p "$ROOTU"; chmod 700 "$ROOTU"
PLANU="$tmp/planU.json"
"$PY" - "$PLANU" "$SRC" <<'PYEOF'
import json,sys
path,src=sys.argv[1],sys.argv[2]
json.dump({"schema":"installer-core-plan-v1","operations":[
  {"op":"exec-shell","src":src,"dst":"pwn.txt","cmd":"whoami"}]}, open(path,"w"))
PYEOF
set +e
core install --root "$ROOTU" --plan "$PLANU" >/dev/null 2>&1; rc=$?
set -e
ck "$([ "$rc" -ne 0 ] && echo y || echo n)" "y" "operacion desconocida se rechaza (rc!=0)"
ck "$([ -e "$ROOTU/pwn.txt" ] && echo escribio || echo bloqueado)" "bloqueado" "op desconocida no escribio nada"

# ── G. CONFLICTO DE PROPIEDAD: target ajeno preexistente bloquea pre-pisada ──
# Un target que ya existe con contenido que el core NO instalo (sin huella de
# propiedad) no puede pisarse a ciegas: es un conflicto de propiedad.
ROOTC="$tmp/hhC"; mkdir -p "$ROOTC/a/b"; chmod 700 "$ROOTC"
printf 'AJENO-no-lo-instale-yo\n' > "$ROOTC/a/b/c.txt"; chmod 644 "$ROOTC/a/b/c.txt"
PLANC="$tmp/planC.json"; plan_copy "$PLANC" "$SRC" "a/b/c.txt"
set +e
core install --root "$ROOTC" --plan "$PLANC" >/dev/null 2>&1; rc=$?
set -e
ck "$([ "$rc" -ne 0 ] && echo y || echo n)" "y" "conflicto de propiedad bloquea install (rc!=0)"
ck "$(cat "$ROOTC/a/b/c.txt" 2>/dev/null)" "AJENO-no-lo-instale-yo" "conflicto: no piso el fichero ajeno"

# ── H. RECUPERACION: un WAL de txnwrite corrupto en el root bloquea, no pisa ──
ROOTR="$tmp/hhR"; mkdir -p "$ROOTR"; chmod 700 "$ROOTR"
printf 'no-es-un-wal\n' > "$ROOTR/.cckit-txn.wal"; chmod 600 "$ROOTR/.cckit-txn.wal"
PLANR="$tmp/planR.json"; plan_copy "$PLANR" "$SRC" "d.txt"
set +e
core install --root "$ROOTR" --plan "$PLANR" >/dev/null 2>&1; rc=$?
set -e
ck "$([ "$rc" -ne 0 ] && echo y || echo n)" "y" "WAL corrupto bloquea el install (pide fsck)"
ck "$([ -e "$ROOTR/d.txt" ] && echo escribio || echo bloqueado)" "bloqueado" "no escribio con WAL corrupto"

# ── I. "sin cambiar a Claude": la caracterizacion sigue identica ────────────
CHAR="$REPO/scripts/claude-characterization.sh"
BASE="$HERE/fixtures/claude-characterization-baseline.json"
now="$(bash "$CHAR")"; base="$(cat "$BASE")"
ck "$([ "$now" = "$base" ] && echo y || echo n)" "y" "la caracterizacion de Claude sigue byte-a-byte identica (core aditivo)"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
