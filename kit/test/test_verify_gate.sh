#!/usr/bin/env bash
# test_verify_gate.sh — el Stop hook contra el contrato `mch task gate`.
#
# Lo que se mide es la asimetria, que es la leccion de 6edfd73: AUSENCIA de autoridad
# (no hay mch, o mch dice que no gobierna) => NO bloquear, porque el kit tiene que
# seguir siendo util en los cientos de repos que no usan mch. AUTORIDAD PRESENTE QUE
# NO RESPONDE (timeout, rc desconocido) => BLOQUEAR, porque ahi el silencio es el fallo.
# Un gate que confunda esos dos casos falla en abierto justo cuando importa.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; RAIZ="$(cd "$HERE/../.." && pwd)"
GATE="$RAIZ/.claude/hooks/verify-gate.sh"
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

if ! command -v jq >/dev/null 2>&1; then
  echo "skip - jq ausente: esta suite decodifica con jq la decision JSON del gate"
  echo "== 0 passed, 0 failed, 1 skipped =="; exit 0
fi

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/proj"

# En if/then, no 'A && B || C': ese patron ejecuta C tambien cuando A es cierto
# pero B falla, y es como se cuela un falso negativo (MISTAKES M-003).
decision(){ if [ -n "$1" ]; then printf '%s' "$1" | jq -r '.decision // "ninguna"' 2>/dev/null
            else echo "ninguna"; fi; }
pl(){ printf '{"session_id":"s1","cwd":"%s","stop_hook_active":%s}' "$T/proj" "${1:-false}"; }

# `mch` de mentira: $1 rc, $2 json en stdout (sin comillas simples), $3 retardo.
fabrica_mch(){
  { echo '#!/usr/bin/env bash'
    [ -n "${3:-}" ] && echo "sleep $3"
    [ -n "${2:-}" ] && printf "printf '%%s\\\\n' '%s'\n" "$2"
    echo "exit $1"
  } > "$T/bin/mch"
  chmod +x "$T/bin/mch"
}
# $2 opcional: que copia del hook correr (por defecto $GATE). Lo usa H-2 para
# ejercitar una version "vieja" del hook sin mantener un segundo fichero real.
corre(){ printf '%s' "$(pl "${1:-false}")" | env PATH="$T/bin:$PATH" bash "${2:-$GATE}" 2>/dev/null; }

# Para el caso A6 no basta con borrar $T/bin/mch: en una maquina con mch instalado
# seguiria encontrandolo en el PATH del sistema y el test pasaria por la razon
# equivocada. Se construye un PATH del que se ha quitado todo directorio que
# contenga un mch ejecutable.
sin_mch_path(){
  printf '%s' "$PATH" | tr ':' '\n' | while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ -x "$d/mch" ] || printf '%s:' "$d"
  done
}
corre_sin_mch(){ printf '%s' "$(pl false)" | env PATH="$(sin_mch_path)" bash "$GATE" 2>/dev/null; }

# Para F-1 de degradacion no basta con quitar del PATH el directorio de jq como
# hace sin_mch_path: en esta maquina jq vive en /usr/bin junto con bash, git,
# grep... y quitar ese directorio entero se llevaria por delante el propio
# interprete del hook. Tampoco vale recorrer cada directorio del PATH real con
# un glob: esta maquina es WSL y varios directorios del PATH cuelgan del
# montaje 9P de Windows (/mnt/c/...), donde listar un directorio entero es
# minutos, no milisegundos. Se resuelve por nombre, uno a uno, solo lo que el
# hook necesita de verdad -- ni jq ni mch entran en esta lista.
sin_jq_path(){
  farm="$T/nojq"; mkdir -p "$farm"
  for b in bash cat git grep printf rm sed timeout; do
    p="$(command -v "$b" 2>/dev/null)" || continue
    ln -sf "$p" "$farm/$b" 2>/dev/null
  done
  printf '%s' "$T/bin:$farm"
}

ROJO='{"contrato":1,"gobierna":true,"veredicto":"rojo","motivo":"no hay ejecucion VERDE del oraculo registrada tras el ultimo start","tarea":"T-042","titulo":"x","clase":"sensor","oraculo_sellado":"pytest tests/ -q","intentos":7,"ultimo_run_rc":1,"alcance":"verificable","evidencia":"incompleta"}'
VERDE='{"contrato":1,"gobierna":true,"veredicto":"verde","motivo":"ok","tarea":"T-042","intentos":1}'
FUTURO='{"contrato":99,"gobierna":true,"veredicto":"rojo","motivo":"algo","tarea":"T-042","intentos":1}'
# rc=0 tiene DOS significados muy distintos y este es el segundo: mch no tiene ninguna
# tarea en curso de la que opinar. No dice que el turno este verificado.
SIN_TAREA='{"contrato":1,"gobierna":true,"veredicto":"verde","motivo":"no hay ninguna tarea en curso"}'
# El primer significado de rc=0 (F-1): lazo cerrado -- hay tarea, con sonda sellada y
# run VERDE. Comparte gobierna:true y veredicto:verde con SIN_TAREA; verificado contra
# _gate_estado() en bin/mch, solo `evidencia` distingue los dos casos.
VERDE_CERRADO='{"contrato":1,"gobierna":true,"veredicto":"verde","evidencia":"completa","motivo":"start con sonda sellada y run VERDE del oraculo sellado","tarea":"T-042","intentos":1}'

# --- A6: sin mch en PATH, NUNCA bloquea -----------------------------------
rm -f "$T/bin/mch"
ck "$(decision "$(corre_sin_mch)")" "ninguna" "A6: sin mch en PATH el hook no bloquea jamas"
# Falsabilidad del propio andamio: si sin_mch_path no quitara de verdad el mch del
# sistema, este test pasaria por la razon equivocada.
ck "$(env PATH="$(sin_mch_path)" command -v mch >/dev/null 2>&1 && echo encontrado || echo no)" "no" \
   "falsabilidad del andamio: el PATH recortado no tiene ningun mch"

# --- rc=3: mch no gobierna este proyecto -> no bloquea ---------------------
fabrica_mch 3 '{"contrato":1,"gobierna":false,"veredicto":"no-gobernado","motivo":"sin cola"}'
ck "$(decision "$(corre)")" "ninguna" "rc=3 (mch no gobierna aqui): no bloquea"

# --- rc=2: error de uso (version de mch sin el subcomando) -> no bloquea ---
fabrica_mch 2 ''
ck "$(decision "$(corre)")" "ninguna" "rc=2 (error de uso): se trata como 3, no bloquea"

# --- rc=0: mch no objeta -> este bloque no bloquea --------------------------
# Ojo: este caso pasa con las DOS implementaciones posibles del rc=0 (salir con exit 0,
# o seguir hacia abajo), porque el $T/proj temporal no es un repo git y el modo normal
# se calla igual. Por si solo no mide la diferencia; el ultimo caso de la suite si.
fabrica_mch 0 "$VERDE"
ck "$(decision "$(corre)")" "ninguna" "rc=0: mch no objeta y el hook no bloquea por su cuenta"

# --- A7: rc=1 -> BLOQUEA, y el motivo llega al modelo ----------------------
fabrica_mch 1 "$ROJO"
out="$(corre)"
ck "$(decision "$out")" "block" "A7: rc=1 (tarea en curso sin evidencia) bloquea"
razon="$(printf '%s' "$out" | jq -r '.reason // ""')"
ck "$(printf '%s' "$razon" | grep -qE '\bT-042\b' && echo y || echo n)" "y" "el bloqueo nombra la tarea"
ck "$(printf '%s' "$razon" | grep -q 'no hay ejecucion VERDE' && echo y || echo n)" "y" "el bloqueo lleva el motivo de mch"
ck "$(printf '%s' "$razon" | grep -qE '^Intentos registrados desde el ultimo start: 7$' && echo y || echo n)" "y" \
   "el bloqueo lleva los intentos derivados del journal"

# --- rc desconocido: autoridad presente que no responde -> BLOQUEA ---------
fabrica_mch 9 ''
ck "$(decision "$(corre)")" "block" "rc desconocido: fallo cerrado, bloquea"

# --- timeout: idem. El hook no puede esperar indefinidamente ni liberar ----
fabrica_mch 0 "$VERDE" 30
ck "$(decision "$(corre)")" "block" "timeout de mch: fallo cerrado, bloquea"

# --- contrato mas nuevo del que el hook entiende: bloquea Y lo advierte ----
fabrica_mch 1 "$FUTURO"
out2="$(corre)"
ck "$(decision "$out2")" "block" "contrato futuro: el rc sigue siendo el contrato estable"
ck "$(printf '%s' "$out2" | jq -r '.reason // ""' | grep -qi 'contrato' && echo y || echo n)" "y" \
   "contrato futuro: el hook advierte que puede no entender el detalle"

# --- el cap de Claude Code se respeta -------------------------------------
fabrica_mch 1 "$ROJO"
ck "$(decision "$(corre true)")" "ninguna" "stop_hook_active=true: el hook se aparta (cap de 8)"

# --- intentos altos: sigue bloqueando, y el modelo ve cuantos lleva --------
# Sustituye al caso "presupuesto agotado" del modo autonomo. La diferencia es que
# el presupuesto ya no se puede agotar borrando un fichero: 'intentos' se deriva
# de un journal append-only, y solo baja si alguien reescribe la historia.
AGOTADO='{"contrato":1,"gobierna":true,"veredicto":"rojo","motivo":"la ultima ejecucion registrada es ROJA (rc=1)","tarea":"T-042","clase":"sensor","oraculo_sellado":"make test","intentos":9,"ultimo_run_rc":1,"alcance":"verificable","evidencia":"incompleta"}'
fabrica_mch 1 "$AGOTADO"
out3="$(corre)"
ck "$(decision "$out3")" "block" "muchos intentos: sigue bloqueando (el presupuesto no se borra)"
ck "$(printf '%s' "$out3" | jq -r '.reason // ""' | grep -qE '^Intentos registrados desde el ultimo start: 9$' && echo y || echo n)" "y" \
   "el bloqueo dice cuantos intentos van"

# --- modo aviso: mch no gobierna y hay cambios sin verificar ---------------
# El kit tiene que seguir sirviendo en repos sin mch: avisa por stderr, no bloquea.
fabrica_mch 3 '{"contrato":1,"gobierna":false,"veredicto":"no-gobernado","motivo":"sin cola"}'
git -C "$T/proj" init -q 2>/dev/null
git -C "$T/proj" config user.email t@t; git -C "$T/proj" config user.name t
echo "base" > "$T/proj/f.txt"; git -C "$T/proj" add -A; git -C "$T/proj" commit -qm base
echo "cambio sin verificar" >> "$T/proj/f.txt"
err="$(printf '%s' "$(pl false)" | env PATH="$T/bin:$PATH" bash "$GATE" 2>&1 >/dev/null)"
ck "$(printf '%s' "$err" | grep -qi 'oraculo\|oráculo\|verific' && echo y || echo n)" "y" \
   "mch no gobierna + cambios sin verificar: avisa por stderr"
salida="$(printf '%s' "$(pl false)" | env PATH="$T/bin:$PATH" bash "$GATE" 2>/dev/null)"
ck "$(decision "$salida")" "ninguna" "mch no gobierna: avisa pero NO bloquea"

# --- rc=0 NO puede apagar lo que hay debajo (fallo en abierto) -------------
# La rama 0) del case cae hacia abajo a proposito: `gate` devuelve rc=0 tambien
# cuando no hay ninguna tarea en curso, y un `exit 0` ahi dejaria mudo el modo
# aviso en cualquier repo con TAREAS.md. Antes esto se medía contra el modo
# autonomo; retirado ese, se mide contra el aviso, que es lo que hay debajo ahora.
fabrica_mch 0 "$SIN_TAREA"
avisa="$(printf '%s' "$(pl false)" | env PATH="$T/bin:$PATH" bash "$GATE" 2>&1 >/dev/null)"
ck "$(printf '%s' "$avisa" | grep -qi 'oráculo' && echo y || echo n)" "y" \
   "rc=0 sin tarea en curso no apaga el modo aviso"
ck "$(decision "$(corre)")" "ninguna" "rc=0 avisa por stderr pero no bloquea"

# --- F-1: rc=0 con lazo cerrado en verde -> el aviso NO se repite ----------
# mch ya certifico (gobierna:true, veredicto:verde, evidencia:completa): repetir
# "NINGUN oraculo ejecutado" seria mentir. Caso nuevo que exige el brief.
fabrica_mch 0 "$VERDE_CERRADO"
ck "$(corre)" "" "F-1: lazo cerrado en verde no bloquea (stdout vacio)"
err_f1="$(printf '%s' "$(pl false)" | env PATH="$T/bin:$PATH" bash "$GATE" 2>&1 >/dev/null)"
ck "$(printf '%s' "$err_f1" | grep -qi 'NINGÚN oráculo ejecutado' && echo y || echo n)" "n" \
   "F-1: lazo cerrado en verde no repite 'NINGUN oraculo ejecutado' (mch ya certifico)"

# --- F-1 degradacion: mismo lazo cerrado, pero SIN jq -> no se puede leer el
# JSON, asi que no se puede confirmar el cierre: avisa igual. Perder un aviso
# sale barato; fabricar un silencio que parezca una certificacion no.
# 'command' es un builtin, no un ejecutable: 'env PATH=... command -v jq' no lo
# lanzaria (fallaria con "No such file or directory" y de rebote diria "no"
# aunque jq siguiera en el PATH). Por eso aqui se invoca con 'bash -c', que si
# arranca un interprete real con el PATH recortado.
ck "$(PATH="$(sin_jq_path)" bash -c 'command -v jq' >/dev/null 2>&1 && echo encontrado || echo no)" "no" \
   "falsabilidad del andamio: el PATH recortado no tiene ningun jq"
err_f1d="$( (cd "$T/proj" && printf '%s' "$(pl false)" | env PATH="$(sin_jq_path)" bash "$GATE") 2>&1 >/dev/null)"
ck "$(printf '%s' "$err_f1d" | grep -qi 'oráculo' && echo y || echo n)" "y" \
   "F-1 degradacion: sin jq, lazo cerrado en verde avisa igual (no se puede confirmar)"
salida_f1d="$( (cd "$T/proj" && printf '%s' "$(pl false)" | env PATH="$(sin_jq_path)" bash "$GATE") 2>/dev/null)"
ck "$(decision "$salida_f1d")" "ninguna" "F-1 degradacion sin jq: avisa pero no bloquea"

# --- H-2: el hook entiende el contrato 2 que emite mch hoy -----------------
# `mch task gate --json` subio de contrato 1 a 2 (T-042 en mcharness: separo
# 'sin comprobar' de 'no verificable', dos cosas que antes compartian cadena
# en `alcance`; este hook no lee esa clave). Aqui se prueban las DOS
# direcciones del desfase de version, y la que de verdad importa es la
# primera: un hook viejo desplegado, sin actualizar, tiene que seguir
# protegiendo a quien no lo haya subido -- bloquear Y avisar que el detalle
# puede estar incompleto. No se mantiene un segundo fichero para eso: se
# fabrica una copia del hook ACTUAL con CONTRATO_SOPORTADO parcheado de
# vuelta a 1, para no divergir de la logica real del `case` de mas arriba.
GATE_VIEJO="$T/verify-gate-viejo.sh"
sed 's/^CONTRATO_SOPORTADO=2$/CONTRATO_SOPORTADO=1/' "$GATE" > "$GATE_VIEJO"
chmod +x "$GATE_VIEJO"
ck "$(grep -c '^CONTRATO_SOPORTADO=1$' "$GATE_VIEJO")" "1" \
   "falsabilidad del andamio H-2: el hook viejo declara de verdad CONTRATO_SOPORTADO=1"

MCH2_ROJO='{"contrato":2,"gobierna":true,"veredicto":"rojo","motivo":"no hay ejecucion VERDE del oraculo registrada tras el ultimo start","tarea":"T-050","titulo":"y","clase":"sensor","oraculo_sellado":"pytest -q","intentos":2,"ultimo_run_rc":1,"alcance":"sin comprobar","evidencia":"incompleta"}'
fabrica_mch 1 "$MCH2_ROJO"
out_viejo="$(corre false "$GATE_VIEJO")"
ck "$(decision "$out_viejo")" "block" \
   "H-2: hook viejo (CONTRATO_SOPORTADO=1) contra mch en contrato 2 sigue bloqueando"
ck "$(printf '%s' "$out_viejo" | jq -r '.reason // ""' | grep -qi 'contrato' && echo y || echo n)" "y" \
   "H-2: hook viejo avisa de que mch habla un contrato mas nuevo del que entiende"

out_nuevo="$(corre)"
ck "$(decision "$out_nuevo")" "block" \
   "H-2: hook actual (CONTRATO_SOPORTADO=2) bloquea igual contra mch en contrato 2"
ck "$(printf '%s' "$out_nuevo" | jq -r '.reason // ""' | grep -qi 'contrato' && echo y || echo n)" "n" \
   "H-2: hook actual NO avisa -- entiende el contrato 2 de verdad, no es que perdiera el aviso"

# Mutacion CERCANA (2 -> 3), no lejana (no -> 99 como FUTURO mas arriba): fija
# el limite exacto de la comparacion en 'mas nuevo que 2', no en 'un numero
# grande cualquiera'. Sin este caso, un "> 2" roto como ">= 2" o un ">" que en
# realidad compara contra 1 seguirian pasando la asercion de arriba.
MCH3_ROJO='{"contrato":3,"gobierna":true,"veredicto":"rojo","motivo":"no hay ejecucion VERDE del oraculo registrada tras el ultimo start","tarea":"T-050","titulo":"y","clase":"sensor","oraculo_sellado":"pytest -q","intentos":2,"ultimo_run_rc":1,"alcance":"sin comprobar","evidencia":"incompleta"}'
fabrica_mch 1 "$MCH3_ROJO"
out_mut="$(corre)"
ck "$(decision "$out_mut")" "block" "H-2 mutacion cercana: mch en contrato 3 sigue bloqueando"
ck "$(printf '%s' "$out_mut" | jq -r '.reason // ""' | grep -qi 'contrato' && echo y || echo n)" "y" \
   "H-2 mutacion cercana: contrato 3 SI dispara el aviso (el limite esta en 2, no en 99)"

# --- L-1: sin jq, el camino ROJO tambien tiene que bloquear ----------------
# El andamio de arriba solo medía el camino VERDE ("avisa pero no bloquea"), y por
# eso la suite entera pasaba con `bloquear()` construyendo su veredicto con `jq -n`:
# sin jq ese `jq -n` falla, stdout queda VACIO y el `exit 0` de la funcion PERMITE
# el turno -- justo el que mch acababa de rechazar. La autoridad hablo y el que se
# quedo mudo fue el hook.
#
# Sin jq el mecanismo ya NO puede ser el JSON por stdout, asi que aqui no se mide
# `.decision`: se mide el CODIGO DE SALIDA, que es lo que el runtime honra en un
# hook Stop -- "Exit code 2 - show stderr to model and continue conversation"
# (documentacion del evento Stop embebida en el binario de claude 2.1.260; por
# dentro el runtime lo convierte en el mismo {"decision":"block"}). Es el mismo
# protocolo que J-1 dejo en kit/claude/hooks/destructive-guard.sh.
#
# El `cd` a $T/proj no es adorno: sin jq el hook no puede leer `.cwd` del payload y
# cae a $PWD, asi que el directorio real del proceso es el unico cwd que ve.
rc_sin_jq(){
  ( cd "$T/proj" && printf '%s' "$(pl false)" \
      | env PATH="$(sin_jq_path)" bash "$GATE" >"$T/out_sinjq" 2>"$T/err_sinjq" )
  echo $?
}

fabrica_mch 1 "$ROJO"
ck "$(rc_sin_jq)" "2" "L-1: rc=1 (lazo abierto) sin jq bloquea igual, por codigo de salida"

fabrica_mch 9 ''
ck "$(rc_sin_jq)" "2" "L-1: autoridad presente pero muda, sin jq, bloquea igual"
# El motivo tiene que llegar por stderr, que es de donde el runtime lo saca para
# el modelo cuando el hook sale con 2. Anclado por bordes: 'rc=9' como subcadena
# emparejaria tambien un 'rc=91' de otro camino.
ck "$(grep -qE '\brc=9\b' "$T/err_sinjq" && echo y || echo n)" "y" \
   "L-1: el bloqueo sin jq lleva el motivo por stderr"

# Regresion: la asimetria del OTRO lado se queda intacta. Sin mch no se bloquea, y
# tampoco por no tener jq: el kit tiene que seguir sirviendo en los cientos de
# repos que no usan mch. Sin este caso, "bloquear siempre" pasaria los dos de
# arriba y seria indistinguible del arreglo.
rm -f "$T/bin/mch"
ck "$(PATH="$(sin_jq_path)" bash -c 'command -v mch' >/dev/null 2>&1 && echo encontrado || echo no)" "no" \
   "falsabilidad del andamio: el PATH recortado no tiene ni jq ni mch"
ck "$(rc_sin_jq)" "0" "L-1 regresion: sin mch y sin jq el hook NO bloquea"


# --- M: sin jq pero CON python3 -> INDISTINGUIBLE de con jq ----------------
# L-1 (arriba) dejo el fallo cerrado, que es correcto pero convierte una maquina sin jq
# en una que bloquea TODO, tambien lo inocuo. Track M antepone un segundo eslabon:
# python3, que no es dependencia nueva -- kit/install.sh aborta si no puede crear el venv
# con el. El fallo cerrado sigue ahi, pero como ULTIMO recurso.
#
# La granja de L-1 (sin_jq_path) NO tiene python3, asi que sigue midiendo el tercer
# entorno; esta anade uno con python3 para medir el segundo.
sin_jq_con_py_path(){
  farm="$T/nojq_py"; mkdir -p "$farm"
  for b in bash cat git grep printf rm sed timeout python3; do
    p="$(command -v "$b" 2>/dev/null)" || continue
    ln -sf "$p" "$farm/$b" 2>/dev/null
  done
  printf '%s' "$T/bin:$farm"
}
ck "$(PATH="$(sin_jq_con_py_path)" bash -c 'command -v jq' >/dev/null 2>&1 && echo encontrado || echo no)" "no" \
   "falsabilidad del andamio M: la granja del segundo eslabon no tiene jq"
ck "$(PATH="$(sin_jq_con_py_path)" bash -c 'command -v python3' >/dev/null 2>&1 && echo encontrado || echo no)" "encontrado" \
   "falsabilidad del andamio M: la granja del segundo eslabon SI tiene python3 (es lo que mide)"
# Y la del ultimo recurso NO puede tener python3: si alguien se lo anade, los casos L-1
# de exit 2 de mas arriba dejarian de medir lo que dicen medir, y en silencio.
ck "$(PATH="$(sin_jq_path)" bash -c 'command -v python3' >/dev/null 2>&1 && echo encontrado || echo no)" "no" \
   "falsabilidad del andamio M: la granja del ultimo recurso tampoco tiene python3"

# Sin cd a $T/proj a proposito, al reves que en rc_sin_jq: aqui el hook SI puede leer
# `.cwd` del payload, y que lo lea es justo lo que se esta midiendo.
# El parametro opcional que tenia aqui no lo pasaba ninguna de las cuatro llamadas. El
# linter de la CI (mas viejo que el de esta maquina) lo ve como SC2120 y rompe el job; el
# de aqui no. Se va el parametro: `pl false` es lo que las cuatro querian decir.
# (Una linea de comentario que EMPIEZA por la palabra del linter se parsea como directiva
#  suya y da SC1073, asi que no se nombra al principio de linea.)
corre_py(){ printf '%s' "$(pl false)" | env PATH="$(sin_jq_con_py_path)" bash "$GATE" 2>/dev/null; }
rc_py(){
  printf '%s' "$(pl false)" | env PATH="$(sin_jq_con_py_path)" bash "$GATE" >"$T/out_py" 2>"$T/err_py"
  echo $?
}

fabrica_mch 1 "$ROJO"
ck "$(decision "$(corre_py)")" "block" \
   "M: rc=1 (lazo abierto) sin jq pero con python3 bloquea POR JSON, como con jq"
ck "$(rc_py)" "0" \
   "M: y con rc=0 -- el protocolo documentado de Stop, no el repuesto exit 2 de L-1"
ck "$(corre_py)" "$(corre)" \
   "M: el JSON del bloqueo es identico byte a byte al que produce jq"

# Lo que se olvida: que ademas de bloquear lo que debe, DEJE PASAR lo que debe. Sin estas
# tres, "bloquear siempre" pasaria las tres de arriba y pareceria el arreglo.
fabrica_mch 0 "$VERDE_CERRADO"
ck "$(corre_py)" "" "M: lazo cerrado en verde sin jq (con python3): no bloquea, stdout vacio"
err_py="$(printf '%s' "$(pl false)" | env PATH="$(sin_jq_con_py_path)" bash "$GATE" 2>&1 >/dev/null)"
ck "$(printf '%s' "$err_py" | grep -qi 'NINGÚN oráculo ejecutado' && echo y || echo n)" "n" \
   "M: con python3 el cierre YA se puede confirmar, asi que no repite el aviso (con jq tampoco)"

fabrica_mch 3 '{"contrato":1,"gobierna":false,"veredicto":"no-gobernado","motivo":"sin cola"}'
ck "$(decision "$(corre_py)")" "ninguna" \
   "M: mch no gobierna, sin jq (con python3): avisa pero NO bloquea"

# La asimetria del otro lado, intacta: el kit tiene que seguir sirviendo en los cientos
# de repos que no usan mch, y tampoco por no tener jq.
rm -f "$T/bin/mch"
ck "$(PATH="$(sin_jq_con_py_path)" bash -c 'command -v mch' >/dev/null 2>&1 && echo encontrado || echo no)" "no" \
   "falsabilidad del andamio M: la granja del segundo eslabon no tiene ningun mch"
ck "$(rc_py)" "0" "M regresion: sin mch y sin jq (pero con python3) el hook NO bloquea"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
