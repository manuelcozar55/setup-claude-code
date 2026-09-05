#!/usr/bin/env bash
# test_claude_characterization.sh — el sensor del todo 14.
#
# Ata dos entregables al arbol ACTUAL (setup-claude-code @ 59fee491) para que los
# todos posteriores comparen contra una baseline que se pone en rojo ante deriva:
#
#   A. La FOTO de Claude (scripts/claude-characterization.sh) coincide byte-a-byte con la
#      baseline sellada kit/test/fixtures/claude-characterization-baseline.json.
#      Una deriva conocida de un byte en la superficie de Claude (kit/claude,
#      kit/sentinel) o en install/doctor/uninstall mueve el digest y ROMPE esto.
#
#   B. El expected-delta ledger (knowledge/CLAUDE-42-LEDGER.md) mapea EXACTAMENTE
#      los 42 hallazgos canonicos (F-01..F-42) a uno de cuatro estados permitidos,
#      cada linea con evidencia. Ni 41 ni 43: 42.
#
# Falsabilidad: si la foto no comparara nada (baseline copiada del propio output en
# caliente) el caso de deriva de A no podria fallar; por eso A2 verifica que la
# baseline NO esta vacia y A3 que un byte cambiado en la superficie la rompe.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
CHAR="$REPO/scripts/claude-characterization.sh"
BASELINE="$HERE/fixtures/claude-characterization-baseline.json"
LEDGER="$REPO/knowledge/CLAUDE-42-LEDGER.md"

pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

# ── A. Caracterizacion de Claude ────────────────────────────────────────────
ck "$( [ -f "$BASELINE" ] && echo y || echo n )" "y" "A0: existe la baseline sellada"
ck "$( [ -s "$BASELINE" ] && echo y || echo n )" "y" "A1: la baseline no esta vacia (si no, la comparacion no medira nada)"

now="$(bash "$CHAR")"
base="$( [ -f "$BASELINE" ] && cat "$BASELINE" || echo '<sin-baseline>')"
ck "$( [ "$now" = "$base" ] && echo y || echo n )" "y" "A2: la foto actual coincide byte-a-byte con la baseline"

# A3 (falsabilidad): una deriva de un byte en la superficie DEBE romper la foto.
# Se hace en un clon de trabajo temporal para no tocar el arbol real.
work="$(mktemp -d)"
cp -a "$REPO/kit" "$work/kit"; cp -a "$REPO/scripts" "$work/scripts"; cp -a "$REPO/uninstall.sh" "$work/uninstall.sh"
printf '\n# deriva deliberada de un byte\n' >> "$work/kit/claude/settings.json"
drift="$(cd "$work" && bash "$work/scripts/claude-characterization.sh")"
ck "$( [ "$drift" != "$base" ] && echo y || echo n )" "y" "A3: una deriva de 1 byte en kit/claude ROMPE la foto (el sensor sirve)"
find "$work" -mindepth 1 -delete 2>/dev/null || true; rmdir "$work" 2>/dev/null || true

# ── B. Expected-delta ledger de los 42 hallazgos ────────────────────────────
ck "$( [ -f "$LEDGER" ] && echo y || echo n )" "y" "B0: existe el ledger de 42 hallazgos"

# Cada F-ID canonico aparece exactamente una vez en una fila de tabla.
missing=""; dup=""
for n in $(seq -w 1 42); do
  c="$(grep -cE "^\| \*\*F-$n\*\* " "$LEDGER" 2>/dev/null || echo 0)"
  [ "$c" -eq 0 ] && missing="$missing F-$n"
  [ "$c" -gt 1 ] && dup="$dup F-$n(x$c)"
done
ck "$missing" "" "B1: los 42 F-IDs estan presentes (faltan:$missing)"
ck "$dup" "" "B2: ningun F-ID esta duplicado (dup:$dup)"

# Exactamente 42 filas de hallazgo, ni una mas.
rows="$(grep -cE '^\| \*\*F-[0-9]{2}\*\* ' "$LEDGER" 2>/dev/null || echo 0)"
ck "$rows" "42" "B3: hay exactamente 42 filas de hallazgo"

# Cada fila usa uno de los cuatro estados permitidos, y solo esos.
STATES='unresolved|fixed-at-59fee-with-regression|superseded|residual-hypothesis'
bad_state="$(grep -E '^\| \*\*F-[0-9]{2}\*\* ' "$LEDGER" \
  | grep -vE "\`($STATES)\`" | grep -oE 'F-[0-9]{2}' | tr '\n' ' ' || true)"
ck "$bad_state" "" "B4: toda fila declara un estado permitido (invalidas:$bad_state)"

# F-38 debe seguir siendo residual-hypothesis (no hay sanitizador de Read).
f38="$(grep -E '^\| \*\*F-38\*\* ' "$LEDGER" 2>/dev/null | grep -c 'residual-hypothesis' || true)"; f38="${f38:-0}"
ck "$f38" "1" "B5: F-38 permanece residual-hypothesis (no hay sanitizador de Read)"

echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
