#!/bin/bash
# block-dangerous-commands.sh — PreToolUse Bash security blocklist
# Source: randomdreft/claude-code-security-hook (public domain), extended
# Protocol: JSON deny/ask output + exit 0, or silent exit 0 to allow

set -uo pipefail

deny() {
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

# Fail-closed. Sin jq no se puede leer el comando, y permitir a ciegas apagaba la Capa 1
# entera sin un solo mensaje. El compromiso es real -- denegar sin jq bloquea al usuario --
# y por eso install.sh trae una puerta de dependencia: jq se exige al instalar, asi que
# llegar aqui sin el es una instalacion incompleta, no el caso normal. El JSON va literal
# porque deny() necesita el jq que falta.
if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED (fail-closed): falta jq en el PATH, asi que este guard no puede evaluar el comando. Instala jq (apt install jq) y reintenta."}}'
  exit 0
fi
COMMAND=$(jq -r '.tool_input.command // empty' 2>/dev/null) \
  || deny "BLOCKED (fail-closed): el payload de PreToolUse no es JSON parseable, asi que este guard no puede evaluar el comando."
[[ -z "$COMMAND" ]] && exit 0

ALLOWLIST_FILE="${HOME:-/nonexistent}/.claude/sentinel-allowlist.json"

command_allowlisted() {
  [[ -f "$ALLOWLIST_FILE" ]] || return 1
  jq -e --arg cmd "$COMMAND" '(.commands // []) | index($cmd) != null' "$ALLOWLIST_FILE" >/dev/null 2>&1
}

command_allowlisted && exit 0

# El texto que se escanea sale de la normalizacion comun (lib/cmdnorm.sh): la continuacion
# barra+salto de linea unida (partia el pipe-a-shell en dos lineas que grep miraba por separado) y los
# comentarios quitados solo fuera de comillas. La allowlist de arriba compara el comando EXACTO, por
# eso va antes y sobre el literal. Si la lib falta o awk falla se deniega: seguir con el literal
# reabriria justo estos huecos.
# shellcheck source=SCRIPTDIR/lib/cmdnorm.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/cmdnorm.sh" 2>/dev/null \
  || deny "BLOCKED (fail-closed): falta lib/cmdnorm.sh junto al guard; reinstala el kit."
cmdn_oversize "$COMMAND" && exit 0
cmdn_parse "$COMMAND" \
  || deny "BLOCKED (fail-closed): awk no pudo normalizar el comando, asi que este guard no puede evaluarlo."
COMMAND=$CMDN_TEXT

ask() {
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

# Las reglas de `curl`/`wget` tras un pipe a interprete viven en variables porque la excepcion
# estrecha de K1 (fetch_safe_reader, mas abajo) necesita reconocerlas por identidad para saltarlas
# cuando la descarga alimenta solo a un lector de datos. Una sola fuente: la tabla y la excepcion ven
# el mismo patron. RCE_TAIL es lo que sigue al pipe: agrupadores `( {`, prefijos (sudo, env...),
# envoltorios con sus opciones (`time`, `nice -n 5`, `timeout 9`, `stdbuf -o0`, `busybox`), ruta
# opcional e interprete (sh, ash, dash, ksh93, fish, node/nodejs, lua, php...).
RCE_INTERP='((a|ba|z|da|k|mk)?sh|ksh[0-9]+|fish|python[0-9.]*|perl|ruby|node(js)?|php|lua[0-9.]*|tclsh|pwsh|Rscript|deno|bun)'
RCE_TAIL='\|&?\s*([({]\s*)*(\w+=\S*\s+)*((\S*/)?(sudo|env|exec|command|xargs|nohup)\b[^|]*\s)?((\S*/)?(time|nice|timeout|stdbuf|setsid|ionice|busybox|doas|unbuffer|chrt|taskset)\s+(-\S+\s+|[0-9.]+[smhd]?\s+|[A-Z]{3,7}\s+|\w+=\S*\s+)*)*(\S*/)?'$RCE_INTERP'\b'
RCE_CURL='\bcurl\b.*'$RCE_TAIL
RCE_WGET='\bwget\b.*'$RCE_TAIL
# Un socket o un canal TLS crudo por tuberia a un shell es la misma ejecucion remota que la descarga.
RCE_NET='\b(nc|ncat|netcat|socat|telnet|openssl\s+s_client)\b[^|]*'$RCE_TAIL
RCE_MSG_CURL="BLOCKED: curl piped to shell (RCE); descarga a fichero (-o), revisalo y ejecutalo aparte; para JSON, jq o python -c que solo lea e imprima (json, sys, print)"
RCE_MSG_WGET="BLOCKED: wget piped to shell (RCE); descarga a fichero (-o), revisalo y ejecutalo aparte; para JSON, jq o python -c que solo lea e imprima (json, sys, print)"

# ── K1: excepcion estrecha sobre el comportamiento de main ──────────────────────
# La UNICA relajacion: una descarga (`curl`/`wget`) por tuberia hacia un lector que solo
# CONSUME los bytes como datos -- un Python con su programa en `-c`, `python -m json.tool`, o
# `jq` -- se permite. Nada ejecuta lo descargado. Cada condicion falla CERRADO (bloquea): si la
# forma no es exactamente una de esas, el bloqueo de main se mantiene. Misma logica, con las
# mismas palabras, que `fetch_safe_reader` en kit/sentinel/sentinel_preflight.py.

# Parte el comando en sentencias de primer nivel (en ; \n && || & ( ), respetando comillas),
# separadas por \036. El pipe `|` NO parte: se queda dentro de la sentencia.
# shellcheck disable=SC2016  # el programa awk va literal: nada se expande en bash.
FETCH_SPLIT_AWK='
function flush() { out = out cur SEP; cur = "" }
BEGIN { RS = "\001"; SEP = "\036" }
{ s = s $0 }
END {
  n = length(s); i = 1; q = ""
  while (i <= n) {
    c = substr(s, i, 1)
    if (q != "") {
      cur = cur c
      if (c == "\\" && q == "\042" && i < n) { cur = cur substr(s, i + 1, 1); i += 2; continue }
      if (c == q) q = ""
      i++; continue
    }
    if (c == "\047" || c == "\042") { q = c; cur = cur c; i++; continue }
    if (c == "\\" && i < n) { cur = cur c substr(s, i + 1, 1); i += 2; continue }
    if (c == ";" || c == "\n" || c == "(" || c == ")") { flush(); i++; continue }
    if (c == "&") {
      nx = substr(s, i + 1, 1)
      if (nx == ">") { cur = cur c; i++; continue }
      if (nx == "&") i++
      flush(); i++; continue
    }
    if (c == "|") {
      if (substr(s, i + 1, 1) == "|") { flush(); i += 2; continue }
      cur = cur c; i++; continue
    }
    cur = cur c; i++
  }
  out = out cur
  printf "%s", out
}
'

# Nombres que el programa de `-c` puede usar fuera de sus cadenas: leer JSON de stdin, filtrarlo
# e imprimirlo. Lista BLANCA a proposito: Python llega a ejecutar codigo por demasiadas puertas
# (exec, pdb, code, timeit, `sys._getframe`, `operator.attrgetter`...) para cerrarlas una a una.
# Valen tambien cualquier nombre de una letra y los enteros. Ninguno convierte texto en codigo,
# asi que lo que hay dentro de las cadenas no cuenta. Misma lista que `_PYC_NAMES` en Sentinel.
PYC_NAMES='import from as for in if else elif and or not is None True False lambda
json sys stdin load loads dumps read readlines get keys values items
print sep end len sorted reversed str int float bool list dict set tuple min max sum any all
enumerate range zip round abs isinstance map filter
strip lstrip rstrip split splitlines join lower upper replace startswith endswith append
indent sort_keys ensure_ascii key reverse
data obj item row line res resp out name value val entry tag'

# strict_pyc_ok "$codigo" "$comilla": 0 si el programa de `-c` solo nombra PYC_NAMES fuera de
# sus cadenas. Ante la duda, 1: fuera de ASCII (Python normaliza los identificadores con NFKC),
# entre comillas dobles con `$`, backtick o `\` (el shell los expande antes que Python), una
# cadena con prefijo (f"{...}" evalua), un `#` o un `\` fuera de cadena, o una comilla suelta.
strict_pyc_ok() {
  local LC_ALL=C c=$1 q=$2 rest out='' t m0 m1
  local lit='^([^"'\'']*)("([^"\\]|\\.)*"|'\''([^'\''\\]|\\.)*'\'')'
  (( ${#c} > 1024 )) && return 1
  [[ $c == *[![:print:][:space:]]* ]] && return 1
  [[ $q == '"' && $c == *[\$\`\\]* ]] && return 1
  rest=$c
  while [[ $rest =~ $lit ]]; do
    m0=${BASH_REMATCH[0]} m1=${BASH_REMATCH[1]}
    [[ $m1 =~ [A-Za-z0-9_]$ ]] && return 1
    out+="$m1 "
    rest=${rest:${#m0}}
  done
  out+=$rest
  [[ $out == *[\"\'\#\\]* ]] && return 1
  while [[ $out =~ [A-Za-z0-9_]+ ]]; do
    t=${BASH_REMATCH[0]}
    out=${out#*"$t"}
    [[ $t =~ ^([0-9]+|[A-Za-z_])$ || $PYC_NAMES =~ (^|[[:space:]])$t($|[[:space:]]) ]] || return 1
  done
  return 0
}

# fetch_shape_ok "$sentencia": 0 si es EXACTAMENTE `curl|wget … | LECTOR` sin nada despues,
# con LECTOR uno de los tres lectores de datos. Un pipe intermedio, una bandera ajena, codigo
# despues de la cadena o un `-` posicional la dejan fuera (bloquea). El lector va SIN ruta (o
# `.venv/bin/`, `venv/bin/`): `/tmp/x/python3` o `./python3` es el binario que alguien dejo ahi, y un
# prefijo de entorno (`PYTHONPATH=… python3`) no casa con la forma. La descarga tampoco puede tocar
# ficheros: `-o/-O/--output`, `-K/--config`, `-T/--upload-file` y los datos `@fichero` la excluyen
# (la excepcion es leer JSON de la red sin escribir ni leer nada del disco). En wget valen `-O-`/`-O -`.
# `jq -f`, `--from-file`, `--rawfile`, `env` y `$ENV` tampoco entran.
fetch_shape_ok() {
  local st=$1 code dl=${1%%|*}
  local fetch='^[[:space:]]*(curl|wget)([^A-Za-z0-9_|][^|]*)?\|[[:space:]]*'
  local pyre='(\.?venv/bin/)?python[0-9.]*'
  local pyc=$fetch$pyre'[[:space:]]+-[ISEBsu]*c[[:space:]]+('\''[^'\'']*'\''|"[^"]*")[[:space:]]*$'
  local jtool=$fetch$pyre'[[:space:]]+-m[[:space:]]*json\.tool([[:space:]]+(--sort-keys|--compact|--indent(=[0-9]+|[[:space:]]+[0-9]+)))*[[:space:]]*$'
  local jqre=$fetch'jq([[:space:]][^|]*)?$'
  # bad_curl_out mira el texto SIN las cadenas entre comillas (un valor de cabecera no son opciones) y sin
  # clusters que abren con una opcion que toma valor: en `-XPOST` la O es parte del metodo, no `-O`. Las
  # letras sin valor de curl (0-9 # a B f g G h i I j J k l L M n N p q R s S v V Z) pueden ir delante de
  # o/O/K/T; cualquier otra se come el resto del cluster. Con una barra invertida no se quitan comillas
  # (`\"` abre una cadena que el shell no ve): se mira el texto entero, como antes.
  local bad_curl_out='(^|[[:space:]])(-[0-9#aBfgGhiIjJklLMnNpqRsSvVZ]*[oOKT]|--(output|remote-name|remote-name-all|config|upload-file|output-dir)([[:space:]=]|$))'
  local bad_curl_data='(^|[[:space:]])(-[A-Za-z]*d|--data(-binary|-raw|-urlencode|-ascii)?|-F|--form|--json)[[:space:]=]*["'\'']?([A-Za-z0-9_]*=)?@'
  local bad_wget='(^|[[:space:]])(-[A-Za-z]*[oiP]|--(output-file|input-file|directory-prefix|post-file|body-file|config))([[:space:]=]|$)|(^|[[:space:]])-[A-Za-z]*O([[:space:]]+[^-[:space:]]|[^-[:space:]])|(^|[[:space:]])--output-document[[:space:]=]*[^-[:space:]]'
  # shellcheck disable=SC2016 # patron literal para =~, no interpolacion de shell
  local bad_jq='(^|[[:space:]])(-[A-Za-z]*f|-L|--(from-file|rawfile|slurpfile|argfile|library-path))([[:space:]=]|$)|(^|[^.[:alnum:]_$])(env|input_filename)([^[:alnum:]_]|$)|\$(ENV|__prog_args)'
  if [[ $st =~ ^[[:space:]]*curl ]]; then
    local dq=$dl
    [[ $dl == *\\* ]] || dq=$(sed -E "s/\"[^\"]*\"|'[^']*'/Q/g" <<<"$dl")
    [[ $dq =~ $bad_curl_out || $dl =~ $bad_curl_data ]] && return 1
  fi
  [[ $st =~ ^[[:space:]]*wget && $dl =~ $bad_wget ]] && return 1
  if [[ $st =~ $pyc ]]; then
    code=${BASH_REMATCH[4]}
    strict_pyc_ok "${code:1:${#code}-2}" "${code:0:1}"; return
  fi
  [[ $st =~ $jtool ]] && return 0
  [[ $st =~ $jqre && ! ${st#*|} =~ $bad_jq ]]
}

# fetch_safe_reader "$cmd": 0 (SAFE) si TODA sentencia que descarga hacia un interprete es un
# lector de datos y existe al menos una. Clasifica con los mismos patrones RCE que la tabla, de
# modo que ninguna descarga peligrosa se escapa. Falla cerrado.
fetch_safe_reader() {
  local stmt safe=0
  local -a S
  # Un pipe hacia un agrupador (`| (bash)`, `| { bash; }`) parte la sentencia en el `(`: la mitad con la
  # descarga ya no nombra al interprete y la otra no baja nada, y otra sentencia segura bastaria para
  # perdonar el conjunto. Sin excepcion posible: se mantiene el bloqueo.
  printf '%s' "$1" | LC_ALL=C grep -qE '\|&?[[:space:]]*[({]' && return 1
  mapfile -t -d $'\036' S < <(printf '%s' "$1" | awk "$FETCH_SPLIT_AWK")
  (( ${#S[@]} > 64 )) && return 1
  for stmt in "${S[@]}"; do
    if printf '%s' "$stmt" | LC_ALL=C grep -qiE "$RCE_CURL" || printf '%s' "$stmt" | LC_ALL=C grep -qiE "$RCE_WGET"; then
      fetch_shape_ok "$stmt" && { safe=$((safe + 1)); continue; }
      return 1
    fi
  done
  (( safe > 0 ))
}

# Reglas como tabla (patron, mensaje) en vez de 43 llamadas a un `chk` que lanzaba su
# propio `echo | grep`: 43 procesos costaban 58 ms por llamada en este equipo (87 ms en el
# de la auditoria), practicamente todo arranque de proceso. Abajo se evalua primero la
# UNION de todos los patrones en UNA sola invocacion de grep; solo si esa union dispara se
# recorre la tabla regla a regla para saber cual fue y devolver su mensaje exacto (el
# mensaje es contrato). La union se DERIVA de las tablas, asi que no hay copia paralela
# que se pueda quedar sin la regla nueva que alguien anada aqui manana.
# Posicion de comando de un `gh api` para las dos reglas de abajo: inicio, tras `; & | ( { ` !`, `then`/`do`/`else`,
# el programa de un `sh -c '...'`/`eval '...'`/`ssh host '...'` y envoltorios con sus opciones (`timeout 5`, `nice -n 5`,
# `sudo -u u`, `xargs -I{}`, `watch -n 5`, `env VAR=x`). Una comilla NO es ancla por si sola: el texto de un
# `--body "gh api -X DELETE"` o de un `echo` no pide confirmacion. Un `;` o un `|` dentro de ese texto si (ask aceptado).
GH_PRE='(^[[:space:]]*|[;&|({`!][[:space:]]*|\b(then|do|else)[[:space:]]+|\b(ba|z|da)?sh[[:space:]]+(-[A-Za-z]+[[:space:]]+)*-[A-Za-z]*c[[:space:]]+["'"'"']|\beval[[:space:]]+["'"'"']|\bssh[[:space:]]+(-\S+[[:space:]]+(\w+[[:space:]]+)?)*\S+[[:space:]]+["'"'"']?)(\w+=\S*[[:space:]]+)*((sudo|env|command|exec|time|nohup|nice|timeout|watch|xargs|stdbuf|setsid|ionice|doas)[[:space:]]+(-\S+[[:space:]]+(\w+[[:space:]]+)?|[0-9.]+[smhd]?[[:space:]]+|\w+=\S*[[:space:]]+)*)*'

DENY_RULES=(
  # ── DESTRUCTIVE FILE/DISK ──────────────────────────────────────────────────
  '\brm\s+-[a-z]*r[a-z]*f'            "BLOCKED: rm -rf (recursive force delete)"
  '\brm\s+-[a-z]*f[a-z]*r'            "BLOCKED: rm -fr (recursive force delete)"
  # Formas largas: `rm --recursive --force ruta` borra lo mismo que `rm -rf` y no lleva
  # ninguna r ni f agrupada tras un guion, asi que las dos reglas de arriba la dejaban
  # pasar entera. Se exige recursivo Y forzado (en cualquiera de los dos ordenes, corto o
  # largo) para no bloquear un `rm -r node_modules` ni un `rm --force fichero`.
  # LIMITE CONOCIDO, deliberadamente no cubierto: `rm -"rf" ruta` y `F=-rf; rm $F ruta`
  # derrotan cualquier regex de flags -- el hook ve el literal del comando, no el argv que
  # el shell expandira. Mas regex no lo arregla; eso lo cubre la capa de permisos.
  '\brm\b[^;&|]*\s(--recursive|-[a-z]*r[a-z]*)\b[^;&|]*\s(--force|-[a-z]*f[a-z]*)\b'  "BLOCKED: rm --recursive --force (recursive force delete)"
  '\brm\b[^;&|]*\s(--force|-[a-z]*f[a-z]*)\b[^;&|]*\s(--recursive|-[a-z]*r[a-z]*)\b'  "BLOCKED: rm --force --recursive (recursive force delete)"
  '\bshred\b'                          "BLOCKED: shred (secure file destruction)"
  '\bdd\s+.*\bof=/dev/[hsv][da]'      "BLOCKED: dd write to block device"
  '\bmkfs\b'                           "BLOCKED: mkfs (format filesystem)"
  '\bfdisk\b'                          "BLOCKED: fdisk (partition table editor)"
  '\bwipefs\b'                         "BLOCKED: wipefs (wipe filesystem signatures)"
  '>\s*/dev/sd'                        "BLOCKED: redirect to block device"

  # ── SYSTEM SHUTDOWN/REBOOT ─────────────────────────────────────────────────
  '(^|[;&|]\s*)(sudo\s+)?reboot\b'    "BLOCKED: reboot"
  '(^|[;&|]\s*)(sudo\s+)?shutdown\b'  "BLOCKED: shutdown"
  '(^|[;&|]\s*)(sudo\s+)?halt\b'      "BLOCKED: halt"
  '(^|[;&|]\s*)(sudo\s+)?poweroff\b'  "BLOCKED: poweroff"
  '\binit\s+[06]\b'                   "BLOCKED: init 0/6 (shutdown/reboot)"

  # ── NETWORK / REMOTE CODE EXECUTION ────────────────────────────────────────
  '\biptables\s+-F'                   "BLOCKED: iptables -F (flush firewall)"
  '\bufw\s+disable'                   "BLOCKED: ufw disable"
  # Interprete tras el pipe, con prefijo opcional (`sudo -E`, `env -i`, `xargs -0`...) y `|&`:
  # la forma canonica de NodeSource (`| sudo -E bash -`), `| dash`, `| python3` o `| node` pasaban.
  "$RCE_CURL"  "$RCE_MSG_CURL"
  "$RCE_WGET"  "$RCE_MSG_WGET"
  "$RCE_NET"   "BLOCKED: network stream piped to shell (RCE); guarda la salida en un fichero, revisalo y ejecutalo aparte"
  # `| while read l; do eval "$l"; done` y `| awk '{system($0)}'` ejecutan linea a linea lo que baja.
  '\b(curl|wget|nc|ncat|netcat)\b[^;&]*\|&?\s*(while|for)\b.*(\b(eval|source)\s|\b((ba|da|z|k|a)?sh)\s+-c\b|\|\s*(ba|da|z|k|a)?sh\b)'  "BLOCKED: download piped to a loop that executes it (RCE); descarga a fichero (-o), revisalo y ejecutalo aparte"
  '\b(curl|wget|nc|ncat|netcat)\b[^;&]*\|&?\s*(g|m|n)?awk\b[^|]*\bsystem\b'  "BLOCKED: download piped to awk system() (RCE); descarga a fichero (-o), revisalo y ejecutalo aparte"
  '\b(curl|wget)\b.*\|\s*(\.|source)\s+/dev/stdin'  "BLOCKED: curl/wget piped to source (RCE)"
  # Sustitucion de comando/proceso: `sh -c "$(curl ..)"`, `eval "$(curl ..)"`, `bash < <(curl ..)`.
  # El curl tiene que estar en posicion de CODIGO (justo tras el interprete o su -c): como
  # argumento (`bash script.sh "$(curl ..)"`, `node x.js "$(curl ..)"`) no se ejecuta.
  '(^|[[:space:];&|(])(\S*/)?'"$RCE_INTERP"'\s+(-c\s+)?["'"'"']?(\$\(|<\(|`)\s*(curl|wget)'  "BLOCKED: curl/wget output executed by an interpreter (RCE)"
  # `bash <<< "$(curl ..)"` y `bash <(cat <(curl ..))`: la descarga entra al interprete como programa.
  '(^|[[:space:];&|(])(\S*/)?'"$RCE_INTERP"'\s+(-\S+\s+)*<<<\s*["'"'"']?(\$\(|`)\s*(curl|wget)'  "BLOCKED: curl/wget output executed by an interpreter (RCE)"
  '(^|[[:space:];&|(])(\S*/)?'"$RCE_INTERP"'\s+(-\S+\s+)*(<\s*)?<\([^;&|]*\b(curl|wget)\b'  "BLOCKED: curl/wget output executed by an interpreter (RCE)"
  '\beval\s+["'"'"']?\$\(\s*(curl|wget)'      "BLOCKED: curl/wget output executed by an interpreter (RCE)"
  '<\s*<\(\s*(curl|wget)'                      "BLOCKED: curl/wget output executed by an interpreter (RCE)"
  '(^|[;&|]\s*)(\.|source)\s+<\(\s*(curl|wget)'  "BLOCKED: curl/wget output executed by an interpreter (RCE)"
  # La salida de la descarga como COMANDO: `$(curl ..)` o `` `curl ..` `` en posicion de comando, y
  # `X=$(curl ..); $X`. Mismas formas que en Sentinel: los dos guards tienen que coincidir.
  '(^|[;&|(]\s*)(\$\(|`)\s*(curl|wget)\b'  "BLOCKED: curl/wget output executed as a command (RCE)"
  '=["'"'"']?(\$\(|`)\s*(curl|wget)\b[^;&]*[;&]+\s*["'"'"']?\$\{?[A-Za-z_]'  "BLOCKED: curl/wget output executed as a command (RCE)"
  # Redirigir o `tee` hacia los ficheros de arranque del shell planta codigo que corre en la proxima sesion.
  '(>>?\|?|\btee\s+(-a\s+)?)\s*["'"'"']?(~|\$\{?HOME\}?|/root|/home/[^/[:space:]"'"'"']+)/\.((bashrc|zshrc|bash_profile|bash_login|profile|zprofile|zshenv|zlogin)(["'"'"'[:space:];&|)<>}]|$)|(bashrc|profile|zshrc)\.d/)'  "BLOCKED: write to a shell startup file (persistence)"
  '\bnc\s+-[a-z]*l'                   "BLOCKED: netcat listener (reverse shell)"
  '/dev/tcp/'                         "BLOCKED: /dev/tcp (reverse shell)"
  '/dev/udp/'                         "BLOCKED: /dev/udp (reverse shell)"

  # ── SSH DIRECTORY TAMPERING ────────────────────────────────────────────────
  '(>|>>)\s*\S*/\.ssh/'              "BLOCKED: redirect to .ssh directory"
  '\btee\s+\S*\.ssh/'                "BLOCKED: tee to .ssh directory"

  # ── GIT FORCE PUSH ─────────────────────────────────────────────────────────
  # El prefijo es independiente de la POSICION del subcomando: exigir `git\s+push`
  # se rompia con cualquier opcion de git por delante (`git -C /ruta push -f origin main`
  # pasaba los cinco guards), y el ancla la ponia el propio patron, no el usuario.
  # Flags cortos agrupados: `git push -uf origin main` fuerza de verdad y no contiene "-f"
  # como token suelto, asi que la version anterior ('-f\b') lo dejaba pasar -- justo la
  # proteccion que el kit anuncia como dura. Se acepta cualquier grupo de flags cortos que
  # contenga una f: en `git push` la unica opcion corta con f es --force, y las largas tipo
  # --follow-tags no emparejan porque tras el guion viene otro guion, no letras.
  # --force-with-lease y --force-if-includes siguen cayendo por la regla de --force.
  '\bgit\b[^;&|]*\bpush\b[^;&|]*--force'        "BLOCKED: git push --force"
  '\bgit\b[^;&|]*\bpush\b[^;&|]*\s-[A-Za-z]*f'  "BLOCKED: git push -f / -uf (force push)"
  # El refspec forzado (`+rama`) no va en esta tabla: se decide sobre tokens, mas abajo.
  # git acepta cualquier prefijo no ambiguo de una opcion larga: `--mirr` es `--mirror`, `--de` es
  # `--delete` y `--no-veri` es `--no-verify` (`--forc` y `--no-v` son ambiguas: git las rechaza).
  '\bgit\b[^;&|]*\bpush\b[^;&|]*--m(i(r(r(or?)?)?)?)?([[:space:]=]|$)'  "BLOCKED: git push --mirror (can delete remote refs)"
  # `git -c core.hooksPath=...` y `git -c alias.x=...` (salta los hooks del repo / redefine un subcomando) se deciden
  # mas abajo, sobre el texto sin comillas: `-c "core.hooksPath=..."` es el mismo -c.
  # Los borrados remotos requieren tokens descomillados, no regex sobre el texto literal.

  # ── CREDENTIAL EXFILTRATION ────────────────────────────────────────────────
  '\b(printenv|env)\b.*\|\s*(curl|nc|wget)\b'   "BLOCKED: env vars leaked to network"
  '\bcat\b.*\.env.*\|\s*(curl|nc|wget)\b'       "BLOCKED: .env file leaked to network"
  '\b(printenv|env)\b.*>\s*/dev/tcp/'            "BLOCKED: env via /dev/tcp"
  'base64\s*(-d|--decode).*\|\s*(ba)?sh'        "BLOCKED: base64-decoded payload to shell"

  # ── SUPPLY CHAIN — URL EXECUTION ───────────────────────────────────────────
  '\bnpx\s+https?://'                  "BLOCKED: npx from URL (supply chain / RCE risk)"
  '\bpnpm\s+dlx\s+https?://'           "BLOCKED: pnpm dlx from URL (supply chain risk)"
  '\bdeno\s+(run|install)\s+https?://' "BLOCKED: deno run/install from URL"
  '\bbun\s+(x|run)\s+https?://'        "BLOCKED: bun x/run from URL (supply chain risk)"

  # ── PROSA → HOOK (convenciones del kit) ────────────────────────────────────
  # Anclado a posicion de comando: `echo "npm install foo" >> README.md` no instala nada.
  '(^|[;&|(]\s*)npm\s+(install|i|add|ci|update)\b'  "BLOCKED: usa pnpm (pnpm install/add/update), no npm"

  # ── MISC ───────────────────────────────────────────────────────────────────
  ':\(\)\s*\{.*\|'                    "BLOCKED: fork bomb pattern"
)

ASK_RULES=(
  # ── SYSTEM ADMINISTRATION (ASK — HITL) ─────────────────────────────────────
  '\bsystemctl\s+(stop|disable)\b'    "Confirm: systemctl stop/disable — may interrupt running services"
  '\bchmod\s+777'                     "Confirm: chmod 0777 sets world-writable permissions"
  '\bssh-keygen\b'                    "Confirm: ssh-keygen — will this overwrite an existing key?"

  # Cerrar o fusionar un issue/PR y tocar paquetes del sistema se confirman: no son irreversibles
  # como un rm -rf, pero la politica de la casa exige que lo decida una persona. `--no-verify`
  # NO esta aqui a proposito: sigue en DENY (decision 1 del plan v3).
  '\bgh\s+([-A-Za-z0-9_./=@]+\s+)*(pr|issue)\s+(close|merge)\b'  "Confirm: gh pr/issue close|merge — closes or merges on the remote"
  '\bsudo\s+(-[A-Za-z-]+\s+)*(apt|apt-get|dnf|pip3?)\b'          "Confirm: sudo apt/apt-get/dnf/pip — installs or removes system packages"
  # `gh api` hace por la API lo que `gh pr merge` o `gh repo delete` hacen con su subcomando, y se
  # salta la regla de arriba: DELETE/PUT/PATCH, fusionar (`/merge`), forzar una ref, cerrar un issue y
  # las mutaciones GraphQL se confirman igual. Un GET o un POST de crear (comentario, issue) pasa.
  # Se ancla a un `gh api` en posicion de comando y `mutation` solo cuenta dentro de `-f/-F query=`: el texto de un
  # `gh pr create --body`, un `echo` o una ruta con esa palabra no piden confirmacion.
  "$GH_PRE"'gh\s+([-A-Za-z0-9_./=@]+\s+)*api\b[^;&|]*(-X|--method)[[:space:]=]*(DELETE|PUT|PATCH)\b'  "Confirm: gh api DELETE/PUT/PATCH — changes or deletes remote state"
  "$GH_PRE"'gh\s+([-A-Za-z0-9_./=@]+\s+)*api\b[^;&|]*(/merge\b|force=true|state=closed|(-[fF]|--raw-field|--field)[[:space:]=]*["'"'"']?query=[^;&|]*\bmutation\b)'  "Confirm: gh api merge/force/close/mutation — changes remote state"
  '\bgh\s+([-A-Za-z0-9_./=@]+\s+)*repo\s+delete\b'  "Confirm: gh repo delete — deletes the repository on the remote"

  # `git config core.hooksPath ruta` es el comando que documenta 05-security.md para la Capa 2 y el de
  # husky/.githooks: se pregunta, no se niega. Lo de una sola orden (`git -c core.hooksPath=...`) sigue en deny.
  '\bgit\b[^;&|]*\bconfig\b[^;&|]*core\.hookspath[[:space:]]+[^-[:space:]]'  "Confirm: git config core.hooksPath cambia donde busca git los hooks de este repo (los del repo y los del kit dejan de correr si apunta a otro sitio). Para activar la Capa 2 de secretos: bash install.sh --enable-secrets-layer2"

  # ── DATABASE OPERATIONS (ASK — HITL) ───────────────────────────────────────
  '\bDROP\s+DATABASE\b'   "Confirm: DROP DATABASE — irreversible data loss"
  '\bDROP\s+TABLE\b'      "Confirm: DROP TABLE — irreversible data loss"
  '\bTRUNCATE\s+TABLE\b'  "Confirm: TRUNCATE TABLE — deletes all rows permanently"

  # ── DOCKER DESTRUCTIVE (ASK — HITL) ────────────────────────────────────────
  '\bdocker\s+system\s+prune'  "Confirm: docker system prune — removes all unused containers/images"
  '\bdocker\s+volume\s+rm'     "Confirm: docker volume rm — permanent volume data loss"

  # ── DOWNLOAD AND EXECUTE (ASK — HITL) ──────────────────────────────────────
  '\b(curl|wget)\b[^|]*(&&|;)\s*(sudo\s+)?((a|ba|z|da|k)?sh\b|(\.|source)\s+\S)'  "Confirm: download then run a script — review it before executing"

  # ── PACKAGE PUBLISH / INSTALL FROM URL (ASK — HITL) ────────────────────────
  '\bnpm\s+publish'             "Confirm: npm publish — will publish to public npm registry"
  '\bpip\s+install\s+https?://' "Confirm: pip install from URL — verify source before installing"
)

# --no-verify (y su forma corta `commit -n`, tambien agrupada: `-nm`) se mira SIN los tramos
# entre comillas: en el mensaje (`git commit -m "skip --no-verify docs"`) es texto, no un flag.
if [[ $COMMAND == *git* ]]; then
  sed -E "s/\"[^\"]*\"|'[^']*'//g" <<<"$COMMAND" \
    | LC_ALL=C grep -qiE '\bgit\b[^;&|]*\b(commit|push)\b[^;&|]*--no-veri|\bgit\b[^;&|]*\bcommit\b[^;&|]*\s-[a-z]*n' \
    && deny "BLOCKED: --no-verify salta los hooks de git; arregla el hook que falla"
fi

if [[ $COMMAND == *git* ]]; then
  sed -E "s/[\"']//g" <<<"$COMMAND" | LC_ALL=C grep -qiE '\bgit\b[^;&|]*[[:space:]]-c[[:space:]]*core\.hookspath' \
    && deny "BLOCKED: git -c core.hooksPath (skips the repo's git hooks)"
  sed -E "s/[\"']//g" <<<"$COMMAND" | LC_ALL=C grep -qiE '\bgit\b[^;&|]*[[:space:]]-c[[:space:]]*alias\.' \
    && deny "BLOCKED: git -c alias.* (redefines a git subcommand)"
fi

# Los refspecs forzados (`+rama`) y los tres borrados remotos (`--delete`, `-d`, `:rama`) se
# deciden sobre operandos de `git push` descomillados. El argumento de `-o` y compania no cuenta.
# Como en branch-guard.sh, la cadena de un `bash -c`, `eval`, `ssh`, `xargs`... se vuelve a
# normalizar, hasta 3 niveles; lo que solo muestra texto no cuenta.
# Cada cadena anidada cuesta un awk (~3 ms): sin tope, 12 KB de `x git;` eran 7 s de CPU, y un guard
# que pasa de su timeout deja ejecutar el comando ENTERO. Solo se vuelve a normalizar la cadena que
# puede llevar el refspec (push y +), y pasadas 16 se deniega: fallar cerrado.
NEST=0
push_refspec() {
  local depth=$1 kind=$2 seg a i inner skip dd rc
  local -a T segs
  segs=("${CMDN_SEGS[@]}")
  for seg in "${segs[@]}"; do
    case $kind in
      force) [[ $seg == *push* && $seg == *+* ]] || continue ;;
      delete) [[ $seg == *push* && ( $seg == *-d* || $seg == *-[A-Za-z]*d* || $seg == *--de* || $seg == *:* ) ]] || continue ;;
    esac
    cmdn_fields "$seg"
    if [[ ${T[1]:-} != git ]]; then
      case ${T[1]:-} in echo|printf|grep|egrep|fgrep|rg|sed|awk|cat|man|type|which|less|head|tail|test|'[') (( PIPED )) || continue ;; esac
      for (( i = 2; i < ${#T[@]}; i++ )); do
        a=${T[i]}
        [[ $a == *git* ]] || continue
        inner=$a
        [[ $a == git || $a == */git ]] && printf -v inner '%s ' "${T[@]:i}"
        case ${T[1]:-} in
          python*|perl|ruby|node|php) cmdn_code_inner "$a" git && inner=$REPLY ;;
          echo|printf) inner=${inner//\\n/$'\n'} ;;
        esac
        case $kind in
          force) [[ $inner == *push* && $inner == *+* ]] || continue ;;
          delete) [[ $inner == *push* && ( $inner == *-d* || $inner == *-[A-Za-z]*d* || $inner == *--de* || $inner == *:* ) ]] || continue ;;
        esac
        (( depth < 3 && ++NEST <= 16 )) || return 2
        cmdn_parse "$inner" || continue
        push_refspec $(( depth + 1 )) "$kind"; rc=$?
        (( rc == 1 )) || return $rc
      done
      continue
    fi
    [[ ${T[2]:-} == push ]] || continue
    skip=0; dd=0
    for a in "${T[@]:3}"; do
      if (( skip )); then skip=0; continue; fi
      if (( ! dd )) && [[ $a == -- ]]; then dd=1; continue; fi
      if (( ! dd )) && [[ $a == -* ]]; then
        if [[ $kind == delete ]]; then
          case $a in
            --*) [[ ${#a} -ge 4 && --delete == "$a"* ]] && return 0 ;;
            -*) [[ ${a#-} == *d* ]] && return 0 ;;
          esac
        fi
        case $a in --repo|-o|--push-option|--receive-pack|--exec) skip=1 ;; esac
        continue
      fi
      if [[ $kind == force ]]; then
        [[ $a == +* || $a == '$'+* ]] && return 0
      else
        [[ $a == :?* || $a == '$':?* ]] && return 0
      fi
    done
  done
  return 1
}
PIPED=0; cmdn_pipes_to_shell && PIPED=1
if [[ $COMMAND == *git* && $COMMAND == *push* && $COMMAND == *+* ]]; then
  push_refspec 0 force; rc_refspec=$?
  (( rc_refspec == 0 )) && deny "BLOCKED: git push +refspec (forced refspec)"
  (( rc_refspec == 2 )) && deny "BLOCKED: mas de 3 niveles o 16 comandos anidados (bash -c, ssh, xargs...) con git push: no caben en el timeout del guard; dividelo en comandos cortos"
fi
NEST=0
if [[ $COMMAND == *git* && $COMMAND == *push* && ( $COMMAND == *-d* || $COMMAND == *-[A-Za-z]*d* || $COMMAND == *--de* || $COMMAND == *:* ) ]]; then
  push_refspec 0 delete; rc_refspec=$?
  (( rc_refspec == 0 )) && deny "BLOCKED: git push --delete/-d/:rama (deletes a remote branch)"
  (( rc_refspec == 2 )) && deny "BLOCKED: mas de 3 niveles o 16 comandos anidados (bash -c, ssh, xargs...) con git push: no caben en el timeout del guard; dividelo en comandos cortos"
fi

# LC_ALL=C en los grep: con UTF-8 la union de patrones deja de ir por el automata y recorre el
# comando con retroceso, cuadratico en una linea larga (32 KB = 2,8 s, 64 KB = 13 s de CPU, y el
# timeout del hook corre en abierto). Los patrones son ASCII; en C solo cambia que un byte no
# ASCII pegado a una palabra ya no cuenta como letra para \b, que es el lado seguro.
UNION=''
for ((i = 0; i < ${#DENY_RULES[@]}; i += 2)); do UNION+="|${DENY_RULES[i]}"; done
for ((i = 0; i < ${#ASK_RULES[@]}; i += 2)); do UNION+="|${ASK_RULES[i]}"; done
# `|| exit 0` confundia "no ha emparejado" (grep rc=1) con "la regex no compila" (grep rc=2):
# un solo patron mal formado en la tabla convertia TODO el blocklist en un permiso silencioso,
# porque el error de grep sale por stderr y con exit 0 no se muestra. Se distinguen los dos.
echo "$COMMAND" | LC_ALL=C grep -qiE "${UNION#|}"
rc_union=$?
if [ "$rc_union" -ge 2 ]; then
  deny "BLOCKED: el blocklist no compila (grep rc=$rc_union); se deniega por seguridad"
fi
[ "$rc_union" -eq 0 ] || exit 0

# writes_text_to_file: el comando parece ESCRIBIR texto (un heredoc, o un echo/printf con
# redireccion), no ejecutar. El cuerpo sigue juzgandose como en main (no se vacia), pero si lo
# que cae es un literal peligroso dentro de ese texto, el mensaje apunta a la salida correcta.
writes_text_to_file() {
  [[ $COMMAND == *'<<'* ]] && return 0
  [[ $COMMAND =~ (^|[;&|[:space:]])(echo|printf)[[:space:]].*\> ]] && return 0
  return 1
}

SAFE_FETCH=''
for ((i = 0; i < ${#DENY_RULES[@]}; i += 2)); do
  echo "$COMMAND" | LC_ALL=C grep -qiE "${DENY_RULES[i]}" || continue
  if [[ ${DENY_RULES[i]} == "$RCE_CURL" || ${DENY_RULES[i]} == "$RCE_WGET" ]]; then
    [[ -z $SAFE_FETCH ]] && { if fetch_safe_reader "$COMMAND"; then SAFE_FETCH=yes; else SAFE_FETCH=no; fi; }
    [[ $SAFE_FETCH == yes ]] && continue
  fi
  msg=${DENY_RULES[i + 1]}
  case $msg in
    *"(RCE)"*) ;;
    "BLOCKED: rm "*|"BLOCKED: shred"*|"BLOCKED: dd "*|"BLOCKED: mkfs"*|"BLOCKED: fdisk"*|"BLOCKED: wipefs"*|"BLOCKED: redirect to block device"*)
      writes_text_to_file && msg="$msg; si es texto para un fichero, escribelo con la herramienta Write" ;;
  esac
  deny "$msg"
done
for ((i = 0; i < ${#ASK_RULES[@]}; i += 2)); do
  echo "$COMMAND" | LC_ALL=C grep -qiE "${ASK_RULES[i]}" && ask "${ASK_RULES[i + 1]}"
done

exit 0
