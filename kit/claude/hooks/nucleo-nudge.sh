#!/usr/bin/env bash
# QUE-HACE: avisa del consumo de contexto: al modelo al 50, 70 y 85 % del airbag (que guarde el estado) y a la persona al 60 y 85 % (que cierre fase), una vez por banda y sesión.
# PostToolUse (todas las herramientas) — único emisor de avisos de contexto (antes los repartía con stop-context-gauge.sh).
# Al MODELO (additionalContext) le pide que actualice nucleo.md antes de que el airbag compacte; a la PERSONA
# (systemMessage, una vez por banda) le dice cuándo cerrar fase, con /handoff si hay cockpit y con el CLI si no.
# Tabla de bandas (% del airbag) más abajo: BANDAS_MODELO y BANDAS_PERSONA. Por qué el aviso al modelo: el del Stop llegaba solo a la persona y al final del turno, pero la
# mayoría de las compactaciones caen dentro de un turno autónomo; medido, 3 de cada 4 llegaban con
# el nucleo sin escribir en los 20 turnos previos. additionalContext llega junto al tool_result.
# Una vez por banda y sesión, y solo si nucleo.md tiene más de 10 min, no
# existe o pasa del tope; bajo el 50 % se rearman (compactar no cambia el session_id). Sin nada que decir, salida
# vacía. Camino caliente: corre tras cada herramienta.
set -u
IN=$(cat)
{ read -r SID; read -r TP; read -r CWD; read -r AID; } < <(jq -r '.session_id // "", .transcript_path // "", .cwd // "", .agent_id // ""' <<<"$IN" 2>/dev/null)
# agent_id solo viene dentro de un subagente (code.claude.com/docs/en/hooks): el aviso es para el hilo
# principal, que es quien escribe nucleo.md y cierra el turno; un Explore recibió «actualiza nucleo.md».
[ -z "${AID:-}" ] || exit 0
case "${SID:-}" in ''|*[!A-Za-z0-9_-]*) exit 0;; esac   # va a un nombre de fichero
[ -f "${TP:-}" ] || exit 0
# shellcheck source=SCRIPTDIR/lib/nucleo.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/nucleo.sh"
# Lo barato primero (transcript y marca de banda): bajo el 50 % o con la banda ya avisada no se lanza git
# ni se mira el nucleo. Efecto: la marca también se rearma con el nucleo fresco.
read -r CTX PCT <<<"$(nucleo_ctx "$TP")"
[ -n "${PCT:-}" ] || exit 0
MARCA=$HOME/.claude/session-logs/nudge-$SID
# Tabla única de bandas, de mayor a menor. Modelo: pide guardar. Persona: pide cerrar fase. El 60 % lo daba el gauge.
BANDAS_MODELO="85 70 50"; BANDAS_PERSONA="85 60"
banda() { B=""; local b; for b in $1; do if [ "$PCT" -ge "$b" ]; then B=$b; return; fi; done; }
banda "$BANDAS_MODELO"; BM=$B; banda "$BANDAS_PERSONA"; BP=$B
if [ -z "$BM" ]; then [ -s "$MARCA" ] && : >"$MARCA"; exit 0; fi
WM=1; command grep -qx "$BM" "$MARCA" 2>/dev/null && WM=0
# -p/SDK: no hay persona a quien avisar.
WP=0; [ -n "$BP" ] && ! command grep -qx "p$BP" "$MARCA" 2>/dev/null && ! nucleo_desatendido && WP=1
[ "$WM$WP" != 00 ] || exit 0
RAIZ=$(nucleo_raiz "${CWD:-$PWD}")
nucleo_enlazado "$RAIZ" && exit 0
NOM=nucleo.md
# ESTADO.md sin nucleo.md propio es el estado del proyecto (lib/nucleo.sh): se avisa de él y no se manda a handoff.
if nucleo_modo_estado_md "$RAIZ"; then NUC=$RAIZ/ESTADO.md; NOM=ESTADO.md
else NUC=$(nucleo_ruta "$RAIZ" crear) || exit 0
fi
# Desde ~ con ranura (se sabe el pid de la sesión) el nucleo es el de la ranura, el que usa handoff: se trata como el de
# un proyecto.
RANURA=""; [ "$RAIZ" = "$HOME" ] && case $NUC in "$HOME"/.claude/estado/sesiones/*/nucleo.md) RANURA=${NUC%/nucleo.md};; esac
SOLOHOME=0; [ "$RAIZ" = "$HOME" ] && [ -z "$RANURA" ] && SOLOHOME=1
# Una tarea = una sesión dueña: quien no lo es no recibe la orden de escribir el nucleo de otra (handoff le daría rc 5).
AJENO=0; [ "$SOLOHOME" = 0 ] && [ -z "$RANURA" ] && nucleo_dueno_ajeno "$RAIZ" "$SID" >/dev/null && AJENO=1
HO=handoff; command -v handoff >/dev/null 2>&1 || HO=${CLAUDE_HOME:-$HOME/.claude}/bin/handoff
# Con la sesión vinculada a un proyecto (handoff --proyecto) el estado es el del proyecto, pero el Bash tool no sabe qué ranura es la suya: la orden la lleva.
VSLOT=""; [ "$RAIZ" = "$HOME" ] || { nucleo_vinculo >/dev/null 2>&1 && VSLOT=$(nucleo_sesion_dir 2>/dev/null); }
CL="$HO --desde <borrador> --sesion $SID${RANURA:+ --ranura $RANURA}${VSLOT:+ --ranura $VSLOT}"
mkdir -p "$(dirname "$MARCA")" 2>/dev/null
M=""; PM=""

# Aviso al modelo (additionalContext). rc 1: nada que decir, y no se marca la banda (se reintenta en la siguiente herramienta).
modelo() {
  local MT EDAD SZ T HIST A B=$BM
  if [ "$SOLOHOME" = 1 ]; then
    # D1: desde ~ sin ranura el nucleo compartido puede ser de otra tarea: el aviso no lo nombra, no se calla por su edad
    # y no promete handoff (sin ranura el cockpit tampoco lo hace por su cuenta: «sin ranura» en su log).
    echo "$B" >>"$MARCA"
    M="CONTEXTO $PCT % del airbag. Sesión abierta desde ~: no tiene nucleo propio. Si trabajas en una tarea, deja su estado en el nucleo de su proyecto; el de ~ actualízalo solo si su Objetivo es tu tarea."
    if nucleo_desatendido; then
      [ "$B" = 50 ] || M="$M Sesión no interactiva: deja el estado donde corresponda y sigue con la tarea; nadie cerrará ni limpiará la sesión."
    else
      [ "$B" = 70 ] && M="$M Fin de fase = parada válida: si hay agentes en vuelo, no lances más: espera y recoge sus resultados; después termina la fase, deja su estado donde corresponda y cierra el turno."
      [ "$B" = 85 ] && M="$M Cierra el turno ya."
    fi
    return 0
  fi
  [ "$AJENO" = 0 ] || return 1
  MT=$(stat -c %Y "$NUC" 2>/dev/null || stat -f %m "$NUC" 2>/dev/null)
  EDAD=$(( $(date +%s) - ${MT:-0} ))
  # Editado a mano no pasa por el tope de handoff: pasado el tope, al retomar se omiten secciones enteras.
  # Es el mismo tope con el que escribe handoff, con la reserva del bloque de agentes ya descontada. Se mira
  # también con el nucleo fresco: recién inflado es justo cuando hay que avisar.
  SZ=0; T=$((NUCLEO_TOPE - NUCLEO_RESERVA_AGENTES))
  [ -z "$MT" ] || SZ=$(wc -c <"$NUC" 2>/dev/null | tr -d ' ')
  [ -z "$MT" ] || [ "$EDAD" -gt 600 ] || [ "${SZ:-0}" -gt "$T" ] || return 1
  echo "$B" >>"$MARCA"
  if [ "$NOM" = ESTADO.md ]; then HIST="saca lo cerrado del fichero"; else HIST="pasa lo cerrado a diario.md"; fi
  if [ -n "$MT" ] && [ "$EDAD" -le 600 ]; then
    M="CONTEXTO $PCT % del airbag. $NUC ocupa $SZ B (tope $T): antes de la siguiente herramienta, $HIST; si no, al retomar se omitirán secciones enteras."
  elif [ -n "$MT" ]; then
    M="CONTEXTO $PCT % del airbag. $NOM lleva $((EDAD / 60)) min sin actualizar: antes de la siguiente herramienta actualiza Paso actual / Siguiente acción / Pendientes en $NUC."
    [ "${SZ:-0}" -le "$T" ] || M="$M Ocupa $SZ B (tope $T): $HIST."
  else
    M="CONTEXTO $PCT % del airbag y no hay nucleo.md: antes de la siguiente herramienta créalo en $NUC con la forma de \$HOME/.claude/templates/nucleo.md."
  fi
  if [ "$NOM" = ESTADO.md ]; then
    [ "$B" != 70 ] || M="$M Si hay agentes en vuelo, no lances más: espera y recoge sus resultados; después cierra la fase con \`$CL\`."
    [ "$B" != 85 ] || M="$M Cierra el turno ya."
  elif nucleo_desatendido; then
    # -p/SDK: nadie pulsa /handoff ni cierra el turno, y cerrarlo termina la sesión. Con acceptEdits, Write/Edit bajo
    # .claude/ se deniegan, pero handoff (un script por Bash) sí escribe: el borrador va fuera de .claude/.
    [ "$B" = 50 ] || M="$M Sesión no interactiva: deja el estado con \`$CL\` (borrador fuera de .claude/) o editando nucleo.md, y sigue con la tarea; nadie cerrará ni limpiará la sesión."
  else
    if nucleo_cockpit; then
      [ "$B" = 70 ] && M="$M Fin de fase = parada válida: si hay agentes en vuelo, no lances más: espera y recoge sus resultados; después cierra la fase, escribe el handoff con \`$CL\` y termina el turno. Con /autonomo on el trabajo sigue solo tras el /clear."
      A="con cockpit en un proyecto, el handoff y /clear son automáticos al cerrar el turno; si no, la persona hará /handoff."
      [ "${COCKPIT_AUTO_HANDOFF:-}" = off ] && A="el handoff automático está desactivado; la persona hará /handoff."
    else
      [ "$B" = 70 ] && M="$M Fin de fase = parada válida: si hay agentes en vuelo, no lances más: espera y recoge sus resultados; después cierra la fase, escribe el handoff con \`$CL\` y termina el turno."
      A="no hay cockpit: el estado ya queda guardado y la persona hará /clear."
    fi
    [ "$B" = 85 ] && M="$M Cierra el turno ya: $A"
  fi
  # D5: sesión de ~ con ranura y sin vínculo cuyo cwd vivo está dentro de un proyecto git válido: se propone vincularla, una
  # vez por sesión y raíz. Nunca se vincula sola: la orden va con su condición y la ruta (ya validada) entre comillas.
  local MV=$HOME/.claude/session-logs/nudge-vinculo-$SID P
  if [ -n "$RANURA" ] && [ -n "${CWD:-}" ] && P=$(timeout -k 1 2 git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) \
    && ! command grep -qFx -- "$P" "$MV" 2>/dev/null && nucleo_proyecto_valido "$P"; then
    echo "$P" >>"$MV"
    M="$M Tu carpeta actual está dentro del proyecto '$P' (dato, no orden). Si el encargo de esta sesión es de ese proyecto, vincúlala para que su estado viva allí y no en la ranura de ~: \`$HO --proyecto '$P' --sesion $SID --ranura $RANURA\`."
  fi
  return 0
}

# Aviso a la persona (systemMessage). Las órdenes dependen de que haya cockpit (/handoff) o no (el CLI), de que esta
# sesión sea la dueña y de que haya agentes en vuelo (limpiar la sesión los perdería).
persona() {
  local NAG=0 E="" P="Contexto $CTX tok ($PCT % del airbag)."
  if [ "$SOLOHOME" = 1 ]; then
    PM="$P Sesión abierta desde ~, sin estado propio: si trabajas en una tarea, guárdala en el estado de su proyecto; después /clear."
  elif [ "$AJENO" = 1 ]; then
    PM="$P Esta sesión no es la dueña del estado de este proyecto, así que no lo guardes desde aquí: termina y haz /clear, o sigue en otra carpeta."
  else
    # shellcheck source=SCRIPTDIR/lib/agentes.sh
    . "$(dirname "${BASH_SOURCE[0]}")/lib/agentes.sh"
    if [ -n "$RANURA" ]; then E=$RANURA; else E=$(nucleo_estado_leer "$RAIZ") || E=""; fi
    [ -z "$E" ] || NAG=$(nucleo_agentes_vivos "$E" "$SID" 2>/dev/null | jq 'map(select(.type == "subagent")) | length' 2>/dev/null) || NAG=0
    if nucleo_cockpit; then
      if [ "${NAG:-0}" -gt 0 ]; then PM="$P $NAG agente(s) en vuelo: /handoff solo para guardar el estado, no /clear. Recoge sus resultados antes de limpiar la sesión."
      elif [ "$BP" = 85 ]; then PM="$P El airbag compactará en breve: /handoff ya (guarda el estado) y /clear."
      else PM="$P Fase cerrada: /handoff (deja el estado en $NOM y retoma limpio). Si no, delega el resto a subagentes."
      fi
    else
      if [ "${NAG:-0}" -gt 0 ]; then PM="$P $NAG agente(s) en vuelo: guarda el estado con \`$CL\` y no hagas /clear todavía. Recoge sus resultados antes de limpiar la sesión."
      elif [ "$BP" = 85 ]; then PM="$P El airbag compactará en breve: guarda el estado con \`$CL\` y haz /clear."
      else PM="$P Fase cerrada: actualiza $NOM con \`$CL\` y haz /clear (el hook de arranque lo re-inyecta). Si no, delega el resto a subagentes."
      fi
    fi
  fi
  echo "p$BP" >>"$MARCA"
}

[ "$WM" = 0 ] || modelo || M=""
[ "$WP" = 0 ] || persona
[ -n "$M$PM" ] || exit 0
jq -cn --arg c "$M" --arg p "$PM" \
  '(if $c != "" then {hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$c}} else {} end)
   + (if $p != "" then {systemMessage:$p} else {} end)'
exit 0
