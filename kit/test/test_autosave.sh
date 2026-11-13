#!/usr/bin/env bash
# test_autosave.sh — ADR 028, capa 1: `handoff --auto` y el hook autosave.sh escriben solo «## Último turno (auto)»,
# sin modelo, sin rotar nucleo.prev-*, sin tocar el dueño ni el mtime de nucleo.md. Sin red; HOME falso.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
K=$HERE/../claude
BIN=$K/bin/handoff
HOOK=$K/hooks
T=$(mktemp -d)
PIDS=()
trap 'kill "${PIDS[@]}" 2>/dev/null; find "$T" -depth -delete' EXIT
export HOME=$T/home GIT_CEILING_DIRECTORIES=$T LC_ALL=C.UTF-8; unset CLAUDE_PROJECT_DIR CLAUDE_PID CLAUDE_CODE_SESSION_ID CLAUDE_HOME
mkdir -p "$HOME" "$T/repo/.claude/estado"
R=$T/repo; E=$R/.claude/estado; NUC=$E/nucleo.md
git -C "$R" init -q; git -C "$R" config user.email a@b; git -C "$R" config user.name a
echo x >"$R/a.sh"; git -C "$R" add a.sh; git -C "$R" commit -qm init
echo y >>"$R/a.sh"; echo n >"$R/nuevo.md"
# shellcheck source=SCRIPTDIR/../claude/hooks/lib/nucleo.sh
. "$HOOK/lib/nucleo.sh"
FAIL=0
ok() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (esperado '$3', sale '$2')"; FAIL=1; fi; }
AUTOH='## Último turno (auto)'
seccion() { awk -v h="$AUTOH" '/^## / { g = ($0 == h) } g { print }' "$1"; }
sin_seccion() { awk -v h="$AUTOH" '/^## / { g = ($0 == h) } !g { print }' "$1" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'; }

TR=$HOME/t.jsonl
cat >"$TR" <<EOF
{"type":"user","message":{"role":"user","content":"arregla el login de la app"}}
{"type":"assistant","message":{"model":"claude-opus-4-7","usage":{"input_tokens":1000,"cache_read_input_tokens":50000,"cache_creation_input_tokens":0},"content":[{"type":"text","text":"Voy a editar."},{"type":"tool_use","name":"Edit","input":{"file_path":"$R/a.sh"}},{"type":"tool_use","name":"Bash","input":{"command":"make test"}},{"type":"tool_use","name":"Bash","input":{"command":"oraculo -- bash t.sh"}}]}}
EOF
printf '%s\t%s\t%s\n' 2026-11-09T10:00:00Z 0 'bash t.sh' >"$E/verificaciones.log"
# hook_json <evento> [extra jq]: el stdin de un hook con las claves reales de Stop/PostCompact/SessionEnd.
hook_json() { jq -cn --arg e "$1" --arg t "${TP:-$TR}" --arg c "${CWD:-$R}" --arg s "${SID:-sid-1}" --arg sm "${SUMM:-resumen de la compactación}" \
  '{hook_event_name:$e,session_id:$s,transcript_path:$t,cwd:$c,last_assistant_message:"Hecho: login arreglado."}
   + (if $e == "PostCompact" then {compact_summary:$sm} else {} end)'; }
auto() { hook_json "${1:-Stop}" | bash "$BIN" --auto --json "${@:2}"; }

printf '# Estado\n\n## Objetivo\nhacer algo\n\n## Paso actual\nuno\n\n## Siguiente acción\ndos\n' >"$NUC"
ORIG=$(cat "$NUC")
touch -d '2026-01-01 10:00:00' "$NUC"; MT0=$(stat -c %Y "$NUC")

# 1. la sección: forma, tope y que es la última
auto Stop >"$T/out" 2>"$T/err"; RC=$?
ok "1 --auto sale 0" "$RC" 0
ok "1 el camino feliz no escribe en stderr" "$(wc -c <"$T/err" | tr -d ' ')" 0
ok "1 la salida es el recibo JSON" "$(jq -r '.motivo' "$T/out")" stop
ok "1 la sección existe y es la última cabecera" "$(grep -c '^## ' "$NUC"),$(grep '^## ' "$NUC" | tail -1)" "4,$AUTOH"
ok "1 la sección pesa <= 600 B" "$([ "$(seccion "$NUC" | wc -c)" -le 600 ] && echo si)" si
S=$(seccion "$NUC")
ok "1 trae persona, asistente, tocados y comandos" "$(grep -c '^- Persona: «arregla el login\|^- Asistente: «Hecho: login arreglado.»\|^- Tocados: .*a.sh\|^- Comandos: oraculo -- bash t.sh rc 0 · make test$' <<<"$S")" 4
ok "1 primera línea: fecha, motivo, rama y ctx" "$(sed -n 2p <<<"$S" | grep -c '^- [0-9-]*T[0-9:]* · stop · rama .* @ [0-9a-f]\{7\} · ctx [0-9]* %$')" 1
ok "1 los tocados incluyen lo no versionado" "$(grep -c 'nuevo.md' <<<"$S")" 1
# 2. solo cambia esa sección
ok "2 el resto del nucleo es el original" "$(sin_seccion "$NUC")" "$ORIG"
# 3. mtime conservado
ok "3 el mtime de nucleo.md no se mueve" "$(stat -c %Y "$NUC")" "$MT0"
# 4. sin rotación, dueño intacto, tope, 50 seguidos
printf 'sesion=sid-1\ndesde=%s\n' "$(date +%s)" >"$E/.dueno"; D0=$(cksum <"$E/.dueno")
for _ in $(seq 50); do auto Stop >/dev/null 2>&1 || break; done
ok "4 50 --auto seguidos: ningún nucleo.prev-*" "$(find "$E" -name 'nucleo.prev-*' | wc -l | tr -d ' ')" 0
ok "4 el dueño sigue intacto" "$(cksum <"$E/.dueno")" "$D0"
ok "4 nucleo <= 5700 B" "$([ "$(wc -c <"$NUC")" -le 5700 ] && echo si)" si
ok "4 una sola sección auto" "$(grep -c "^$AUTOH\$" "$NUC")" 1
ok "4 sigue sin cambiar el resto ni el mtime" "$(sin_seccion "$NUC" | cksum),$(stat -c %Y "$NUC")" "$(printf '%s\n' "$ORIG" | cksum),$MT0"
# 5. dueño ajeno
printf 'sesion=otra-sesion\ndesde=%s\n' "$(date +%s)" >"$E/.dueno"; B0=$(cksum <"$NUC")
SID=sid-1 auto Stop >"$T/out"; RC=$?
ok "5 dueño ajeno: rc 0, omitido y sin cambios" "$RC,$(jq -r .omitido "$T/out"),$([ "$(cksum <"$NUC")" = "$B0" ] && echo igual)" "0,dueño ajeno,igual"
rm -f "$E/.dueno"
# 6. lock ocupado
exec {FD}>>"$E/.handoff.lock"; flock -x "$FD"
auto Stop >"$T/out"; RC=$?
ok "6 lock ocupado: rc 0, omitido y sin esperar" "$RC,$(jq -r .omitido "$T/out")" "0,ocupado"
flock -u "$FD"; exec {FD}>&-
# 7. transcript a medias
printf '\n%s' '{"type":"assistant","message":{"content":[{"type":"text","text":"cort' >>"$TR"
auto Stop >"$T/out" 2>"$T/err"; RC=$?
ok "7 transcript con la última línea cortada: rc 0 y sección escrita" "$RC,$(jq -r .motivo "$T/out"),$(grep -c '^- Persona: ' "$NUC")" "0,stop,1"
RT=$TR; TR=$HOME/no-existe.jsonl
auto Stop >"$T/out" 2>"$T/err"; RC=$?
ok "7 transcript ausente: rc 0 y primera línea sin ctx" "$RC,$(seccion "$NUC" | sed -n 2p | grep -c ctx)" "0,0"
TR=$RT
# 8. repo git sin estado (cv2/estado, D2: antes «no crea nada»; el método promete que se guarda solo): sin trabajo
# no crea nada y lo anota en el log; con trabajo crea el estado desde la plantilla, lo excluye de git y hace dueña a la sesión.
N=$T/vacio; mkdir -p "$N"; git -C "$N" init -q
printf '%s\n' '{"type":"user","message":{"role":"user","content":"hola"}}' >"$T/sin-trabajo.jsonl"
: >"$T/log0"; ALOGF=$HOME/.claude/session-logs/autosave.log; L0=$(wc -l <"$ALOGF" 2>/dev/null || echo 0)
CWD=$N TP=$T/sin-trabajo.jsonl auto Stop >"$T/out"; RC=$?
ok "8 sin nucleo ni trabajo: rc 0, omitido y no crea .claude/" "$RC,$(jq -r .omitido "$T/out"),$([ -e "$N/.claude" ] && echo creado || echo nada)" "0,sin trabajo,nada"
ok "8 el turno saltado queda en autosave.log con su motivo" "$(tail -n +"$((L0 + 1))" "$ALOGF" | command grep -c 'omitido=sin trabajo')" 1
NUCLEO_AUTOINICIO=0 CWD=$N TP=$T/sin-trabajo.jsonl auto Stop >"$T/out"
ok "8 NUCLEO_AUTOINICIO=0 apaga el autoinicio" "$(jq -r .omitido "$T/out"),$([ -e "$N/.claude" ] && echo creado || echo nada)" "sin estado,nada"
echo trabajo >"$N/hecho.md"
CWD=$N TP=$T/sin-trabajo.jsonl auto Stop >"$T/out"; RC=$?
ok "8 sin nucleo y con trabajo: crea nucleo.md desde la plantilla y escribe la sección" "$RC,$(grep -c '^## Paso actual' "$N/.claude/estado/nucleo.md"),$(grep -c '^## Último turno (auto)$' "$N/.claude/estado/nucleo.md"),$(grep -c 'hecho.md' "$N/.claude/estado/nucleo.md")" "0,1,1,1"
ok "8 el estado nuevo queda fuera de git (info/exclude)" "$(git -C "$N" status --short | command grep -c claude)" 0
ok "8 la sesión que lo creó es la dueña" "$(nucleo_dueno "$N" | cut -d' ' -f1)" sid-1
N=$T/solo-estado-md; mkdir -p "$N"; git -C "$N" init -q; printf '# Estado\nESTADO\n' >"$N/ESTADO.md"
CWD=$N auto Stop >"$T/out"
ok "8 modo ESTADO.md: omitido y ESTADO.md intacto" "$(jq -r .omitido "$T/out"),$(cat "$N/ESTADO.md" | tr '\n' ' ')" "modo ESTADO.md,# Estado ESTADO "
# 9. compact
rm -f "$E/autosave.dirty"
auto Stop >/dev/null 2>&1
ok "9 un Stop con trabajo deja motivo=edit" "$(sed -n 1p "$E/autosave.dirty")" motivo=edit
auto PostCompact >"$T/out" 2>&1
SHA=$(printf '%s' sid-1 | sha256sum | cut -d' ' -f1)
ok "9 PostCompact: motivo=compact y compact-summary" "$(sed -n 1p "$E/autosave.dirty"),$(cat "$E/checkpoints/compact-summary-$SHA.md")" "motivo=compact,resumen de la compactación"
ok "9 el motivo del hook se deduce del evento" "$(jq -r .motivo "$T/out")" compact
auto Stop >/dev/null 2>&1
ok "9 un Stop posterior no degrada compact a edit" "$(sed -n 1p "$E/autosave.dirty")" motivo=compact
ok "9 el dirty trae desde= y ultimo=" "$(grep -c '^desde=\|^ultimo=' "$E/autosave.dirty")" 2
auto SessionEnd >"$T/out" 2>&1
ok "9 SessionEnd deduce motivo fin" "$(jq -r .motivo "$T/out")" fin
# 10. --desde: borra dirty, conserva la sección, no falla por no traerla
printf '## Paso actual\nnuevo paso\n' >"$T/draft"
CLAUDE_CODE_SESSION_ID=sid-1 bash "$BIN" --raiz "$R" --desde "$T/draft" >"$T/out" 2>"$T/err"; RC=$?
ok "10 --desde tras --auto sale 0 (no es un 4)" "$RC" 0
ok "10 --desde borra autosave.dirty" "$([ -e "$E/autosave.dirty" ] && echo queda || echo borrado)" borrado
ok "10 --desde conserva la sección auto, la última" "$(grep -c "^$AUTOH\$" "$NUC"),$(grep '^## ' "$NUC" | tail -1)" "1,$AUTOH"
ok "10 --desde aplicó el borrador" "$(grep -c '^nuevo paso$' "$NUC")" 1
ok "10 un --auto tras --desde no rota ni toca el dueño" "$(auto Stop >/dev/null 2>&1; find "$E" -name 'nucleo.prev-*' | wc -l | tr -d ' ')" 1
printf '%s\n## Ficheros tocados\n- x\n## Último turno (auto)\n- inventada\n' "$(printf '## Paso actual\notro paso')" >"$T/draft2"
CLAUDE_CODE_SESSION_ID=sid-1 bash "$BIN" --raiz "$R" --desde "$T/draft2" >/dev/null 2>&1; RC=$?
ok "10 un borrador que copia la sección auto no falla ni la sustituye" "$RC,$(grep -c inventada "$NUC"),$(grep '^## ' "$NUC" | tail -1)" "0,0,$AUTOH"
# 10b. al recortar, la sección auto es lo primero que sale, sin copia en diario ni aviso
{ printf '## Paso actual\n'; for i in $(seq 1 75); do printf 'linea de paso %03d con algo de relleno para pesar bastante en el nucleo\n' "$i"; done; } >"$T/grande"
CLAUDE_CODE_SESSION_ID=sid-1 bash "$BIN" --raiz "$R" --desde "$T/grande" >"$T/out" 2>"$T/err"; RC=$?
ok "10b tope: rc 0, la sección auto se fue y el paso entero se conserva" "$RC,$(grep -c "^$AUTOH\$" "$NUC"),$(grep -c 'linea de paso 075' "$NUC")" "0,0,1"
ok "10b tope: sin copia de la sección auto en diario.md" "$(grep -c 'Último turno (auto)\|omitido por tope: Último' "$E/diario.md" 2>/dev/null)" 0
# 11. tope: con el nucleo casi al tope la sección se recorta o no entra; nunca otra sección
CLAUDE_CODE_SESSION_ID=sid-1 bash "$BIN" --raiz "$R" --desde "$T/draft" >/dev/null 2>&1
{ cat "$NUC"; printf '\n## Pendientes\n'; for i in $(seq 1 120); do printf -- '- [ ] pendiente %02d con texto de relleno para engordar el fichero\n' "$i"; done; } >"$T/gordo"
head -c 5560 "$T/gordo" >"$NUC"; printf '\n' >>"$NUC"; touch -d '2026-01-01 10:00:00' "$NUC"; ORIG11=$(cat "$NUC")
auto Stop >"$T/out" 2>"$T/err"; RC=$?
ok "11 nucleo casi al tope: rc 0 y <= 5700 B" "$RC,$([ "$(wc -c <"$NUC")" -le 5700 ] && echo si)" "0,si"
ok "11 lo demás intacto" "$(sin_seccion "$NUC" | cksum)" "$(printf '%s\n' "$ORIG11" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' | cksum)"
# Sin sitio ni para dos líneas se escribe la sección mínima igualmente: omitirla dejaba la vieja, que tras compactar
# engaña más que unos bytes de más (la inyección los recorta, y la sección auto es lo primero que sale).
head -c 5690 "$T/gordo" >"$NUC"; printf '\n' >>"$NUC"
B11=$(sin_seccion "$NUC" | cksum); auto Stop >"$T/out"
ok "11 sin sitio ni para dos líneas: escribe la sección mínima y lo demás intacto" "$(jq -r '.omitido // "escrito"' "$T/out"),$(sed -n "/^$AUTOH\$/,\$p" "$NUC" | wc -l | tr -d ' '),$([ "$(sin_seccion "$NUC" | cksum)" = "$B11" ] && echo igual)" "escrito,2,igual"
printf '# Estado\n\n## Objetivo\nhacer algo\n\n## Paso actual\nuno\n\n## Siguiente acción\ndos\n' >"$NUC"
# 12. inyección: la sección se emite como dato en los SessionStart, sin avisos de «fuera de forma»
auto Stop >/dev/null 2>&1
EM=$(nucleo_emitir "$NUC")
ok "12 nucleo_emitir emite la sección" "$(grep -c "^$AUTOH\$" <<<"$EM"),$(grep -c 'fuera de forma\|recortado' <<<"$EM")" "1,0"
for src in clear compact; do
  h=session-start-clear.sh; [ "$src" != compact ] || h=session-start-compact.sh
  CTX=$(jq -cn --arg c "$R" --arg s other '{cwd:$c,session_id:$s,source:"'"$src"'"}' | bash "$HOOK/$h" | jq -r '.hookSpecificOutput.additionalContext // empty')
  ok "12 SessionStart $src inyecta la sección" "$(grep -c "^$AUTOH\$" <<<"$CTX"),$(grep -c 'fuera de forma' <<<"$CTX")" "1,0"
done
rm -f "$E/.dueno"   # el SessionStart de 12 reclamó el dueño para otra sesión
# 13. el hook: sin stdout, rc 0, agent_id lo salta
B13=$(cksum <"$NUC")
OUT=$(hook_json Stop | jq -c '. + {agent_id:"ag1"}' | bash "$HOOK/autosave.sh" 2>&1); RC=$?
ok "13 hook con agent_id: rc 0, sin salida y nada escrito" "$RC,${#OUT},$([ "$(cksum <"$NUC")" = "$B13" ] && echo igual)" "0,0,igual"
OUT=$(hook_json Stop | bash "$HOOK/autosave.sh" 2>&1); RC=$?
ok "13 hook del hilo principal: rc 0 y sin salida" "$RC,${#OUT}" "0,0"
ok "13 el hook escribió (timestamp de la sección reciente)" "$(seccion "$NUC" | sed -n 2p | grep -c '^- 20')" 1
OUT=$(printf 'esto no es json' | bash "$HOOK/autosave.sh" 2>&1); RC=$?
ok "13 stdin roto: rc 0 y sin salida" "$RC,${#OUT}" "0,0"
OUT=$(jq -cn '{hook_event_name:"Stop",session_id:"x",cwd:"/tmp/../etc",transcript_path:"../t.jsonl"}' | bash "$HOOK/autosave.sh" 2>&1); RC=$?
ok "13 rutas con «..» no se usan: rc 0 y sin salida" "$RC,${#OUT}" "0,0"
# 13b. validación de rutas del JSON: ni «..» ni fuera de ~ y la raíz entran; un cwd rechazado omite (nunca cae a $PWD)
mkdir -p "$HOME/sub"; sed 's/arregla el login de la app/PERSONA-TRAMPA/' "$TR" >"$HOME/t2.jsonl"; cp "$HOME/t2.jsonl" "$T/fuera.jsonl"
B13=$(cksum <"$NUC")
for tp in "$HOME/sub/../t2.jsonl" "$T/fuera.jsonl"; do
  TP=$tp auto Stop >/dev/null 2>&1
  ok "13b transcript_path $(basename "$(dirname "$tp")")/…: no se lee (la sección no trae su persona)" "$(grep -c PERSONA-TRAMPA "$NUC")" 0
done
TP=$HOME/t2.jsonl auto Stop >/dev/null 2>&1
ok "13b el mismo transcript sin «..» y bajo ~ sí se lee" "$(grep -c PERSONA-TRAMPA "$NUC")" 1
auto Stop >/dev/null 2>&1; B13=$(cksum <"$NUC")
CWD=$R/../repo auto Stop >"$T/out"; RC=$?
ok "13b cwd con «..»: omitido «cwd inválido» y nada cambia" "$RC,$(jq -r .omitido "$T/out"),$([ "$(cksum <"$NUC")" = "$B13" ] && echo igual)" "0,cwd inválido,igual"
# 13c. topes: la sección con textos largos pesa <= 600 B; el compact_summary guardado <= 4096 B
LARGO=$(printf 'é%.0s' $(seq 1 400))   # 2 B por carácter: los topes por carácter solos no bastan para 600 B
jq -cn --arg l "$LARGO" --arg r "$R" '{type:"user",message:{content:("persona " + $l)}},
  {type:"assistant",message:{usage:{input_tokens:9000},content:[{type:"text",text:("asistente " + $l)},
   {type:"tool_use",name:"Edit",input:{file_path:($r + "/dir/" + $l + ".sh")}},{type:"tool_use",name:"Bash",input:{command:("echo " + $l)}}]}}' >"$HOME/largo.jsonl"
TP=$HOME/largo.jsonl auto Stop >/dev/null 2>&1
ok "13c textos largos: la sección pesa <= 600 B y sigue con su cabecera y primera línea" "$([ "$(seccion "$NUC" | wc -c)" -le 600 ] && echo si),$(seccion "$NUC" | sed -n 1p | grep -c '^## Último')" "si,1"
ok "13c y el recorte respeta cada línea (la persona, cortada a 120 caracteres, se conserva)" "$(seccion "$NUC" | grep -c "^- Persona: «persona é\{112\}»$")" 1
SUMM=$(head -c 10000 /dev/zero | tr '\0' 'r') auto PostCompact >/dev/null 2>&1
ok "13c compact_summary de 10 KB: el fichero guardado pesa <= 4096 B" "$(wc -c <"$E/checkpoints/compact-summary-$(printf '%s' sid-1 | sha256sum | cut -d' ' -f1).md" | tr -d ' ')" 4096
# 14. KPI de pre-compact: edad_auto al final
touch -d '2026-01-01 10:00:00' "$NUC"
jq -cn --arg c "$R" --arg t "$TR" '{trigger:"auto",session_id:"kpi",transcript_path:$t,cwd:$c}' | bash "$HOOK/pre-compact.sh" >/dev/null 2>&1
L=$(tail -n1 "$HOME/.claude/session-logs/nucleo-freshness.log")
ok "14 pre-compact: KPI con 5 campos y edad_auto numérica al final" "$(awk '{ print NF "," ($5 ~ /^[0-9]+$/ ? "num" : "no") }' <<<"$L")" "5,num"
ok "14 la edad del nucleo (campo 4) sigue siendo la del mtime" "$([ "$(awk '{print $4}' <<<"$L")" -gt 1000000 ] && echo si)" si
# 15. ~: sin trabajo no crea ranura; con tocados sí y deja .sesion; por_sid recupera
sleep 300 & PH=$!; PIDS+=("$PH")
TRH=$HOME/th.jsonl; printf '{"type":"user","message":{"content":"hola"}}\n' >"$TRH"
SES=$HOME/.claude/estado/sesiones
jq -cn --arg c "$HOME" --arg t "$TRH" '{hook_event_name:"Stop",session_id:"home-1",transcript_path:$t,cwd:$c,last_assistant_message:"hola"}' | CLAUDE_PID=$PH bash "$BIN" --auto --json >"$T/out" 2>&1; RC=$?
ok "15 en ~ sin trabajo: omitido y no crea ranura" "$RC,$(jq -r .omitido "$T/out"),$(find "$SES" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')" "0,sin trabajo,0"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"%s/notas.md"}}]}}\n' "$HOME" >>"$TRH"
jq -cn --arg c "$HOME" --arg t "$TRH" '{hook_event_name:"Stop",session_id:"home-1",transcript_path:$t,cwd:$c}' | CLAUDE_PID=$PH bash "$BIN" --auto --json >"$T/out" 2>&1; RC=$?
SH=$(ls -d "$SES"/*-"$PH" 2>/dev/null)
ok "15 en ~ con un fichero tocado: crea la ranura con nucleo.md y .sesion" "$RC,$([ -f "$SH/nucleo.md" ] && echo nucleo),$(cat "$SH/.sesion" 2>/dev/null)" "0,nucleo,home-1"
ok "15 la sección de la ranura trae el fichero relativo a ~" "$(seccion "$SH/nucleo.md" | grep -c '^- Tocados: notas.md$')" 1
ok "15 por_sid encuentra la ranura" "$(nucleo_sesion_dir por_sid home-1)" "$SH"
# 16. el hook en ~ (timeout es el padre de handoff): CLAUDE_PID le da la ranura
jq -cn --arg c "$HOME" --arg t "$TRH" '{hook_event_name:"Stop",session_id:"home-1",transcript_path:$t,cwd:$c}' | CLAUDE_PID=$PH bash "$HOOK/autosave.sh"
ok "16 autosave.sh en ~ escribe en la ranura del proceso" "$(find "$SES" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' '),$(seccion "$SH/nucleo.md" | grep -c "^$AUTOH\$")" "1,1"

# 17. D6: la sección no copia secretos (mismas reglas que el redact del cockpit). Claves falsas por concatenación.
R17=$T/repo17; mkdir -p "$R17/.claude/estado"; git -C "$R17" init -q; printf '# Estado\n\n## Objetivo\nx\n' >"$R17/.claude/estado/nucleo.md"
AT=@; K1="sk-""ant-api03-ABCDEFGHIJKLMNOPQRSTUV"; K2="gh""p_0123456789abcdefghijABCDEFGHIJ012345"; K3="AK""IAABCDEFGHIJKLMNOP"; K4="ey""JhbGciOiJIUzI1NiJ9.ey""JzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghij12345"
TR17=$HOME/t17.jsonl
jq -cn --arg p "usa la clave $K1 y el token $K2 para el deploy, password=hunter2x y $K4" '{type:"user",message:{role:"user",content:$p}}' >"$TR17"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"%s/a.sh"}}]}}\n' "$R17" >>"$TR17"
jq -cn --arg t "$TR17" --arg c "$R17" --arg m "Listo, la clave era $K3 y la URL https://usuario:clave99${AT}host.ejemplo/x con Bearer abcdef123456" \
  '{hook_event_name:"Stop",session_id:"sid-17",transcript_path:$t,cwd:$c,last_assistant_message:$m}' | bash "$BIN" --auto --json >"$T/out" 2>&1; RC=$?
S17=$(seccion "$R17/.claude/estado/nucleo.md")
ok "17 la sección se escribe (rc 0, con persona y asistente)" "$RC,$(grep -c '^- Persona: \|^- Asistente: ' <<<"$S17")" "0,2"
ok "17 ninguna clave, token, contraseña, JWT ni credencial de URL sobrevive" "$(grep -c "$K1\|$K2\|$K3\|hunter2x\|ey""JhbGci\|clave99\|abcdef123456" <<<"$S17")" 0
ok "17 queda la marca [REDACTADO]" "$(grep -c 'REDACTADO' <<<"$S17")" 2

[ "$FAIL" -eq 0 ] && echo "PASS" || echo "FAIL"
exit "$FAIL"
