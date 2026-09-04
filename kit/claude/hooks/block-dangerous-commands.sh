#!/bin/bash
# block-dangerous-commands.sh — PreToolUse Bash security blocklist
# Source: randomdreft/claude-code-security-hook (public domain), extended
# Protocol: JSON deny/ask output + exit 0, or silent exit 0 to allow. When the input
# cannot be read AT ALL (no jq and no python3), the fallback is exit 2 + stderr (also a
# block in Claude Code, and the only one left: emitting the JSON verdict needs a parser).

set -uo pipefail

# >>> hk-json ─────────────────────────────────────────────────────────────────
# Leer JSON sin depender de jq. Cadena de tres eslabones, en este orden:
#   1. jq si esta         -> el camino de siempre, sin cambiar un byte
#   2. python3 si no      -> json de la stdlib, parseo de verdad
#   3. ninguno de los dos -> fallo cerrado; quien llama decide como bloquear
# python3 NO es una dependencia nueva: kit/install.sh aborta con exit 1 si no puede crear
# el venv con `python3 -m venv`, y el kit ya distribuye cuatro hooks .py. jq, en cambio,
# no esta declarado como requisito en ningun sitio.
# PROHIBIDO parsear esto con grep/sed/awk: el payload lleva llaves, comillas y saltos de
# linea DENTRO de los valores, y una igualdad por subcadena es exactamente el defecto que
# este repo lleva media rama persiguiendo.
# Este bloque esta DUPLICADO en los seis hooks que leen JSON, y kit/test/test_guards.sh
# comprueba que los seis son identicos byte a byte. Se duplica en vez de compartirse
# porque un hook es un ejecutable hoja que el runtime lanza por ruta absoluta: ninguno de
# los 14 del kit hace `source` de nada, los cuatro guards se instalan en ~/.claude/hooks/
# mientras que auto-spec y verify-gate viven en el repo (no hay ruta relativa comun), y
# una libreria compartida anadiria a un control de seguridad un modo de fallo nuevo --
# libreria ausente => bloquear TODO.
if command -v jq >/dev/null 2>&1; then HK_JSON=jq
elif command -v python3 >/dev/null 2>&1; then HK_JSON=py
else HK_JSON=no; fi

# hk_get <ruta.punteada> [defecto]  --  JSON por stdin, valor por stdout.
# El contrato es el que ya tenia jq a solas, y de el depende todo lo de abajo:
#   rc=0 con salida vacia -> el campo no esta (permitir es lo correcto)
#   rc!=0                 -> no se ha podido leer la entrada (ciego: no puede autorizar)
# El defecto viaja por --arg/argv, nunca interpolado dentro del programa.
hk_get() {
  case "$HK_JSON" in
    jq) if [ $# -ge 2 ]; then jq -r --arg d "$2" ".$1 // \$d" 2>/dev/null
        else jq -r ".$1 // empty" 2>/dev/null; fi ;;
    py) python3 -c 'import json,sys
try: d = json.load(sys.stdin)
except Exception: sys.exit(5)
for k in sys.argv[1].split("."):
    if d is None: break
    if not isinstance(d, dict): sys.exit(5)
    d = d.get(k)
if d is None or d is False: d = sys.argv[2] if len(sys.argv) > 2 else None
if d is not None: print(d if isinstance(d, str) else json.dumps(d))' "$1" ${2+"$2"} 2>/dev/null ;;
    *)  return 127 ;;
  esac
}
# <<< hk-json ─────────────────────────────────────────────────────────────────

# >>> hk-ciego ────────────────────────────────────────────────────────────────
# Un guard que no ha podido leer su entrada no puede autorizarla. El bloqueo va por
# exit 2 + motivo por stderr porque es el unico mecanismo que no depende de nada
# instalado, que es justo el punto cuando lo que falta es el parser. Identico en los
# cuatro guards salvo el nombre, que se pasa como argumento en vez de sacarlo de $0:
# el runtime no garantiza con que $0 los invoca, y el nombre es parte del mensaje.
# El texto del caso jq se conserva palabra por palabra desde J-1: con jq presente no
# cambia ni un byte, tampoco cuando lo que falla es que la entrada no sea JSON.
hk_ciego() { # $1 nombre del hook, $2 rc de la lectura
  case "$HK_JSON" in
    jq) echo "BLOCKED: cannot read the hook input with jq (rc=$2: jq missing from PATH, or input that is not readable JSON)." >&2
        echo "$1 will not allow a command it could not inspect. Install jq, or remove this hook deliberately." >&2 ;;
    py) echo "BLOCKED: cannot read the hook input with python3 (rc=$2: the input is not readable JSON)." >&2
        echo "$1 will not allow a command it could not inspect. Send it valid JSON, or remove this hook deliberately." >&2 ;;
    *)  echo "BLOCKED: cannot read the hook input: no JSON parser found (rc=$2: neither jq nor python3 in PATH)." >&2
        echo "$1 will not allow a command it could not inspect. Install jq or python3, or remove this hook deliberately." >&2 ;;
  esac
  exit 2
}
# <<< hk-ciego ────────────────────────────────────────────────────────────────

# Lo que separa "no hay comando que revisar" de "no he podido leer el comando" NO es que
# la salida venga vacia: es el CODIGO DE SALIDA del lector. rc=0 con salida vacia permite
# (un evento que no es Bash no trae .tool_input.command, y ahi permitir es correcto);
# rc!=0 significa que el guard esta ciego, y un guard ciego no puede autorizar.
# Sin jq ya no se esta ciego: hk_get lee con python3 y el veredicto sigue saliendo por
# JSON, que es el protocolo de este hook. El exit 2 de hk_ciego es el ULTIMO recurso --
# sin jq NI python3 no hay con que construir ese JSON, y ahi el unico bloqueo que queda
# es el de los otros tres guards: codigo de salida 2 y motivo por stderr.
COMMAND=$(hk_get tool_input.command); HK_RC=$?
if [[ "$HK_RC" -ne 0 ]]; then hk_ciego "block-dangerous-commands.sh" "$HK_RC"; fi
[[ -z "$COMMAND" ]] && exit 0

ALLOWLIST_FILE="${HOME}/.claude/sentinel-allowlist.json"

command_allowlisted() {
  [[ -f "$ALLOWLIST_FILE" ]] || return 1
  if [ "$HK_JSON" = jq ]; then
    jq -e --arg cmd "$COMMAND" '(.commands // []) | index($cmd) != null' "$ALLOWLIST_FILE" >/dev/null 2>&1
  else
    # Pertenencia exacta a la lista, no subcadena: el equivalente literal del
    # `index($cmd) != null` de jq. Un fichero ilegible NO exime a nadie.
    python3 -c 'import json,sys
try: o = json.load(open(sys.argv[1]))
except Exception: sys.exit(1)
sys.exit(0 if sys.argv[2] in (o.get("commands") or []) else 1)' "$ALLOWLIST_FILE" "$COMMAND" 2>/dev/null
  fi
}

command_allowlisted && exit 0

# deny y ask son el MISMO protocolo con distinto veredicto, y el runtime los honra de
# forma distinta a como honra un exit 2: por eso este hook no se unifica con los otros
# tres. La rama de jq es la de siempre -- el literal pasa a --arg, que imprime los mismos
# bytes -- y la de python3 reproduce la sangria de 2 espacios con la que jq pretty-imprime.
veredicto() { # $1 deny|ask, $2 motivo
  if [ "$HK_JSON" = jq ]; then
    jq -n --arg d "$1" --arg r "$2" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: $d,
        permissionDecisionReason: $r
      }
    }'
  else
    python3 -c 'import json,sys
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": sys.argv[1],
    "permissionDecisionReason": sys.argv[2]}}, indent=2, ensure_ascii=False))' "$1" "$2"
  fi
  exit 0
}

deny() { veredicto deny "$1"; }
ask()  { veredicto ask  "$1"; }

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
  '\bcurl\b.*\|\s*(ba)?sh'            "BLOCKED: curl piped to shell (RCE)"
  '\bwget\b.*\|\s*(ba)?sh'            "BLOCKED: wget piped to shell (RCE)"
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
  '\bgit\b[^;&|]*\bpush\b[^;&|]*\s\+[^ ]*:'     "BLOCKED: git push +refspec (forced refspec)"
  '\bgit\b[^;&|]*\bpush\b[^;&|]*--mirror'       "BLOCKED: git push --mirror (can delete remote refs)"
  '\bgit\b[^;&|]*\bpush\b[^;&|]*--delete'       "BLOCKED: git push --delete (deletes a remote branch)"
  # Las otras dos grafias del mismo borrado. Medido: contra rama protegida las tres caian, pero
  # por branch-guard.sh --que bloquea por el NOMBRE de la rama--, no por esta regla; contra una
  # rama de feature `--delete` se denegaba y `-d` / `:rama` pasaban. Cubrir una sola grafia de un
  # borrado remoto es la misma trampa que dejaba pasar `git push -uf`: la proteccion se anuncia
  # entera y solo existe para la forma larga.
  #
  # La valla NO es la de las reglas de force (`[^;&|]*`). Con ella, estos dos patrones daban
  # falsos positivos medidos, porque `d` es una letra de flag mucho mas frecuente que `f`:
  # `git log --grep push --since=$(date -d ...)`, `git branch push-notifications -d`,
  # `git push origin main # nota :importante` y `git commit -m "fix push :bug" && git push`
  # se denegaban todos. Un guard que grita en falso se acaba desactivando, asi que aqui la
  # valla es una LISTA BLANCA de tokens de refspec: nada de `$`, parentesis, comillas ni `#`,
  # que es donde vivian los cuatro. Y `push` tiene que ser token suelto (`push[[:space:]]`),
  # porque `\bpush\b` emparejaba dentro de `push-notifications`. El precio, declarado: si el
  # flag llega por sustitucion (`git push $FLAGS`) no se ve -- limite general de leer el
  # literal en vez del argv, ya documentado en el kit.
  '\bgit\b[-A-Za-z0-9_./ =+@]*\bpush[[:space:]]+([-A-Za-z0-9_./=+@]+[[:space:]]+)*-[A-Za-z]*d[A-Za-z]*\b' "BLOCKED: git push -d (deletes a remote branch)"
  '\bgit\b[-A-Za-z0-9_./ =+@]*\bpush[[:space:]]+([-A-Za-z0-9_./=+@]+[[:space:]]+)*:[^[:space:]]' "BLOCKED: git push :rama (deletes a remote branch)"

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

  # ── MISC ───────────────────────────────────────────────────────────────────
  ':\(\)\s*\{.*\|'                    "BLOCKED: fork bomb pattern"
)

ASK_RULES=(
  # ── SYSTEM ADMINISTRATION (ASK — HITL) ─────────────────────────────────────
  '\bsystemctl\s+(stop|disable)\b'    "Confirm: systemctl stop/disable — may interrupt running services"
  '\bchmod\s+777'                     "Confirm: chmod 0777 sets world-writable permissions"
  '\bssh-keygen\b'                    "Confirm: ssh-keygen — will this overwrite an existing key?"

  # ── DATABASE OPERATIONS (ASK — HITL) ───────────────────────────────────────
  '\bDROP\s+DATABASE\b'   "Confirm: DROP DATABASE — irreversible data loss"
  '\bDROP\s+TABLE\b'      "Confirm: DROP TABLE — irreversible data loss"
  '\bTRUNCATE\s+TABLE\b'  "Confirm: TRUNCATE TABLE — deletes all rows permanently"

  # ── DOCKER DESTRUCTIVE (ASK — HITL) ────────────────────────────────────────
  '\bdocker\s+system\s+prune'  "Confirm: docker system prune — removes all unused containers/images"
  '\bdocker\s+volume\s+rm'     "Confirm: docker volume rm — permanent volume data loss"

  # ── PACKAGE PUBLISH / INSTALL FROM URL (ASK — HITL) ────────────────────────
  '\bnpm\s+publish'             "Confirm: npm publish — will publish to public npm registry"
  '\bpip\s+install\s+https?://' "Confirm: pip install from URL — verify source before installing"
)

UNION=''
for ((i = 0; i < ${#DENY_RULES[@]}; i += 2)); do UNION+="|${DENY_RULES[i]}"; done
for ((i = 0; i < ${#ASK_RULES[@]}; i += 2)); do UNION+="|${ASK_RULES[i]}"; done
# `|| exit 0` confundia "no ha emparejado" (grep rc=1) con "la regex no compila" (grep rc=2):
# un solo patron mal formado en la tabla convertia TODO el blocklist en un permiso silencioso,
# porque el error de grep sale por stderr y con exit 0 no se muestra. Se distinguen los dos.
echo "$COMMAND" | grep -qiE "${UNION#|}"
rc_union=$?
if [ "$rc_union" -ge 2 ]; then
  deny "BLOCKED: el blocklist no compila (grep rc=$rc_union); se deniega por seguridad"
fi
[ "$rc_union" -eq 0 ] || exit 0

for ((i = 0; i < ${#DENY_RULES[@]}; i += 2)); do
  echo "$COMMAND" | grep -qiE "${DENY_RULES[i]}" && deny "${DENY_RULES[i + 1]}"
done
for ((i = 0; i < ${#ASK_RULES[@]}; i += 2)); do
  echo "$COMMAND" | grep -qiE "${ASK_RULES[i]}" && ask "${ASK_RULES[i + 1]}"
done

exit 0
