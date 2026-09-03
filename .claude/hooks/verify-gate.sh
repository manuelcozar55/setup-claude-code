#!/usr/bin/env bash
# Stop — dos modos, y la diferencia entre ellos es quien esta mirando.
#
#   MODO NORMAL (por defecto): AVISA si se toco codigo sin verificar. No bloquea.
#     Un falso positivo bloqueante deja la sesion atrapada, y el coste de eso es mucho
#     mayor que el de un aviso ignorado cuando hay un humano delante que puede reaccionar.
#
#   MODO AUTONOMO (hay un run activo): BLOQUEA hasta que el oraculo pase o se agoten los
#     intentos. Aqui no hay nadie mirando -- ese es el objetivo del modo -- asi que la
#     asimetria se invierte: el aviso que nadie lee no vale nada, y el unico control que
#     cierra el lazo es el que impide terminar. Es lo que dice la doc oficial: el Stop hook
#     es lo que "lets an unattended run finish correctly without you".
#
# Contrato Stop (verificado en code.claude.com/docs/en/hooks-guide, 2026-08-21):
#   bloquear = stdout {"decision":"block","reason":"..."}
#   'stop_hook_active' true => salir ya; Claude Code anula el hook tras 8 bloqueos
#   seguidos sin progreso (cap ajustable con CLAUDE_CODE_STOP_HOOK_BLOCK_CAP).
set -uo pipefail

STATE_DIR="${MCHARNESS_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/mcharness}"
payload=$(cat 2>/dev/null) || exit 0

if command -v jq >/dev/null 2>&1; then
  sid=$(printf '%s' "$payload" | jq -r '.session_id // "unknown"' 2>/dev/null)
  cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
  active=$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null)
else
  sid="unknown"; cwd="$PWD"; active="false"
fi
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
CONTRATO_SOPORTADO=1

bloquear() { jq -n --arg r "$1" '{decision:"block", reason:$r}'; exit 0; }

if command -v mch >/dev/null 2>&1; then
  # 10 s es holgado: gate solo lee ficheros sellados, no ejecuta el oraculo.
  gate_out=$(cd "$cwd" && timeout 10 mch task gate --json 2>/dev/null)
  gate_rc=$?

  case "$gate_rc" in
    # rc=0 significa "mch no objeta", NO "el turno esta verificado": lo devuelve
    # tambien cuando simplemente no hay ninguna tarea en curso de la que opinar.
    # Salir aqui con exit 0 apagaria en silencio todo lo que hay debajo -- incluido
    # un run autonomo en marcha -- en cualquier repo con TAREAS.md. Solo el rojo
    # cortocircuita; el verde se limita a no anadir nada.
    0)   : ;;
    2|3) : ;;                           # mch no gobierna aqui: sigue abajo, en modo aviso
    1)
      motivo=$(printf '%s' "$gate_out"   | jq -r '.motivo // "sin motivo"' 2>/dev/null)
      tarea=$(printf '%s' "$gate_out"    | jq -r '.tarea // "?"' 2>/dev/null)
      intentos=$(printf '%s' "$gate_out" | jq -r '.intentos // 0' 2>/dev/null)
      oraculo=$(printf '%s' "$gate_out"  | jq -r '.oraculo_sellado // "?"' 2>/dev/null)
      contrato=$(printf '%s' "$gate_out" | jq -r '.contrato // 0' 2>/dev/null)
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

AUT="$cwd/scripts/autonomy.sh"

# Se invoca SIEMPRE desde $cwd y SIN --session: la clave del estado es el directorio del
# proyecto. Pasar aqui el session_id del payload era el fallo original -- quien arranca el
# run (el modelo, por Bash) no conoce ese UUID, asi que escribia en otro fichero, el gate
# no encontraba nada y caia a modo normal sin bloquear. Fallaba en abierto y en silencio.
aut() { (cd "$cwd" && "$AUT" "$@"); }

# ─────────────────────────── MODO AUTONOMO ───────────────────────────
if [ -x "$AUT" ] && oracle=$(aut oracle 2>/dev/null) && [ -n "$oracle" ]; then
  out=$(cd "$cwd" && timeout 600 sh -c "$oracle" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    aut stop >/dev/null 2>&1
    printf '%s\n' "$out" | tail -5 >&2
    echo "── mcharness: oraculo VERDE, run autonomo cerrado ──" >&2
    exit 0
  fi

  n=$(aut attempt 2>/dev/null); arc=$?
  tail_out=$(printf '%s' "$out" | tail -25)

  if [ "$arc" -ne 0 ]; then
    # Presupuesto agotado: se deja terminar y se devuelve el control con el fallo delante.
    aut stop >/dev/null 2>&1
    {
      echo "── mcharness: presupuesto de reparaciones agotado ($n) ──"
      echo "El oraculo sigue en rojo. NO se ha aflojado el sensor: se para y se te devuelve."
      echo "$oracle -> exit $rc"
      echo "$tail_out"
    } >&2
    exit 0
  fi

  jq -n --arg r "El oraculo del run autonomo esta en ROJO (intento $n). No termines el turno.

Comando: $oracle
Exit: $rc
Salida (ultimas lineas):
$tail_out

Repara la causa, no el sintoma. PROHIBIDO tocar el propio sensor: si en 'git diff --name-only' aparece un fichero de test, un conftest, un pytest.ini, un umbral o el comando del oraculo, revierte ese cambio -- aflojar el sensor no cierra el lazo, lo rompe dejando apariencia de exito. Si crees que el test esta mal, para y dilo: eso se decide fuera de este lazo." \
    '{decision:"block", reason:$r}'
  exit 0
fi

# ─────────────────────────── MODO NORMAL ───────────────────────────
[ -f "$STATE_DIR/session-$sid.oracle" ] && exit 0

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
