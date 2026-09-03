#!/usr/bin/env bash
# test_doctor_drift.sh — doctor tiene que distinguir DOS cosas opuestas que hoy
# colapsa en un solo WARN: una instalacion RANCIA (el fichero desplegado es una
# version antigua del propio kit -> fallo, hay que reinstalar) y una PERSONALIZADA
# (el fichero no coincide con ninguna version historica -> es del usuario, se avisa).
# Confundirlas es como nueve huecos de guardas cerrados en 69db95d siguieron abiertos
# en la maquina durante dias con doctor saliendo 0.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
REPO="$(cd "$KIT/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

if ! git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  echo "ok - el kit no es un checkout de git: suite omitida"; echo "== 1 passed, 0 failed =="; exit 0
fi

# Un HOME desplegado identico al kit: la linea base desde la que se fabrica cada caso.
preparar_home(){
  rm -rf "$tmp/dot"; mkdir -p "$tmp/dot/hooks/git"
  for f in "$KIT"/claude/hooks/*; do [ -f "$f" ] && cp "$f" "$tmp/dot/hooks/"; done
}
correr(){ env -u ANTHROPIC_BASE_URL CLAUDE_HOME="$tmp/dot" HOME="$tmp/home" \
            XDG_CONFIG_HOME="$tmp/home/.config" bash "$KIT/doctor.sh" 2>&1; }
mkdir -p "$tmp/home/.config"

# Un hook con al menos dos versiones en el historial: el segundo commit da el "rancio".
HOOK=""; VIEJO=""
for h in "$KIT"/claude/hooks/*.sh; do
  n="$(basename "$h")"
  v="$(git -C "$REPO" rev-list HEAD -- "kit/claude/hooks/$n" 2>/dev/null | sed -n '2p')"
  if [ -n "$v" ]; then HOOK="$n"; VIEJO="$v"; break; fi
done
if [ -z "$HOOK" ]; then
  echo "ok - ningun hook tiene dos versiones en el historial: suite omitida"
  echo "== 1 passed, 0 failed =="; exit 0
fi

# --- Caso 1: instalacion RANCIA -> FAIL, y doctor no puede salir 0 ---------
preparar_home
git -C "$REPO" show "$VIEJO:kit/claude/hooks/$HOOK" > "$tmp/dot/hooks/$HOOK"
out="$(correr)"; rc=$?
ck "$(printf '%s' "$out" | grep -qi 'version ANTIGUA del kit' && echo y || echo n)" "y" \
   "instalacion rancia: doctor la nombra como version antigua del kit ($HOOK)"
ck "$(printf '%s' "$out" | grep -qi "FAIL.*$HOOK" && echo y || echo n)" "y" \
   "instalacion rancia: se reporta como FAIL, no como WARN"
ck "$([ "$rc" -ne 0 ] && echo y || echo n)" "y" \
   "instalacion rancia: doctor sale con rc != 0 (hoy salia 0: ese era el fallo)"

# --- Caso 2: personalizacion local -> WARN, y NO se llama rancia -----------
preparar_home
printf '\n# personalizacion que no existio nunca en el kit %s\n' "$(date +%s%N)" \
  >> "$tmp/dot/hooks/$HOOK"
out2="$(correr)"
ck "$(printf '%s' "$out2" | grep -qi 'personalizacion local' && echo y || echo n)" "y" \
   "personalizacion: doctor la nombra como local"
ck "$(printf '%s' "$out2" | grep -qi 'version ANTIGUA del kit' && echo y || echo n)" "n" \
   "personalizacion: doctor NO la confunde con una instalacion rancia"

# --- Caso 3 (falsabilidad): identico al kit -> ni FAIL ni WARN por deriva --
preparar_home
out3="$(correr)"
ck "$(printf '%s' "$out3" | grep -qi 'version ANTIGUA del kit\|personalizacion local' && echo y || echo n)" "n" \
   "falsabilidad: sin deriva no se reporta ninguna de las dos (el check mira donde debe)"
ck "$(printf '%s' "$out3" | grep -qi 'coinciden byte a byte' && echo y || echo n)" "y" \
   "falsabilidad: sin deriva se reporta el PASS de siempre"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
