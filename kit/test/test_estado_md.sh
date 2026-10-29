#!/usr/bin/env bash
# test_estado_md.sh — un proyecto con ESTADO.md en la raíz y sin .claude/estado/nucleo.md usa ESTADO.md como su
# estado: inyección de SessionStart (clear y compact), avisos de edad y de airbag con el fichero activo, sin
# mandar crear nucleo.md ni escribirlo con handoff. Con los dos ficheros manda nucleo.md; con ninguno, como siempre.
# Sin red; HOME falso en un mktemp que se borra.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; H="$HERE/../claude/hooks"; HO="$HERE/../claude/bin/handoff"
T=$(mktemp -d -t scc-estmd.XXXXXX); trap 'rm -rf -- "$T"' EXIT
export HOME=$T/home GIT_CEILING_DIRECTORIES=$T LC_ALL=C.UTF-8 CC_NUCLEO_GATE=1; unset CLAUDE_PID CLAUDE_PROJECT_DIR NUCLEO_GATE CLAUDE_CODE_AUTO_COMPACT_WINDOW CLAUDE_CODE_SESSION_ATTENDED CLAUDE_CODE_ENTRYPOINT
mkdir -p "$HOME"
FAIL=0
ok() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (esperado '$3', sale '$2')"; FAIL=1; fi; }
ctx() { jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }
ev() { jq -cn --arg c "$1" --arg s "$2" --arg t "${3:-}" --arg src "${4:-}" '{cwd:$c,session_id:$s,transcript_path:$t,source:$src,trigger:"auto"}'; }
repo() { mkdir -p "$1"; git -C "$1" init -q; git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base; }
# Un ESTADO.md con la forma de una plantilla de proyecto: viñetas y secciones que no son las de nucleo.md.
estado() { printf '# Estado\n\n- Objetivo (una línea): OBJETIVO-VIVO\n- Paso actual: PASO-VIVO\n\n## Decisiones\n- DECISION-UNICA\n<!-- nota para quien escribe -->\n' >"$1"; }
# Ventana por defecto 200 000 → airbag de 167 000 tokens; 60 % = banda 50.
printf '%s\n' '{"type":"assistant","message":{"usage":{"input_tokens":1000,"cache_read_input_tokens":99200},"content":[]}}' >"$T/p60.jsonl"
nudge() { jq -cn --arg c "$1" --arg s "$2" --arg t "$T/p60.jsonl" '{session_id:$s,transcript_path:$t,cwd:$c,tool_name:"Bash"}' | bash "$H/nucleo-nudge.sh"; }

E=$T/solo-estado; repo "$E"; estado "$E/ESTADO.md"
B=$T/los-dos; repo "$B"; estado "$B/ESTADO.md"; mkdir -p "$B/.claude/estado"; printf '# Estado\n## Objetivo\nOBJETIVO-NUCLEO\n## Paso actual\nPASO-NUCLEO\n' >"$B/.claude/estado/nucleo.md"
N=$T/ninguno; repo "$N"

# --- solo ESTADO.md ---
OUT=$(ev "$E" s1 "" startup | bash "$H/session-start-clear.sh"); C=$(ctx <<<"$OUT")
ok "clear: inyecta ESTADO.md como datos" "$(command grep -c "^<nucleo-datos fuente=\"$E/ESTADO.md\">" <<<"$C")" 1
ok "clear: trae el contenido tal cual (secciones y viñetas propias)" "$(command grep -c 'OBJETIVO-VIVO\|PASO-VIVO\|DECISION-UNICA' <<<"$C")" 3
ok "clear: los comentarios <!-- --> no se inyectan" "$(command grep -c 'nota para quien escribe' <<<"$C")" 0
ok "clear: no nombra nucleo.md" "$(command grep -c 'nucleo\.md' <<<"$C")" 0
ok "clear: el protocolo nombra ESTADO.md" "$(command grep -c 'corrige ESTADO.md' <<<"$C")" 1
ok "clear: no crea .claude/estado" "$([ -e "$E/.claude/estado/nucleo.md" ] && echo si || echo no)" no
{ for i in $(seq 1 400); do echo "- linea de relleno numero $i para pasar el tope de inyeccion del estado"; done; } >>"$E/ESTADO.md"
OUT=$(ev "$E" s1 "" startup | bash "$H/session-start-clear.sh")
ok "clear: mismo tope (≤ 9 500) con un ESTADO.md de 28 KB" "$([ "$(printf '%s' "$OUT" | wc -m)" -le 9500 ] && echo si)" si
ok "clear: lo recortado se dice" "$(ctx <<<"$OUT" | command grep -c '\[recortado')" 1
estado "$E/ESTADO.md"

C=$(ev "$E" s1 | bash "$H/session-start-compact.sh" | ctx)
ok "compact: re-inyecta ESTADO.md" "$(command grep -c "^<nucleo-datos fuente=\"$E/ESTADO.md\">" <<<"$C"),$(command grep -c 'PASO-VIVO' <<<"$C")" 1,1
ok "compact: no nombra nucleo.md" "$(command grep -c 'nucleo\.md' <<<"$C")" 0
ok "compact: fresco, sin aviso de edad" "$(command grep -c 'sin actualizarse' <<<"$C")" 0
touch -d '-30 minutes' "$E/ESTADO.md"
C=$(ev "$E" s2 | bash "$H/session-start-compact.sh" | ctx)
ok "compact: aviso de edad con ESTADO.md rancio, nombrándolo" "$(command grep -c "Aviso del hook: $E/ESTADO.md lleva más de 10 min sin actualizarse" <<<"$C")" 1
ok "compact: el aviso no manda a handoff ni a nucleo.md" "$(command grep -c 'nucleo\.md\|handoff' <<<"$C")" 0

C=$(nudge "$E" s3 | ctx)
ok "nudge: nombra ESTADO.md y su ruta" "$(command grep -c "CONTEXTO 60 % del airbag. ESTADO.md lleva 30 min .* en $E/ESTADO.md\." <<<"$C")" 1
ok "nudge: no nombra nucleo.md ni manda a handoff" "$(command grep -c 'nucleo\.md\|handoff' <<<"$C")" 0

ev "$E" s4 "$T/p60.jsonl" | bash "$H/pre-compact.sh" 2>/dev/null
ok "pre-compact: la edad del KPI es la de ESTADO.md" "$(tail -1 "$HOME/.claude/session-logs/nucleo-freshness.log" | awk '{print ($4 >= 1790)}')" 1

printf '# Estado\n## Objetivo\nX\n' >"$T/b.md"
ok "handoff --desde: no crea un nucleo.md en paralelo y dice qué hacer" "$(bash "$HO" --desde "$T/b.md" --raiz "$E" 2>&1 >/dev/null | command grep -c 'ESTADO.md'),$([ -e "$E/.claude/estado/nucleo.md" ] && echo si || echo no)" 1,no
ok "handoff --iniciar: tampoco" "$(bash "$HO" --iniciar --raiz "$E" 2>&1 >/dev/null | command grep -c 'ESTADO.md'),$([ -e "$E/.claude/estado/nucleo.md" ] && echo si || echo no)" 1,no
ok "handoff --desde en modo ESTADO.md sale con rc 1" "$(bash "$HO" --desde "$T/b.md" --raiz "$E" >/dev/null 2>&1; echo $?)" 1

# ESTADO.md enlazado: el repo es de terceros, no decide qué fichero de fuera se inyecta.
L=$T/enlazado; repo "$L"; echo SECRETO-DE-FUERA >"$T/fuera.md"; ln -s "$T/fuera.md" "$L/ESTADO.md"
ok "ESTADO.md enlazado: no se inyecta" "$(ev "$L" s5 "" startup | bash "$H/session-start-clear.sh" | ctx | command grep -c 'SECRETO-DE-FUERA')" 0

# --- los dos: manda nucleo.md, como hoy ---
C=$(ev "$B" s6 "" startup | bash "$H/session-start-clear.sh" | ctx)
ok "clear con los dos: manda nucleo.md" "$(command grep -c "fuente=\"$B/.claude/estado/nucleo.md\"" <<<"$C"),$(command grep -c 'PASO-NUCLEO' <<<"$C"),$(command grep -c 'PASO-VIVO\|corrige ESTADO.md' <<<"$C")" 1,1,0
C=$(ev "$B" s6 | bash "$H/session-start-compact.sh" | ctx)
ok "compact con los dos: manda nucleo.md" "$(command grep -c 'PASO-NUCLEO' <<<"$C"),$(command grep -c 'PASO-VIVO' <<<"$C")" 1,0
touch -d '-30 minutes' "$B/.claude/estado/nucleo.md"
ok "nudge con los dos: habla de nucleo.md" "$(nudge "$B" s6 | ctx | command grep -c 'nucleo.md lleva 30 min')" 1
ok "handoff --iniciar con los dos: sigue su curso (nucleo.md ya existe)" "$(bash "$HO" --iniciar --raiz "$B" 2>&1 | command grep -c 'ya existe')" 1

# --- ninguno: comportamiento actual ---
C=$(ev "$N" s8 | bash "$H/session-start-compact.sh" | ctx)
ok "compact sin ninguno: pide nucleo.md con la plantilla" "$(command grep -c "No existe $N/.claude/estado/nucleo.md" <<<"$C")" 1
ok "clear sin ninguno: nada que inyectar" "$(ev "$N" s8 "" startup | bash "$H/session-start-clear.sh" | ctx | command grep -c 'nucleo-datos')" 0
ok "handoff --iniciar sin ninguno: crea nucleo.md" "$(bash "$HO" --iniciar --raiz "$N" >/dev/null 2>&1; [ -f "$N/.claude/estado/nucleo.md" ] && echo si)" si

exit $FAIL
