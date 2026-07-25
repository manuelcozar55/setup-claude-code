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

chk() {
  if echo "$COMMAND" | grep -qiE "$1"; then
    deny "$2"
  fi
}

ask_chk() {
  if echo "$COMMAND" | grep -qiE "$1"; then
    ask "$2"
  fi
}

# ── DESTRUCTIVE FILE/DISK (HARD DENY) ────────────────────────────────────────
chk '\brm\s+-[a-z]*r[a-z]*f'            "BLOCKED: rm -rf (recursive force delete)"
chk '\brm\s+-[a-z]*f[a-z]*r'            "BLOCKED: rm -fr (recursive force delete)"
chk '\bshred\b'                          "BLOCKED: shred (secure file destruction)"
chk '\bdd\s+.*\bof=/dev/[hsv][da]'      "BLOCKED: dd write to block device"
chk '\bmkfs\b'                           "BLOCKED: mkfs (format filesystem)"
chk '\bfdisk\b'                          "BLOCKED: fdisk (partition table editor)"
chk '\bwipefs\b'                         "BLOCKED: wipefs (wipe filesystem signatures)"
chk '>\s*/dev/sd'                        "BLOCKED: redirect to block device"

# ── SYSTEM SHUTDOWN/REBOOT (HARD DENY) ───────────────────────────────────────
chk '(^|[;&|]\s*)(sudo\s+)?reboot\b'    "BLOCKED: reboot"
chk '(^|[;&|]\s*)(sudo\s+)?shutdown\b'  "BLOCKED: shutdown"
chk '(^|[;&|]\s*)(sudo\s+)?halt\b'      "BLOCKED: halt"
chk '(^|[;&|]\s*)(sudo\s+)?poweroff\b'  "BLOCKED: poweroff"
chk '\binit\s+[06]\b'                   "BLOCKED: init 0/6 (shutdown/reboot)"

# ── NETWORK / REMOTE CODE EXECUTION (HARD DENY) ──────────────────────────────
chk '\biptables\s+-F'                   "BLOCKED: iptables -F (flush firewall)"
chk '\bufw\s+disable'                   "BLOCKED: ufw disable"
chk '\bcurl\b.*\|\s*(ba)?sh'            "BLOCKED: curl piped to shell (RCE)"
chk '\bwget\b.*\|\s*(ba)?sh'            "BLOCKED: wget piped to shell (RCE)"
chk '\bnc\s+-[a-z]*l'                   "BLOCKED: netcat listener (reverse shell)"
chk '/dev/tcp/'                         "BLOCKED: /dev/tcp (reverse shell)"
chk '/dev/udp/'                         "BLOCKED: /dev/udp (reverse shell)"

# ── SSH DIRECTORY TAMPERING (HARD DENY) ──────────────────────────────────────
chk '(>|>>)\s*\S*/\.ssh/'              "BLOCKED: redirect to .ssh directory"
chk '\btee\s+\S*\.ssh/'                "BLOCKED: tee to .ssh directory"

# ── GIT FORCE PUSH (HARD DENY) ───────────────────────────────────────────────
chk '\bgit\s+push\s+.*--force'          "BLOCKED: git push --force"
chk '\bgit\s+push\s+(-f\b|.*\s-f\b)'   "BLOCKED: git push -f (force push)"

# ── CREDENTIAL EXFILTRATION (HARD DENY) ──────────────────────────────────────
chk '\b(printenv|env)\b.*\|\s*(curl|nc|wget)\b'   "BLOCKED: env vars leaked to network"
chk '\bcat\b.*\.env.*\|\s*(curl|nc|wget)\b'       "BLOCKED: .env file leaked to network"
chk '\b(printenv|env)\b.*>\s*/dev/tcp/'            "BLOCKED: env via /dev/tcp"
chk 'base64\s*(-d|--decode).*\|\s*(ba)?sh'        "BLOCKED: base64-decoded payload to shell"

# ── SUPPLY CHAIN — URL EXECUTION (HARD DENY) ─────────────────────────────────
chk '\bnpx\s+https?://'                  "BLOCKED: npx from URL (supply chain / RCE risk)"
chk '\bpnpm\s+dlx\s+https?://'           "BLOCKED: pnpm dlx from URL (supply chain risk)"
chk '\bdeno\s+(run|install)\s+https?://' "BLOCKED: deno run/install from URL"
chk '\bbun\s+(x|run)\s+https?://'        "BLOCKED: bun x/run from URL (supply chain risk)"

# ── MISC (HARD DENY) ─────────────────────────────────────────────────────────
chk ':\(\)\s*\{.*\|'                    "BLOCKED: fork bomb pattern"

# ── SYSTEM ADMINISTRATION (ASK — HITL) ───────────────────────────────────────
ask_chk '\bsystemctl\s+(stop|disable)\b'    "Confirm: systemctl stop/disable — may interrupt running services"
ask_chk '\bchmod\s+777'                     "Confirm: chmod 0777 sets world-writable permissions"
ask_chk '\bssh-keygen\b'                    "Confirm: ssh-keygen — will this overwrite an existing key?"

# ── DATABASE OPERATIONS (ASK — HITL) ─────────────────────────────────────────
ask_chk '\bDROP\s+DATABASE\b'   "Confirm: DROP DATABASE — irreversible data loss"
ask_chk '\bDROP\s+TABLE\b'      "Confirm: DROP TABLE — irreversible data loss"
ask_chk '\bTRUNCATE\s+TABLE\b'  "Confirm: TRUNCATE TABLE — deletes all rows permanently"

# ── DOCKER DESTRUCTIVE (ASK — HITL) ──────────────────────────────────────────
ask_chk '\bdocker\s+system\s+prune'  "Confirm: docker system prune — removes all unused containers/images"
ask_chk '\bdocker\s+volume\s+rm'     "Confirm: docker volume rm — permanent volume data loss"

# ── PACKAGE PUBLISH / INSTALL FROM URL (ASK — HITL) ─────────────────────────
ask_chk '\bnpm\s+publish'             "Confirm: npm publish — will publish to public npm registry"
ask_chk '\bpip\s+install\s+https?://' "Confirm: pip install from URL — verify source before installing"

exit 0
