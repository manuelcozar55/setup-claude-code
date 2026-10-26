#!/usr/bin/env bash
# test_nucleo_gate.sh — contrato de kit/claude/hooks/nucleo-gate.sh (PreToolUse): tras el aviso 70/85 % del
# nudge con el nucleo sin escribir, deniega UNA llamada del hilo principal (la 4.ª) por banda y sesión.
# Uso: test_nucleo_gate.sh [ruta al hook]. Sin red; HOME falso en un mktemp que se borra.
set -u
H=$(realpath "${1:-$(dirname "$0")/../claude/hooks/nucleo-gate.sh}"); T=$(mktemp -d); trap 'rm -rf -- "$T"' EXIT
export HOME=$T/home; unset CLAUDE_PID CLAUDE_PROJECT_DIR CC_NUCLEO_GATE
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
seq5() { local r=""; for _ in 1 2 3 4 5; do r="$r$(llama "$@") "; done; echo "${r% }"; }
rep() { for _ in 1 2 3 4 5; do llama "$@"; done | sort -u; }

arma a 50 70
ok "banda 70 + nucleo viejo: 1-3 pasan, 4.ª deniega, 5.ª pasa" "$(seq5 a)" "pasa pasa pasa deny pasa"
O=$(jq -cn '{session_id:"a2",tool_name:"Bash",tool_input:{command:"ls"}}'); arma a2 70; for _ in 1 2 3; do bash "$H" <<<"$O" >/dev/null; done
M=$(bash "$H" <<<"$O" | jq -r '.hookSpecificOutput.permissionDecisionReason')
ok "el motivo cita la ruta del nucleo y handoff" "$(command grep -c "$NUC.*handoff --desde <borrador> --sesion a2" <<<"$M")" 1

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
mkdir -p "$L/nudge-k"; printf '70\n' >"$L/nudge-k/x"; echo "$NUC" >"$L/nudge-k/x.nucleo"; touch -d '-10 minutes' "$L/nudge-k/x.nucleo"; touch -d '-30 minutes' "$NUC"
ok "SID con / : sin deny" "$(rep 'k/x')" pasa
arma l 70
ok "CC_NUCLEO_GATE=0 apaga" "$(CC_NUCLEO_GATE=0 rep l)" pasa

arma n 70 85
ok "banda 85 avisada: cuenta propia, deniega la 4.ª" "$(seq5 n)" "pasa pasa pasa deny pasa"
arma o 70; seq5 o >/dev/null; printf '70\n85\n' >"$L/nudge-o"; touch -d '-5 minutes' "$L/nudge-o.nucleo"
ok "banda 85 deniega otra vez si la 70 ya denegó" "$(seq5 o)" "pasa pasa pasa deny pasa"
ok "y la 85 ya denegada no vuelve" "$(seq5 o)" "pasa pasa pasa pasa pasa"
arma p 70; seq5 p >/dev/null
ok "la 70 ya denegada no vuelve a denegar" "$(seq5 p)" "pasa pasa pasa pasa pasa"

exit $FAIL
