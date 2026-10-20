#!/usr/bin/env bash
# test_presupuesto_contexto.sh — tope de contexto por canal (ADR 018). Sin red. Mide con
# scripts/contexto-base.sh --peor (nucleo.md de 24 KB, ruta de ~200 chars, dueño ajeno, todos los avisos
# encendidos, la entrada sintética de cada guard) y falla si un canal pasa de su tope. Los topes son la medida
# del 20-oct (knowledge/COST-LOG.md, «Presupuesto por canal») + 10 %, subida a la centena.
# Subir un tope exige repetir la medida y apuntarla en COST-LOG.md: no se sube «por si acaso».
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$HERE/../.." && pwd)"
pass=0; fail=0

# prefijo de la fila de contexto-base.sh | tope en caracteres
TOPES='instrucciones globales|6900
SessionStart compact|9500
SessionStart startup|9500
SessionStart clear|9500
SessionStart resume|9500
SessionStart memoria|100
PostToolUse nucleo-nudge|600
Stop context-gauge|400
write-guard (fichero nuevo|500
write-guard (secretos|600
stale-read-guard|800
narthex|1400
UserPromptSubmit|0
agentes: suma|2600
skills: suma|900'
TOPE_AGENTE=500   # la mayor description de un agente
SKIP_W3='bloque de agentes|800'   # lo añade W3 a SessionStart: SKIP hasta que se fusione; lo cierra el hilo principal

TAB=$(bash "$REPO/scripts/contexto-base.sh" --peor 2>&1) || { echo "NOT ok - contexto-base.sh --peor falla"; echo "$TAB" | tail -n 5; exit 1; }
cifra() { awk -v p="$1" 'index($0, p) == 1 { print $(NF-1); exit }' <<<"$TAB"; }

# juzga: canal cifra tope -> 0 si cabe. Pasarse es FAIL con el canal, la cifra y el tope.
juzga() { [ -n "$2" ] && [ "$2" -le "$3" ]; }
ck() { # canal cifra tope
  if juzga "$1" "$2" "$3"; then echo "ok - $1: $2 <= $3"; pass=$((pass+1))
  else echo "NOT ok - $1: ${2:-sin medida} pasa del tope $3"; fail=$((fail+1)); fi
}
while IFS='|' read -r canal tope; do ck "$canal" "$(cifra "$canal")" "$tope"; done <<<"$TOPES"

mayor=$(awk '/^agente /{ if ($(NF-1) > m) m = $(NF-1) } END { print m }' <<<"$TAB")
ck "agente con la mayor description" "$mayor" "$TOPE_AGENTE"
echo "SKIP - ${SKIP_W3%|*}: tope ${SKIP_W3#*|} (W3)"

# falsable: un caracter por encima del tope tiene que dar FAIL, y en el tope exacto, ok
while IFS='|' read -r canal tope; do
  if juzga "$canal" $((tope + 1)) "$tope" || ! juzga "$canal" "$tope" "$tope"; then
    echo "NOT ok - falsable: $canal no distingue tope+1 de tope"; fail=$((fail+1))
  else echo "ok - falsable: $canal da FAIL con tope+1"; pass=$((pass+1)); fi
done <<<"$TOPES"

echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
