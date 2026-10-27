#!/usr/bin/env bash
# SubagentStart | SubagentStop | SessionEnd — registro mecánico de agentes (ADR 017): una línea JSON por evento en
# <raíz>/.claude/estado/agentes.jsonl (lib/nucleo.sh: nucleo_agentes_anotar, que rota a 200 líneas o 14 días).
# Por qué: SubagentStop marca el fin del *turno* del agente, no el de su trabajo, y no trae resultado; tras /clear, una
# compactación o al reanudar, la sesión nueva no sabe si debe recoger o relanzar. El estado se deriva al leer
# (nucleo_agentes_estado), no aquí; el informe también: al saltar SubagentStop el transcript aún no tiene el
# SubagentHandback (medido en Debian, 3 de 3), así que si no hay informe aquí, el estado lo relee al leer.
#   SubagentStart: id, tipo, hora, sesión y transcript.
#   SubagentStop:  lo mismo + las últimas ~300 letras del informe: el message de su SubagentHandback si lo usó; si no,
#                  last_assistant_message (medido en 2.1.308); si falta o viene vacío, el último texto de su transcript y la ruta del RESULTADO.md que pedía su brief
#                  (primer mensaje de su transcript; barato: 3 líneas; vacía si no la nombra).
#                  background_tasks puede contener hermanos: no demuestra descendencia ni trabajo pendiente del agente.
#   SessionEnd:    los subagentes que seguían vivos en la última foto de Stop de esta sesión (SessionEnd no trae
#                  background_tasks; la foto la deja stop-context-gauge.sh): «cortado al cerrar».
# Agentes internos (sugerencias de prompt, resúmenes de /compact): llegan con agent_type vacío (medido en S0, una muestra;
# la doc no lo dice) y no se registran, para que no desplacen a los reales del tope de 200 líneas.
# Sin red ni modelo. Fail-open: exit 0 siempre, sin salida; JSON roto, enlaces o disco lleno no rompen nada.
set -u
IN=$(cat)
{ read -r EV; read -r SID; read -r ID; read -r TIPO; read -r CWD; read -r TP; } < <(
  jq -r '.hook_event_name // "", .session_id // "", .agent_id // "", .agent_type // "",
         .cwd // "", (.agent_transcript_path // .transcript_path // "")' <<<"$IN" 2>/dev/null)
# shellcheck source=SCRIPTDIR/lib/nucleo.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/nucleo.sh"
# shellcheck source=SCRIPTDIR/lib/agentes.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/agentes.sh"
RAIZ=$(nucleo_raiz "${CWD:-$PWD}") || RAIZ=$HOME
estado() {
  if [ "$RAIZ" = "$HOME" ]; then nucleo_sesion_dir crear
  else nucleo_estado_dir "$RAIZ"; fi
}
case $ID in *[!A-Za-z0-9_-]*) exit 0 ;; esac
NOW=$(date -u +%FT%T.%NZ)

# res_de <transcript del agente>: la ruta absoluta del RESULTADO.md que pide su brief. Una ruta que acaba en
# RESULTADO.md vale tal cual; una carpeta de informes/ (la que imprime `handoff --informe`) lleva el fichero dentro, y un
# fichero de esa carpeta (…/BRIEF.md: lo que no es un directorio y tiene extensión) da su carpeta.
res_de() {
  local m r
  [ -f "$1" ] && [ ! -L "$1" ] || return 0
  m=$(head -n 3 -- "$1" 2>/dev/null | jq -rR 'fromjson? | select(.type == "user") | .message.content
      | if type == "string" then . else (map(.text? // "") | join(" ")) end' 2>/dev/null | head -c 20000)
  r=$(grep -oE '/[^][:space:]"'\''`<>|;(),]*RESULTADO\.md' <<<"$m" | head -n 1)
  if [ -z "$r" ]; then
    r=$(grep -oE '/[^][:space:]"'\''`<>|;(),]*/informes/[^][:space:]"'\''`<>|;(),]+' <<<"$m" | head -n 1); r=${r%/}
    [ -d "$r" ] || case ${r##*/} in *.*) r=${r%/*} ;; esac
    [ -z "$r" ] || r="$r/RESULTADO.md"
  fi
  case $r in *..*) r="" ;; esac
  printf '%s' "$r"
}

case ${EV:-} in
  SubagentStart)
    [ -n "$ID" ] && [ -n "$TIPO" ] || exit 0
    E=$(estado 2>/dev/null) || exit 0
    L=$(jq -cn --arg t "$NOW" --arg s "$SID" --arg i "$ID" --arg k "$TIPO" --arg p "$TP" \
      '{ev:"start", t:$t, sid:$s, id:$i, tipo:$k, tp:$p}') || exit 0 ;;
  SubagentStop)
    [ -n "$ID" ] && [ -n "$TIPO" ] || exit 0
    E=$(estado 2>/dev/null) || exit 0
    RES=$(res_de "$TP")
    MSG=$(handback_de "$TP")
    [[ $MSG =~ [^[:space:]] ]] || MSG=$(jq -r '(.last_assistant_message // "") | tostring' <<<"$IN" 2>/dev/null)
    [[ $MSG =~ [^[:space:]] ]] || MSG=$(msg_de "$TP")
    L=$(jq -c --arg t "$NOW" --arg i "$ID" --arg r "$RES" --arg m "$MSG" '{ev:"stop", t:$t, sid:(.session_id // ""), id:$i,
        tipo:(.agent_type // ""), tp:(.agent_transcript_path // .transcript_path // ""),
        msg:($m | .[-300:]),
        res:$r}' <<<"$IN" 2>/dev/null) || exit 0 ;;
  SessionEnd)
    (
      E=$(nucleo_estado_leer "$RAIZ") || exit 0
      [ -f "$E/.dueno" ] || exit 0
      nucleo_bloquear "$E" || exit 0
      D=$(nucleo_dueno "$RAIZ") || exit 0
      [ "${D% *}" != "$SID" ] || rm -f -- "$E/.dueno"
    ) >/dev/null 2>&1
    D=$(nucleo_agentes_dir "$RAIZ") || exit 0
    V=$(nucleo_agentes_vivos "$D" "$SID" | jq -c '[.[] | select(.type == "subagent") | .id]')
    [ -n "$V" ] && [ "$V" != "[]" ] || exit 0
    E=$(estado 2>/dev/null) || exit 0
    L=$(jq -cn --arg t "$NOW" --arg s "$SID" --argjson v "$V" --arg r "$(jq -r '.reason // ""' <<<"$IN" 2>/dev/null)" \
      '{ev:"end", t:$t, sid:$s, razon:$r, vivos:$v}') || exit 0 ;;
  *) exit 0 ;;
esac
[ -n "${L:-}" ] && nucleo_agentes_anotar "$E" "$L"
exit 0
