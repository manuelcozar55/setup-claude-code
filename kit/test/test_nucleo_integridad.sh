#!/usr/bin/env bash
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=$HERE/../claude/bin/handoff
HOOK=$HERE/../claude/hooks
T=$(mktemp -d)
trap 'find "$T" -depth -delete' EXIT
export HOME=$T/home; unset CLAUDE_PROJECT_DIR
mkdir -p "$HOME" "$T/repo/.claude/estado"
git -C "$T/repo" init -q
R=$T/repo; E=$R/.claude/estado
# shellcheck source=SCRIPTDIR/../claude/hooks/lib/nucleo.sh
. "$HOOK/lib/nucleo.sh"
FAIL=0
ok() { if [ "$2" = "$3" ]; then echo "ok $1"; else echo "FAIL $1: $2 != $3"; FAIL=1; fi; }
ho() { bash "$BIN" --raiz "$R" "$@"; }
printf '## Paso actual\noriginal\n' >"$E/nucleo.md"
printf '## Paso actual\nnuevo\n' >"$T/draft"
printf 'sesion=owner\ndesde=%s\n' "$(date +%s)" >"$E/.dueno"
ho --desde "$T/draft" --sesion other >"$T/out" 2>"$T/err"; RC=$?
ok 'dueño ajeno rechaza antes de escribir' "$RC,$(cat "$E/nucleo.md")" $'5,## Paso actual\noriginal'
CLAUDE_CODE_SESSION_ID=owner ho --desde "$T/draft" >"$T/out" 2>"$T/err"; RC=$?
ok 'B-02: --desde sin --sesion usa CLAUDE_CODE_SESSION_ID' "$RC,$(grep -c nuevo "$E/nucleo.md")" '0,1'
printf '## Paso actual\noriginal\n' >"$E/nucleo.md"
printf 'sesion=owner\ndesde=%s\n' "$(date +%s)" >"$E/.dueno"
ho --liberar wrong >/dev/null 2>&1; ok 'liberar exige ID esperado' "$?" 5
ho --liberar owner >"$T/out" 2>"$T/err"; ok 'recuperación explícita libera' "$?,$([ -e "$E/.dueno" ] && echo ocupado || echo libre)" '0,libre'
exec {FD}>>"$E/.handoff.lock"; flock -x "$FD"
ho --desde "$T/draft" >"$T/out" 2>"$T/err"; ok 'escritor ocupado devuelve rc4' "$?" 4
flock -u "$FD"; exec {FD}>&-
printf '## Pendientes\nSEGUNDO-ESCRITOR\n' >"$T/second"
(export HANDOFF_TEST_READY=$T/first-ready
 # shellcheck disable=SC2329  # Invocada por el proceso handoff mediante export -f.
 sleep() { : >"$HANDOFF_TEST_READY"; command sleep "$@"; }
 export -f sleep
 NUCLEO_FUSION_PAUSA=1 ho --desde "$T/draft" >"$T/first.out" 2>"$T/first.err"; echo $? >"$T/first.rc") &
PID=$!
LOCKED=0
for _ in {1..100}; do
  if [ -f "$T/first-ready" ]; then LOCKED=1; break; fi
  sleep 0.01
 done
ho --desde "$T/second" >"$T/second.out" 2>"$T/second.err"; RC=$?
wait "$PID"
ok 'dos escritores reales: primero termina y segundo espera reintento' "$LOCKED,$(cat "$T/first.rc"),$RC" '1,0,4'
ho --desde "$T/second" >/dev/null 2>&1
ok 'reintento fusiona sin perder primero' "$(command grep -c 'nuevo\|SEGUNDO-ESCRITOR' "$E/nucleo.md")" 2
F=$(nucleo_estado_fallback "$R"); mkdir -p "$F"
printf '## Paso actual\nFALLBACK-VIVO\n' >"$F/nucleo.md"
jq -cn --arg r "$R" '{cwd:$r,session_id:"fallback",source:"compact"}' | bash "$HOOK/session-start-compact.sh" >"$T/compact"
ok 'compact lee núcleo fallback' "$(jq -r '.hookSpecificOutput.additionalContext' "$T/compact" | command grep -c '^FALLBACK-VIVO$')" 1
ok 'estado publica ruta real fallback' "$(ho --estado | jq -r .nucleo)" "$F/nucleo.md"
ho --desde "$T/draft" >/dev/null 2>&1
ok 'escritor conserva ruta fallback' "$(command grep -c nuevo "$F/nucleo.md")" 1
jq -cn --arg r "$R" '{cwd:$r,session_id:"new",source:"clear"}' | bash "$HOOK/session-start-clear.sh" >"$T/hook"
ok 'lector clear usa fallback' "$(jq -r '.hookSpecificOutput.additionalContext' "$T/hook" | command grep -c '^nuevo$')" 1
mv "$F/nucleo.md" "$T/outside"; ln -s "$T/outside" "$F/nucleo.md"
ho --estado >/dev/null 2>&1; ok 'fallback enlazado rechazado' "$?" 3
RO=$T/readonly; mkdir -p "$RO/.claude"; git -C "$RO" init -q
chmod a-w "$RO/.claude" "$RO"
bash "$BIN" --raiz "$RO" --desde "$T/draft" >"$T/ro.out" 2>"$T/ro.err"; RC=$?
chmod u+w "$RO/.claude" "$RO"
RF=$(nucleo_estado_fallback "$RO")
ok 'solo lectura: escritura rc0 y aviso stderr con destino real' "$RC,$(command grep -c "$RF" "$T/ro.err")" '0,1'
ok 'fallback tiene ignores de estado e informes' "$(cat "$RF/.gitignore" "$RF/informes/.gitignore" "$RF/checkpoints/.gitignore" | tr '\n' ',')" '*,*,*,'
ok 'tras recuperar permisos se mantiene destino real' "$(bash "$BIN" --raiz "$RO" --estado | jq -r .nucleo)" "$RF/nucleo.md"
bash "$BIN" --raiz "$RO" --desde "$T/draft" --commit >"$T/commit.out" 2>"$T/commit.err"; RC=$?
ok 'commit fallback rechaza versionar otra ruta sin perder escritura' "$RC,$(git -C "$RO" diff --cached --name-only | wc -l),$(command grep -c nuevo "$RF/nucleo.md")" '1,0,1'
M=$T/migrate; mkdir -p "$M/.claude/estado"; git -C "$M" init -q
printf '## Objetivo\nOBJETIVO-LOCAL\n' >"$M/.claude/estado/nucleo.md"
MF=$(nucleo_estado_fallback "$M"); mkdir -p "$MF/checkpoints"
ok 'fallback solo checkpoint no oculta núcleo local' "$(bash "$BIN" --raiz "$M" --estado | jq -r .nucleo)" "$M/.claude/estado/nucleo.md"
printf 'sesion=owner\ndesde=%s\n' "$(date +%s)" >"$M/.claude/estado/.dueno"
chmod a-w "$M/.claude/estado" "$M/.claude" "$M"
bash "$BIN" --raiz "$M" --desde "$T/draft" --sesion other >"$T/m.out" 2>"$T/m.err"; RC=$?
ok 'primer fallback respeta dueño del núcleo local' "$RC" 5
bash "$BIN" --raiz "$M" --desde "$T/draft" --sesion owner >"$T/m.out" 2>"$T/m.err"; RC=$?
chmod u+w "$M/.claude/estado" "$M/.claude" "$M"
ok 'primer fallback fusiona objetivo local antes de publicar' "$RC,$(command grep -c OBJETIVO-LOCAL "$MF/nucleo.md")" '0,1'
A=$T/archive; mkdir -p "$A"; git -C "$A" init -q
bash "$BIN" --raiz "$A" --desde "$T/draft" --json >"$T/receipt" 2>"$T/receipt.err"; RC=$?
AN=$A/.claude/estado/nucleo.md
ok 'guardado JSON entrega recibo SHA256 exacto' "$RC,$(jq -r '.sha256 | test("^[a-f0-9]{64}$")' "$T/receipt" 2>/dev/null)" '0,true'
# El test también prepara el núcleo con el CLI antiguo para aislar la falta de control de archivo.
[ -f "$AN" ] || bash "$BIN" --raiz "$A" --desde "$T/draft" >/dev/null 2>&1
AH=$(sha256sum "$AN" | cut -d' ' -f1)
ok 'recibo identifica bytes y ruta del documento publicado' "$(jq -r '[.sha256,.nucleo]|join(",")' "$T/receipt")" "$AH,$AN"
ok 'estado publica SHA256 del documento actual' "$(bash "$BIN" --raiz "$A" --estado | jq -r .sha256)" "$AH"
printf '## Paso actual\nESCRITURA-POSTERIOR\n' >"$T/later"
bash "$BIN" --raiz "$A" --desde "$T/later" >/dev/null 2>&1
bash "$BIN" --migrar "$A" --sesion own --esperado "$AH" --json >"$T/archive.out" 2>"$T/archive.err"; RC=$?
ok 'escritura posterior al guardado rechaza archivo sin daño' "$RC,$(grep -c ESCRITURA-POSTERIOR "$AN"),$([ -d "$A/.claude/estado/archivo" ] && echo creado || echo ausente)" '4,1,ausente'
AH=$(sha256sum "$AN" | cut -d' ' -f1)
printf 'sesion=rival\ndesde=%s\n' "$(date +%s)" >"$A/.claude/estado/.dueno"
bash "$BIN" --migrar "$A" --sesion own --esperado "$AH" >/dev/null 2>&1; RC=$?
ok 'archivo rechaza dueño ajeno aunque coincida hash' "$RC,$([ -f "$AN" ] && echo intacto)" '5,intacto'
bash "$BIN" --raiz "$A" --liberar rival >/dev/null
exec {FD}>>"$A/.claude/estado/.handoff.lock"; flock "$FD"
bash "$BIN" --migrar "$A" --esperado "$AH" >/dev/null 2>&1; RC=$?
flock -u "$FD"; exec {FD}>&-
ok 'archivo ocupado devuelve4 y conserva núcleo' "$RC,$([ -f "$AN" ] && echo intacto)" '4,intacto'
bash "$BIN" --migrar "$A" --esperado "$AH" --json >"$T/archive.out" 2>"$T/archive.err"; RC=$?
AR=$(jq -r .archivo "$T/archive.out" 2>/dev/null)
ok 'archivo de documento exacto devuelve destino y conserva bytes' "$RC,$([ ! -e "$AN" ] && [ -f "$AR" ] && sha256sum "$AR" | cut -d' ' -f1)" "0,$AH"
bash "$BIN" --migrar "$A" --esperado "$AH" >/dev/null 2>&1; ok 'documento ya ausente con hash esperado devuelve4' "$?" 4
printf 'informe-conservado\n' >"$RF/informes/keep"
printf 'snapshot-conservado\n' >"$RF/checkpoints/keep"
FH=$(sha256sum "$RF/nucleo.md" | cut -d' ' -f1)
bash "$BIN" --migrar "$RO" --esperado "$FH" --json >"$T/fallback-archive.out" 2>"$T/fallback-archive.err"; RC=$?
FA=$(jq -r .archivo "$T/fallback-archive.out" 2>/dev/null)
ok 'archivo transaccional usa fallback y conserva informes/checkpoints' "$RC,$([ ! -e "$RF/nucleo.md" ] && [ -f "$FA" ] && [ -f "$RF/informes/keep" ] && [ -f "$RF/checkpoints/keep" ] && echo conservado)" '0,conservado'
MH=$(sha256sum "$MF/nucleo.md" | cut -d' ' -f1)
bash "$BIN" --migrar "$M" --esperado "$MH" --json >"$T/migrate-archive.out" 2>"$T/migrate-archive.err"; RC=$?
MS=$(bash "$BIN" --raiz "$M" --estado)
ok 'archivar fallback no resucita núcleo local antiguo' "$RC,$(jq -r '[.nucleo,.bytes]|join(",")' <<<"$MS")" "0,$MF/nucleo.md,0"
ok 'archivo fallback conserva documento local antiguo sin usarlo' "$(grep -c OBJETIVO-LOCAL "$M/.claude/estado/nucleo.md")" 1
bash "$BIN" --migrar "$M" --esperado '' >/dev/null 2>&1
ok 'hash esperado vacío es uso inválido y no desactiva guarda' "$?" 64
HINT_ROOT=$T/hints; mkdir -p "$HINT_ROOT/.claude/estado"; git -C "$HINT_ROOT" init -q
HINT_NUC=$HINT_ROOT/.claude/estado/nucleo.md
HINT_HOME=$T/hint-install; mkdir -p "$HINT_HOME/bin"
ln -s "$BIN" "$HINT_HOME/bin/handoff"
printf '%s\n' '{"type":"assistant","message":{"model":"claude-opus-4-6","usage":{"input_tokens":120000}}}' >"$T/hint-transcript"
for HINT_HOOK in nucleo-nudge session-start-compact stop-context-gauge; do
  SID=hint-${HINT_HOOK}
  printf '## Paso actual\nANTES-HINT\n' >"$HINT_NUC"; touch -d '-30 minutes' "$HINT_NUC"
  printf 'sesion=%s\ndesde=%s\n' "$SID" "$(date +%s)" >"$HINT_ROOT/.claude/estado/.dueno"
  OUT=$(jq -cn --arg r "$HINT_ROOT" --arg s "$SID" --arg t "$T/hint-transcript" '{cwd:$r,session_id:$s,transcript_path:$t}' | CLAUDE_HOME=$HINT_HOME PATH=/usr/bin:/bin bash "$HOOK/$HINT_HOOK.sh" | jq -r '.hookSpecificOutput.additionalContext // .systemMessage // ""')
  # shellcheck disable=SC2016  # Backticks literales delimitan el comando emitido.
  COMMAND=$(sed -n 's/.*`\([^`]*--desde <borrador>[^`]*\)`.*/\1/p' <<<"$OUT")
  read -r -a ARGS <<<"${COMMAND//<borrador>/$T/draft}"
  (cd "$HINT_ROOT" && "${ARGS[@]}") >"$T/hint.out" 2>"$T/hint.err"; RC=$?
  ok "$HINT_HOOK comando emitido funciona como dueño" "$RC,$(grep -c nuevo "$HINT_NUC")" '0,1'
  printf 'sesion=rival\ndesde=%s\n' "$(date +%s)" >"$HINT_ROOT/.claude/estado/.dueno"
  BEFORE=$(sha256sum "$HINT_NUC" | cut -d' ' -f1)
  (cd "$HINT_ROOT" && "${ARGS[@]}") >"$T/hint.out" 2>"$T/hint.err"; RC=$?
  ok "$HINT_HOOK comando no suplanta dueño ajeno" "$RC,$(sha256sum "$HINT_NUC" | cut -d' ' -f1)" "5,$BEFORE"
  for BAD_SID in '' 'invalid;sid'; do
    OUT=$(jq -cn --arg r "$HINT_ROOT" --arg s "$BAD_SID" --arg t "$T/hint-transcript" '{cwd:$r,session_id:$s,transcript_path:$t}' | CLAUDE_HOME=$HINT_HOME PATH=/usr/bin:/bin bash "$HOOK/$HINT_HOOK.sh" | jq -r '.hookSpecificOutput.additionalContext // .systemMessage // ""')
    ok "$HINT_HOOK sin SID válido no emite comando ejecutable" "$(grep -c -- '--desde <borrador>' <<<"$OUT")" 0
  done
 done
LIVE=$T/live-owner; mkdir -p "$LIVE/.claude/estado"; git -C "$LIVE" init -q
CLAUDE_PID=$$ nucleo_dueno_reclamar "$LIVE" live
NUCLEO_DUENO_TTL=0 CLAUDE_PID=$$ nucleo_dueno_reclamar "$LIVE" rival
ok 'proceso vivo protege dueño incluso con TTL vencido' "$?" 5
jq -cn --arg r "$LIVE" '{cwd:$r,session_id:"rival",source:"clear"}' | bash "$HOOK/session-start-clear.sh" >"$T/rival-clear"
ok 'clear ajeno no roba propietario vivo' "$(nucleo_dueno "$LIVE" | cut -d' ' -f1)" live
# M10: un [x] sin comando entre comillas invertidas se archiva con la marca y el CLI lo avisa.
R=$T/m10; E=$R/.claude/estado; mkdir -p "$E"; git -C "$R" init -q
# shellcheck disable=SC2016  # Backticks literales.
printf '## Paso actual\nx\n\n## Plan\n- [x] a\n- [x] b \xe2\x80\x94 `cmd`\n' >"$T/draft-m10"
ho --desde "$T/draft-m10" >"$T/out" 2>"$T/err"; RC=$?
ok 'M10: solo el cierre sin comando lleva la marca' "$RC,$(grep -c '(sin comando)' "$E/diario.md"),$(grep -c 'a (sin comando)' "$E/diario.md")" '0,1,1'
ok 'M10: el CLI avisa de los cierres sin comando' "$(grep -c '1 cierre(s) sin comando' "$T/err")" 1
rm -f "$E/.dueno" "$E/diario.md"
# shellcheck disable=SC2016  # Backticks literales.
printf '## Paso actual\nx\n\n## Plan\n- [x] b \xe2\x80\x94 `cmd`\n' >"$T/draft-m10"
ho --desde "$T/draft-m10" >"$T/out" 2>"$T/err"; RC=$?
ok 'M10: con comando el diario no cambia y no hay aviso' "$RC,$(grep -c 'sin comando' "$E/diario.md"),$(grep -c 'sin comando' "$T/err")" '0,0,0'
# B5a/H1: el comando del nudge desde una ranura lleva destino explícito y funciona con el cwd en un proyecto ajeno.
export CLAUDE_HOME=$HOME/.claude
SLOT=$(CLAUDE_PID=$$ nucleo_sesion_dir crear); X=$T/ajeno; XE=$X/.claude/estado; mkdir -p "$XE"; git -C "$X" init -q
printf '## Paso actual\nPROYECTO\n' >"$XE/nucleo.md"; printf '## Paso actual\nDE-LA-RANURA\n' >"$T/draft-r"
printf 'sesion=otra\ndesde=%s\n' "$(date +%s)" >"$XE/.dueno"
(cd "$X" && CLAUDE_PID=$$ bash "$BIN" --desde "$T/draft-r" --sesion mia) >"$T/out" 2>"$T/err"; RC=$?
ok 'B5a: dueño ajeno (rc 5) nombra la ranura y el comando' "$RC,$(grep -cF -- "tu ranura es $SLOT" "$T/err"),$(grep -cF -- "--ranura $SLOT" "$T/err")" '5,1,1'
(cd "$X" && CLAUDE_PID=$$ bash "$BIN" --desde "$T/draft-r" --sesion mia --ranura "$SLOT") >"$T/out" 2>"$T/err"; RC=$?
ok 'B5a: --ranura escribe la ranura con cwd en proyecto ajeno' "$RC,$(grep -c DE-LA-RANURA "$SLOT/nucleo.md"),$(grep -c PROYECTO "$XE/nucleo.md")" '0,1,1'
# Dentro de sesiones/ y sin enlaces, pero de otra sesión: sin --ranura nadie podía escribir la ranura ajena; con él tampoco.
# Va antes del enlace de abajo: con un enlace en sesiones/, nucleo_estado_seguro la da por insegura y no hay ranura propia.
mkdir -p "$CLAUDE_HOME/estado/sesiones/otra"
(cd "$X" && CLAUDE_PID=$$ bash "$BIN" --desde "$T/draft-r" --sesion mia --ranura "$CLAUDE_HOME/estado/sesiones/otra") >"$T/out" 2>"$T/err"; RC=$?
ok 'B5a: --ranura de otra sesión se rechaza (rc 5) y nombra la propia' "$RC,$(find "$CLAUDE_HOME/estado/sesiones/otra" -type f | wc -l),$(grep -cF -- "la tuya es $SLOT" "$T/err")" '5,0,1'
mkdir -p "$T/fuera" "$CLAUDE_HOME/estado/sesiones/x"; ln -s "$T/fuera" "$CLAUDE_HOME/estado/sesiones/enlace"
for MALA in "$T/fuera" "$CLAUDE_HOME/estado/sesiones/../../.." "$CLAUDE_HOME/estado/sesiones/x/../../.." "$CLAUDE_HOME/estado/sesiones/enlace" "$CLAUDE_HOME/estado/sesiones"; do
  (cd "$X" && bash "$BIN" --desde "$T/draft-r" --sesion mia --ranura "$MALA") >"$T/out" 2>"$T/err"; RC=$?
  ok "B5a: --ranura fuera de sesiones/ se rechaza ($MALA)" "$([ "$RC" -ne 0 ] && echo rc),$(find "$T/fuera" -type f | wc -l),$(grep -c DE-LA-RANURA "$XE/nucleo.md")" 'rc,0,0'
done

# --- ESTADO.md como estado del proyecto (sin nucleo.md): inyección, avisos y handoff; con nucleo.md manda nucleo.md.
# Subshell con su HOME y su repo falsos: no comparte entorno con los casos de arriba. Sin red.
(
HERE="$(cd "$(dirname "$0")" && pwd)"; H="$HERE/../claude/hooks"; HO="$HERE/../claude/bin/handoff"
T=$(mktemp -d -t scc-estmd.XXXXXX); trap 'rm -rf -- "$T"' EXIT
export HOME=$T/home GIT_CEILING_DIRECTORIES=$T LC_ALL=C.UTF-8 CC_NUCLEO_GATE=1; unset CLAUDE_HOME CLAUDE_PID CLAUDE_PROJECT_DIR NUCLEO_GATE CLAUDE_CODE_AUTO_COMPACT_WINDOW CLAUDE_CODE_SESSION_ATTENDED CLAUDE_CODE_ENTRYPOINT
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

# handoff en modo ESTADO.md: fusiona en ESTADO.md (rc 0), sin crear nucleo.md. Borrador en forma nucleo: lo que tiene
# equivalente sustituye a su viñeta o sección; lo que no (Plan) se añade como sección propia, nunca se pierde.
# shellcheck disable=SC2016  # los backticks son markdown del borrador, no una expansión
printf '## Objetivo\nOBJ-NUEVO\n## Paso actual\nPASO-NUEVO\ndetalle del paso\n## Siguiente acción\nSIG-NUEVA\n## Decisiones\n- 2026-10-29: DEC-NUEVA\n## Pendientes\n- PEND-NUEVO\n## Comandos de verificación\n- `make test` → rc=0\n## Plan\n- [ ] PLAN-UNO\n' >"$T/b.md"
estado "$E/ESTADO.md"
OUT=$(bash "$HO" --desde "$T/b.md" --raiz "$E" --json 2>"$T/err"); RC=$?
ok "handoff --desde en modo ESTADO.md: rc 0, sin stderr, sin nucleo.md" "$RC,$(wc -c <"$T/err" | tr -d ' '),$([ -e "$E/.claude/estado/nucleo.md" ] && echo si || echo no)" 0,0,no
ok "handoff --desde: el recibo apunta a ESTADO.md y trae sha256" "$(jq -r '.nucleo' <<<"$OUT"),$(jq -r '.sha256 | length' <<<"$OUT")" "$E/ESTADO.md,64"
ok "handoff --desde: objetivo, paso y siguiente acción sustituyen a sus viñetas" "$(command grep -c '^- Objetivo (una línea): OBJ-NUEVO$' "$E/ESTADO.md"),$(command grep -c '^- Paso actual: PASO-NUEVO$' "$E/ESTADO.md"),$(command grep -c '^- Siguiente acción: SIG-NUEVA$' "$E/ESTADO.md"),$(command grep -c 'OBJETIVO-VIVO\|PASO-VIVO' "$E/ESTADO.md")" 1,1,1,0
ok "handoff --desde: el detalle del paso queda sangrado bajo su viñeta" "$(command grep -c '^  detalle del paso$' "$E/ESTADO.md")" 1
ok "handoff --desde: decisiones, pendientes y verificación sustituyen o crean su sección" "$(command grep -c '^## Decisiones$' "$E/ESTADO.md"),$(command grep -c 'DEC-NUEVA' "$E/ESTADO.md"),$(command grep -c '^## Pendientes y riesgos$' "$E/ESTADO.md"),$(command grep -c 'PEND-NUEVO' "$E/ESTADO.md"),$(command grep -c '^## Cómo se comprueba$' "$E/ESTADO.md"),$(command grep -c 'make test. → rc=0' "$E/ESTADO.md"),$(command grep -c 'DECISION-UNICA' "$E/ESTADO.md")" 1,1,1,1,1,1,0
ok "handoff --desde: lo sin equivalente (Plan) se añade, no se pierde" "$(command grep -c '^## Plan$' "$E/ESTADO.md"),$(command grep -c 'PLAN-UNO' "$E/ESTADO.md")" 1,1
HASH1=$(sha256sum <"$E/ESTADO.md")
bash "$HO" --desde "$T/b.md" --raiz "$E" >/dev/null 2>&1
ok "handoff --desde repetido: mismo ESTADO.md, sin duplicar secciones" "$([ "$(sha256sum <"$E/ESTADO.md")" = "$HASH1" ] && echo igual || echo distinto),$(command grep -c '^## ' "$E/ESTADO.md")" igual,4
ok "handoff --desde: la copia previa va a .claude/estado (fuera del árbol versionado) y un repetido sin cambios no la duplica" "$(find "$E/.claude/estado" -name 'ESTADO.prev-*.md' | wc -l | tr -d ' ')" 1
ok "handoff --estado: nombra ESTADO.md y su modo" "$(bash "$HO" --estado --raiz "$E" | jq -r '(.estado | endswith("/ESTADO.md")), .modo' | paste -sd,)" true,estado-md
# El comando que dictan stop-context-gauge.sh y session-start-compact.sh: --desde con --sesion y sin --ranura, desde un cwd dentro del repo.
estado "$E/ESTADO.md"
ok "handoff --desde --sesion sin --ranura (el que dictan los hooks) funciona en modo ESTADO.md" "$(cd "$E" && bash "$HO" --desde "$T/b.md" --sesion s-h5 >/dev/null 2>&1; echo $?),$(command grep -c 'PASO-NUEVO' "$E/ESTADO.md"),$([ -e "$E/.claude/estado/nucleo.md" ] && echo si || echo no)" 0,1,no
printf '# Estado\n## Cosa rara\nX\n' >"$T/mala.md"
HASH1=$(sha256sum <"$E/ESTADO.md")
ok "handoff --desde en modo ESTADO.md: un borrador inválido sale con 2 sin tocar nada" "$(bash "$HO" --desde "$T/mala.md" --raiz "$E" >/dev/null 2>&1; echo $?),$([ "$(sha256sum <"$E/ESTADO.md")" = "$HASH1" ] && echo igual)" 2,igual
{ printf '## Paso actual\n'; for i in $(seq 1 30); do echo "- linea $i"; done; printf '## Ficheros tocados\n'; for i in $(seq 1 400); do echo "- ruta/larga/numero/$i con relleno para pasar el tope del estado"; done; } >"$T/g.md"
bash "$HO" --desde "$T/g.md" --raiz "$E" >/dev/null 2>&1
ok "handoff --desde: respeta el tope: lo que el borrador añadió y no cabe va a diario.md" "$([ "$(wc -c <"$E/ESTADO.md")" -le 5700 ] && echo si),$(command grep -c 'omitido por tope: Ficheros tocados' "$E/.claude/estado/diario.md")" si,1
ok "handoff --iniciar en modo ESTADO.md: rc 0 y no crea nucleo.md" "$(bash "$HO" --iniciar --raiz "$E" >/dev/null 2>&1; echo $?),$([ -e "$E/.claude/estado/nucleo.md" ] && echo si || echo no)" 0,no
ok "handoff --desde --solo en modo ESTADO.md: no aplica (64)" "$(bash "$HO" --desde "$T/b.md" --raiz "$E" --solo >/dev/null 2>&1; echo $?)" 64

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


# Las tres situaciones, con la lib, handoff --estado y el aviso de los hooks: solo nucleo.md, solo ESTADO.md y los dos (manda nucleo.md).
SN=$T/solo-nucleo; repo "$SN"; mkdir -p "$SN/.claude/estado"; printf '# Estado\n## Paso actual\nPASO-NUCLEO\n' >"$SN/.claude/estado/nucleo.md"
modo() { if nucleo_modo_estado_md "$1"; then echo estado-md; else echo nucleo; fi; }
ok "tres situaciones: solo nucleo.md / solo ESTADO.md / los dos / ninguno (lib)" "$(modo "$SN"),$(modo "$E"),$(modo "$B"),$(modo "$N")" nucleo,estado-md,nucleo,nucleo
ok "tres situaciones: handoff --estado, «modo» solo con ESTADO.md como estado" "$(for d in "$SN" "$E" "$B"; do bash "$HO" --estado --raiz "$d" | jq -r '.modo // "nucleo"'; done | paste -sd,)" nucleo,estado-md,nucleo
touch -d '-30 minutes' "$SN/.claude/estado/nucleo.md" "$E/ESTADO.md" "$B/.claude/estado/nucleo.md" "$B/ESTADO.md"
ok "tres situaciones: el aviso del nudge nombra el fichero que manda (con los dos, ya cubierto arriba)" "$(for d in "$SN" "$E"; do nudge "$d" "s9-${d##*/}" | ctx | command grep -o '[A-Za-z]*\.md lleva 30 min' | head -1; done | paste -sd,)" "nucleo.md lleva 30 min,ESTADO.md lleva 30 min"
# Revisión de la fusión en ESTADO.md (H1-H6 + temporal): ESTADO.md es de la persona; solo se reescribe lo que el borrador aporta.
nuevo() { local d=$T/$1; repo "$d"; estado "$d/ESTADO.md"; printf '%s' "$d"; }
relleno() { seq 1 "$1" | sed 's/$/ linea de relleno para pasar el tope de bytes del estado/'; }
# H1: una sección ajena al borrador nunca se omite por tope; si pasa del tope se escribe igual, rc 0, y se avisa.
X=$(nuevo h1); { echo; echo '## Notas del cliente'; relleno 120; } >>"$X/ESTADO.md"
printf '## Paso actual\nx\n' >"$T/d1.md"
bash "$HO" --desde "$T/d1.md" --raiz "$X" >"$T/o1" 2>"$T/e1"; RC=$?
ok "H1: sección ajena al borrador no se omite por tope (rc 0, avisa, no va a diario)" "$RC,$(command grep -c '^## Notas del cliente' "$X/ESTADO.md"),$(command grep -c 'supera el tope' "$T/e1"),$(command grep -c 'Notas del cliente' "$X/.claude/estado/diario.md" 2>/dev/null)" 0,1,1,0
# H2: sin cambios no hay copia ni rotación.
X=$(nuevo h2); printf '## Paso actual\nigual\n' >"$T/d2.md"
bash "$HO" --desde "$T/d2.md" --raiz "$X" >/dev/null 2>&1; bash "$HO" --desde "$T/d2.md" --raiz "$X" >/dev/null 2>&1; bash "$HO" --desde "$T/d2.md" --raiz "$X" >/dev/null 2>&1
ok "H2: el mismo borrador repetido no copia ni rota ESTADO.prev-*" "$(find "$X/.claude/estado" -name 'ESTADO.prev-*.md' | wc -l | tr -d ' '),$(command grep -c 'PASO-VIVO' "$(find "$X/.claude/estado" -name 'ESTADO.prev-*.md' | head -1)")" 1,1
# H3: varias secciones con la misma clave: solo se sustituye la primera.
X=$(nuevo h3); printf '\n## PENDIENTES\nPRIMERO\n\n## Pendientes y riesgos\nSEGUNDO\n\n## Invariantes del dominio\nINV-A\n\n## Invariantes\nINV-B\n' >>"$X/ESTADO.md"
printf '## Pendientes\nPEND-NUEVO\n## Invariantes\nINV-NUEVO\n' >"$T/d3.md"
bash "$HO" --desde "$T/d3.md" --raiz "$X" >/dev/null 2>&1
ok "H3: se sustituye solo la primera sección de cada clave (la familia invariantes* incluida)" "$(command grep -c 'PEND-NUEVO' "$X/ESTADO.md"),$(command grep -c 'SEGUNDO' "$X/ESTADO.md"),$(command grep -c 'PRIMERO' "$X/ESTADO.md"),$(command grep -c 'INV-NUEVO' "$X/ESTADO.md"),$(command grep -c 'INV-A' "$X/ESTADO.md"),$(command grep -c 'INV-B' "$X/ESTADO.md")" 1,1,0,1,0,1
# H4: CRLF de entrada, CRLF de salida.
X=$(nuevo h4); sed -i 's/$/\r/' "$X/ESTADO.md"; printf '## Paso actual\nCRLF-NUEVO\n## Decisiones\n- d\n' >"$T/d4.md"
bash "$HO" --desde "$T/d4.md" --raiz "$X" >/dev/null 2>&1
ok "H4: un ESTADO.md con CRLF sale con CRLF en todas sus líneas" "$(command grep -c 'CRLF-NUEVO' "$X/ESTADO.md"),$(command grep -vc $'\r$' "$X/ESTADO.md")" 1,0
# H5: línea en blanco antes de la siguiente sección; un borrador solo con comentarios no cambia nada.
X=$(nuevo h5); printf '\n## Pendientes y riesgos\nviejo\n\n## Cómo se comprueba\nviejo\n' >>"$X/ESTADO.md"
printf '## Pendientes\nPEND-H5\n' >"$T/d5.md"; bash "$HO" --desde "$T/d5.md" --raiz "$X" >/dev/null 2>&1
ok "H5: la sección sustituida conserva la línea en blanco antes de la siguiente" "$(command grep -B1 '^## Cómo se comprueba' "$X/ESTADO.md" | head -1 | command grep -c '^$')" 1
H5=$(sha256sum <"$X/ESTADO.md"); printf '## Pendientes\n<!-- nada -->\n## Paso actual\n<!-- nada -->\n' >"$T/d5c.md"
bash "$HO" --desde "$T/d5c.md" --raiz "$X" >/dev/null 2>&1
ok "H5: un borrador solo con comentarios no cambia ESTADO.md" "$([ "$(sha256sum <"$X/ESTADO.md")" = "$H5" ] && echo igual)" igual
# H6: la rotación borra la copia más vieja por mtime, no por nombre.
X=$(nuevo h6); mkdir -p "$X/.claude/estado"
for n in 1 2 3; do f=$X/.claude/estado/ESTADO.prev-2099123${n}T000000Z.md; echo "viejo-$n" >"$f"; touch -d "-$((n + 1)) days" "$f"; done
printf '## Paso actual\nH6\n' >"$T/d6.md"; bash "$HO" --desde "$T/d6.md" --raiz "$X" >/dev/null 2>&1
ok "H6: tras rotar sobreviven 3 copias y la nueva (la de mtime más reciente) no se borra" "$(find "$X/.claude/estado" -name 'ESTADO.prev-*.md' | wc -l | tr -d ' '),$(command grep -lc 'PASO-VIVO' "$X"/.claude/estado/ESTADO.prev-*.md | wc -l | tr -d ' ')" 3,1
# Temporal: si el proceso muere entre mktemp y mv no queda un .ESTADO.* en el árbol.
X=$(nuevo tmp); mkdir -p "$T/stub"
# shellcheck disable=SC2016  # el stub lleva su propio $PPID
printf '#!/usr/bin/env bash\nkill -TERM "$PPID"; sleep 2\n' >"$T/stub/mv"; chmod +x "$T/stub/mv"
printf '## Paso actual\nTMP\n' >"$T/dt.md"; { PATH=$T/stub:$PATH bash "$HO" --desde "$T/dt.md" --raiz "$X"; } >/dev/null 2>&1
ok "temporal: un handoff muerto antes del mv no deja .ESTADO.* en el árbol" "$(find "$X" -maxdepth 1 -name '.ESTADO.*' | wc -l | tr -d ' ')" 0
exit $FAIL
) || FAIL=1
exit "$FAIL"
