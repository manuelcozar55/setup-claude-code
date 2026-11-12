#!/usr/bin/env bash
# Stop | PostCompact | SessionEnd — guardado sin modelo (ADR 028, capa 1): `handoff --auto` deja en nucleo.md la sección
# «Último turno (auto)» (ver bin/handoff). Un script para los tres eventos: el stdin trae hook_event_name, session_id,
# transcript_path y cwd, y el CLI decide el resto.
# PostCompact además mide las anclas del checkpoint (nucleo_compact_medir): solo log, sin systemMessage.
# Stop va con async:true y timeout 10, PostCompact con 8 y SessionEnd con 10 (settings.json): el timeout declarado manda; sin él
# SessionEnd se cancela a 1,5 s (medido en 2.1.311) y no escribe. El CLI se acota a 5 s por dentro.
# Solo el hilo principal (agent_id vacío). Nunca escribe en stdout (no inyecta contexto) y sale 0 siempre.
set -u
IN=$(cat)
AGENTE=$(jq -r '.agent_id // empty' <<<"$IN" 2>/dev/null) || AGENTE=""
[ -z "$AGENTE" ] || exit 0
# shellcheck source=SCRIPTDIR/lib/nucleo.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/nucleo.sh"
[ "$(jq -r '.hook_event_name // empty' <<<"$IN" 2>/dev/null)" != PostCompact ] || nucleo_compact_medir "$IN" || true
# `timeout` es el padre de handoff: sin esto la ranura de ~ (por pid de claude) no se encontraría.
P=$(nucleo_sesion_pid 2>/dev/null) && export CLAUDE_PID=$P
HO=$(dirname "${BASH_SOURCE[0]}")/../bin/handoff
[ -x "$HO" ] || HO=$HOME/.claude/bin/handoff
[ -x "$HO" ] || exit 0
printf '%s' "$IN" | timeout 5 "$HO" --auto --json >/dev/null 2>&1 || true
exit 0
