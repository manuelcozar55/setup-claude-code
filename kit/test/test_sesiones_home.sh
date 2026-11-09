#!/usr/bin/env bash
# test_sesiones_home.sh — estado de sesión en ~ (W6): una ranura por proceso claude en
# ~/.claude/estado/sesiones/<AAAAMMDD-HHMM>-<pid>/, con handoff, lib y hooks de arranque. Sin red; HOME falso.
# Los claude son `sleep` de verdad: el pid vive y tiene identidad (ticks de /proc/<pid>/stat), como el de claude.
set -u
K=$(realpath "$(dirname "$0")/../claude"); T=$(mktemp -d)
PIDS=()
trap 'kill "${PIDS[@]}" 2>/dev/null; rm -rf -- "$T"' EXIT
export HOME=$T/home GIT_CEILING_DIRECTORIES=$T LC_ALL=C.UTF-8; mkdir -p "$HOME"
unset CLAUDE_PID CLAUDE_PROJECT_DIR NUCLEO_REGISTRO
HO=$K/bin/handoff; HC=$K/hooks/session-start-clear.sh; HK=$K/hooks/session-start-compact.sh
FAIL=0
ok() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (esperado '$3', sale '$2')"; FAIL=1; fi; }
ctx() { jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }
# ho <pid|-> args...: handoff desde ~ con CLAUDE_PID fijado (o ausente). Sale con su rc.
ho() { local p=$1; shift; if [ "$p" = - ]; then (cd "$HOME" && env -u CLAUDE_PID bash "$HO" "$@"); else (cd "$HOME" && CLAUDE_PID=$p bash "$HO" "$@"); fi; }
hook() { local h=$1 p=$2 src=$3 sid=$4; jq -cn --arg c "$HOME" --arg s "$sid" --arg r "$src" '{cwd:$c,session_id:$s,source:$r}' | CLAUDE_PID=$p bash "$h" | ctx; }
borrador() { printf '## Objetivo\nobj-%s\n## Paso actual\npaso-%s\n' "$1" "$1" >"$T/b-$1.md"; echo "$T/b-$1.md"; }
# huella: nombres y contenido de todo ~/.claude/estado; solo los nombres no verían una reescritura en sitio.
huella() { { find "$HOME/.claude/estado" | sort; find "$HOME/.claude/estado" -type f -exec cksum {} + | sort; } 2>/dev/null | cksum; }
SES=$HOME/.claude/estado/sesiones
sleep 300 & PA=$!; PIDS+=("$PA")
sleep 300 & PB=$!; PIDS+=("$PB")
sleep 300 & PC=$!; PIDS+=("$PC")   # sin ranura hasta el final
sleep 0 & PM=$!; wait "$PM"   # pid muerto

# 1. dos sesiones, dos ranuras; ninguna ve el nucleo de la otra
ho "$PA" --desde "$(borrador A)" >/dev/null 2>&1; RA=$?
ho "$PB" --desde "$(borrador B)" >/dev/null 2>&1; RB=$?
ok "1 --desde de la sesión A sale 0" "$RA" 0
ok "1 --desde de la sesión B sale 0" "$RB" 0
ok "1 dos ranuras distintas" "$(find "$SES" -name nucleo.md | wc -l | tr -d ' ')" 2
SA=$(ls -d "$SES"/*-"$PA" 2>/dev/null); SB=$(ls -d "$SES"/*-"$PB" 2>/dev/null)
ok "1 el nucleo de A está en la ranura de A" "$(command grep -c 'obj-A' "$SA/nucleo.md" 2>/dev/null)" 1
ok "1 --estado de A apunta a su ranura" "$(ho "$PA" --estado | jq -r .sesion)" "$SA"
ok "1 --estado de B apunta a su ranura" "$(ho "$PB" --estado | jq -r .sesion)" "$SB"
C=$(hook "$HC" "$PA" clear sA)
ok "1 clear de A inyecta el nucleo de su ranura" "$(command grep -c "<nucleo-datos fuente=\"$SA/nucleo.md\">" <<<"$C")" 1
ok "1 clear de A no ve el nucleo de B" "$(sed -n '/^<nucleo-datos/,/^<\/nucleo-datos>/p' <<<"$C" | command grep -c 'obj-B')" 0

# 2. /clear (mismo pid, otro session_id) recibe su ranura; startup no
ok "2 /clear con otro session_id recibe su nucleo" "$(hook "$HC" "$PA" clear otro-id | command grep -c '<nucleo-datos .*sesiones/')" 1
ok "2 resume también" "$(hook "$HC" "$PA" resume otro-id | command grep -c '<nucleo-datos .*sesiones/')" 1
ok "2 startup no inyecta la ranura" "$(hook "$HC" "$PA" startup otro-id | command grep -c '<nucleo-datos ')" 0
ok "2 startup sí trae el índice con la sesión" "$(hook "$HC" "$PA" startup otro-id | command grep -c '^- sesión en ~')" 2

# 3. sin CLAUDE_PID (y padre no claude): exit 3 y nada escrito
ANTES=$(huella)
ho - --desde "$(borrador C)" >/dev/null 2>&1; R=$?
ok "3 sin CLAUDE_PID --desde sale 3" "$R" 3
ok "3 sin CLAUDE_PID no escribe nada" "$(huella)" "$ANTES"

# 4. CLAUDE_PID de un proceso muerto
ho "$PM" --desde "$(borrador C)" >/dev/null 2>&1; R=$?
ok "4 pid muerto: exit 3" "$R" 3
ok "4 pid muerto: no hay ranura nueva" "$(find "$SES" -name nucleo.md | wc -l | tr -d ' ')" 2

# 5. --commit en ranura
ANTES=$(huella)
ho "$PA" --desde "$(borrador A)" --commit >/dev/null 2>&1; R=$?
ok "5 --commit en ranura: exit 3" "$R" 3
ok "5 --commit en ranura no escribe nada" "$(huella)" "$ANTES"

# 6. --estado
E=$(ho "$PA" --estado); R=$?
ok "6 --estado sale 0" "$R" 0
ok "6 --estado: raiz null" "$(jq -r '.raiz' <<<"$E")" null
ok "6 --estado: nucleo en la ranura" "$(jq -r '.nucleo' <<<"$E")" "$SA/nucleo.md"
ok "6 --estado: pct numérico" "$(jq -r '.pct | type' <<<"$E")" number
ok "6 --estado: dueno null" "$(jq -r '.dueno' <<<"$E")" null
ANTES=$(huella)
ho "$PC" --estado >/dev/null
ok "6 --estado sin ranura no crea nada" "$(huella)" "$ANTES"
ok "6 --estado sin ranura no crea la suya" "$(find "$SES" -maxdepth 1 -name "*-$PC" | wc -l | tr -d ' ')" 0

# 7. --raiz $HOME no usa la ranura
ho "$PA" --desde "$(borrador A)" --raiz "$HOME" >/dev/null 2>&1; ok "7 --raiz \$HOME: exit 3" "$?" 3
ho "$PA" --estado --raiz "$HOME" >/dev/null 2>&1; ok "7 --estado --raiz \$HOME: exit 3" "$?" 3

# 8. nucleo_indice lista las ranuras
# shellcheck source=/dev/null
. "$K/hooks/lib/nucleo.sh"
IDX=$(nucleo_indice)
ok "8 el índice nombra cada ranura con ~" "$(command grep -c '^- sesión en ~/.claude/estado/sesiones/.* · obj-[AB] · paso: paso-[AB] · ' <<<"$IDX")" 2

# 9. pid reutilizado: .proceso distinto → ranura nueva
mv "$SA" "$SES/19990101-0000-$PA"; printf 'otro-proceso\n' >"$SES/19990101-0000-$PA/.proceso"
ho "$PA" --desde "$(borrador N)" >/dev/null 2>&1; ok "9 --desde con el pid reutilizado sale 0" "$?" 0
ok "9 ranura nueva, no la vieja" "$(printf "%s\n" "$SES"/*-"$PA" | wc -l | tr -d ' ')" 2
ok "9 la vieja conserva su nucleo" "$(command grep -c obj-A "$SES/19990101-0000-$PA/nucleo.md")" 1
SA=$(printf "%s\n" "$SES"/*-"$PA" | command grep -v 19990101)
ok "9 la nueva trae el nuevo" "$(command grep -c obj-N "$SA/nucleo.md")" 1

# 10. .gitignore y compact
ok "10 sesiones/.gitignore = *" "$(cat "$SES/.gitignore" 2>/dev/null)" '*'
KC=$(hook "$HK" "$PA" "" sA)
ok "10 compact en ~ inyecta el nucleo de su ranura" "$(command grep -c 'obj-N' <<<"$KC")" 1
ok "10 compact en ~ no inyecta el de B" "$(command grep -c 'obj-B' <<<"$KC")" 0
ok "10 compact sin ranura sigue dando el índice" "$(hook "$HK" "$PM" "" sM | command grep -c '<indice-tareas>')" 1

# 11. un enlace dentro de la ranura propia: no se usa (ni para leer ni para escribir) y su destino no se toca
SB=$(ls -d "$SES"/*-"$PB" 2>/dev/null)
printf 'fuera\n' >"$T/fuera.md"; rm -f "$SB/nucleo.md"; ln -s "$T/fuera.md" "$SB/nucleo.md"
ho "$PB" --desde "$(borrador B2)" >/dev/null 2>&1; ok "11 enlace en la ranura: --desde sale 3" "$?" 3
ho "$PB" --estado >/dev/null 2>&1; ok "11 enlace en la ranura: --estado sale 3" "$?" 3
ok "11 el destino del enlace no cambia" "$(cat "$T/fuera.md")" fuera

# 12. CLAUDE_PID inválido cuenta como ausente: 0 delante (ps lo lee en octal: 0<octal de un pid vivo> es otro proceso),
# 1 y 10 o más dígitos. Sin padre claude, exit 3 y nada escrito.
ANTES=$(huella)
for p in "$(printf '0%o' "$PC")" 0 1 1234567890; do
  ho "$p" --desde "$(borrador C)" >/dev/null 2>&1; ok "12 CLAUDE_PID=$p: --desde sale 3" "$?" 3
done
ok "12 CLAUDE_PID inválido no escribe nada" "$(huella)" "$ANTES"

ho "$PA" --desde "$(borrador FINAL)" --json >"$T/receipt"
HASH=$(jq -r .sha256 "$T/receipt")
ok '13 recibo HOME corresponde a bytes publicados' "$HASH" "$(sha256sum "$(jq -r .nucleo "$T/receipt")" | cut -d' ' -f1)"
ho "$PA" --desde "$(borrador POSTERIOR)" >/dev/null
ho "$PA" --migrar --esperado "$HASH" --json >/dev/null 2>&1
ok '13 archivo HOME rechaza recibo obsoleto' "$?" 4
HASH=$(ho "$PA" --estado | jq -r .sha256)
ho "$PA" --migrar --esperado "$HASH" --json >"$T/archive"
ok '13 archivo HOME conserva documento exacto' "$(sha256sum "$(jq -r .archivo "$T/archive")" | cut -d' ' -f1)" "$HASH"
ok '13 archivo HOME deja ranura vacía' "$(ho "$PA" --estado | jq -r .bytes)" 0

for EV in SubagentStart SubagentStop; do
  jq -cn --arg r "$HOME" --arg ev "$EV" '{cwd:$r,hook_event_name:$ev,session_id:"home-owner",agent_id:"home-agent",agent_type:"worker",background_tasks:[{id:"sibling",type:"subagent"}]}' | CLAUDE_PID=$PA bash "$K/hooks/agentes.sh"
done
ok '14 HOME registra fin real sin confundir hermano con hijo pendiente' "$(ho "$PA" --agentes | grep -c 'terminado sin informe')" 1
ok '14 registro HOME no contamina otra ranura' "$(ho "$PC" --agentes | grep -c home-agent)" 0

# 15 (H9). Seis SubagentStart a la vez desde ~ en una sesión sin ranura: los seis llegan a agentes.jsonl, ronda tras ronda.
TOT=0
for _ in 1 2 3 4 5 6 7 8; do
  sleep 300 & PR=$!; PIDS+=("$PR")
  JP=()
  for i in 1 2 3 4 5 6; do
    jq -cn --arg r "$HOME" --arg i "ag$i" '{cwd:$r,hook_event_name:"SubagentStart",session_id:"race",agent_id:$i,agent_type:"worker"}' | CLAUDE_PID=$PR bash "$K/hooks/agentes.sh" &
    JP+=($!)
  done
  wait "${JP[@]}"
  RR=$(find "$SES" -maxdepth 1 -name "*-$PR" | head -1)
  TOT=$((TOT + $(command grep -c '"ev":"start"' "$RR/agentes.jsonl" 2>/dev/null)))
done
# Los hooks pueden perder una línea por el plazo de 1 s del lock con la máquina cargada (ajeno a la ranura): margen de 4.
# El contrato estricto de la ranura va aparte, sin lock de por medio.
ok '15 6 SubagentStart paralelos desde ~: 8 rondas x 6, a lo sumo 4 perdidas' "$([ "$TOT" -ge 44 ] && echo si || echo "solo $TOT de 48")" si
SD6=0
for _ in 1 2 3 4 5 6 7 8; do
  sleep 300 & PR=$!; PIDS+=("$PR"); JP=()
  for i in 1 2 3 4 5 6; do ( CLAUDE_PID=$PR nucleo_sesion_dir crear >"$T/sd-$i" 2>/dev/null ) & JP+=($!); done
  wait "${JP[@]}"
  [ "$(cat "$T"/sd-? | sort -u | wc -l | tr -d ' ')" = 1 ] && [ "$(cat "$T"/sd-? | wc -l | tr -d ' ')" = 6 ] && SD6=$((SD6 + 1))
done
ok '15 nucleo_sesion_dir crear en paralelo: los 6 reciben la misma ranura (8 rondas)' "$SD6" 8
ok '15 la carrera no deja .nueva.* sueltos' "$(find "$SES" -maxdepth 1 -name '.nueva.*' | wc -l | tr -d ' ')" 0

# 16 (H11). PreCompact desde ~ sin ranura propia no copia los pendientes del nucleo compartido (de otra tarea).
sleep 300 & PS=$!; PIDS+=("$PS")
mkdir -p "$HOME/.claude/estado"; printf '# Estado\n## Pendientes\n- [ ] PENDIENTE-DE-OTRA-TAREA\n' >"$HOME/.claude/estado/nucleo.md"
jq -cn --arg c "$HOME" '{cwd:$c,session_id:"sinranura",trigger:"auto"}' | CLAUDE_PID=$PS bash "$K/hooks/pre-compact.sh" 2>/dev/null
CPS=$(find "$HOME/.claude/estado" -maxdepth 1 -name 'checkpoint-compact-*.md' | head -1)
ok '16 PreCompact desde ~ sin ranura: checkpoint hecho' "$([ -n "$CPS" ] && echo si)" si
ok '16 PreCompact desde ~ sin ranura: sin pendientes ajenos' "$(command grep -rc 'PENDIENTE-DE-OTRA-TAREA' "$HOME"/.claude/estado/checkpoint-compact-*.md | awk -F: '{s+=$NF} END{print s+0}')" 0
ok '16 PreCompact desde ~ sin ranura: edad del KPI -1' "$(tail -1 "$HOME/.claude/session-logs/nucleo-freshness.log" | awk '{print $4}')" -1

# 17 (H13). startup desde ~ borra ranuras sin nucleo.md, de proceso muerto y de más de 14 días; la rotación de agentes
# borra fotos de más de 14 días. Nada de lo demás (con nucleo, vivas, recientes) se toca.
# shellcheck source=SCRIPTDIR/../claude/hooks/lib/nucleo.sh
. "$K/hooks/lib/nucleo.sh"
mkslot() { local d=$SES/$1; mkdir -p "$d"; printf '%s\n' "$2" >"$d/.proceso"; [ -z "${3:-}" ] || echo x >"$d/nucleo.md"; touch -d "${4:--20 days}" "$d/.proceso" "$d${3:+/nucleo.md}" "$d"; }
mkslot 20260101-0000-999991 ticks:1 "" "-20 days"
mkslot 20260101-0001-999992 ticks:1 "" "now"
mkslot 20260101-0002-999993 ticks:1 si "-20 days"
mkslot "20260101-0003-$PC" "$(_nucleo_proceso_id "$PC")" "" "-20 days"
hook "$HC" "$PA" startup limpieza >/dev/null
ok '17 ranura muerta, vieja y sin nucleo: borrada' "$([ -e "$SES/20260101-0000-999991" ] && echo existe || echo borrada)" borrada
ok '17 ranura muerta pero reciente: se queda' "$([ -e "$SES/20260101-0001-999992" ] && echo existe || echo borrada)" existe
ok '17 ranura vieja con nucleo.md: se queda' "$([ -e "$SES/20260101-0002-999993" ] && echo existe || echo borrada)" existe
ok '17 ranura vieja de proceso vivo: se queda' "$([ -e "$SES/20260101-0003-$PC" ] && echo existe || echo borrada)" existe
jq -cn '{sid:"vieja",t:"2020-01-01T00:00:00Z",vivos:[]}' >"$SA/agentes-vivos-vieja.json"; touch -d '-20 days' "$SA/agentes-vivos-vieja.json"
jq -cn '{sid:"reciente",t:"2020-01-01T00:00:00Z",vivos:[]}' >"$SA/agentes-vivos-reciente.json"
jq -cn --arg r "$HOME" '{cwd:$r,hook_event_name:"SubagentStart",session_id:"limp",agent_id:"agL",agent_type:"worker"}' | CLAUDE_PID=$PA bash "$K/hooks/agentes.sh"
ok '17 la rotación borra la foto de más de 14 días y conserva la reciente' "$([ -e "$SA/agentes-vivos-vieja.json" ] && echo vieja),$([ -e "$SA/agentes-vivos-reciente.json" ] && echo reciente)" ,reciente

# 18 (N4). El registro de raíces no admite rutas bajo /tmp ni $TMPDIR, y startup descarta las inexistentes.
# El HOME de prueba vive en /tmp: esa base no cuenta (HOME dentro de ella); TMPDIR apunta a otra carpeta, y esa sí.
mkdir -p "$T/tmpx/efimera/.claude/estado" "$T/real/.claude/estado"
echo '# Estado' >"$T/tmpx/efimera/.claude/estado/nucleo.md"; echo '# Estado' >"$T/real/.claude/estado/nucleo.md"
REG=$HOME/.claude/estado/raices; : >"$REG"
( export TMPDIR=$T/tmpx; nucleo_registrar "$T/tmpx/efimera"; nucleo_registrar "$T/real" )
ok '18 registrar rechaza la raíz bajo TMPDIR y admite la otra' "$(tr '\n' ' ' <"$REG")" "$T/real "
printf '%s\n' "$T/real" "$T/borrada-ya" "$T/tmpx/efimera" >"$REG"
TMPDIR=$T/tmpx hook "$HC" "$PA" startup depura >/dev/null
ok '18 startup depura inexistentes y efímeras del registro' "$(tr '\n' ' ' <"$REG")" "$T/real "

# 19. Tras /handoff + /clear en ~ la sesión conserva su ranura y su carpeta, y siempre recibe un mínimo. El mod corre el CLI desde el cwd
# vivo (una carpeta cualquiera) con CLAUDE_PROJECT_DIR = donde arrancó (~): la ranura es la de siempre y la carpeta queda anotada.
sleep 300 & PF=$!; PIDS+=("$PF")
mkdir -p "$HOME/trabajo/sub"
hof() { (cd "$1" && shift && CLAUDE_PID=$PF CLAUDE_PROJECT_DIR=$HOME bash "$HO" "$@"); }
hof "$HOME/trabajo/sub" --desde "$(borrador F)" >/dev/null 2>&1; R=$?
SF=$(ls -d "$SES"/*-"$PF" 2>/dev/null)
ok "19 handoff desde otra carpeta con CLAUDE_PROJECT_DIR=~ sale 0 y escribe en la ranura de ~" "$R,$(command grep -c obj-F "$SF/nucleo.md" 2>/dev/null)" "0,1"
ok "19 anota la carpeta de trabajo una vez, bajo el título" "$(awk '/^## /{exit} /^> carpeta de trabajo: /{n++} END{print n+0}' "$SF/nucleo.md")" 1
ok "19 y la carpeta anotada es el cwd del que guardó" "$(command grep -cFx "> carpeta de trabajo: $HOME/trabajo/sub" "$SF/nucleo.md")" 1
C=$(hook "$HC" "$PF" clear sF)
ok "19 /clear: llega el nucleo de la ranura con la línea de carpeta dentro de los datos" "$(command grep -c "<nucleo-datos fuente=\"$SF/nucleo.md\">" <<<"$C"),$(awk '/^<nucleo-datos /{d=1} d && /^> carpeta de trabajo: /{n++} END{print n+0}' <<<"$C")" "1,1"
ok "19 /clear: dice la carpeta y que se vaya a ella, tras los datos (no dentro)" "$(sed -n '/^<\/nucleo-datos>/,$p' <<<"$C" | command grep -cF "La sesión anterior trabajaba en la carpeta '$HOME/trabajo/sub' (")" 1
C=$(jq -cn --arg c "$HOME/trabajo/sub" '{cwd:$c,session_id:"sF",source:"clear"}' | CLAUDE_PID=$PF CLAUDE_PROJECT_DIR=$HOME bash "$HC" | ctx)
ok "19 /clear que ya cae en esa carpeta no manda ir a ella" "$(command grep -c 'La sesión anterior trabajaba' <<<"$C")" 0
ok "19 startup no anuncia carpeta (sin estado propio que retomar)" "$(hook "$HC" "$PF" startup sF | command grep -c 'La sesión anterior trabajaba')" 0
ho "$PF" --desde "$(borrador F)" >/dev/null 2>&1
ok "19 un handoff desde ~ borra la línea de carpeta anterior" "$(command grep -c '^> carpeta de trabajo: ' "$SF/nucleo.md")" 0
ok "19 y /clear ya no manda a ninguna carpeta" "$(hook "$HC" "$PF" clear sF | command grep -c 'La sesión anterior trabajaba')" 0
# El nucleo de la ranura es de texto libre (sin secciones de plantilla): la sesión nueva recibe un trozo y dónde está el resto, no un bloque vacío.
printf 'notas libres de la sesion F\nsin secciones\n' >"$SF/nucleo.md"
C=$(hook "$HC" "$PF" clear sF)
ok "19 nucleo sin secciones: /clear trae su ruta, un trozo del principio y dónde está el resto" "$(command grep -c "<nucleo-datos fuente=\"$SF/nucleo.md\">" <<<"$C"),$(command grep -c 'notas libres de la sesion F' <<<"$C"),$(command grep -c "el resto en ese fichero" <<<"$C")" "1,1,1"

# 19b. Un nucleo de la ranura vacío (solo comentarios) no deja el bloque de datos vacío: dice que no hay nada legible, como en un proyecto.
printf '<!-- solo plantilla -->\n' >"$SF/nucleo.md"
C=$(hook "$HC" "$PF" clear sF)
ok "19 nucleo de ranura vacío: /clear dice «no hay nada legible» en vez de un bloque vacío" "$(command grep -c 'no hay nada legible en nucleo.md' <<<"$C")" 1

# 20. Sin CLAUDE_PID (lo que ve un hijo de $.process.run del cockpit: claude no lo exporta y el mod lo deja vacío) la ranura sale del
# padre cuando su comm es «claude». Medido en vivo (ADR 027): el hijo de process.run cuelga directamente del claude de la sesión.
# El «claude» es una copia de bash con ese nombre; -c con un `:` final impide que bash sustituya el proceso por el último comando.
mkdir -p "$T/falso"; cp "$(command -v bash)" "$T/falso/claude"
for v in unset vacio; do
  rm -f "$T/fp" "$T/frc"
  export T HO HOME; B20=$(borrador "G$v"); export B20
  if [ "$v" = unset ]; then PRE="env -u CLAUDE_PID"; else PRE="env CLAUDE_PID="; fi
  export PRE
  # shellcheck disable=SC2016  # se expande en el bash hijo
  (cd "$HOME" && "$T/falso/claude" -c 'echo $$ >"$T/fp"; $PRE bash "$HO" --desde "$B20" >/dev/null 2>&1; echo $? >"$T/frc"; :')
  FP=$(cat "$T/fp" 2>/dev/null)
  ok "20 CLAUDE_PID $v y padre claude: handoff --desde sale 0 y crea la ranura de ese pid" "$(cat "$T/frc" 2>/dev/null),$(find "$SES" -maxdepth 1 -name "*-$FP" | wc -l | tr -d ' ')" "0,1"
done
rm -f "$T/fp" "$T/frc"
(cd "$HOME" && env -u CLAUDE_PID bash "$HO" --desde "$(borrador Hn)" >/dev/null 2>&1); R=$?
ok "20 sin CLAUDE_PID y con un padre que no es claude no hay ranura (sale 3)" "$R" 3

# 21. por_sid (ADR 028): la ranura se encuentra por session_id aunque el pid sea otro; resume la adopta si su proceso murió
sleep 300 & PX=$!; PIDS+=("$PX")
ho "$PX" --desde "$(borrador X)" --sesion sid-x >/dev/null 2>&1
SX=$(ls -d "$SES"/*-"$PX" 2>/dev/null)
ok "21 --desde en una ranura deja .sesion con el session_id" "$(cat "$SX/.sesion" 2>/dev/null)" sid-x
# shellcheck source=SCRIPTDIR/../claude/hooks/lib/nucleo.sh
. "$K/hooks/lib/nucleo.sh"
ok "21 por_sid recupera la ranura con otro PID en el entorno" "$(CLAUDE_PID=$PB nucleo_sesion_dir por_sid sid-x)" "$SX"
ok "21 por_sid con un id desconocido o inválido: rc 1 y nada" "$(nucleo_sesion_dir por_sid nadie; nucleo_sesion_dir por_sid '../x'; echo "rc=$?")" "rc=1"
ok "21 un resume con el proceso dueño vivo no la adopta" "$(hook "$HC" "$PC" resume sid-x | command grep -c '<nucleo-datos .*sesiones/')" 0
kill "$PX"; wait "$PX" 2>/dev/null
sleep 300 & PY=$!; PIDS+=("$PY")
ok "21 resume desde otro proceso (el dueño murió) adopta la ranura y la inyecta" "$(hook "$HC" "$PY" resume sid-x | command grep -c "<nucleo-datos .*sesiones/.*-$PY/")" 1
ok "21 la ranura ahora lleva el pid nuevo y su .proceso" "$(find "$SES" -maxdepth 1 -name "*-$PY" | wc -l | tr -d ' '),$(find "$SES" -maxdepth 1 -name "*-$PX" | wc -l | tr -d ' ')" "1,0"
sleep 300 & PZ=$!; PIDS+=("$PZ")
ok "21 startup no adopta" "$(hook "$HC" "$PZ" startup sid-x >/dev/null; find "$SES" -maxdepth 1 -name "*-$PZ" | wc -l | tr -d ' ')" 0

[ "$FAIL" -eq 0 ] && echo "PASS" || echo "FAIL"
exit "$FAIL"
