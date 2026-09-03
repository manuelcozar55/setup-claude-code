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
#   'stop_hook_active' true => salir ya; Claude Code anula el hook tras 8 bloqueos
#   seguidos sin progreso (cap ajustable con CLAUDE_CODE_STOP_HOOK_BLOCK_CAP).
set -uo pipefail

payload=$(cat 2>/dev/null) || exit 0

if command -v jq >/dev/null 2>&1; then
  HAY_JQ=1
  cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
  active=$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null)
else
  HAY_JQ=0
  cwd="$PWD"; active="false"
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
#
# Subido a 2 (T-042 en mcharness, F-3): ese contrato solo cambio el
# significado de `alcance` -- separo "sin comprobar" (una puerta anterior aun
# no llego al cotejo) de "no verificable" (se intento y no habia con que),
# dos cosas que antes compartian la misma cadena. Este hook nunca lee
# `alcance`. Las claves que si lee (gobierna, veredicto, evidencia, motivo,
# tarea, intentos, oraculo_sellado, contrato) no cambiaron de significado
# entre 1 y 2 -- comprobado contra _gate_estado()/_gate_alcance() en bin/mch.
CONTRATO_SOPORTADO=2

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
      if [ "$HAY_JQ" = 1 ]; then
        gobierna=$(printf '%s' "$gate_out"  | jq -r '.gobierna // false' 2>/dev/null)
        veredicto=$(printf '%s' "$gate_out" | jq -r '.veredicto // ""' 2>/dev/null)
        evidencia=$(printf '%s' "$gate_out" | jq -r '.evidencia // ""' 2>/dev/null)
        if [ "$gobierna" = "true" ] && [ "$veredicto" = "verde" ] && [ "$evidencia" = "completa" ]; then
          # El lazo esta cerrado y mch ya certifico: repetir el aviso de mas abajo
          # seria mentir. Termina aqui, sin stdout ni stderr.
          exit 0
        fi
      fi
      # Sin jq no se puede leer ningun campo del JSON: no se puede confirmar
      # lazo cerrado, asi que se cae al modo aviso. Perder un aviso sale barato;
      # fabricar un silencio que parece una certificacion no.
      ;;
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
