#!/usr/bin/env bash
# test_guardlog.sh — contrato del registro único de decisiones de los guards (kit/claude/hooks/lib/guardlog.sh y su gemelo de Sentinel):
# una línea JSONL por deny/ask de los cinco guards de Bash y de Sentinel, con la orden enmascarada y truncada, y con el
# registro fail-open (un registro roto no cambia el veredicto). Los comandos peligrosos solo se dan como texto a los guards.
# Los secretos de prueba se montan por concatenación para que scan-secrets.sh no vea uno en el fichero.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
H="$KIT/claude/hooks"; SEN="$KIT/sentinel/sentinel_preflight.py"
T=$(mktemp -d); trap 'rm -rf -- "$T"' EXIT
export HOME=$T/home; mkdir -p "$HOME/.claude" "$T/repo"
unset OPENRIG_OCCUPANT_GENERATION CLAUDE_CODE_SESSION_ATTENDED GUARDLOG_PATTERNS
cp "$KIT/claude/sentinel-allowlist.json" "$HOME/.claude/"
LOG=$T/g.jsonl; export CC_GUARD_LOG=$LOG CC_BLOCK_LOG=$T/blocked.log
( cd "$T/repo" && git init -q -b feat/x ) >/dev/null 2>&1
FAIL=0
ok() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (esperado '$3', sale '$2')"; FAIL=1; fi; }

ANT="sk-""ant-$(printf 'a%.0s' {1..30})"
GHP="gh""p_$(printf 'b%.0s' {1..36})"
AWS="AKI""A""Q3WJ5ZK7P2M9X4TB"
PEM="-----BE""GIN RSA PRIVATE KEY-----"
BT=abcdefgh""12345678

# payload CMD [MODO]: la entrada de un hook de Bash, con cwd y permission_mode como los manda Claude Code.
payload() { jq -nc --arg c "$1" --arg cwd "$T/repo" --arg m "${2:-}" '{tool_name:"Bash",cwd:$cwd,tool_input:{command:$c}} + (if $m == "" then {} else {permission_mode:$m} end)'; }
# g GUARD CMD [MODO]: corre el guard (rc en RC, salida en $T/out) sobre el comando.
g() { rm -f -- "$LOG"; payload "$2" "${3:-}" | (cd "$T/repo" && bash "$H/$1" >"$T/out" 2>/dev/null); RC=$?; }
n() { [ -f "$LOG" ] && wc -l <"$LOG" | tr -d ' ' || echo 0; }
f() { tail -n1 "$LOG" | jq -r "$1"; }

g destructive-guard.sh 'rm -rf ~' auto
ok "destructive: rc 2" "$RC" 2
ok "destructive: una línea" "$(n)" 1
ok "destructive: campos" "$(f '[.guard, .decision, .rule, .cwd, .mode, .unattended, .tool, .cmd] | join("|")')" "destructive-guard.sh|deny|rm on sensitive path|$T/repo|auto|false|Bash|rm -rf ~"
ok "destructive: ts UTC con Z" "$(f '.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")')" true

g destructive-guard.sh 'git reset --hard'
ok "destructive: reset --hard, modo vacío" "$(f '[.rule, .mode] | join("|")')" "git reset --hard|"

g block-dangerous-commands.sh 'git push --force origin feat/x'
ok "block-dangerous: deny (rc 0, JSON)" "$RC $(jq -r .hookSpecificOutput.permissionDecision "$T/out")" "0 deny"
ok "block-dangerous: línea deny" "$(f '[.guard, .decision, (.rule | length > 0)] | join("|")')" "block-dangerous-commands.sh|deny|true"

g block-dangerous-commands.sh 'git config alias.x "push origin main"'
ok "block-dangerous: ask" "$(jq -r .hookSpecificOutput.permissionDecision "$T/out") $(f .decision) $(n)" "ask ask 1"
rm -f -- "$LOG"; payload 'git config alias.x "push origin main"' | (cd "$T/repo" && CLAUDE_CODE_SESSION_ATTENDED=0 bash "$H/block-dangerous-commands.sh" >"$T/out" 2>/dev/null)
ok "desatendido: el ask sale deny y se marca" "$(f '[.decision, .unattended] | join("|")')" "deny|true"

g secret-guard.sh 'cat ~/.ssh/id_rsa'
ok "secret-guard: rc 2 y línea" "$RC $(f '[.guard, .decision, .rule] | join("|")')" "2 secret-guard.sh|deny|lectura de credenciales por Bash"

g branch-guard.sh 'git push origin main'
ok "branch-guard: rc 2 y línea" "$RC $(f '[.guard, .decision, .rule] | join("|")')" "2 branch-guard.sh|deny|push a rama protegida"

g bash-write-guard.sh "echo $AWS > f"
ok "bash-write-guard: deny y línea" "$(jq -r .hookSpecificOutput.permissionDecision "$T/out") $(f '[.guard, .decision] | join("|")')" "deny bash-write-guard.sh|deny"
ok "bash-write-guard: la clave no está en el registro" "$(grep -c "$AWS" "$LOG")" 0

# Una orden permitida no deja línea.
g destructive-guard.sh 'ls -la'
ok "permitida: sin línea" "$(n)" 0

# Orden grande: una sola línea por guard (el sondeo de block-dangerous no registra).
printf 'echo %0200000d' 0 | jq -Rs --arg cwd "$T/repo" '{tool_name:"Bash",cwd:$cwd,tool_input:{command:.}}' > "$T/big.json"
for gd in block-dangerous-commands destructive-guard secret-guard branch-guard; do
  rm -f -- "$LOG"; (cd "$T/repo" && bash "$H/$gd.sh" <"$T/big.json" >/dev/null 2>&1)
  ok "orden grande: $gd registra 1 ask" "$(n) $(f .decision)" "1 ask"
done

# Enmascarado: ningún secreto en claro, tampoco el que cae en el corte de los 300 caracteres ni el cuerpo de una clave privada.
PAD=$(printf 'x%.0s' {1..285})
C="rm -rf ~; echo $GHP $ANT; curl -H 'Authorization: Bea""rer $BT' https://usr:pw0rdXYZ@h/x; export TOKEN=hunter2hunter2; echo $PEM MIIEBODYSECRET"
g destructive-guard.sh "$C"
for s in "$GHP" "$ANT" abcdefgh12345678 pw0rdXYZ hunter2hunter2 MIIEBODYSECRET; do
  ok "enmascarado: '${s:0:12}…' ausente" "$(grep -c -- "$s" "$LOG")" 0
done
ok "enmascarado: hay marcas [SECRETO]" "$(f '.cmd | contains("[SECRETO]")')" true
g destructive-guard.sh "rm -rf ~; echo $PAD $ANT"
ok "corte: ni un prefijo de la clave (sk-ant-)" "$(grep -c 'sk-ant-' "$LOG")" 0
g destructive-guard.sh "rm -rf ~; echo $(printf 'y%.0s' {1..400})"
ok "truncado: 300 caracteres y puntos suspensivos" "$(f '.cmd | length')" 301
GUARDLOG_PATTERNS=/no/existe g destructive-guard.sh 'rm -rf ~'
ok "sin patrones legibles no se registra la orden" "$(f .cmd)" "[orden omitida: no se pudo enmascarar]"

# Fail-open: un registro roto (directorio, ruta imposible, lib ausente) no cambia ni el rc ni la salida del guard.
for gd in destructive-guard block-dangerous-commands branch-guard secret-guard; do
  c='rm -rf ~'; [ $gd = branch-guard ] && c='git push origin main'; [ $gd = secret-guard ] && c='cat ~/.ssh/id_rsa'
  g $gd.sh "$c"; rc0=$RC; out0=$(cat "$T/out")
  for bad in "$T" /proc/no/existe/x.jsonl; do
    payload "$c" | (cd "$T/repo" && CC_GUARD_LOG=$bad bash "$H/$gd.sh" >"$T/out" 2>/dev/null); rc1=$?
    ok "fail-open $gd ($bad): mismo rc y salida" "$rc1/$(cat "$T/out")" "$rc0/$out0"
  done
done
mkdir -p "$T/sin/lib"; cp "$H"/*.sh "$T/sin/"; cp "$H/lib/cmdnorm.sh" "$H/lib/secret-patterns" "$T/sin/lib/"
rm -f -- "$LOG"; payload 'rm -rf ~' | (cd "$T/repo" && bash "$T/sin/destructive-guard.sh" >/dev/null 2>&1); rc1=$?
ok "sin lib/guardlog.sh: sigue denegando (rc 2) y no registra" "$rc1 $(n)" "2 0"

# Sentinel: deny de Bash (con enmascarado), de otra herramienta (la ruta es el objetivo) y orden grande desatendida.
sen() { rm -f -- "$LOG"; printf '%s' "$1" | (cd "$T/repo" && "${@:2}" python3 -I -S "$SEN" >"$T/out" 2>/dev/null); RC=$?; }
sen "$(payload "echo $ANT; cat ~/.ssh/id_rsa" plan)" env
ok "sentinel: deny" "$(jq -r .hookSpecificOutput.permissionDecision "$T/out")" deny
ok "sentinel: campos" "$(f '[.guard, .decision, .cwd, .mode, .unattended, .tool] | join("|")')" "sentinel|deny|$T/repo|plan|false|Bash"
ok "sentinel: la clave está enmascarada" "$(grep -c 'sk-ant-' "$LOG")" 0
ok "sentinel: regla no vacía" "$(f '.rule | length > 0')" true
sen "$(jq -nc --arg cwd "$T/repo" '{tool_name:"Read",cwd:$cwd,tool_input:{file_path:"~/.ssh/id_rsa"}}')" env
ok "sentinel: Read, la ruta es el objetivo" "$(f '[.decision, .tool, .cmd] | join("|")')" "deny|Read|~/.ssh/id_rsa"
sen "$(payload 'ls')" env
ok "sentinel: lo permitido no deja línea" "$(n)" 0
for bad in "$T" /proc/no/existe/x.jsonl; do
  sen "$(payload 'cat ~/.ssh/id_rsa')" env CC_GUARD_LOG="$bad"
  ok "sentinel fail-open ($bad): sigue denegando" "$RC $(jq -r .hookSpecificOutput.permissionDecision "$T/out")" "0 deny"
done
sen "$(jq -c . "$T/big.json")" env CLAUDE_CODE_SESSION_ATTENDED=0
ok "sentinel: orden grande desatendida, deny marcado" "$(f '[.decision, .unattended] | join("|")') $(n)" "deny|true 1"

exit $FAIL
