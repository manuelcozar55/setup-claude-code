#!/bin/bash
# block-dangerous-commands.sh — PreToolUse Bash security blocklist
# Source: randomdreft/claude-code-security-hook (public domain), extended
# Protocol: JSON deny/ask output + exit 0, or silent exit 0 to allow

set -uo pipefail

COMMAND=$(jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0

ALLOWLIST_FILE="${HOME}/.claude/sentinel-allowlist.json"

command_allowlisted() {
  [[ -f "$ALLOWLIST_FILE" ]] || return 1
  jq -e --arg cmd "$COMMAND" '(.commands // []) | index($cmd) != null' "$ALLOWLIST_FILE" >/dev/null 2>&1
}

command_allowlisted && exit 0

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
echo "$COMMAND" | grep -qiE "${UNION#|}" || exit 0

for ((i = 0; i < ${#DENY_RULES[@]}; i += 2)); do
  echo "$COMMAND" | grep -qiE "${DENY_RULES[i]}" && deny "${DENY_RULES[i + 1]}"
done
for ((i = 0; i < ${#ASK_RULES[@]}; i += 2)); do
  echo "$COMMAND" | grep -qiE "${ASK_RULES[i]}" && ask "${ASK_RULES[i + 1]}"
done

exit 0
