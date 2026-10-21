#!/usr/bin/env bash
set -euo pipefail
umask 077
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[ "$#" -eq 1 ] || { echo 'uso: aceptacion-local.sh DIRECTORIO_NUEVO'; exit 64; }
D=$(realpath -m -- "$1")
[ ! -e "$D" ] && [ ! -L "$D" ] || { echo 'el directorio de artefactos debe ser nuevo'; exit 64; }
mkdir -- "$D"
exec > >(tee "$D/aceptacion.log") 2>&1
trap 'rc=$?; printf "FAIL linea=%s rc=%s\n" "$LINENO" "$rc"; exit "$rc"' ERR
export CLAUDE_HOME=$D/install NUCLEO_REGISTRO=$D/raices GITLEAKS_AUTO_INSTALL=0
unset CLAUDE_PROJECT_DIR
R=$D/project
mkdir -p "$R"
cd "$R"
sanear() {
  local linea
  while IFS= read -r linea || [ -n "$linea" ]; do
    linea=${linea//"$D"/'<ARTEFACTOS>'}
    printf '%s\n' "${linea//"$HOME"/'<HOME>'}"
  done
}
ejecutar() {
  local nombre=$1 esperado=$2 rc
  shift 2
  if (trap - ERR; "$@") 2>&1 | sanear > "$D/$nombre.log"; then rc=0
  else rc=${PIPESTATUS[0]}; fi
  printf '%s rc=%s esperado=%s\n' "$nombre" "$rc" "$esperado"
  [ "$rc" -eq "$esperado" ]
}
comprobar() {
  local nombre=$1
  shift
  "$@" || { echo "FAIL $nombre"; return 1; }
  echo "PASS $nombre"
}
ejecutar instalar 0 bash "$REPO/kit/install.sh" </dev/null
cp "$CLAUDE_HOME/settings.json" "$D/settings-original.json"
jq --arg destino "$CLAUDE_HOME" 'walk(if type == "string" then gsub("\\$HOME/\\.claude"; $destino) else . end)' \
  "$D/settings-original.json" > "$CLAUDE_HOME/settings.json"
echo "Fixture: rutas \$HOME/.claude de settings.json apuntan a CLAUDE_HOME; original conservado."
ejecutar doctor 0 bash "$REPO/kit/doctor.sh"
git init -q
git -c user.name=Aceptacion -c user.email=test@example.com commit -qm inicial --allow-empty
H=$CLAUDE_HOME/hooks
CLI=$CLAUDE_HOME/bin/handoff
E=$R/.claude/estado
S1=aceptacion-primera S2=aceptacion-segunda
ejecutar iniciar 0 bash "$CLI" --iniciar --raiz "$R"
cat > "$D/primero.md" <<'EOF'
# Estado
## Objetivo
OBJETIVO-PERSISTENTE
## Invariantes
- INVARIANTE-PERSISTENTE
## Paso actual
PRIMERA-SESION
## Siguiente acción
SEGUNDA-SESION
## Pendientes
- PENDIENTE-PERSISTENTE
## Comandos de verificación
- aceptación local
EOF
cat > "$D/segundo.md" <<'EOF'
## Paso actual
SEGUNDA-SESION
## Siguiente acción
CONTINUIDAD-VERIFICADA
EOF
ejecutar guardar-primero 0 bash "$CLI" --desde "$D/primero.md" --solo --raiz "$R" --sesion "$S1"
jq -cn '{type:"user",message:{content:"PROMPT-SINTETICO-CONSERVADO"}}' > "$D/transcript.jsonl"
jq -cn '{type:"assistant",message:{usage:{input_tokens:1000},content:[]}}' >> "$D/transcript.jsonl"
evento() {
  jq -cn --arg r "$R" --arg s "$1" --arg source "$2" --arg tp "$D/transcript.jsonl" \
    '{cwd:$r,session_id:$s,source:$source,trigger:"manual",transcript_path:$tp}'
}
evento "$S1" startup > "$D/startup.json"
ejecutar startup 0 bash "$H/session-start-clear.sh" < "$D/startup.json"
ejecutar propietario 0 bash "$CLI" --estado --raiz "$R" --sesion "$S1"
comprobar propietario-primero jq -e --arg s "$S1" ".dueno.sesion == \$s" "$D/propietario.log"
ejecutar precompact 0 bash "$H/pre-compact.sh" < "$D/startup.json"
CP=$E/checkpoints/checkpoint-compact-$(printf '%s' "$S1" | sha256sum | cut -d' ' -f1).md
comprobar checkpoint-contiene-prompt grep -q PROMPT-SINTETICO-CONSERVADO "$CP"
for ev in SubagentStart SubagentStop; do
  jq -cn --arg r "$R" --arg s "$S1" --arg ev "$ev" --arg tp "$D/transcript.jsonl" \
    '{cwd:$r,session_id:$s,hook_event_name:$ev,agent_id:"aceptacion-agente",agent_type:"worker",agent_transcript_path:$tp,last_assistant_message:"turno sintético"}' > "$D/$ev.json"
  ejecutar "$ev" 0 bash "$H/agentes.sh" < "$D/$ev.json"
done
jq '. + {background_tasks:[{id:"aceptacion-agente",type:"subagent",status:"running"}]}' "$D/startup.json" > "$D/stop.json"
ejecutar foto 0 bash "$H/stop-context-gauge.sh" < "$D/stop.json"
ejecutar agentes 0 bash "$CLI" --agentes --raiz "$R"
comprobar agente-en-vuelo grep -q 'en vuelo' "$D/agentes.log"
ejecutar estado-primera 0 bash "$CLI" --estado --raiz "$R" --sesion "$S1"
ejecutar estado-segunda 0 bash "$CLI" --estado --raiz "$R" --sesion "$S2"
comprobar conteo-propio jq -e '.agentes_vivos == 1' "$D/estado-primera.log"
comprobar conteo-ajeno jq -e '.agentes_vivos == 0' "$D/estado-segunda.log"
evento "$S1" compact > "$D/compact.json"
ejecutar compact 0 bash "$H/session-start-compact.sh" < "$D/compact.json"
comprobar contexto-completo jq -e '.hookSpecificOutput.additionalContext | contains("OBJETIVO-PERSISTENTE") and contains("PROMPT-SINTETICO-CONSERVADO") and contains("<agentes>") and contains("</agentes>") and (length <= 9500)' "$D/compact.log"
jq '. + {hook_event_name:"SessionEnd",reason:"aceptacion"}' "$D/startup.json" > "$D/end.json"
ejecutar SessionEnd 0 bash "$H/agentes.sh" < "$D/end.json"
ejecutar agentes-cierre 0 bash "$CLI" --agentes --raiz "$R"
comprobar cierre-agente grep -q 'cortado al cerrar' "$D/agentes-cierre.log"
ejecutar estado-tras-cierre 0 bash "$CLI" --estado --raiz "$R" --sesion "$S1"
comprobar cierre-libera-propietario jq -e '.dueno == null' "$D/estado-tras-cierre.log"
ejecutar retomar-primera 0 bash "$H/session-start-clear.sh" < "$D/startup.json"
ANTES=$(sha256sum "$E/nucleo.md")
ejecutar rechazo-ajeno 5 bash "$CLI" --desde "$D/segundo.md" --raiz "$R" --sesion "$S2"
comprobar rechazo-no-pierde-estado test "$ANTES" = "$(sha256sum "$E/nucleo.md")"
ejecutar liberar-ajeno 5 bash "$CLI" --liberar "$S2" --raiz "$R"
ejecutar liberar-propio 0 bash "$CLI" --liberar "$S1" --raiz "$R"
comprobar liberar-conserva-estado test "$ANTES" = "$(sha256sum "$E/nucleo.md")"
evento "$S2" startup > "$D/startup-segunda.json"
ejecutar startup-segunda 0 bash "$H/session-start-clear.sh" < "$D/startup-segunda.json"
ejecutar propietario-segunda 0 bash "$CLI" --estado --raiz "$R" --sesion "$S2"
comprobar propietario-segunda jq -e --arg s "$S2" ".dueno.sesion == \$s" "$D/propietario-segunda.log"
ejecutar guardar-segunda 0 bash "$CLI" --desde "$D/segundo.md" --raiz "$R" --sesion "$S2"
for marca in OBJETIVO-PERSISTENTE INVARIANTE-PERSISTENTE PENDIENTE-PERSISTENTE CONTINUIDAD-VERIFICADA; do
  comprobar "$marca" grep -q "$marca" "$E/nucleo.md"
done
ejecutar estado-final 0 bash "$CLI" --estado --raiz "$R" --sesion "$S2"
comprobar cierre-libera-dueno jq -e '.dueno == null' "$D/estado-final.log"
comprobar perfil-logs-aislados test -s "$CLAUDE_HOME/session-logs/nucleo-freshness.log"
cp "$E/nucleo.md" "$D/nucleo-final.md"
printf 'PASS aceptación local: instalación, hooks, agentes y continuidad entre dos sesiones\n'
printf 'exit=0\n'
