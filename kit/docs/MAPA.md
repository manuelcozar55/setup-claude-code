# Mapa del kit

> Generado por `scripts/generar-mapa.sh` desde `kit/claude/settings.json` y el código. No lo edites a mano:
> cambia el código (o `scripts/mapa-interruptores.tsv`) y regenera. `kit/test/test_mapa.sh` falla si no coincide.

## Hooks cableados

Cada fila es una entrada de `settings.json`. Todos terminan sin bloquear salvo los guards, que bloquean con un mensaje que dice qué hacer.
Para quitar un hook, bórralo de `~/.claude/settings.json` y anota el script en `~/.claude/.kit-desactivados` (ver `OPERAR.md`).

| Evento | Matcher | Script | Qué hace | Variables que lee | Cómo se apaga |
|---|---|---|---|---|---|
| PreToolUse | — | `sentinel_preflight.py` | Deniega leer o enviar ficheros de credenciales (.env, ~/.ssh, ~/.aws), patrones de exfiltracion y comandos peligrosos en CUALQUIER herramienta; pregunta si agota su presupuesto de analisis; deja pasar el texto que solo nombra un fichero como dato (echo, git rm --cached) en una linea de una sola orden. | `CC_WARN_DIR`, `PYTHON_HOOK_BIN` | `CC_WARN_DIR`: cambia dónde anota los avisos; `PYTHON_HOOK_BIN`: elige el intérprete de Python |
| PreToolUse | `Bash` | `block-dangerous-commands.sh` | Deniega pipe-a-shell, rm -rf sin prueba de inocuidad, force push y --no-verify, -c core.hooksPath y exfiltracion de credenciales; pregunta ante un lease a una rama de trabajo, un rm -rf de un build, --tags o git config de hooks; deja pasar el texto que solo es dato (echo, mensaje de commit, patron de grep) en una linea de una sola orden. | `CC_SAFE_DELETE_DIRS` | solo quitándolo de `settings.json` |
| PreToolUse | `Bash` | `branch-guard.sh` | Deniega git push a las ramas protegidas (main, master, production; CC_PROTECT_BRANCHES) aunque vaya con refspec, HEAD, +rama o dentro de bash -c; falla cerrado si no puede analizar la orden; deja pasar los push a ramas de trabajo y todo lo que no sea git push. | `CC_PROTECT_BRANCHES`, `CC_SAFE_DELETE_DIRS` | `CC_PROTECT_BRANCHES`: cambia las ramas protegidas (por defecto `main:master:production`) |
| PreToolUse | `Bash` | `destructive-guard.sh` | Deniega rm -rf de rutas sensibles (home, /, .., comodines, enlaces), find -delete amplio, git reset --hard y git clean; deja pasar rm -rf de un directorio de build probado (CC_SAFE_DELETE_DIRS) y el texto que solo menciona esos comandos; CC_ALLOW_DESTRUCTIVE=1 lo apaga. | `CC_ALLOW_DESTRUCTIVE`, `CC_BLOCK_LOG`, `CC_SAFE_DELETE_DIRS` | `CC_ALLOW_DESTRUCTIVE`: `CC_ALLOW_DESTRUCTIVE=1` en el entorno de la sesión apaga el guard entero (no vale como prefijo de una orden); `CC_BLOCK_LOG`: cambia el fichero donde anota lo que bloquea (por defecto `audit-logs/blocked-commands.log`); `CC_SAFE_DELETE_DIRS`: amplía los directorios que se pueden borrar sin avisar |
| PreToolUse | `Bash` | `secret-guard.sh` | Deniega git add de .env, credenciales y claves privadas (por nombre, patron o comodin) y git add -A/. con un .env sin ignorar; deja pasar el resto de git add; el contenido de lo que se commitea lo mira el pre-commit con gitleaks (Capa 2). | `CC_SAFE_DELETE_DIRS` | solo quitándolo de `settings.json` |
| PreToolUse | `Bash` | `bash-write-guard.sh` | Deniega una orden que ESCRIBE un secreto (clave privada, token, clave de API) con cat > f <<EOF, echo >>, tee o sed -i; deja pasar las que no escriben (no hay > ni << ni tee ni sed) y el texto sin patron de secreto. | — | solo quitándolo de `settings.json` |
| PreToolUse | `Read` | `stale-read-guard.py` | avisa, sin bloquear, cuando se va a releer un fichero que esta misma sesión ya editó. | `CC_WARN_DIR`, `PYTHON_HOOK_BIN` | `CC_WARN_DIR`: cambia dónde anota los avisos; `PYTHON_HOOK_BIN`: elige el intérprete de Python |
| PreToolUse | `Write\|Edit\|MultiEdit\|NotebookEdit` | `write-guard.py` | escanea lo que Write, Edit, MultiEdit y NotebookEdit van a escribir en busca de secretos: avisa y bloquea los de alta confianza. | `CC_WARN_DIR`, `PYTHON_HOOK_BIN` | `CC_WARN_DIR`: cambia dónde anota los avisos; `PYTHON_HOOK_BIN`: elige el intérprete de Python |
| PostToolUse | `mcp__.*` | `narthex-post-mcp.py` | revisa lo que devuelve una herramienta MCP de terceros en busca de inyección de instrucciones (Unicode invisible, frases de jailbreak) y avisa al modelo, sin bloquear; anota en audit-logs/narthex.jsonl. | `CC_WARN_DIR`, `PYTHON_HOOK_BIN` | `CC_WARN_DIR`: cambia dónde anota los avisos; `PYTHON_HOOK_BIN`: elige el intérprete de Python |
| PostToolUse | — | `nucleo-nudge.sh` | avisa del consumo de contexto: al modelo al 50, 70 y 85 % del airbag (que guarde el estado) y a la persona al 60 y 85 % (que cierre fase), una vez por banda y sesión. | `CLAUDE_HOME`, `COCKPIT_AUTO_HANDOFF`, `NUCLEO_COCKPIT`, `NUCLEO_DUENO_TTL`, `NUCLEO_GATE`, `NUCLEO_REGISTRO`, `NUCLEO_TOPE`, `NUCLEO_VINCULO` | `NUCLEO_COCKPIT`: fuerza «hay cockpit» (`1`) o «no hay» (`0`) |
| SessionStart | — | `session-start.sh` | al empezar la sesión imprime una línea de señal de vida con las entradas de memoria del proyecto y avisa si el índice MEMORY.md pasa de 60 líneas. | — | solo quitándolo de `settings.json` |
| SessionStart | `startup\|clear\|resume` | `session-start-clear.sh` | al arrancar, limpiar o reanudar inyecta nucleo.md como dato para retomar el trabajo, y avisa si la caché caducó o si otra sesión es dueña del estado. | `CLAUDE_HOME`, `NUCLEO_COCKPIT`, `NUCLEO_DUENO_TTL`, `NUCLEO_GATE`, `NUCLEO_REGISTRO`, `NUCLEO_TOPE`, `NUCLEO_VINCULO` | solo quitándolo de `settings.json` |
| SessionStart | `compact` | `session-start-compact.sh` | tras compactar re-inyecta nucleo.md por secciones y el checkpoint que dejó pre-compact.sh (recortado a 1 500 bytes), envueltos como datos. | `CLAUDE_HOME`, `NUCLEO_COCKPIT`, `NUCLEO_DUENO_TTL`, `NUCLEO_GATE`, `NUCLEO_REGISTRO`, `NUCLEO_TOPE`, `NUCLEO_VINCULO` | solo quitándolo de `settings.json` |
| PreCompact | `manual\|auto` | `pre-compact.sh` | deja un checkpoint determinista en .claude/estado/checkpoints/ antes de compactar y anota si nucleo.md llegaba fresco a la compactación. | `CLAUDE_HOME`, `NUCLEO_CHECKPOINT_KEEP`, `NUCLEO_COCKPIT`, `NUCLEO_DUENO_TTL`, `NUCLEO_GATE`, `NUCLEO_REGISTRO`, `NUCLEO_TOPE`, `NUCLEO_VINCULO` | `NUCLEO_CHECKPOINT_KEEP`: cuántos checkpoints se conservan por proyecto |
| PostCompact | — | `autosave.sh` | guarda sin modelo la sección «Último turno (auto)» de nucleo.md al terminar el turno, tras compactar y al cerrar la sesión; no escribe nada en la conversación. | `CLAUDE_HOME`, `NUCLEO_COCKPIT`, `NUCLEO_DUENO_TTL`, `NUCLEO_GATE`, `NUCLEO_REGISTRO`, `NUCLEO_TOPE`, `NUCLEO_VINCULO` | solo quitándolo de `settings.json` |
| Stop | — | `agentes.sh` | registra cada subagente (inicio, fin e informe) en .claude/estado/agentes.jsonl y, en el Stop, anota si hubo un commit sin actualizar nucleo.md (solo bloquea con NUCLEO_GATE=block). | `CLAUDE_HOME`, `NUCLEO_COCKPIT`, `NUCLEO_DUENO_TTL`, `NUCLEO_GATE`, `NUCLEO_REGISTRO`, `NUCLEO_TOPE`, `NUCLEO_VINCULO` | solo quitándolo de `settings.json` |
| Stop | — | `autosave.sh` | guarda sin modelo la sección «Último turno (auto)» de nucleo.md al terminar el turno, tras compactar y al cerrar la sesión; no escribe nada en la conversación. | `CLAUDE_HOME`, `NUCLEO_COCKPIT`, `NUCLEO_DUENO_TTL`, `NUCLEO_GATE`, `NUCLEO_REGISTRO`, `NUCLEO_TOPE`, `NUCLEO_VINCULO` | solo quitándolo de `settings.json` |
| SubagentStart | — | `agentes.sh` | registra cada subagente (inicio, fin e informe) en .claude/estado/agentes.jsonl y, en el Stop, anota si hubo un commit sin actualizar nucleo.md (solo bloquea con NUCLEO_GATE=block). | `CLAUDE_HOME`, `NUCLEO_COCKPIT`, `NUCLEO_DUENO_TTL`, `NUCLEO_GATE`, `NUCLEO_REGISTRO`, `NUCLEO_TOPE`, `NUCLEO_VINCULO` | solo quitándolo de `settings.json` |
| SubagentStop | — | `agentes.sh` | registra cada subagente (inicio, fin e informe) en .claude/estado/agentes.jsonl y, en el Stop, anota si hubo un commit sin actualizar nucleo.md (solo bloquea con NUCLEO_GATE=block). | `CLAUDE_HOME`, `NUCLEO_COCKPIT`, `NUCLEO_DUENO_TTL`, `NUCLEO_GATE`, `NUCLEO_REGISTRO`, `NUCLEO_TOPE`, `NUCLEO_VINCULO` | solo quitándolo de `settings.json` |
| SessionEnd | — | `agentes.sh` | registra cada subagente (inicio, fin e informe) en .claude/estado/agentes.jsonl y, en el Stop, anota si hubo un commit sin actualizar nucleo.md (solo bloquea con NUCLEO_GATE=block). | `CLAUDE_HOME`, `NUCLEO_COCKPIT`, `NUCLEO_DUENO_TTL`, `NUCLEO_GATE`, `NUCLEO_REGISTRO`, `NUCLEO_TOPE`, `NUCLEO_VINCULO` | solo quitándolo de `settings.json` |
| SessionEnd | — | `autosave.sh` | guarda sin modelo la sección «Último turno (auto)» de nucleo.md al terminar el turno, tras compactar y al cerrar la sesión; no escribe nada en la conversación. | `CLAUDE_HOME`, `NUCLEO_COCKPIT`, `NUCLEO_DUENO_TTL`, `NUCLEO_GATE`, `NUCLEO_REGISTRO`, `NUCLEO_TOPE`, `NUCLEO_VINCULO` | solo quitándolo de `settings.json` |

## Variables de entorno

Todas las que leen los hooks, las órdenes de `bin/` y Sentinel con un valor por defecto, y quién las lee.

| Variable | La leen |
|---|---|
| `CC_ALLOW_DESTRUCTIVE` | `destructive-guard.sh` |
| `CC_BLOCK_LOG` | `destructive-guard.sh` |
| `CC_PROTECT_BRANCHES` | `branch-guard.sh` |
| `CC_SAFE_DELETE_DIRS` | `cmdnorm.sh` |
| `CC_WARN_DIR` | `optional-hook.sh` |
| `CLAUDE_HOME` | `agentes.sh`, `efectividad`, `handoff`, `nucleo-nudge.sh`, `nucleo.sh`, `pre-compact.sh`, `session-start-compact.sh` |
| `COCKPIT_AUTO_HANDOFF` | `nucleo-nudge.sh` |
| `CUPO_UMBRAL` | `cupo` |
| `NUCLEO_AUTOINICIO` | `handoff` |
| `NUCLEO_CHECKPOINT_KEEP` | `pre-compact.sh` |
| `NUCLEO_COCKPIT` | `nucleo.sh` |
| `NUCLEO_DUENO_TTL` | `nucleo.sh` |
| `NUCLEO_FUSION_PAUSA` | `handoff` |
| `NUCLEO_GATE` | `nucleo.sh` |
| `NUCLEO_REGISTRO` | `nucleo.sh` |
| `NUCLEO_TOPE` | `nucleo.sh` |
| `NUCLEO_VINCULO` | `nucleo.sh` |
| `PYTHON_HOOK_BIN` | `optional-hook.sh` |

## Agentes

| Agente | Para qué |
|---|---|
| `code-explorer` | Deeply analyzes one existing codebase feature by tracing execution paths, mapping architecture layers, and documenting dependencies. |
| `code-reviewer` | Expert code review specialist. |
| `deep-worker` | Use for autonomous end-to-end implementation when scope is already clear. |
| `pr-test-analyzer` | Reviews whether the tests in a pull request or diff cover the new behavior and its edge cases. |
| `quick-checker` | Fast, cheap verification for routine checks. |
| `security-reviewer` | Security vulnerability detection specialist. |
| `silent-failure-hunter` | Audits a diff for silent failures: swallowed exceptions, broad catch blocks, fallbacks that mask errors, and shell commands that hide failures. |

## Skills

| Skill | Para qué |
|---|---|
| `deep-change` | Plan, execute and verify substantial code or configuration changes with an approved plan in nucleo.md, evidence-backed commits and isolated validation. |
| `retro` | Conduct a retrospective on a coding session. |
| `verification-before-completion` | Use before saying work is done, fixed or passing, and before committing or opening a PR: run the command that proves the claim and read its real exit code and output first. |

## Órdenes de `~/.claude/bin`

| Orden | Qué hace |
|---|---|
| `cupo` | comprobación previa a una sesión autónoma larga: ¿queda cupo de suscripción? Válido donde haya `claude`. |
| `efectividad` | cifras de uso real de scc leídas de los transcripts y del log de frescura de nucleo.md. |
| `handoff` | el estado de un proyecto (.claude/estado/nucleo.md) entre sesiones. |
| `oraculo` | ejecuta una verificación y dice la verdad sobre su rc. |
| `scc` | lanza Claude Code con el cockpit y los plugins del kit cargados desde la copia que install.sh deja en $CLAUDE_HOME/scc/ (no depende de donde este el clon). |

## Órdenes del cockpit (mod opcional)

| Orden | Qué hace |
|---|---|
| `/autonomo` | Tras un handoff sigue solo con el trabajo ya autorizado, sin esperar tu Enter: /autonomo on\|off |
| `/dock` | Abre el panel de agentes (Agent Dock): subagentes en marcha, misión y tamaño del equipo |
| `/simple` | Activa o desactiva el modo simple: tu tarea como lista de pasos con barra y respuestas cortas |
| `/handoff` | Guarda el estado de la tarea en .claude/estado/nucleo.md y limpia el contexto (/clear) para seguir en una sesión nueva |
| `/nueva` | Cambia de tarea: archiva el estado de la actual, limpia el contexto y deja la tarea nueva escrita en el prompt |
| `/autosave` | Guardado automático del estado en segundo plano con el modelo (gasta tokens; apagado por defecto): /autosave on\|off\|status |
