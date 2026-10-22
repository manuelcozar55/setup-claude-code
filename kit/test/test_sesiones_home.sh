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

[ "$FAIL" -eq 0 ] && echo "PASS" || echo "FAIL"
exit "$FAIL"
