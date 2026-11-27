#!/bin/bash
# guardlog.sh — registro unico de las decisiones deny/ask de los guards de Bash (JSONL). Se hace `source` desde los guards.
#
#   guardlog GUARD DECISION REGLA     (lee COMMAND y, para cwd y modo, el payload en GUARDLOG_PAYLOAD)
#
# Una linea por decision: ts (UTC), guard, decision, rule, cwd, mode (permission_mode si llego), unattended, tool, cmd. La orden va
# con los secretos enmascarados (filas de lib/secret-patterns mas asignaciones, Bearer y user:pass@) y despues truncada a 300
# caracteres: al reves, el corte podia dejar medio secreto sin forma de patron. Sin patrones legibles no se registra la orden.
# Ruta: CC_GUARD_LOG, o ~/.claude/audit-logs/guard-decisions.jsonl. Fail-open DEL REGISTRO: corre en un subshell sin set -e/-u y
# su fallo (sin jq, ruta no escribible...) no cambia el veredicto ni el codigo de salida del guard. Solo se llama en deny y ask.
_GUARDLOG_DIR=${BASH_SOURCE[0]%/*}

# stdin -> stdout con los secretos sustituidos por [SECRETO]; rc != 0 si no pudo enmascarar (el llamador no registra la orden).
guardlog_mask() {
  local pat=${GUARDLOG_PATTERNS:-$_GUARDLOG_DIR/secret-patterns} label ere w o c i d=$'\001'
  local -a args=()
  [[ -r $pat ]] || return 1
  while IFS=$'\t' read -r label _ ere; do
    [[ -z $label || $label == '#'* || -z $ere ]] && continue
    args+=(-e "s${d}${ere}${d}[SECRETO]${d}g")
  done < "$pat"
  (( ${#args[@]} )) || return 1
  # Sin la bandera I de sed (no es portable): cada letra va en su clase.
  ci() { o=; for (( i = 0; i < ${#1}; i++ )); do c=${1:i:1}; case $c in [a-z]) o+="[$c${c^^}]" ;; *) o+=$c ;; esac; done; REPLY=$o; }
  for w in pass password passwd secret token credential apikey api_key api-key; do
    # El valor puede ir entre comillas (`TOKEN='x y'`, JSON `"password":"x"`) o tras una opcion sin `=` (`--password x`).
    ci "$w"; args+=(-e "s${d}(${REPLY}[A-Za-z0-9_-]*[\"']?[[:space:]]*[=:][[:space:]]*)(\"[^\"]*\"|'[^']*'|[^[:space:]'\"]+)${d}\\1[SECRETO]${d}g"
      -e "s${d}(--?${REPLY}[A-Za-z0-9_-]*[[:space:]]+)(\"[^\"]*\"|'[^']*'|[^[:space:]'\"]+)${d}\\1[SECRETO]${d}g")
  done
  ci bearer; args+=(-e "s${d}(${REPLY}[[:space:]]+)[A-Za-z0-9._~+/=-]{8,}${d}\\1[SECRETO]${d}g")
  ci 'authorization: basic'; args+=(-e "s${d}(${REPLY}[[:space:]]+)[A-Za-z0-9+/=]+${d}\\1[SECRETO]${d}g")
  args+=(-e "s${d}((-u|--user)[[:space:]]+[^[:space:]:'\"]+:)[^[:space:]'\"]+${d}\\1[SECRETO]${d}g")
  args+=(-e "s${d}(://)[^/@[:space:]]+:[^/@[:space:]]+@${d}\\1[SECRETO]@${d}g")
  sed -E "${args[@]}"
}

guardlog() {
  (
    set +e +u
    command -v jq >/dev/null 2>&1 || exit 0
    local log=${CC_GUARD_LOG:-${HOME:-/nonexistent}/.claude/audit-logs/guard-decisions.jsonl}
    local cmd=${COMMAND-} rule=${3-} cwd mode tool unat=false
    # Una clave privada pegada ocupa varias lineas y solo la cabecera casa con un patron: del BEGIN en adelante todo es secreto.
    if [[ $cmd == *'PRIVATE KEY-----'* ]]; then cmd=${cmd%%-----BEGIN*}'[SECRETO]'; fi
    cmd=$(printf '%s' "$cmd" | guardlog_mask) || cmd='[orden omitida: no se pudo enmascarar]'
    rule=$(printf '%s' "$rule" | guardlog_mask) || rule=
    rule=${rule%%Que hacer:*}; rule=${rule#*BLOCKED*: }; rule=${rule#Confirm: }
    rule=${rule%%[.(:;]*}; rule=${rule:0:80}; rule=${rule%" "}
    (( ${#cmd} > 300 )) && cmd="${cmd:0:300}…"
    IFS=$'\t' read -r cwd mode tool < <(jq -r '[(.cwd // ""), (.permission_mode // ""), (.tool_name // "")] | map(if . == "" then "-" else gsub("[\t\n]"; " ") end) | join("\t")' <<<"${GUARDLOG_PAYLOAD-}" 2>/dev/null)
    [[ ${cwd-} == - || -z ${cwd-} ]] && cwd=$PWD
    [[ ${mode-} == - ]] && mode=
    [[ ${tool-} == - || -z ${tool-} ]] && tool=Bash
    [ "${CLAUDE_CODE_SESSION_ATTENDED:-}" = 0 ] || [ -n "${OPENRIG_OCCUPANT_GENERATION:-}" ] && unat=true
    mkdir -p "$(dirname "$log")" || exit 0
    jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg guard "$1" --arg decision "$2" --arg rule "$rule" --arg cwd "$cwd" \
      --arg mode "$mode" --argjson unat "$unat" --arg tool "$tool" --arg cmd "$cmd" \
      '{ts:$ts,guard:$guard,decision:$decision,rule:$rule,cwd:$cwd,mode:$mode,unattended:$unat,tool:$tool,cmd:$cmd}' >> "$log"
  ) >/dev/null 2>&1
  return 0
}
