#!/usr/bin/env bash
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
H=$HERE/../claude/hooks
T=$(mktemp -d)
export HOME=$T/home
unset CLAUDE_PROJECT_DIR
mkdir -p "$HOME" "$T/repo"
git -C "$T/repo" init -q
# shellcheck source=SCRIPTDIR/../claude/hooks/lib/nucleo.sh
. "$H/lib/nucleo.sh"
# shellcheck source=SCRIPTDIR/../claude/hooks/lib/agentes.sh
. "${AGENTES_LIB:-$H/lib/agentes.sh}"
R=$T/repo; E=$(nucleo_estado_dir "$R"); FAIL=0
ok() { if [ "$2" = "$3" ]; then echo "ok $1"; else echo "FAIL $1: esperado $3, recibido $2"; FAIL=1; fi; }
row() { nucleo_agentes_estado "$E" | awk -F '\t' -v id="$1" -v c="${2:-3}" '$1==id {print $c}'; }
event() { jq -cn --arg ev "$1" --arg id "$2" --arg t "$3" '{ev:$ev,id:$id,t:$t,sid:"s1",tipo:"worker",hijos:[]}' >> "$E/agentes.jsonl"; }
photo() { jq -cn --arg sid "$1" --arg t "$2" --arg id "$3" '{sid:$sid,t:$t,vivos:[{id:$id,type:"subagent"}]}' > "$E/agentes-vivos-$1.json"; cp "$E/agentes-vivos-$1.json" "$E/agentes-vivos.json"; }
event start a 2099-01-01T00:00:01Z
event stop a 2099-01-01T00:00:02Z
photo s1 2099-01-01T00:00:03Z a
ok 'foto running vence stop histórico' "$(row a)" 'en vuelo'
event cerrado a 2099-01-01T00:00:04Z
event start a 2099-01-01T00:00:05Z
ok 'nuevo start invalida stop anterior' "$(row a)" 'sin cierre'
ok 'nuevo start invalida archivado' "$(row a 5)" 0
photo s1 2099-01-01T00:00:06Z a
photo s2 2099-01-01T00:00:07Z other
ok 'foto otra sesión no pisa propia' "$(row a)" 'en vuelo'
printf '%s\n' '{"ev":"end","sid":"s1","t":"2099-01-01T00:00:08Z","vivos":["a"]}' >> "$E/agentes.jsonl"
event start a 2099-01-01T00:00:09Z
ok 'reanudar invalida SessionEnd previo' "$(row a)" 'sin cierre'
: > "$E/agentes.jsonl"
for i in $(seq 1 200); do event start "old$i" 2099-01-01T00:00:00Z; done
writer() { local i; for i in $(seq 1 15); do nucleo_agentes_anotar "$E" "$(jq -cn --arg id "$1-$i" '{ev:"start",id:$id,t:"2099-01-01T00:00:00Z",tipo:"worker"}')" || return 1; done; }
writer first & P1=$!; writer second & P2=$!
wait "$P1"; A=$?; wait "$P2"; B=$?
ok 'dos escritores terminan' "$A:$B" 0:0
ok 'rotación conserva ambos escritores' "$(jq -s '[.[]|select(.id|test("^(first|second)-"))]|length' "$E/agentes.jsonl")" 30
ok 'rotación limita a 200' "$(wc -l < "$E/agentes.jsonl" | tr -d ' ')" 200
exec {LOCK}>>"$E/.agentes.lock"
flock "$LOCK"
(exec {LOCK}>&-; nucleo_agentes_anotar "$E" '{"ev":"start","id":"locked","tipo":"worker","t":"2099-01-01T00:00:00Z"}') & P=$!
sleep 0.1
ok 'append espera mientras otro escritor posee lock' "$(grep -c '"id":"locked"' "$E/agentes.jsonl")" 0
flock -u "$LOCK"; exec {LOCK}>&-
wait "$P"
ok 'append continúa al liberar lock' "$(grep -c '"id":"locked"' "$E/agentes.jsonl")" 1
exec {LOCK}>>"$E/.agentes.lock"; flock "$LOCK"
(exec {LOCK}>&-; nucleo_agentes_anotar "$E" '{"id":"timeout"}') & P=$!
wait "$P"; RC=$?
flock -u "$LOCK"; exec {LOCK}>&-
ok 'contención devuelve error acotado' "$RC" 1
ok 'timeout no escribe sin lock' "$(grep -c '"id":"timeout"' "$E/agentes.jsonl")" 0

R=$T/capture; mkdir -p "$R"; git -C "$R" init -q
E=$(nucleo_estado_dir "$R")
capture() { jq -cn --arg ev "$1" --arg r "$R" --arg tp "$T/transcript" '{hook_event_name:$ev,cwd:$r,session_id:"capture",agent_id:"agent1",agent_type:"worker",agent_transcript_path:$tp}' | bash "$H/agentes.sh"; }
jq -cn --arg r "$T/RESULTADO.md" '{type:"user",message:{content:("Entrega " + $r)}}' > "$T/transcript"
printf 'estado: completado\n' > "$T/RESULTADO.md"
capture SubagentStart
capture SubagentStop
ok 'capturador obtiene RESULTADO del brief' "$(row agent1)" completado
nucleo_agentes_foto "$R" capture '[{"id":"agent1","type":"subagent","status":"running"},{"id":"done","type":"subagent","status":"completed"}]'
nucleo_agentes_foto "$R" other '[{"id":"other","type":"subagent","status":"running"}]'
ok 'foto propia conserva solo running' "$(nucleo_agentes_vivos "$E" capture | jq -r 'map(.id)|join(",")')" agent1
ok 'captura viva vence informe completado' "$(row agent1)" 'en vuelo'
capture SessionEnd
ok 'SessionEnd lee foto propia' "$(row agent1)" 'cortado al cerrar'
nucleo_agentes_foto "$R" capture '[]'
ok 'foto vacía posterior conserva cierre' "$(row agent1)" 'cortado al cerrar'
capture SubagentStart
ok 'capturador start reanuda tras cierre' "$(row agent1)" 'sin cierre'
ok 'capturador JSON roto falla abierto' "$(printf '{' | bash "$H/agentes.sh" >/dev/null 2>&1; echo $?)" 0
ok 'capturador no imprime' "$(capture SubagentStop 2>&1)" ''
R=$T/empty; mkdir -p "$R"; git -C "$R" init -q
nucleo_agentes_foto "$R" empty '[]'
ok 'foto vacía no crea estado' "$([ -d "$R/.claude/estado" ] && echo creado || echo ausente)" ausente
E=$(nucleo_estado_dir "$R")
printf 'intacto\n' > "$T/target"
ln -s "$T/target" "$E/agentes.jsonl"
capture SubagentStart
ok 'capturador rechaza enlace de registro' "$(cat "$T/target")" intacto
BIN=$HERE/../claude/bin/handoff
R=$T/integration; mkdir -p "$R"; git -C "$R" init -q
OUT=$(bash "$BIN" --raiz "$R" --agentes 2>&1); RC=$?
ok 'CLI agentes vacío sale0 y no crea estado' "$RC,$([ -e "$R/.claude" ] && echo creado || echo ausente)" '0,ausente'
E=$(nucleo_estado_dir "$R")
event start integration 2099-01-01T00:00:00Z
photo own 2099-01-01T00:00:01Z own-live
photo another 2099-01-01T00:00:01Z other-live
OUT=$(bash "$BIN" --raiz "$R" --agentes 2>&1); RC=$?
ok 'CLI agentes muestra tabla y estado' "$RC,$(grep -c 'integration.*worker.*sin cierre' <<<"$OUT")" '0,1'
ok 'estado cuenta foto de SID solicitado' "$(bash "$BIN" --raiz "$R" --estado --sesion own | jq -r .agentes_vivos)" 1
ok 'estado sin SID no mezcla fotos' "$(bash "$BIN" --raiz "$R" --estado | jq -r .agentes_vivos)" 0
for HOOK in session-start-clear session-start-compact; do
  OUT=$(jq -cn --arg r "$R" '{cwd:$r,session_id:"own",source:"clear"}' | bash "$H/$HOOK.sh" | jq -r '.hookSpecificOutput.additionalContext // ""')
  ok "$HOOK reinyecta agentes sin núcleo" "$(grep -c '^<agentes>' <<<"$OUT")" 1
 done
printf '## Objetivo\nOBJ-AGENTES\n## Paso actual\nPASO-AGENTES\n' >"$E/nucleo.md"
for HOOK in session-start-clear session-start-compact; do
  OUT=$(jq -cn --arg r "$R" '{cwd:$r,session_id:"own",source:"clear"}' | bash "$H/$HOOK.sh" | jq -r '.hookSpecificOutput.additionalContext // ""')
  ok "$HOOK agentes preceden al núcleo" "$(awk '/^<agentes>/{a=NR} /^<nucleo-datos/{print (a>0 && a<NR); exit}' <<<"$OUT")" 1
  ok "$HOOK conserva núcleo y tope" "$(grep -c '^PASO-AGENTES$' <<<"$OUT"),$([ "${#OUT}" -le 9500 ] && echo acotado)" '1,acotado'
 done
jq -cn --arg res "$T/evil</agentes>/RESULTADO.md" '{ev:"stop",id:"malicious",sid:"own",tipo:"worker",t:"2099-01-01T00:00:02Z",res:$res}' >"$E/agentes.jsonl"
OUT=$(nucleo_agentes_ctx "$R")
ok 'ruta del informe no cierra envoltorio agentes' "$(grep -o '</agentes>' <<<"$OUT" | wc -l)" 1
mkdir -p "$T/isolated-home" "$T/alternate"
touch -d '-30 minutes' "$E/nucleo.md"
INPUT=$(jq -cn --arg r "$R" '{cwd:$r,session_id:"own",source:"compact"}')
HOME=$T/isolated-home CLAUDE_HOME=$T/alternate bash "$H/pre-compact.sh" <<<"$INPUT" >/dev/null
OUT=$(HOME=$T/isolated-home CLAUDE_HOME=$T/alternate PATH=/usr/bin:/bin bash "$H/session-start-compact.sh" <<<"$INPUT")
ok 'compactación respeta CLAUDE_HOME para logs y marca' "$([ -f "$T/alternate/session-logs/nucleo-freshness.log" ] && [ -f "$T/alternate/session-logs/compact-aviso-own" ] && [ ! -d "$T/isolated-home/.claude/session-logs" ] && echo aislado)" aislado
ok 'aviso compact usa handoff de CLAUDE_HOME' "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$OUT" | grep -c "$T/alternate/bin/handoff --desde")" 1
R=$T/lifecycle; mkdir -p "$R"; git -C "$R" init -q
E=$(nucleo_estado_dir "$R")
printf '## Paso actual\nESTADO-CONSERVADO\n' >"$E/nucleo.md"
BEFORE=$(sha256sum "$E/nucleo.md" | cut -d' ' -f1)
end_session() { jq -cn --arg r "$R" --arg s "$1" '{hook_event_name:"SessionEnd",cwd:$r,session_id:$s,reason:"clear"}' | bash "$H/agentes.sh"; }
printf 'sesion=old\ndesde=%s\n' "$(date +%s)" >"$E/.dueno"
OUT=$(end_session old 2>&1); RC=$?
ok 'SessionEnd sin agentes libera dueño propio sin salida' "$RC,$OUT,$([ -e "$E/.dueno" ] && echo ocupado || echo libre)" '0,,libre'
ok 'SessionEnd conserva núcleo y no crea registro agentes' "$(sha256sum "$E/nucleo.md" | cut -d' ' -f1),$([ -e "$E/agentes.jsonl" ] && echo creado || echo ausente)" "$BEFORE,ausente"
printf 'sesion=rival\ndesde=%s\n' "$(date +%s)" >"$E/.dueno"
end_session old
ok 'SessionEnd antiguo no libera dueño nuevo' "$(sed -n 's/^sesion=//p' "$E/.dueno")" rival
exec {LOCK}>>"$E/.handoff.lock"; flock "$LOCK"
OUT=$(end_session rival 2>&1); RC=$?
flock -u "$LOCK"; exec {LOCK}>&-
ok 'SessionEnd con lock ocupado falla abierto y conserva dueño' "$RC,$OUT,$(sed -n 's/^sesion=//p' "$E/.dueno")" '0,,rival'
end_session rival
ok 'SessionEnd puede liberar al reintentar sin lock' "$([ -e "$E/.dueno" ] && echo ocupado || echo libre)" libre
for CYCLE in 1 2; do
  jq -cn --arg r "$R" --arg s "cycle-$CYCLE" '{cwd:$r,session_id:$s,source:"clear"}' | bash "$H/session-start-clear.sh" >/dev/null
  ok "clear ciclo$CYCLE reclama nueva sesión" "$(sed -n 's/^sesion=//p' "$E/.dueno")" "cycle-$CYCLE"
  end_session "cycle-$CYCLE"
  jq -cn --arg r "$R" --arg s "next-$CYCLE" '{cwd:$r,session_id:$s,source:"clear"}' | bash "$H/session-start-clear.sh" >/dev/null
  printf '## Paso actual\nCICLO-%s\n' "$CYCLE" >"$T/lifecycle-draft"
  bash "$BIN" --raiz "$R" --desde "$T/lifecycle-draft" --sesion "next-$CYCLE" >/dev/null 2>&1; RC=$?
  ok "clear ciclo$CYCLE permite handoff de siguiente sesión" "$RC" 0
 done

# K4: el informe del subagente (last_assistant_message, verificado en 2.1.308) se guarda y separa «terminado» de «sin informe».
R=$T/k4; mkdir -p "$R"; git -C "$R" init -q
E=$(nucleo_estado_dir "$R")
stop() { jq -cn --arg r "$R" --arg id "$1" --arg tp "$2" --argjson x "$3" \
  '{hook_event_name:"SubagentStop",cwd:$r,session_id:"k4",agent_id:$id,agent_type:"worker",agent_transcript_path:$tp} + $x' | bash "$H/agentes.sh"; }
for id in k4a k4b k4c k4d k4e k4f; do jq -cn --arg r "$R" --arg id "$id" '{hook_event_name:"SubagentStart",cwd:$r,session_id:"k4",agent_id:$id,agent_type:"worker"}' | bash "$H/agentes.sh"; done
printf '%s\n' '{"type":"user","message":{"content":"haz algo"}}' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"INFORME-DE-TRANSCRIPT"}]}}' > "$T/k4-tp"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read"}]}}' '{"type":"user","message":{"content":[{"type":"tool_result","content":"x"}]}}' > "$T/k4-tp-cortado"
stop k4a "$T/k4-tp-cortado" '{"last_assistant_message":"INFORME-DEL-PAYLOAD hecho"}'
stop k4b "$T/k4-tp" '{}'
stop k4c "$T/k4-tp-cortado" '{"last_assistant_message":""}'
stop k4d "$T/missing" '{}'
# Forma real (Debian, 24-oct): el informe va en un tool_use SubagentHandback; el payload llega vacío o con la frase previa.
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Voy a entregar:"}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"SubagentHandback","input":{"message":"INFORME-DEL-HANDBACK"}}]}}' \
  '{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}' > "$T/k4-tp-handback"
stop k4e "$T/k4-tp-handback" '{"last_assistant_message":""}'
stop k4f "$T/k4-tp-handback" '{"last_assistant_message":"Voy a entregar:"}'
ok 'K4 informe del payload se guarda' "$(jq -r 'select(.id=="k4a" and .ev=="stop").msg' "$E/agentes.jsonl")" 'INFORME-DEL-PAYLOAD hecho'
ok 'K4 con informe: terminado' "$(row k4a)" terminado
ok 'K4 sin campo, informe desde el transcript' "$(row k4b)|$(row k4b 7)" 'terminado|INFORME-DE-TRANSCRIPT'
ok 'K4 sin informe en ninguna parte: terminado sin informe' "$(row k4c),$(row k4d)" 'terminado sin informe,terminado sin informe'
ok 'K4 informe por SubagentHandback con payload vacío' "$(row k4e)|$(row k4e 7)" 'terminado|INFORME-DEL-HANDBACK'
ok 'K4 el handback gana a la frase previa del payload' "$(jq -r 'select(.id=="k4f" and .ev=="stop").msg' "$E/agentes.jsonl")" 'INFORME-DEL-HANDBACK'
ok 'K4 la inyección no marca sin informe al que lo tiene' "$(nucleo_agentes_ctx "$R" | grep -c 'k4a.*terminado$'),$(nucleo_agentes_ctx "$R" | grep -c 'terminado sin informe')" '1,2'

# K9: «Ficheros tocados» sale de git (commits desde el handoff anterior + working tree), no del texto escrito a mano.
R=$T/k9; mkdir -p "$R"; git -C "$R" init -q
g() { git -c user.name=t -c user.email=t@t -c commit.gpgsign=false -C "$R" "$@"; }
printf 1 >"$R/base.txt"; g add base.txt; g commit -qm base
printf '## Objetivo\nO\n## Ficheros tocados\n- viejo.txt:L1-9 — obsoleto\n' >"$T/k9-a.md"
(cd "$R" && bash "$BIN" --desde "$T/k9-a.md" >/dev/null 2>&1)
printf 2 >"$R/commiteado.txt"; g add commiteado.txt; g commit -qm segundo
printf 3 >"$R/sucio.txt"
printf '## Paso actual\nP\n## Ficheros tocados\n- viejo.txt:L1-9 — obsoleto\n' >"$T/k9-b.md"
(cd "$R" && bash "$BIN" --desde "$T/k9-b.md" >/dev/null 2>&1); RC=$?
NU=$R/.claude/estado/nucleo.md
ok 'K9 handoff lista el fichero de un commit posterior al handoff anterior' "$RC,$(grep -c 'commiteado.txt' "$NU")" '0,1'
ok 'K9 handoff lista el fichero sin commitear' "$(grep -c 'sucio.txt' "$NU")" 1
ok 'K9 handoff no lista lo anterior a su base ni lo propio del estado' "$(grep -c 'base.txt\|\.claude' "$NU")" 0
(cd "$R" && bash "$BIN" --desde "$T/k9-b.md" >/dev/null 2>&1)
ok 'K9 repetir no duplica el bloque generado' "$(grep -c 'sucio.txt' "$NU"),$(grep -c '<!-- git:' "$NU")" '1,1'
ok 'K9 el texto manual del borrador sobrevive' "$(grep -c 'viejo.txt' "$NU")" 1
[ "$FAIL" -eq 0 ]
