#!/usr/bin/env bash
# Stop — el turno solo termina cuando el motor del lazo puede DEMOSTRAR que se gano.
#
# Dos caminos, y cual se toma lo decide la AUTORIDAD, no la severidad:
#
#   mch GOBIERNA este proyecto: se le pregunta y se obedece su codigo de salida.
#     El criterio de exito vive en .agents/journal.jsonl, que es append-only: el
#     agente no puede borrarlo ni decrementarlo. Antes vivia en un fichero de
#     estado que el propio agente reescribia con sed -i y borraba con rm -f.
#
#   mch NO gobierna (no esta, o este repo no usa cola): modo aviso. Se dice que hay
#     cambios sin verificar y se deja terminar. Un falso positivo bloqueante en un
#     repo que no pidio nada deja la sesion atrapada, y eso cuesta mas que el aviso.
#
# Contrato Stop (code.claude.com/docs/en/hooks-guide, verificado 2026-08-21):
#   bloquear = stdout {"decision":"block","reason":"..."}
#   bloquear sin jq ni python3 = exit 2 con el motivo por stderr; el runtime lo
#     traduce a ese mismo {"decision":"block"} (ver bloquear(), verificado en 2.1.260)
#   'stop_hook_active' true => salir ya; Claude Code anula el hook tras 8 bloqueos
#   seguidos sin progreso (cap ajustable con CLAUDE_CODE_STOP_HOOK_BLOCK_CAP).
set -uo pipefail

payload=$(cat 2>/dev/null) || exit 0

# >>> hk-json ─────────────────────────────────────────────────────────────────
# Leer JSON sin depender de jq. Cadena de tres eslabones, en este orden:
#   1. jq si esta         -> el camino de siempre, sin cambiar un byte
#   2. python3 si no      -> json de la stdlib, parseo de verdad
#   3. ninguno de los dos -> fallo cerrado; quien llama decide como bloquear
# python3 NO es una dependencia nueva: kit/install.sh aborta con exit 1 si no puede crear
# el venv con `python3 -m venv`, y el kit ya distribuye cuatro hooks .py. jq, en cambio,
# no esta declarado como requisito en ningun sitio.
# PROHIBIDO parsear esto con grep/sed/awk: el payload lleva llaves, comillas y saltos de
# linea DENTRO de los valores, y una igualdad por subcadena es exactamente el defecto que
# este repo lleva media rama persiguiendo.
# Este bloque esta DUPLICADO en los seis hooks que leen JSON, y kit/test/test_guards.sh
# comprueba que los seis son identicos byte a byte. Se duplica en vez de compartirse
# porque un hook es un ejecutable hoja que el runtime lanza por ruta absoluta: ninguno de
# los 14 del kit hace `source` de nada, los cuatro guards se instalan en ~/.claude/hooks/
# mientras que auto-spec y verify-gate viven en el repo (no hay ruta relativa comun), y
# una libreria compartida anadiria a un control de seguridad un modo de fallo nuevo --
# libreria ausente => bloquear TODO.
if command -v jq >/dev/null 2>&1; then HK_JSON=jq
elif command -v python3 >/dev/null 2>&1; then HK_JSON=py
else HK_JSON=no; fi

# hk_get <ruta.punteada> [defecto]  --  JSON por stdin, valor por stdout.
# El contrato es el que ya tenia jq a solas, y de el depende todo lo de abajo:
#   rc=0 con salida vacia -> el campo no esta (permitir es lo correcto)
#   rc!=0                 -> no se ha podido leer la entrada (ciego: no puede autorizar)
# El defecto viaja por --arg/argv, nunca interpolado dentro del programa.
hk_get() {
  case "$HK_JSON" in
    jq) if [ $# -ge 2 ]; then jq -r --arg d "$2" ".$1 // \$d" 2>/dev/null
        else jq -r ".$1 // empty" 2>/dev/null; fi ;;
    py) python3 -c 'import json,sys
try: d = json.load(sys.stdin)
except Exception: sys.exit(5)
for k in sys.argv[1].split("."):
    if d is None: break
    if not isinstance(d, dict): sys.exit(5)
    d = d.get(k)
if d is None or d is False: d = sys.argv[2] if len(sys.argv) > 2 else None
if d is not None: print(d if isinstance(d, str) else json.dumps(d))' "$1" ${2+"$2"} 2>/dev/null ;;
    *)  return 127 ;;
  esac
}
# <<< hk-json ─────────────────────────────────────────────────────────────────

cwd=$(printf '%s' "$payload" | hk_get cwd)
active=$(printf '%s' "$payload" | hk_get stop_hook_active false)
[ -n "$cwd" ] || cwd="$PWD"

# El cap de 8 existe para que un hook mal escrito no secuestre la sesion. Respetarlo no
# es opcional: ignorarlo es como se construye el hook que todo el mundo acaba desactivando.
[ "$active" = "true" ] && exit 0

# ──────────────────────── EL CONTRATO CON mch ────────────────────────
# Este hook no tiene criterio propio: se lo pregunta al motor del lazo, que lee
# .agents/journal.jsonl -- la unica raiz de confianza. Dos lectores del journal
# divergen (mcharness/U4), asi que aqui solo hay uno, y no es este.
#
#   rc 0 -> el turno puede terminar        rc 1 -> no deberia (bloquear)
#   rc 2 -> error de uso                   rc 3 -> mch no gobierna este proyecto
#
# La asimetria del final es deliberada y es la leccion de 6edfd73:
#   ausencia de autoridad              => NO bloquear (el kit sirve sin mch)
#   autoridad presente que no responde => BLOQUEAR (fallo cerrado)
#
# Subido a 2 (T-042 en mcharness, F-3): ese contrato solo cambio el
# significado de `alcance` -- separo "sin comprobar" (una puerta anterior aun
# no llego al cotejo) de "no verificable" (se intento y no habia con que),
# dos cosas que antes compartian la misma cadena. Este hook nunca lee
# `alcance`. Las claves que si lee (gobierna, veredicto, evidencia, motivo,
# tarea, intentos, oraculo_sellado, contrato) no cambiaron de significado
# entre 1 y 2 -- comprobado contra _gate_estado()/_gate_alcance() en bin/mch.
CONTRATO_SOPORTADO=2

# Con jq, el veredicto va por stdout: es el contrato documentado del evento Stop.
# Sin jq, `jq -n` fallaba, stdout quedaba VACIO y el `exit 0` de aqui PERMITIA el
# turno -- justo el que mch acababa de rechazar. Autoridad presente que habla y
# hook que se queda mudo: exactamente la asimetria que este fichero declara, al
# reves.
#
# Desde Track M ese caso casi no se alcanza: sin jq el veredicto lo construye
# python3 y sale por stdout con el MISMO JSON, asi que se respeta el contrato
# documentado y no se pierden ni el motivo ni los campos. El repuesto por codigo
# de salida queda para el ULTIMO recurso -- ni jq ni python3 -- y no necesita nada
# instalado: es el mismo protocolo que J-1 dejo en
# kit/claude/hooks/destructive-guard.sh, salir con 2 y el motivo por stderr.
# Verificado contra el binario que lo ejecuta (claude 2.1.260), no
# supuesto: la doc del evento Stop que trae dentro dice "Exit code 2 - show
# stderr to model and continue conversation", y su interprete de resultados
# convierte ese 2 en el mismo {"decision":"block", reason:<stderr>} -- la
# excepcion que Stop SI tiene (no bloquear con 2) es solo para hooks que anuncian
# `async` por stdout, que no es el caso. Sin ningun parser los campos que vienen
# del JSON de mch salen vacios; el bloqueo no depende de ellos, y se dice en vez
# de presentar huecos como si fueran la respuesta del gate.
bloquear() {
  if [ "$HK_JSON" = jq ]; then
    jq -n --arg r "$1" '{decision:"block", reason:$r}'
    exit 0
  fi
  if [ "$HK_JSON" = py ]; then
    python3 -c 'import json,sys
print(json.dumps({"decision": "block", "reason": sys.argv[1]}, indent=2, ensure_ascii=False))' "$1"
    exit 0
  fi
  printf '%s\n\n(sin jq ni python3: los campos leidos del JSON de mch salen vacios; el veredicto del gate, que es un codigo de salida, no.)\n' "$1" >&2
  exit 2
}

if command -v mch >/dev/null 2>&1; then
  # 10 s es holgado: gate solo lee ficheros sellados, no ejecuta el oraculo.
  gate_out=$(cd "$cwd" && timeout 10 mch task gate --json 2>/dev/null)
  gate_rc=$?

  case "$gate_rc" in
    # rc=0 significa "mch no objeta", NO "el turno esta verificado": lo devuelve
    # tambien cuando simplemente no hay ninguna tarea en curso de la que opinar.
    # Salir aqui con exit 0 apagaria en silencio todo lo que hay debajo -- incluido
    # un run autonomo en marcha -- en cualquier repo con TAREAS.md. Solo el rojo
    # cortocircuita; el verde se limita a no anadir nada... salvo en el unico
    # sub-caso en que mch SI se ha pronunciado: lazo cerrado en verde.
    #
    # _gate_estado() en mch (bin/mch) tiene DOS ramas con rc=0, y ambas devuelven
    # gobierna:true y veredicto:verde -- esas dos claves NO alcanzan para
    # distinguirlas. Solo `evidencia` lo hace: la rama "no hay ninguna tarea en
    # curso" no trae esa clave; la rama "start con sonda sellada y run VERDE"
    # trae evidencia:"completa". Exigir tambien evidencia=="completa" es el
    # criterio mas estrecho que de verdad discrimina; gobierna+veredicto solos
    # (la sugerencia obvia) habrian apagado el aviso tambien cuando no hay
    # tarea en curso, que es justo el caso que R29 esta aqui para no repetir.
    0)
      if [ "$HK_JSON" != no ]; then
        gobierna=$(printf '%s' "$gate_out"  | hk_get gobierna false)
        veredicto=$(printf '%s' "$gate_out" | hk_get veredicto "")
        evidencia=$(printf '%s' "$gate_out" | hk_get evidencia "")
        if [ "$gobierna" = "true" ] && [ "$veredicto" = "verde" ] && [ "$evidencia" = "completa" ]; then
          # El lazo esta cerrado y mch ya certifico: repetir el aviso de mas abajo
          # seria mentir. Termina aqui, sin stdout ni stderr.
          exit 0
        fi
      fi
      # Sin jq NI python3 no se puede leer ningun campo del JSON: no se puede
      # confirmar lazo cerrado, asi que se cae al modo aviso. Perder un aviso sale
      # barato; fabricar un silencio que parece una certificacion no.
      ;;
    2|3) : ;;                           # mch no gobierna aqui: sigue abajo, en modo aviso
    1)
      motivo=$(printf '%s' "$gate_out"   | hk_get motivo "sin motivo")
      tarea=$(printf '%s' "$gate_out"    | hk_get tarea "?")
      intentos=$(printf '%s' "$gate_out" | hk_get intentos 0)
      oraculo=$(printf '%s' "$gate_out"  | hk_get oraculo_sellado "?")
      contrato=$(printf '%s' "$gate_out" | hk_get contrato 0)
      # Un contrato mas nuevo del que este hook entiende: el rc sigue siendo el
      # contrato estable, asi que el bloqueo se mantiene; lo que se degrada es la
      # confianza en el detalle, y se dice.
      nota=""
      if [ "$contrato" -gt "$CONTRATO_SOPORTADO" ] 2>/dev/null; then
        nota="

(aviso: mch habla contrato $contrato y este hook entiende $CONTRATO_SOPORTADO: el detalle de arriba puede estar incompleto.)"
      fi
      bloquear "El lazo no esta cerrado: $tarea sigue en curso sin evidencia suficiente. No termines el turno.

Motivo: $motivo
Oraculo sellado: $oraculo
Intentos registrados desde el ultimo start: $intentos

Repara la causa, no el sintoma. PROHIBIDO tocar el propio sensor: mch lo detecta por huella SHA-256 sellada en el start y \`mch task done\` rechazara el cierre. Si crees que el test esta mal, para y dilo: eso se decide fuera de este lazo.
Cuando el oraculo pase: \`mch task run $tarea\` y luego \`mch task done $tarea\`.$nota"
      ;;
    *)
      bloquear "El motor del lazo (mch) esta presente pero no pudo responder: \`mch task gate\` salio con rc=$gate_rc (124 = timeout).

No termines el turno dando por bueno lo que no se ha podido comprobar. Ejecuta \`mch task gate\` a mano en $cwd y arregla la causa."
      ;;
  esac
fi

# ─────────────────────────── MODO AVISO ───────────────────────────
# Solo habla si de verdad se toco codigo: en una sesion de lectura el aviso seria el ruido
# que hace que manana se ignore el aviso que si importaba.
git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || exit 0
changed=$(git -C "$cwd" diff --name-only 2>/dev/null | grep -c . || true)
staged=$(git -C "$cwd" diff --cached --name-only 2>/dev/null | grep -c . || true)
[ "$((changed + staged))" -gt 0 ] || exit 0

oracle=""
[ -x "$cwd/scripts/detect-oracle.sh" ] && oracle=$("$cwd/scripts/detect-oracle.sh" "$cwd" 2>/dev/null | head -1)

{
  echo "── mcharness ──────────────────────────────────────────────"
  echo "  $((changed + staged)) fichero(s) modificado(s) y NINGÚN oráculo ejecutado."
  [ -n "$oracle" ] && echo "  Oráculo de este proyecto: $oracle"
  echo "  Evidencia antes que afirmaciones:  /verify"
  echo "───────────────────────────────────────────────────────────"
} >&2

exit 0
