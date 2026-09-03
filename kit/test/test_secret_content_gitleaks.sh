#!/bin/bash
# test_secret_content_gitleaks.sh — regresion de la Capa 2 (pre-commit +
# gitleaks). A diferencia de test_guards.sh (Capa 1, por nombre de fichero),
# esta suite prueba que el CONTENIDO de lo que se va a comitear se escanea de
# verdad: credenciales con nombre de fichero inocente, ficheros ignorados
# anadidos con -f, senuelos "EXAMPLE" antes de una credencial real, etc.
#
# Las credenciales de este fichero son sinteticas (generadas aqui con un seed
# fijo o compuestas en tiempo de ejecucion), nunca reales.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
HOOK_SRC="$KIT/claude/hooks/git/pre-commit"
CONFIG_SRC="$KIT/claude/.gitleaks.toml"
pass=0; fail=0

newrepo() {
  local d="$1"
  rm -rf "$d"; mkdir -p "$d/.git/hooks"
  (cd "$d" && git init -q && git config user.email t@example.com && git config user.name t)
  cp "$HOOK_SRC" "$d/.git/hooks/pre-commit"
  chmod +x "$d/.git/hooks/pre-commit"
  # La config NO se copia a la raiz del repo: eso era el fixture que tapaba el bug.
  # install.sh deja .gitleaks.toml en $CLAUDE_HOME, no en el repo protegido, asi que
  # sembrarlo aqui simulaba una instalacion que no existe y ocultaba que el hook
  # bloqueaba todos los commits de cualquier repo ajeno. Se replica la instalacion
  # de verdad: la config vive en $CLAUDE_HOME/.gitleaks.toml (ver FAKE_CLAUDE_HOME).
}

expect_commit() { # $1 dir, $2 desc, $3 BLOCK|ALLOW [, $4 CLAUDE_HOME a usar]
  local d="$1" desc="$2" want="$3" home="${4:-$FAKE_CLAUDE_HOME}"
  (cd "$d" && CLAUDE_HOME="$home" git commit -q -m test >/dev/null 2>&1)
  local st=$?
  if { [ "$want" = BLOCK ] && [ $st -ne 0 ]; } || { [ "$want" = ALLOW ] && [ $st -eq 0 ]; }; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); echo "FAIL: $desc (esperado $want, exit=$st)"
  fi
}

if ! command -v gitleaks >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/gitleaks" ]; then
  echo "SKIP: gitleaks no instalado (ver docs/02-install.md); esta suite requiere el binario."
  exit 0
fi

BASE=$(mktemp -d)

# Instalacion simulada: la config donde de verdad la deja install.sh.
FAKE_CLAUDE_HOME="$BASE/claude-home"
mkdir -p "$FAKE_CLAUDE_HOME"
cp "$CONFIG_SRC" "$FAKE_CLAUDE_HOME/.gitleaks.toml"
# Y una instalacion SIN config, para el caso que el fixture anterior tapaba.
SIN_CONFIG="$BASE/claude-home-vacio"
mkdir -p "$SIN_CONFIG"

# 1/3) credencial real con nombre de fichero inocente, incl. via comando
#      multilinea (la posicion de "git add" en el comando es irrelevante:
#      el hook ve el indice en el momento de git commit, no el texto del
#      comando que lo genero).
D="$BASE/innocent-name"; newrepo "$D"
ANT_KEY=$(python3 -c "
import random
random.seed(1)
c='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-'
print('sk-ant-api03-'+''.join(random.choice(c) for _ in range(93))+'AA')
")
printf 'app_key: %s\n' "$ANT_KEY" > "$D/config.yaml"
(cd "$D" && git add config.yaml)
expect_commit "$D" "credencial real (Anthropic) con nombre de fichero inocente" BLOCK

# 4) fichero ignorado por .gitignore, anadido con -f
D="$BASE/ignored-force"; newrepo "$D"
printf '*\n' > "$D/.gitignore"
AKIA1="AKIA$(printf '%s' J7Q2M4P6R3S5T2W4)"
printf 'KEY=%s\n' "$AKIA1" > "$D/ignored-creds.txt"
(cd "$D" && git add -f ignored-creds.txt)
expect_commit "$D" "credencial real en fichero ignorado, anadido con -f" BLOCK

# 5) credencial anidada en directorio ignorado, add del fichero
D="$BASE/nested-ignored-file"; newrepo "$D"
printf '*\n' > "$D/.gitignore"
mkdir -p "$D/sub/deep"
AKIA2="AKIA$(printf '%s' M3N7P2Q6R4S3T7V2)"
printf 'KEY=%s\n' "$AKIA2" > "$D/sub/deep/plainkey.txt"
(cd "$D" && git add -f sub/deep/plainkey.txt)
expect_commit "$D" "credencial anidada en directorio ignorado, add del fichero" BLOCK

# 6) credencial anidada en directorio ignorado, add del directorio completo
D="$BASE/nested-ignored-dir"; newrepo "$D"
printf '*\n' > "$D/.gitignore"
mkdir -p "$D/sub/deep"
AKIA3="AKIA$(printf '%s' Q4W7E3R5T2Y6U4I3)"
printf 'KEY=%s\n' "$AKIA3" > "$D/sub/deep/plainkey.txt"
(cd "$D" && git add -f sub/)
expect_commit "$D" "credencial anidada en directorio ignorado, add del directorio" BLOCK

# 7) senuelo "fake"/EXAMPLE antes de una credencial real en el mismo fichero
D="$BASE/decoy-then-real"; newrepo "$D"
AKIA4="AKIA$(printf '%s' J7Q2M4P6R3S5T2W4)"
{ printf 'FAKE_EXAMPLE=AKIA00000000EXAMPLE\n'; printf 'REAL=%s\n' "$AKIA4"; } > "$D/decoy.txt"
(cd "$D" && git add decoy.txt)
expect_commit "$D" "senuelo EXAMPLE antes de credencial real, mismo fichero" BLOCK

# 8) "AWS_LATEST=<credencial real>" no debe confundirse con un marcador fake
D="$BASE/latest-not-fake-marker"; newrepo "$D"
AKIA5="AKIA$(printf '%s' Z3X4C7V2B5N4M2K7)"
printf 'AWS_LATEST=%s\n' "$AKIA5" > "$D/latest.txt"
(cd "$D" && git add latest.txt)
expect_commit "$D" "'AWS_LATEST=' con credencial real no se confunde con marcador fake" BLOCK

# 2) cd + git add + git commit: el name-guard de PreToolUse puede no ver esto
#    (o verlo, tras el fix del ancla), pero el commit debe abortar en cualquier
#    caso porque esta capa no lee el texto del comando.
D="$BASE/cd-then-commit"; newrepo "$D"
FNAME="server$(printf '_key')$(printf '.pem')"
DASHES="-----"
BEGIN="${DASHES}BEGIN$(printf ' PRIVATE KEY')${DASHES}"
END="${DASHES}END$(printf ' PRIVATE KEY')${DASHES}"
printf '%s\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDx1\n%s\n' "$BEGIN" "$END" > "$D/$FNAME"
(cd "$D" && git add "$FNAME")
expect_commit "$D" "cd + git add + git commit con clave PEM real" BLOCK

# --- regla propia (claude/.gitleaks.toml) para contraseñas tipo diccionario en
# ficheros de config. Las contraseñas de abajo son generadas para este test,
# no credenciales reales.

# 9) contraseña tipo diccionario en .yaml -- el caso que motivo la regla
D="$BASE/dict-password-yaml"; newrepo "$D"
printf 'DB_PASSWORD=hunter2superSecret\n' > "$D/config.yaml"
(cd "$D" && git add config.yaml)
expect_commit "$D" "contraseña tipo diccionario (hunter2superSecret) en .yaml" BLOCK

# 10) passphrase de varias palabras pegadas, sin numeros ni simbolos
D="$BASE/passphrase-yaml"; newrepo "$D"
printf 'DB_PASSWORD=correcthorsebatterystaple\n' > "$D/config.yaml"
(cd "$D" && git add config.yaml)
expect_commit "$D" "passphrase de diccionario (correcthorsebatterystaple) en .yaml" BLOCK

# 11) password con mayusculas/numeros/simbolo pero aun asi de baja entropia real
D="$BASE/symbolic-password-yaml"; newrepo "$D"
printf 'DB_PASSWORD=P@ssw0rd2024\n' > "$D/config.yaml"
(cd "$D" && git add config.yaml)
expect_commit "$D" "contraseña con simbolos (P@ssw0rd2024) en .yaml" BLOCK

# 12/13/14) allowlist: valores obviamente ficticios en el mismo tipo de fichero
D="$BASE/allowlist-changeme"; newrepo "$D"
printf 'PASSWORD=changeme\n' > "$D/config.yaml"
(cd "$D" && git add config.yaml)
expect_commit "$D" "PASSWORD=changeme en .yaml permitido (allowlist)" ALLOW

D="$BASE/allowlist-var"; newrepo "$D"
# shellcheck disable=SC2016 # ${DB_PASS} literal a proposito: el fixture prueba
# una referencia a variable sin expandir (patron comun de config), no un valor real.
printf 'PASSWORD=${DB_PASS}\n' > "$D/config.yaml"
(cd "$D" && git add config.yaml)
expect_commit "$D" "PASSWORD=\${VAR} en .yaml permitido (allowlist)" ALLOW

D="$BASE/allowlist-placeholder"; newrepo "$D"
printf 'PASSWORD=<your-password>\n' > "$D/config.yaml"
(cd "$D" && git add config.yaml)
expect_commit "$D" "PASSWORD=<your-password> en .yaml permitido (allowlist)" ALLOW

# 15/16) misma asignacion fuera del ambito de rutas (.md / .js): permitida.
# Es la razon de acotar por path -- sin esto, la regla da falsos positivos
# sobre prosa/codigo real que solo menciona PASSWORD=/TOKEN= como ejemplo.
D="$BASE/out-of-scope-md"; newrepo "$D"
printf 'DB_PASSWORD=hunter2superSecret\n' > "$D/notes.md"
(cd "$D" && git add notes.md)
expect_commit "$D" "misma contraseña en .md permitida (fuera de ambito de path)" ALLOW

D="$BASE/out-of-scope-js"; newrepo "$D"
printf 'const pw = "DB_PASSWORD=hunter2superSecret"\n' > "$D/app.js"
(cd "$D" && git add app.js)
expect_commit "$D" "misma contraseña en .js permitida (fuera de ambito de path)" ALLOW

# 17) .json esta deliberadamente fuera del path de esta regla (ver
# kit/claude/.gitleaks.toml): en un proyecto Node real, package-lock.json,
# tsconfig.json, etc. usan a menudo una clave "token" con un valor interno
# inocuo de mas de 8 caracteres -- exactamente el patron que dispararia la
# regla si .json siguiera en el path. Se documenta con un fixture realista
# en vez de solo mencionarlo en un comentario.
D="$BASE/out-of-scope-json"; newrepo "$D"
printf '{\n  "name": "demo",\n  "config": {\n    "token": "internal-build-marker"\n  }\n}\n' > "$D/package.json"
(cd "$D" && git add package.json)
expect_commit "$D" "token interno en package.json permitido (.json fuera de ambito de path)" ALLOW

# 18) control: una clave de alta entropia en .yaml sigue bloqueando -- la
# regla propia no debilito las reglas por defecto de gitleaks (useDefault = true)
D="$BASE/high-entropy-still-blocks"; newrepo "$D"
HIGHENT="aB3xK9mQ7zP2w$(printf '%s' R5tY8uJ)"
printf 'API_KEY=%s\n' "$HIGHENT" > "$D/config.yaml"
(cd "$D" && git add config.yaml)
expect_commit "$D" "clave de alta entropia en .yaml sigue bloqueando (reglas por defecto intactas)" BLOCK

# --- 19/20/21) resolucion de la config: el defecto que el fixture tapaba -------
# El hook pasaba a ciegas -c "$REPO_ROOT/.gitleaks.toml". Como install.sh deja ese
# fichero en $CLAUDE_HOME y no en el repo protegido, cualquier compañero que activase
# la Capa 2 siguiendo docs/05-security.md se quedaba sin poder comitear NADA, con un
# mensaje que decia "posibles secretos" cuando lo que faltaba era un fichero. Estos
# tres casos son la linea que separa "no encuentra la config" de "no hay secretos".

# 19) instalacion normal (config solo en CLAUDE_HOME): un fichero inocente pasa
D="$BASE/config-en-claude-home"; newrepo "$D"
printf 'hola mundo\n' > "$D/README.md"
(cd "$D" && git add README.md)
expect_commit "$D" "config en CLAUDE_HOME: fichero inocente comitea" ALLOW

# 20) sin config en ninguna parte: se degrada a las reglas por defecto, NO se bloquea
D="$BASE/sin-config"; newrepo "$D"
printf 'hola mundo\n' > "$D/README.md"
(cd "$D" && git add README.md)
expect_commit "$D" "sin .gitleaks.toml en ningun sitio: NO bloquea un commit limpio" ALLOW "$SIN_CONFIG"

# 21) ...y degradarse no es rendirse: la credencial real sigue bloqueando
D="$BASE/sin-config-con-secreto"; newrepo "$D"
AKIA6="AKIA$(printf '%s' L2K5J8H3G6F9D4S7)"
printf 'KEY=%s\n' "$AKIA6" > "$D/creds.txt"
(cd "$D" && git add creds.txt)
expect_commit "$D" "sin config, credencial real sigue bloqueando (reglas por defecto)" BLOCK "$SIN_CONFIG"

# --- 22/23) clave de Anthropic FUERA de un fichero de config ------------------
# El caso 1 de arriba pasaba por una razon que no era la que parecia: lo que lo
# bloqueaba era la regla por defecto anthropic-api-key, que exige la forma
# exacta sk-ant-<tipo>-<93 chars>AA. Medido con gitleaks 8.30.1: la misma clave
# alargada a 105 chars se COMITEA en .yaml, .txt y .md, y en .yaml solo la
# salvaba un prefijo de asignacion tipo ANTHROPIC_API_KEY= (eso lo caza
# dict-password-config-file, no una regla de Anthropic). O sea: fuera de las
# extensiones de config no quedaba nada, justo lo contrario de lo que decia el
# comentario de claude/.gitleaks.toml.
#
# Falsificabilidad (probada por mutacion, no por confianza): si se borra la
# regla anthropic-api-key-prefix de claude/.gitleaks.toml, el caso 22 pasa a
# ALLOW y esta suite falla. El 23 es su control: el prefijo citado en prosa,
# sin clave detras, no debe bloquear.
#
# La clave se compone en ejecucion a proposito: un literal de 20+ caracteres
# tras "sk-ant-" en este fichero haria que la propia regla bloquease el commit
# que anade el test.
D="$BASE/anthropic-plain-txt"; newrepo "$D"
ANT_KEY_LONG=$(python3 -c "
import random
random.seed(7)
c='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-'
print('sk-ant-'+'api03-'+''.join(random.choice(c) for _ in range(105)))
")
printf '%s\n' "$ANT_KEY_LONG" > "$D/key.txt"
(cd "$D" && git add key.txt)
expect_commit "$D" "clave de Anthropic de 105 chars en .txt (fuera de path de config)" BLOCK

D="$BASE/anthropic-prefix-prose"; newrepo "$D"
printf 'las claves de Anthropic empiezan por %s\n' 'sk-ant-api03-' > "$D/notes.md"
(cd "$D" && git add notes.md)
expect_commit "$D" "prefijo sk-ant- citado en prosa, sin clave detras, no bloquea" ALLOW

rm -rf "$BASE"
echo "PASS=$pass FAIL=$fail"
[ $fail -eq 0 ]
