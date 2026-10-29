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
printf '## Paso actual\nx\n\n## Plan\n- [x] a\n- [x] b \xe2\x80\x94 `cmd`\n' >"$T/draft-m10"
ho --desde "$T/draft-m10" >"$T/out" 2>"$T/err"; RC=$?
ok 'M10: solo el cierre sin comando lleva la marca' "$RC,$(grep -c '(sin comando)' "$E/diario.md"),$(grep -c 'a (sin comando)' "$E/diario.md")" '0,1,1'
ok 'M10: el CLI avisa de los cierres sin comando' "$(grep -c '1 cierre(s) sin comando' "$T/err")" 1
rm -f "$E/.dueno" "$E/diario.md"
printf '## Paso actual\nx\n\n## Plan\n- [x] b \xe2\x80\x94 `cmd`\n' >"$T/draft-m10"
ho --desde "$T/draft-m10" >"$T/out" 2>"$T/err"; RC=$?
ok 'M10: con comando el diario no cambia y no hay aviso' "$RC,$(grep -c 'sin comando' "$E/diario.md"),$(grep -c 'sin comando' "$T/err")" '0,0,0'
exit "$FAIL"
