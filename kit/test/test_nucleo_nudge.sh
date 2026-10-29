#!/usr/bin/env bash
# test_nucleo_nudge.sh — contrato de kit/claude/hooks/nucleo-nudge.sh (PostToolUse): pide al modelo
# actualizar nucleo.md por bandas del airbag (50/70/85 %), una vez por banda y sesión, solo con el
# nucleo rancio (> 10 min) o ausente, en ≤ 400 chars y con la ruta exacta; si no toca, nada.
# Uso: test_nucleo_nudge.sh [ruta al hook]. Sin red; HOME falso en un mktemp que se borra.
set -u
H=$(realpath "${1:-$(dirname "$0")/../claude/hooks/nucleo-nudge.sh}"); T=$(mktemp -d); trap 'rm -rf -- "$T"' EXIT; export CC_NUCLEO_GATE=1
export HOME=$T/home GIT_CEILING_DIRECTORIES=$T; unset CLAUDE_PID CLAUDE_PROJECT_DIR CLAUDE_CODE_AUTO_COMPACT_WINDOW CLAUDE_CODE_SESSION_ATTENDED CLAUDE_CODE_ENTRYPOINT
FAIL=0
ok() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (esperado '$3', sale '$2')"; FAIL=1; fi; }
R=$T/repo; mkdir -p "$R/.claude/estado" "$HOME"; git -C "$R" init -q
NUC=$R/.claude/estado/nucleo.md
# Ventana por defecto 200 000 → airbag de 167 000 tokens.
mk() { jq -cn --argjson n "$2" '{type:"assistant",message:{usage:{input_tokens:1000,cache_read_input_tokens:($n-1000)},content:[]}}' >"$T/$1.jsonl"; }
run() { jq -cn --arg c "$R" --arg s "$1" --arg t "$T/$2.jsonl" '{session_id:$s,transcript_path:$t,cwd:$c,hook_event_name:"PostToolUse",tool_name:"Bash"}' | bash "$H"; }
# Los topes miden el texto del kit, no la ruta del mktemp: $T cuenta como un mktemp típico (16 chars).
largo() { local s=${1//"$T"/0123456789abcdef}; echo "${#s}"; }
ctx() { jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }
mk p20 33400; mk p60 100200; mk p72 120240; mk p90 150300

echo x >"$NUC"; touch -d '-30 minutes' "$NUC"
ok "20 % → vacío" "$(run s1 p20)" ""
OUT=$(run s1 p60); C=$(ctx <<<"$OUT")
ok "60 % + nucleo viejo → nudge" "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$OUT")" PostToolUse
ok "nudge: cita la banda, la edad y la ruta exacta" "$(command grep -c "CONTEXTO 60 % del airbag. nucleo.md lleva 30 min .* en $NUC\." <<<"$C")" 1
ok "nudge ≤ 400 chars" "$([ "$(largo "$C")" -le 400 ] && echo si)" si
ok "nucleo dentro del tope: sin aviso de tamaño" "$(command grep -c 'Ocupa .* B (tope' <<<"$C")" 0
ok "misma banda dos veces → una sola" "$(run s1 p60)" ""
ok "banda siguiente (70 %) sí avisa" "$(run s1 p72 | ctx | command grep -c '72 % del airbag')" 1
ok "70 %: fin de fase es parada válida" "$(run s6 p72 | ctx | command grep -c 'Fin de fase = parada válida: termina la fase, actualiza nucleo.md y cierra el turno\.')" 1
C90=$(run s1 p90 | ctx)
ok "85 %: cierra ya; handoff y /clear automáticos con cockpit" "$(command grep -c 'Cierra el turno ya: con cockpit en un proyecto, el handoff y /clear son automáticos al cerrar el turno; si no, la persona hará /handoff\.' <<<"$C90")" 1
ok "85 % ≤ 400 chars" "$([ "$(largo "$C90")" -le 400 ] && echo si)" si
ok "85 % con COCKPIT_AUTO_HANDOFF=off: no promete handoff automático" "$(COCKPIT_AUTO_HANDOFF=off run s7 p90 | ctx | command grep -c 'Cierra el turno ya: el handoff automático está desactivado; la persona hará /handoff\.')" 1
# K7: un subagente (agent_id no vacío) no recibe el aviso: no es quien escribe nucleo.md ni quien decide cerrar.
runa() { jq -cn --arg c "$R" --arg s "$1" --arg t "$T/$2.jsonl" --arg a "$3" '{session_id:$s,transcript_path:$t,cwd:$c,tool_name:"Bash",agent_id:$a}' | bash "$H"; }
ok "subagente (agent_id) al 60 % → vacío" "$(runa s30 p60 x)" ""
ok "agent_id vacío → avisa como el hilo principal" "$(runa s31 p60 '' | ctx | command grep -c '60 % del airbag')" 1
ok "el subagente no gasta la banda del hilo principal" "$(run s30 p60 | ctx | command grep -c '60 % del airbag')" 1
ok "otra sesión tiene sus propias bandas" "$(run s2 p60 | ctx | command grep -c '60 % del airbag')" 1
# Compactar no cambia el session_id: sin rearme, solo avisaba en el primer ciclo de la sesión.
run s5 p60 >/dev/null; run s5 p20 >/dev/null
ok "bajo el 50 % se rearma: 60 % avisa otra vez" "$(run s5 p60 | ctx | command grep -c '60 % del airbag')" 1
touch "$NUC"
ok "60 % + nucleo fresco → vacío" "$(run s3 p60)" ""
# Editado a mano por encima del tope: al retomar se omitirían secciones enteras; el aviso lo dice con su tamaño.
# 6 000 B caben en 6 500, pero no junto al bloque de agentes: el tope es el que usa handoff (6 500 − 800).
head -c 6000 /dev/zero | tr '\0' x >"$NUC"; touch -d '-30 minutes' "$NUC"
C=$(run s40 p60 | ctx)
ok "nucleo por encima del tope: el aviso da tamaño y tope" "$(command grep -c 'Ocupa 6000 B (tope 5700): pasa lo cerrado a diario.md\.' <<<"$C")" 1
ok "con el aviso de tope sigue ≤ 400 chars" "$([ "$(largo "$C")" -le 400 ] && echo si)" si
rm -f "$NUC"
ok "sin nucleo → pide crearlo con la plantilla" "$(run s4 p60 | ctx | command grep -c "créalo en $NUC con la forma de .*templates/nucleo.md")" 1
ok "session_id con barras → nada (va a un nombre de fichero)" "$(run '../x' p60)" ""
ok "stdin roto → nada y exit 0" "$(echo 'no json' | bash "$H"; echo "rc=$?")" "rc=0"

# K8 (D1): desde ~ el aviso no nombra ni ordena el nucleo compartido, que puede ser de otra tarea.
runh() { jq -cn --arg c "$HOME" --arg s "$1" --arg t "$T/$2.jsonl" '{session_id:$s,transcript_path:$t,cwd:$c,tool_name:"Bash"}' | bash "$H"; }
HN=$HOME/.claude/estado/nucleo.md; mkdir -p "$HOME/.claude/estado"; echo x >"$HN"; touch -d '-30 minutes' "$HN"
C=$(runh s50 p60 | ctx)
ok "K8 ~ al 60 %: avisa sin la ruta del nucleo de ~ y dice «desde ~»" "$(command grep -c 'CONTEXTO 60 % del airbag\. Sesión abierta desde ~: no tiene nucleo propio\.' <<<"$C"),$(command grep -cF "$HN" <<<"$C"),$(command grep -c 'actualiza Paso actual' <<<"$C")" 1,0,0
unlink "$HN"
ok "K8 ~ sin nucleo: el mismo aviso, sin «créalo»" "$(runh s51 p60 | ctx | command grep -c 'desde ~'),$(runh s51b p60 | ctx | command grep -c 'créalo')" 1,0
ok "K8 ~ al 70 %: conserva la coletilla de banda" "$(runh s52 p72 | ctx | command grep -c 'Fin de fase = parada válida')" 1
C=$(runh s53 p90 | ctx)
ok "K8 ~ al 85 %: cierra el turno, sin prometer handoff" "$(command grep -c 'Cierra el turno ya\.' <<<"$C"),$(command grep -c 'handoff' <<<"$C")" 1,0
echo x >"$NUC"; touch -d '-30 minutes' "$NUC"
ok "K8 en proyecto: igual que antes" "$(run s54 p60 | ctx | command grep -c "actualiza Paso actual / Siguiente acción / Pendientes en $NUC")" 1

# v1.5 K3: en -p/SDK nadie cierra el turno ni pulsa /handoff ni h (medido: claude -p da CLAUDE_CODE_SESSION_ATTENDED=0
# y CLAUDE_CODE_ENTRYPOINT=sdk-cli al hook; el interactivo, 1 y cli). Se pide guardar el estado y seguir.
# Sin handoff en el PATH (CI) el aviso da la ruta …/bin/handoff: eso no es el comando /handoff.
echo x >"$NUC"; touch -d '-30 minutes' "$NUC"
for SEN in "CLAUDE_CODE_SESSION_ATTENDED=0" "CLAUDE_CODE_ENTRYPOINT=sdk-cli"; do
  for B in p72 p90; do
    C=$( (export "${SEN?}"; run "k3${SEN//[^A-Za-z]/}$B" "$B") | ctx)
    ok "K3 -p ($SEN, $B): no pide cerrar el turno ni /handoff ni tecla h" "$(command grep -ciE 'cierra el turno|(^|[^[:alnum:]_.-])/handoff|tecla|/clear' <<<"$C"),$([ -n "$C" ] && echo avisa)" 0,avisa
    ok "K3 -p ($SEN, $B): pide guardar el estado y seguir" "$(command grep -c 'handoff --desde\|nucleo.md' <<<"$C"),$(command grep -c 'sigue' <<<"$C")" 1,1
  done
done
ok "K3 interactivo (ATTENDED=1, cli): el 85 % de siempre" "$(CLAUDE_CODE_SESSION_ATTENDED=1 CLAUDE_CODE_ENTRYPOINT=cli run k3-int p90 | ctx | command grep -c 'Cierra el turno ya')" 1
# v1.5 K12: con muchas líneas no-assistant tras el último assistant (adjuntos, api-request…), la ventana de 40 líneas
# no lo veía y el aviso callaba.
{ jq -cn '{type:"assistant",message:{usage:{input_tokens:1000,cache_read_input_tokens:149300},content:[]}}'
  for i in $(seq 1 80); do jq -cn --argjson i "$i" '{type:"attachment",n:$i}'; done; } >"$T/k12.jsonl"
ok "K12: assistant a más de 40 líneas del final: el aviso mide igual" "$(run k12 k12 | ctx | command grep -c '90 % del airbag')" 1

# v3: una tarea = una sesión dueña (.claude/estado/.dueno). Quien no lo es calla: el aviso le pediría escribir
# el nucleo de otra. Con el dueño caducado, o sin dueño, avisa cualquiera.
echo x >"$NUC"; touch -d '-30 minutes' "$NUC"
printf 'sesion=duena1\ndesde=%s\n' "$(date +%s)" >"$R/.claude/estado/.dueno"
ok "dueño: otra sesión al 60 % calla" "$(run s70 p60)" ""
ok "dueño: la dueña sí avisa" "$(run duena1 p60 | ctx | command grep -c '60 % del airbag')" 1
ok "dueño: callar no gasta la banda (al ceder el dueño avisa)" "$(printf 'sesion=duena1\ndesde=1\n' >"$R/.claude/estado/.dueno"; run s70 p60 | ctx | command grep -c '60 % del airbag')" 1
printf 'basura\n' >"$R/.claude/estado/.dueno"
ok "dueño ilegible: avisa cualquiera" "$(run s71 p60 | ctx | command grep -c '60 % del airbag')" 1
unlink "$R/.claude/estado/.dueno"
# v3: al 70 % se propone cerrar la fase con el CLI `handoff` (sin cockpit tampoco hay que esperar a la persona).
C=$(run s72 p72 | ctx)
ok "70 %: propone cerrar la fase con handoff" "$(command grep -c 'handoff' <<<"$C")" 1
ok "60 %: aún no habla de handoff" "$(run s73 p60 | ctx | command grep -c 'handoff')" 0

# Camino caliente: corre tras CADA herramienta. Se mide el camino largo (nucleo rancio, transcript
# leído, banda ya avisada). Mejor de 5: en un runner cargado una sola medida miente.
echo x >"$NUC"; touch -d '-30 minutes' "$NUC"
IN=$(jq -cn --arg c "$R" --arg t "$T/p60.jsonl" '{session_id:"s1",transcript_path:$t,cwd:$c}'); best=99999
for _ in 1 2 3 4 5; do
  t0=$(date +%s%N); bash "$H" <<<"$IN" >/dev/null; ms=$(( ($(date +%s%N) - t0) / 1000000 ))
  [ "$ms" -lt "$best" ] && best=$ms
done
ok "tiempo < 50 ms (mejor de 5: ${best} ms)" "$([ "$best" -lt 50 ] && echo si)" si
# --- #24: camino caliente: bajo el 50 % (y con la banda ya avisada) no se lanza git ni se mira el nucleo ---
mkdir -p "$T/fakebin"; printf '#!/bin/sh\ntouch "%s/git-lanzado"\nexec /usr/bin/git "$@"\n' "$T" >"$T/fakebin/git"; chmod +x "$T/fakebin/git"
runf() { jq -cn --arg c "$R" --arg s "$1" --arg t "$T/$2.jsonl" '{session_id:$s,transcript_path:$t,cwd:$c,tool_name:"Bash"}' | PATH="$T/fakebin:$PATH" bash "$H"; }
rm -f "$T/git-lanzado"; touch -d '-30 minutes' "$NUC"
runf s20 p20 >/dev/null
ok "20 %: no lanza git" "$([ -e "$T/git-lanzado" ] && echo lanzado || echo no)" no
runf s21 p60 >/dev/null
ok "60 % y nucleo viejo: sí lo lanza (control de la sonda)" "$([ -e "$T/git-lanzado" ] && echo lanzado || echo no)" lanzado
rm -f "$T/git-lanzado"; runf s21 p60 >/dev/null
ok "banda ya avisada: no lanza git" "$([ -e "$T/git-lanzado" ] && echo lanzado || echo no)" no

# --- W2: sin handoff en el PATH el texto del 70 % lleva la ruta del kit, y esa ruta existe ---
mkdir -p "$HOME/.claude/bin"; : >"$HOME/.claude/bin/handoff"; chmod +x "$HOME/.claude/bin/handoff"
touch -d '-30 minutes' "$NUC"
WC=$(PATH=/usr/bin:/bin run s40 p72 | ctx); WP=$(sed -n 's/.*`\([^ ]*\) --desde.*/\1/p' <<<"$WC")
ok "W2 nudge: sin handoff en el PATH enseña la ruta absoluta y existe" "$WP,$([ -x "$WP" ] && echo si)" "$HOME/.claude/bin/handoff,si"
ok "W2 nudge 70 % con la ruta ≤ 600 chars" "$([ "$(largo "$WC")" -le 600 ] && echo si)" si
# --- compuerta: el nudge deja la ruta del nucleo que miró (el mtime es la hora del aviso) y rearma la cuenta ---
touch -d '-30 minutes' "$NUC"; run s50 p72 >/dev/null
ok "nudge deja nudge-<sid>.nucleo con la ruta exacta" "$(cat "$HOME/.claude/session-logs/nudge-s50.nucleo" 2>/dev/null)" "$NUC"
G=$(dirname "$H")/nucleo-gate.sh; GC='{"session_id":"s50","tool_name":"Bash","tool_input":{"command":"ls"}}'
gate() { case $(bash "$G" <<<"$GC") in '') echo pasa;; *deny*) echo deny;; esac; }
ok "nudge + compuerta de extremo a extremo: 1.ª a 3.ª pasan, 4.ª deniega" "$(for _ in 1 2 3 4; do gate; done | tr '\n' ' ')" "pasa pasa pasa deny "
# Desde ~ con ranura (se sabe el pid de la sesión): la marca apunta al nucleo de la ranura, el que usa handoff, y la
# compuerta actúa también ahí. Sin pid (K8) sigue sin marca.
C=$(CLAUDE_PID=$$ runh s60 p72 | ctx); SN=$(cat "$HOME/.claude/session-logs/nudge-s60.nucleo" 2>/dev/null)
ok "~ con ranura: nudge-<sid>.nucleo apunta a sesiones/*-<pid>/nucleo.md" "$(case $SN in "$HOME"/.claude/estado/sesiones/*-$$/nucleo.md) echo ranura;; *) echo "${SN:-nada}";; esac)" ranura
ok "~ con ranura: el aviso nombra la ranura y no el nucleo de ~" "$(command grep -cF "${SN:-nada}" <<<"$C"),$(command grep -cF "$HN" <<<"$C")" 1,0
ok "~ con ranura: el comando del nudge lleva --ranura con la ranura" "$(command grep -cF -- "--sesion s60 --ranura ${SN%/nucleo.md}" <<<"$C")" 1
GC='{"session_id":"s60","tool_name":"Bash","tool_input":{"command":"ls"}}'
ok "~ con ranura: nudge + compuerta, la 4.ª deniega" "$(for _ in 1 2 3 4; do gate; done | tr '\n' ' ')" "pasa pasa pasa deny "

exit $FAIL
