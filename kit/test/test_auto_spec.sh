#!/usr/bin/env bash
# Verifica .claude/hooks/auto-spec.sh: el hook UserPromptSubmit que hace que el harness
# entre solo. Lo que se comprueba no es que "produzca texto", sino que DISCRIMINE:
# un clasificador que dice lo mismo ante cualquier entrada no clasifica nada.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
HOOK="$PWD/.claude/hooks/auto-spec.sh"
pass=0; fail=0

if ! command -v jq >/dev/null 2>&1; then
  echo "ok - jq no disponible: suite omitida (el hook tambien se auto-desactiva sin jq)"
  echo "== 1 passed, 0 failed =="; exit 0
fi

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export MCHARNESS_STATE="$T/state"

run() { # run <prompt> <session_id> [cwd]
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"UserPromptSubmit","prompt":%s}' \
    "$2" "${3:-$PWD}" "$(printf '%s' "$1" | jq -Rs .)" | "$HOOK" 2>/dev/null
}
ck() { if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1))
       else echo "NOT ok - $3 (obtenido '$1', esperado '$2')"; fail=$((fail+1)); fi; }
# ckhas <salida> <patron> <y|n esperado> <descripcion>. En if/then y no en 'A && B || C',
# que no es if-then-else: con ese patron C corre tambien cuando A es cierto y B falla.
ckhas() {
  local got=n
  printf '%s' "$1" | grep -q "$2" && got=y
  ck "$got" "$3" "$4"
}

# --- 1. Encargo sin criterio: el caso que justifica todo el hook -------------
o=$(run "arregla el bug del login" s1)
ckhas "$o" "no trae criterio de verificacion" y "encargo sin criterio -> pide criterio de aceptacion"
ckhas "$o" "make test" y "encargo sin criterio -> inyecta el oraculo detectado del proyecto"
ckhas "$o" "EN FRIO" y "encargo sin criterio -> exige ejecutar el oraculo en frio"

# --- 2. Pregunta: SILENCIO. Esta es la mitad que evita que el hook sea ruido --
o=$(run "como funciona el sistema de hooks?" s2)
ck "$(printf '%s' "$o" | grep -c . || true)" "0" "pregunta pura -> silencio total"
o=$(run "que hace la funcion verify_zip?" s3)
ck "$(printf '%s' "$o" | grep -c . || true)" "0" "otra pregunta -> silencio total"

# --- 3. Encargo QUE YA trae criterio: no se le sermonea ---------------------
# Es la rama que premia al usuario por escribir el criterio el mismo.
o=$(run "anade paginacion y verifica que make test siga en verde" s4)
ckhas "$o" "no trae criterio" n "encargo CON criterio -> NO repite la peticion de criterio"

# --- 4. El aviso del hook rtk (retirado en 1.1.0) ya no se inyecta ---------
o=$(run "escribe un test con pytest para el modulo" s5)
ckhas "$o" "rtk" n "prompt que menciona pytest -> NO avisa de un hook rtk que ya no existe"

# --- 5. El brief de errores sale una vez por sesion, no en cada prompt ------
o1=$(run "arregla el login" ses-brief); o2=$(run "arregla el logout" ses-brief)
ckhas "$o1" "Errores ya cometidos" y "primer encargo de la sesion -> incluye el brief de errores"
ckhas "$o2" "Errores ya cometidos" n "segundo encargo -> NO repite el brief"

# --- 6. Proyecto sin oraculo: lo dice, no se lo inventa ---------------------
mkdir -p "$T/vacio"
o=$(run "arregla el parser" s7 "$T/vacio")
ckhas "$o" "No se ha detectado oraculo" y "proyecto sin oraculo -> lo declara en vez de inventarlo"

# --- 7. Robustez: nunca debe romper la sesion ------------------------------
printf '%s' 'no-soy-json' | "$HOOK" >/dev/null 2>&1; ck "$?" "0" "entrada no-JSON -> exit 0 (nunca rompe el prompt)"
printf '' | "$HOOK" >/dev/null 2>&1;                 ck "$?" "0" "entrada vacia -> exit 0"
printf '{"prompt":""}' | "$HOOK" >/dev/null 2>&1;    ck "$?" "0" "prompt vacio -> exit 0"
# exit 2 en UserPromptSubmit BORRA el prompt del usuario: el hook no debe emitirlo jamas.
# Se filtran los comentarios: el hook DOCUMENTA por que no usa exit 2, y esa linea de
# prosa no debe hacer fallar el check. Lo que importa es que no lo EJECUTE.
codigo=$(grep -v '^[[:space:]]*#' "$HOOK")
ckhas "$codigo" 'exit 2' n "el hook no EJECUTA 'exit 2' (borraria el prompt del usuario)"

# --- 8. Falsabilidad: la salida CAMBIA con la entrada -----------------------
# Sin esto, todo lo anterior podria estar pasando por un hook que imprime siempre igual.
a=$(run "arregla el login" f1); b=$(run "que es un hook?" f2)
if [ "$a" != "$b" ] && [ -n "$a" ] && [ -z "$b" ]; then
  echo "ok - falsabilidad: encargo y pregunta producen salidas distintas (una llena, otra vacia)"; pass=$((pass+1))
else
  echo "NOT ok - el hook no discrimina: produce lo mismo ante entradas opuestas"; fail=$((fail+1))
fi

# --- 9. oracle-log: el marcador de sesion solo con un oraculo "plano" (sin rc: Claude Code no lo manda) ----
OLOG="$PWD/.claude/hooks/oracle-log.sh"
olog() { # olog <session_id> <comando>
  jq -n --arg s "$1" --arg c "$2" '{session_id:$s,tool_input:{command:$c}}' | "$OLOG" >/dev/null 2>&1
}
marca() { if [ -f "$MCHARNESS_STATE/session-$1.oracle" ]; then echo y; else echo n; fi; }
olog ol1b "make test | tail -n 5"
ck "$(marca ol1b)" "n" "oracle-log: tuberia sin rc -> no marca verde (el rc seria el de tail)"
olog ol2 "$(printf 'make test\n&& echo hecho')"
ck "$(grep -c "ol2.*make test.*hecho" "$MCHARNESS_STATE/oracle-runs.tsv")" "1" "oracle-log: comando multilinea -> una sola linea en el TSV"
olog ol3 "make test"
ck "$(marca ol3)" "y" "oracle-log: make test plano marca session-<sid>.oracle"
olog ol6 "make test || true"
ck "$(marca ol6)" "n" "oracle-log: 'make test || true' -> no marca verde"
olog ol7 "true; make test"
ck "$(marca ol7)" "n" "oracle-log: 'true; make test' -> no marca verde"
olog ol8 "oraculo -- make test"
ck "$(marca ol8)" "y" "oracle-log: 'oraculo -- make test' -> marca verde"
olog ol9 "make test"
ck "$(marca ol9)" "y" "oracle-log: 'make test' solo -> marca verde"
mkdir -p "$MCHARNESS_STATE/session-../esc"
olog "../esc/ol10" "make test"
ck "$([ -f "$MCHARNESS_STATE/session-___esc_ol10.oracle" ] && echo y || echo n)" "y" "oracle-log: sid con ../ se sanea y no escapa del directorio"
ck "$([ -e "$MCHARNESS_STATE/session-../esc/ol10.oracle" ] && echo y || echo n)" "n" "oracle-log: sid con ../ no crea rutas fuera del estado"
o=$(run "arregla el bug del login" s9)
ckhas "$o" "oraculo -- make test" y "auto-spec: recomienda 'oraculo -- <cmd>' para ejecutar el oraculo"

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ] || exit 1
