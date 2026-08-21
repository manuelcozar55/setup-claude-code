#!/usr/bin/env bash
# Verifica el modo autonomo: scripts/autonomy.sh y el Stop hook verify-gate.sh.
#
# Lo que importa aqui no es que el gate "haga algo", sino que haga lo correcto en los
# cuatro estados que deciden si un run desatendido es seguro: rojo (bloquea), verde
# (libera), presupuesto agotado (libera y avisa), y cap de Claude Code (se aparta).
# Un gate que se equivoque en el tercero o el cuarto secuestra la sesion del usuario.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
AUT="$PWD/scripts/autonomy.sh"
GATE="$PWD/.claude/hooks/verify-gate.sh"
pass=0; fail=0

if ! command -v jq >/dev/null 2>&1; then
  echo "ok - jq no disponible: suite omitida"; echo "== 1 passed, 0 failed =="; exit 0
fi

ck() { if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1))
       else echo "NOT ok - $3 (obtenido '$1', esperado '$2')"; fail=$((fail+1)); fi; }
# ckhas <texto> <patron> <y|n> <desc>. En if/then, no 'A && B || C': ese patron no es
# if-then-else y ejecuta C tambien cuando A es cierto pero B falla (MISTAKES M-003).
ckhas() { local got=n; printf '%s' "$1" | grep -qi "$2" && got=y; ck "$got" "$3" "$4"; }
# decision <salida-del-gate>: "ninguna" si el gate no emitio nada. Sin este guardia, un
# jq sobre cadena vacia devuelve vacio y no el default, que es como se cuela un falso
# negativo justo en el check que debe demostrar que el gate discrimina.
decision() { [ -n "$1" ] && printf '%s' "$1" | jq -r '.decision // "ninguna"' 2>/dev/null || echo "ninguna"; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export MCHARNESS_STATE="$T/state"
mkdir -p "$T/proj/scripts"; cp "$AUT" "$T/proj/scripts/autonomy.sh"
P="$T/proj"

pl() { printf '{"session_id":"%s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":%s}' \
       "$1" "$P" "${2:-false}"; }

# --- 1. El oraculo debe ser inmune a la reescritura de comandos (M-001) -----
"$AUT" start --session g0 --oracle "pytest -q" --goal "x" >/dev/null 2>&1
ck "$?" "1" "rechaza un oraculo por nombre suelto (seria reescrito: MISTAKES M-001)"
"$AUT" start --session g0 --oracle "make test" --goal "x" >/dev/null 2>&1
ck "$?" "0" "acepta 'make ...'"
"$AUT" start --session g0b --oracle "/usr/bin/true" --goal "x" >/dev/null 2>&1
ck "$?" "0" "acepta una ruta absoluta"
"$AUT" stop --session g0 >/dev/null 2>&1; "$AUT" stop --session g0b >/dev/null 2>&1

# --- 2. Presupuesto de intentos --------------------------------------------
"$AUT" start --session g1 --oracle "/bin/false" --goal "x" --max-repairs 2 >/dev/null
"$AUT" attempt --session g1 >/dev/null 2>&1; ck "$?" "0" "intento 1 dentro del presupuesto"
"$AUT" attempt --session g1 >/dev/null 2>&1; ck "$?" "0" "intento 2 dentro del presupuesto"
"$AUT" attempt --session g1 >/dev/null 2>&1; ck "$?" "1" "intento 3 agota el presupuesto de 2"
"$AUT" stop --session g1 >/dev/null

# --- 3. Gate con oraculo ROJO: bloquea -------------------------------------
"$AUT" start --session s1 --oracle "/bin/false" --goal "que pase" --max-repairs 3 >/dev/null
out=$(pl s1 | "$GATE" 2>/dev/null)
ck "$(decision "$out")" "block" "oraculo rojo -> {\"decision\":\"block\"}"
reason=$(printf '%s' "$out" | jq -r '.reason // ""' 2>/dev/null)
ckhas "$reason" "ROJO"   y "el motivo dice que el oraculo esta en rojo"
ckhas "$reason" "sensor" y "el motivo PROHIBE explicitamente aflojar el sensor"

# --- 4. Cap de Claude Code: el hook se aparta ------------------------------
# Si esto falla, el hook secuestra la sesion pese al mecanismo de seguridad del propio
# Claude Code. Es el fallo mas grave posible en un Stop hook.
r=$(pl s1 true | "$GATE" 2>/dev/null)
ck "$(printf '%s' "$r" | grep -c . || true)" "0" "stop_hook_active=true -> NO bloquea (respeta el cap de 8)"

# --- 5. Presupuesto agotado: libera en vez de insistir ---------------------
for _ in 1 2 3 4 5; do pl s1 | "$GATE" >/dev/null 2>&1; done
r=$(pl s1 | "$GATE" 2>/dev/null)
ck "$(printf '%s' "$r" | grep -c . || true)" "0" "agotado el presupuesto -> deja terminar (no insiste indefinidamente)"
"$AUT" status --session s1 >/dev/null 2>&1
ck "$?" "1" "y cierra el run autonomo al agotarlo"

# --- 6. Gate con oraculo VERDE: libera y cierra ----------------------------
"$AUT" start --session s2 --oracle "/bin/true" --goal "trivial" >/dev/null
r=$(pl s2 | "$GATE" 2>/dev/null)
ck "$(printf '%s' "$r" | grep -c . || true)" "0" "oraculo verde -> no bloquea"
"$AUT" status --session s2 >/dev/null 2>&1
ck "$?" "1" "oraculo verde -> cierra el run automaticamente"

# --- 7. Sin run activo: modo normal, nunca bloquea -------------------------
r=$(pl sin-run | "$GATE" 2>/dev/null)
ck "$(printf '%s' "$r" | grep -c . || true)" "0" "sin run autonomo -> modo normal, no emite bloqueo"

# --- 8. Falsabilidad: el gate DISCRIMINA entre rojo y verde ----------------
# Sin esto, todo lo anterior podria estar pasando con un gate que nunca bloquea.
"$AUT" start --session f1 --oracle "/bin/false" --goal "x" >/dev/null
rojo=$(decision "$(pl f1 | "$GATE" 2>/dev/null)")
"$AUT" stop --session f1 >/dev/null
"$AUT" start --session f2 --oracle "/bin/true" --goal "x" >/dev/null
verde=$(decision "$(pl f2 | "$GATE" 2>/dev/null)")
if [ "$rojo" = "block" ] && [ "$verde" = "ninguna" ]; then
  echo "ok - falsabilidad: rojo bloquea y verde no ('$rojo' vs '$verde')"; pass=$((pass+1))
else
  echo "NOT ok - el gate no discrimina rojo de verde ('$rojo' vs '$verde')"; fail=$((fail+1))
fi

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ] || exit 1
