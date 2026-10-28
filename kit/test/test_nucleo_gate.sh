#!/usr/bin/env bash
# test_nucleo_gate.sh — contrato de kit/claude/hooks/nucleo-gate.sh (PreToolUse): tras el aviso 70/85 % del
# nudge con el nucleo sin escribir, deniega UNA llamada del hilo principal (la 4.ª) por banda y sesión.
# Uso: test_nucleo_gate.sh [ruta al hook]. Sin red; HOME falso en un mktemp que se borra.
set -u
H=$(realpath "${1:-$(dirname "$0")/../claude/hooks/nucleo-gate.sh}"); T=$(mktemp -d); trap 'rm -rf -- "$T"' EXIT
export HOME=$T/home; unset CLAUDE_PID CLAUDE_PROJECT_DIR; export CC_NUCLEO_GATE=1
FAIL=0
ok() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (esperado '$3', sale '$2')"; FAIL=1; fi; }
L=$HOME/.claude/session-logs; mkdir -p "$L" "$T/r/.claude/estado"
NUC=$T/r/.claude/estado/nucleo.md; echo x >"$NUC"
# arma SID banda...: marca del nudge (bandas avisadas) + ruta del nucleo, con el aviso 10 min tras el mtime del nucleo.
arma() { local s=$1; shift; printf '%s\n' "$@" >"$L/nudge-$s"; echo "$NUC" >"$L/nudge-$s.nucleo"; rm -f "$L/gate-$s"*
  touch -d '-30 minutes' "$NUC"; touch -d '-10 minutes' "$L/nudge-$s.nucleo"; }
# llama SID [json extra]: «deny» si el hook deniega, «pasa» si sale vacío.
llama() { local o; o=$(jq -cn --arg s "$1" --argjson x "${2:-{\}}" '{session_id:$s,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:"ls"}} + $x' | bash "$H" 2>/dev/null)
  case $o in '') echo pasa;; *) [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$o" 2>/dev/null)" = deny ] && echo deny || echo "raro:$o";; esac; }
llama_raw() { jq -cn --arg s "$1" '{session_id:$s,tool_name:"Bash",tool_input:{command:"ls"}}' | bash "$H"; }
seq5() { local r=""; for _ in 1 2 3 4 5; do r="$r$(llama "$@") "; done; echo "${r% }"; }
rep() { for _ in 1 2 3 4 5; do llama "$@"; done | sort -u; }

arma a 50 70
ok "banda 70 + nucleo viejo: 1-3 pasan, 4.ª deniega, 5.ª pasa" "$(seq5 a)" "pasa pasa pasa deny pasa"
O=$(jq -cn '{session_id:"a2",tool_name:"Bash",tool_input:{command:"ls"}}'); arma a2 70; for _ in 1 2 3; do bash "$H" <<<"$O" >/dev/null; done
M=$(bash "$H" <<<"$O" | jq -r '.hookSpecificOutput.permissionDecisionReason')
ok "el motivo cita la ruta del nucleo y handoff" "$(command grep -c "$NUC.*handoff --desde <borrador> --sesion a2" <<<"$M")" 1
# Para poder medirla: una línea fechada por denegación (fecha, sesión, banda, herramienta, nucleo); las que pasan no escriben.
ok "cada denegación deja una línea fechada en gate-denegaciones.log" "$(awk -F'\t' '$2=="a" && $1 ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}T/ {print $3, $4, $5}' "$L/gate-denegaciones.log" 2>/dev/null)" "70 Bash $NUC"

arma b 70
ok "con agent_id nunca deniega" "$(seq5 b '{"agent_id":"sub1"}')" "pasa pasa pasa pasa pasa"
arma c 70
ok "agent_type sin agent_id = hilo principal: deniega" "$(seq5 c '{"agent_type":"Explore"}')" "pasa pasa pasa deny pasa"
arma d 70
ok "agent_id vacío = hilo principal" "$(seq5 d '{"agent_id":""}')" "pasa pasa pasa deny pasa"

arma e 70; llama e >/dev/null; touch "$NUC"
ok "escribir el nucleo (mtime nuevo) desarma" "$(seq5 e)" "pasa pasa pasa pasa pasa"

arma f 70
EDIT=$(jq -cn --arg p "$NUC" '{file_path:$p}'); BORR='{"file_path":"/x/proyecto/.claude/estado/borrador.md"}'
ok "Edit del nucleo pasa aunque toque denegar" "$(rep f "{\"tool_name\":\"Edit\",\"tool_input\":$EDIT}")" pasa
ok "Write de un borrador bajo estado/ pasa" "$(rep f "{\"tool_name\":\"Write\",\"tool_input\":$BORR}")" pasa
ok "Bash handoff pasa aunque toque denegar" "$(rep f '{"tool_input":{"command":"handoff --desde x --sesion f"}}')" pasa
ok "las exentas no cuentan: después la 4.ª normal deniega" "$(seq5 f)" "pasa pasa pasa deny pasa"

arma g
ok "marca vacía no deniega" "$(seq5 g)" "pasa pasa pasa pasa pasa"
arma h 50
ok "marca solo de la banda 50 no deniega" "$(seq5 h)" "pasa pasa pasa pasa pasa"
ok "sin marca alguna no deniega" "$(seq5 zz)" "pasa pasa pasa pasa pasa"
arma i 70; rm -f "$L/nudge-i.nucleo"
ok "marca sin ruta del nucleo (nudge desde ~) no deniega" "$(seq5 i)" "pasa pasa pasa pasa pasa"
arma m 70; : >"$L/nudge-m.nucleo"
ok "ruta de nucleo vacía: sin deny" "$(seq5 m)" "pasa pasa pasa pasa pasa"

arma j 70
ok "JSON vacío: salida 0 sin deny" "$(printf '' | bash "$H"; echo "rc=$?")" "rc=0"
ok "JSON roto: salida 0 sin deny" "$(echo '{no' | bash "$H"; echo "rc=$?")" "rc=0"
mkdir -p "$L/nudge-k" "$L/gate-k"; printf '70\n' >"$L/nudge-k/x"; echo "$NUC" >"$L/nudge-k/x.nucleo"; touch -d '-10 minutes' "$L/nudge-k/x.nucleo"; touch -d '-30 minutes' "$NUC"
printf '\n\n\n' >"$L/gate-k/x-70"   # sin la guarda del SID, la 4.ª llamada denegaría y escribiría fuera de gate-<sid>
ok "SID con / : sin deny" "$(rep 'k/x')" pasa
ok "SID con / : no escribe nada fuera" "$(wc -l <"$L/gate-k/x-70" | tr -d ' '),$(find "$L/gate-k" -type f -printf '%f ')" "3,x-70 "
arma l 70
ok "CC_NUCLEO_GATE=0 apaga" "$(CC_NUCLEO_GATE=0 rep l)" pasa
arma l2 70
ok "opt-in: sin CC_NUCLEO_GATE no deniega" "$(unset CC_NUCLEO_GATE; seq5 l2)" "pasa pasa pasa pasa pasa"
arma l2 70
ok "opt-in: CC_NUCLEO_GATE=1 sí deniega" "$(seq5 l2)" "pasa pasa pasa deny pasa"

arma n 70 85
ok "banda 85 avisada: cuenta propia, deniega la 4.ª" "$(seq5 n)" "pasa pasa pasa deny pasa"
arma o 70; seq5 o >/dev/null; printf '70\n85\n' >"$L/nudge-o"; touch -d '-5 minutes' "$L/nudge-o.nucleo"
ok "banda 85 deniega otra vez si la 70 ya denegó" "$(seq5 o)" "pasa pasa pasa deny pasa"
ok "y la 85 ya denegada no vuelve" "$(seq5 o)" "pasa pasa pasa pasa pasa"
arma p 70; seq5 p >/dev/null
ok "la 70 ya denegada no vuelve a denegar" "$(seq5 p)" "pasa pasa pasa pasa pasa"

# contador corrupto o ilegible: falla en abierto, rc 0 y sin ruido en stderr
arma q 70; printf 'basura sin salto' >"$L/gate-q-70"
ok "contador con basura: rc 0, sin stderr" "$(llama_raw q 2>&1; echo "rc=$?")" "rc=0"
arma q2 70; mkdir "$L/gate-q2-70"
ok "contador ilegible (es un directorio): rc 0, sin stderr" "$(llama_raw q2 2>&1; echo "rc=$?")" "rc=0"

# handoff: solo como palabra de comando, también con ruta; nohandoff y handoffx no son handoff
arma r 70
ok "Bash con handoff por ruta absoluta pasa (la ruta del motivo)" "$(rep r '{"tool_input":{"command":"/x/.claude/bin/handoff --desde b --sesion r"}}')" pasa
arma r2 70
ok "echo nohandoff no es handoff: la 4.ª deniega" "$(seq5 r2 '{"tool_input":{"command":"echo nohandoff"}}')" "pasa pasa pasa deny pasa"
arma r3 70
ok "./handoffx no es handoff: la 4.ª deniega" "$(seq5 r3 '{"tool_input":{"command":"./handoffx --desde b"}}')" "pasa pasa pasa deny pasa"

# ruta relativa bajo .claude/estado/
arma t 70
ok "Edit con ruta relativa .claude/estado/nucleo.md pasa" "$(rep t '{"tool_name":"Edit","tool_input":{"file_path":".claude/estado/nucleo.md"}}')" pasa

# carrera: 8 PreToolUse en paralelo con la cuenta en 3 → exactamente una denegación
arma u 70; for _ in 1 2 3; do llama u >/dev/null; done
for i in 1 2 3 4 5 6 7 8; do llama u >"$T/par.$i" & done; wait
ok "8 llamadas en paralelo tras 3: exactamente 1 denegación" "$(cat "$T"/par.* | grep -c deny)" 1

exit $FAIL
