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

ALLOWLIST_FILE="${HOME}/.claude/sentinel-allowlist.json"

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

# Las dos reglas de `curl`/`wget` tras un pipe a interprete viven en variables porque la
# excepcion estrecha de K1 (fetch_safe_reader, mas abajo) necesita reconocerlas por identidad
# para saltarlas cuando la descarga alimenta solo a un lector de datos. Una sola fuente: la
# tabla y la excepcion ven el mismo patron.
RCE_CURL='\bcurl\b.*\|&?\s*((sudo|env|exec|command|xargs|nohup)\b[^|]*\s)?(\S*/)?((ba|z|da|k)?sh|python[0-9.]*|perl|ruby|node|php)\b'
RCE_WGET='\bwget\b.*\|&?\s*((sudo|env|exec|command|xargs|nohup)\b[^|]*\s)?(\S*/)?((ba|z|da|k)?sh|python[0-9.]*|perl|ruby|node|php)\b'
RCE_MSG_CURL="BLOCKED: curl piped to shell (RCE); descarga a fichero (-o), revisalo y ejecutalo aparte; para JSON, jq o python -c sin exec"
RCE_MSG_WGET="BLOCKED: wget piped to shell (RCE); descarga a fichero (-o), revisalo y ejecutalo aparte; para JSON, jq o python -c sin exec"

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

# strict_pyc_ok "$codigo": 0 si el programa de `-c` no tiene dunders ni, como palabra o
# subcadena segun el caso, ninguna via a ejecutar codigo o tocar fichero/red. Ante la duda, 1.
strict_pyc_ok() {
  local c=$1 w
  case $c in
    *__*|*exec*|*eval*|*compile*|*getattr*|*globals*|*vars*|*open*|*input*|*breakpoint*|*sys.modules*|*/dev/*) return 1 ;;
  esac
  for w in os subprocess pty ctypes importlib runpy marshal pickle builtins socket system popen spawn; do
    [[ $c =~ (^|[^A-Za-z0-9_])$w($|[^A-Za-z0-9_]) ]] && return 1
  done
  return 0
}

# fetch_shape_ok "$sentencia": 0 si es EXACTAMENTE `curl|wget … | LECTOR` sin nada despues,
# con LECTOR uno de los tres lectores de datos. Un pipe intermedio, una bandera ajena, codigo
# despues de la cadena o un `-` posicional la dejan fuera (bloquea).
fetch_shape_ok() {
  local st=$1 code
  local pyc='^[[:space:]]*(curl|wget)[^|]*\|[[:space:]]*([^[:space:]|]*/)?python[0-9.]*[[:space:]]+-[ISEBsu]*c[[:space:]]+('\''[^'\'']*'\''|"[^"]*")[[:space:]]*$'
  local jtool='^[[:space:]]*(curl|wget)[^|]*\|[[:space:]]*([^[:space:]|]*/)?python[0-9.]*[[:space:]]+-m[[:space:]]*json\.tool([[:space:]]+(--sort-keys|--compact|--indent(=[0-9]+|[[:space:]]+[0-9]+)))*[[:space:]]*$'
  local jqre='^[[:space:]]*(curl|wget)[^|]*\|[[:space:]]*([^[:space:]|]*/)?jq([[:space:]][^|]*)?$'
  if [[ $st =~ $pyc ]]; then
    code=${BASH_REMATCH[3]}
    code=${code:1:${#code}-2}
    strict_pyc_ok "$code"; return
  fi
  [[ $st =~ $jtool || $st =~ $jqre ]]
}

# fetch_safe_reader "$cmd": 0 (SAFE) si TODA sentencia que descarga hacia un interprete es un
# lector de datos y existe al menos una. Clasifica con los mismos patrones RCE que la tabla, de
# modo que ninguna descarga peligrosa se escapa. Falla cerrado.
fetch_safe_reader() {
  local stmt safe=0
  local -a S
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
  '\b(curl|wget)\b.*\|\s*(\.|source)\s+/dev/stdin'  "BLOCKED: curl/wget piped to source (RCE)"
  # Sustitucion de comando/proceso: `sh -c "$(curl ..)"`, `eval "$(curl ..)"`, `bash < <(curl ..)`.
  # El curl tiene que estar en posicion de CODIGO (justo tras el interprete o su -c): como
  # argumento (`bash script.sh "$(curl ..)"`, `node x.js "$(curl ..)"`) no se ejecuta.
  '(^|[[:space:];&|(])(\S*/)?((ba|z)?sh|python[0-9.]*|perl|ruby|node)\s+(-c\s+)?["'"'"']?(\$\(|<\(|`)\s*(curl|wget)'  "BLOCKED: curl/wget output executed by an interpreter (RCE)"
  '\beval\s+["'"'"']?\$\(\s*(curl|wget)'      "BLOCKED: curl/wget output executed by an interpreter (RCE)"
  '<\s*<\(\s*(curl|wget)'                      "BLOCKED: curl/wget output executed by an interpreter (RCE)"
  '(^|[;&|]\s*)(\.|source)\s+<\(\s*(curl|wget)'  "BLOCKED: curl/wget output executed by an interpreter (RCE)"
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
  '\bgit\b[^;&|]*\bpush\b[^;&|]*--mirror'       "BLOCKED: git push --mirror (can delete remote refs)"
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

  # ── DATABASE OPERATIONS (ASK — HITL) ───────────────────────────────────────
  '\bDROP\s+DATABASE\b'   "Confirm: DROP DATABASE — irreversible data loss"
  '\bDROP\s+TABLE\b'      "Confirm: DROP TABLE — irreversible data loss"
  '\bTRUNCATE\s+TABLE\b'  "Confirm: TRUNCATE TABLE — deletes all rows permanently"

  # ── DOCKER DESTRUCTIVE (ASK — HITL) ────────────────────────────────────────
  '\bdocker\s+system\s+prune'  "Confirm: docker system prune — removes all unused containers/images"
  '\bdocker\s+volume\s+rm'     "Confirm: docker volume rm — permanent volume data loss"

  # ── DOWNLOAD AND EXECUTE (ASK — HITL) ──────────────────────────────────────
  '\b(curl|wget)\b[^|]*(&&|;)\s*(sudo\s+)?(ba|z)?sh\b'  "Confirm: download then run a script — review it before executing"

  # ── PACKAGE PUBLISH / INSTALL FROM URL (ASK — HITL) ────────────────────────
  '\bnpm\s+publish'             "Confirm: npm publish — will publish to public npm registry"
  '\bpip\s+install\s+https?://' "Confirm: pip install from URL — verify source before installing"
)

# --no-verify (y su forma corta `commit -n`, tambien agrupada: `-nm`) se mira SIN los tramos
# entre comillas: en el mensaje (`git commit -m "skip --no-verify docs"`) es texto, no un flag.
if [[ $COMMAND == *git* ]]; then
  sed -E "s/\"[^\"]*\"|'[^']*'//g" <<<"$COMMAND" \
    | LC_ALL=C grep -qiE '\bgit\b[^;&|]*\b(commit|push)\b[^;&|]*--no-verify|\bgit\b[^;&|]*\bcommit\b[^;&|]*\s-[a-z]*n' \
    && deny "BLOCKED: --no-verify salta los hooks de git; arregla el hook que falla"
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
      delete) [[ $seg == *push* && ( $seg == *-d* || $seg == *-[A-Za-z]*d* || $seg == *--delete* || $seg == *:* ) ]] || continue ;;
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
          delete) [[ $inner == *push* && ( $inner == *-d* || $inner == *-[A-Za-z]*d* || $inner == *--delete* || $inner == *:* ) ]] || continue ;;
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
            --delete) return 0 ;;
            --*) ;;
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
if [[ $COMMAND == *git* && $COMMAND == *push* && ( $COMMAND == *-d* || $COMMAND == *-[A-Za-z]*d* || $COMMAND == *--delete* || $COMMAND == *:* ) ]]; then
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
