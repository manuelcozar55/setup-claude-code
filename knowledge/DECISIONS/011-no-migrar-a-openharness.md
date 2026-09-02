# ADR 011 — No migrar a OpenHarness: se roban cinco ideas, no la base

**Fecha:** 2026-08-27 · **Estado:** aceptada · **Revisa:** EVAL-CRITERIA.md, «¿Partir de
otra base?»

## Contexto

El encargo pedía decidir **de qué base partir** para el harness definitivo, y después,
explícitamente, si merecía la pena migrar este setup —o lo más interesante de él— a un
**OpenHarness personalizado**. Se revisó con subagentes independientes, en paralelo, junto
a `deepseek-ai/deepseek-harness`, AVO, NVIDIA SkillEvaluator y NVIDIA-NeMo/labs-OO-Agents.

`HKUDS/OpenHarness` (MIT, Python, 15 548 ★, 2 532 forks) no es una librería que se añade:
es un **reemplazo completo del CLI**, agnóstico de proveedor (Claude, Kimi, GLM, OpenAI,
Copilot, Ollama), con daemon, gateway a Telegram/Slack y modo *swarm*.

## Decisión

**No migrar.** Se queda Claude Code como sustrato y este repo como capa de harness. Se
adoptan ideas concretas, cada una con su sensor.

## Por qué

Tres datos verificados el 2026-08-27 mandan sobre el resto:

1. **Está parado.** Último commit el 2026-06-04, ~12 semanas atrás; 51 PRs y 33 issues
   abiertos. Las estrellas suben, el código no.
2. **Cuatro issues de seguridad abiertas sin un solo comentario**: file tools no
   contenidas al workspace (#310), `allowed_tools` saltándose las deny-rules (#313),
   bypass por *parameter shadowing* (#348) y un hook que ejecuta PowerShell arbitrario en
   `full_auto` (#349). Son exactamente los agujeros que aquí tapan los guards y Sentinel.
3. **Sin API key propia, el único camino es un bridge que lee las credenciales de Claude
   Code.** El riesgo de cuenta es asimétrico y su encaje con los ToS **no está
   verificado**.

Y sobre el experimento, que es lo que este repo defiende: se leyó su `cli.py` (2 551
líneas) y **ninguna** de las cuatro banderas de las que dependen los brazos existe allí.
Migrar mata E1 (dos brazos), E22 (ablación), E23 (el flag tiene que seguir existiendo) y
los mutantes M9 y M12. Un `grep` de `eval|mutat|ablat` sobre sus 480 blobs devuelve tres
ficheros, todos de un skill llamado `harness-eval`: **cero mutantes**.

Coste estimado, que es lo que decide:

| Opción | Trabajo | Qué se pierde |
|---|---|---|
| Migrar entero | 100–150 h | E1, E22, E23, M9, M12; 3 041 LOC de suites a reescribir; el pinning por SHA de `install.sh`; auth sin intermediario; y el estado "todo verde" durante toda la travesía |
| Parcial: evals multi-proveedor | 25–40 h | Se estrella contra el propio **E24**: `report.py:comparables()` se niega a restar brazos con modelos distintos. No da un lift, da N experimentos sueltos |
| **Robar cinco ideas** | **8–14 h** | Nada |

## Lo que sí se roba (cada una con sensor, o no entra)

1. **El orden de los guards como contrato.** Hoy los 7 `PreToolUse` dependen del orden del
   JSON: `smart_approve.py` podría adelantar a `secret-guard.sh` sin que nadie se entere.
2. **Un núcleo CRITICAL que la allowlist no puede anular.** *"Nunca amplíes la allowlist"*
   es hoy una guía **sin sensor**, y este repo dice que eso se pudre.
3. **Corpus de evasión de rutas con `known-gap` declarados**, para medir el agujero que
   `CLAUDE.md` ya confiesa en vez de dejarlo escrito.
4. **Huérfanos en `knowledge/`**: 18 762 palabras y ningún sensor detecta el fichero que
   ya no carga nadie.
5. **`DRYRUN=1` en `run.sh`**: el "40 llamadas / ~12 USD" del Makefile está escrito a mano
   — otra afirmación sin sensor.

Descartado por no sensorizable aquí: *swarm*, gateway, TUI/voz/temas, `soul.md` y su
`personalization/extractor.py` (memoria auto-escrita, que choca de frente con la regla de
que `knowledge/` es no-confiable por defecto).

## Lo mejor de cada fuente, en una línea

- **OpenHarness** — mecánica de hooks (cuatro tipos, prioridad, `block_on_failure`) y
  memoria indexada con señal de uso. Su metodología de medida, no.
- **deepseek-harness** — *"saltado por falta de clave" es un tercer estado*, no un fallo.
- **AVO** — la puerta de aceptación **determinista y no agéntica**, y la regla monótona.
  Su hueco declarado (no hay reservado) es el que aquí queda abierto.
- **SkillEvaluator** — *Discoverability* como dimensión, y publicar el crudo para que
  cualquiera reproduzca el titular. Su juez LLM, no.
- **labs-OO-Agents** — *"a clean skip is indistinguishable from a pass"*.

## Anexo — cuánto cuesta exactamente, contado

La decisión de arriba se tomó mirando a OpenHarness. Este anexo mira al otro lado: **qué
parte de este repo está atada a Claude Code**, contado con `wc`, `grep` y `jq` sobre el
árbol, no estimado. Un agente independiente hizo el inventario; sus 3 048 líneas de suites
coinciden con las 3 041 citadas arriba.

Cada línea se clasificó en **PORTABLE** (no depende del sustrato), **ADAPTABLE** (depende,
pero existe equivalente plausible) e **IRREPLICABLE** (depende de un artefacto que solo
existe en Claude Code).

| Área | Líneas | PORTABLE | ADAPTABLE | IRREPLICABLE |
|---|---:|---:|---:|---:|
| Banderas de la CLI | 709 | 0 % | 35 % | **65 %** |
| Parseo de transcripts | 1 269 | 45 % | 20 % | 35 % |
| Hooks (13 programas, 14 cableados, 6 eventos) | 1 081 | 5 % | 60 % | 35 % |
| `settings.json` (3 ficheros) | 378 | 0 % | 45 % | **55 %** |
| Rutas y artefactos (`~/.claude/**`, agentes, comandos, skills) | 2 922 | 25 % | 60 % | 15 % |
| Las 25 suites | 3 048 | 18 % | 28 % | **54 %** |
| Otros (Sentinel, instalador, coste, autonomía) | ~1 000 | 40 % | 40 % | 20 % |
| **Total código + config + tests** | **~10 400** | **~24 %** | **~43 %** | **~33 %** |

Aparte quedan 8 386 líneas de markdown. De ellas, **1 662 son agentes, comandos y skills**:
su *texto* se reaprovecha íntegro, pero su **mecanismo de carga no** —
`disable-model-invocation: true`, `tools: [...]` y `model:` en el frontmatter, la resolución
de skill por su `description`, `$CLAUDE_PROJECT_DIR`.

Un tercio irreplicable no suena a mucho hasta que se mira **cuál** tercio.

### Las cinco dependencias más caras, y por qué

1. **Las cuatro banderas de brazo (`run.sh:46-49`).** No son cuatro líneas: es el diseño
   experimental entero. `--safe-mode` es la única forma de apagar CLAUDE.md, skills, hooks,
   plugins, MCP y comandos **manteniendo la autenticación de suscripción** — `--bare` exige
   `ANTHROPIC_API_KEY`, que una cuenta de suscripción no tiene. Sin control, `report.py`
   imprime `NO MEDIBLE`. Arrastra E1, E22, E23, M9, M12, las 786 líneas de `test_evals.sh` y
   parte de `mutantes.py`.
2. **`scripts/metrics.py` (288 líneas) y el formato interno de `~/.claude/projects/**/*.jsonl`.**
   Produce ~50 KPIs y alimenta `cost-report.sh` y el aviso de medición envejecida. Depende
   del desglose de caché en cuatro campos, de `output_tokens_details.thinking_tokens`, de
   `server_tool_use`, de la convención de ruta `/subagents/`, de los nombres `Skill`/`Task`/
   `ExitPlanMode` y de una tabla de precios por familia de modelo. **Nada de eso es un
   estándar.** Y sin dos instantáneas no hay tendencia: cambiar de sustrato tira el histórico.
3. **El `Stop` hook del modo autónomo (`verify-gate.sh` + `autonomy.sh`).** Depende de tres
   cosas a la vez: `{"decision":"block"}` como protocolo, `stop_hook_active` y el cap de 8
   bloqueos (`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`), y que el `timeout` declarado sea ≥ el
   interno **o el gate falla en abierto en silencio** — hay un fallo histórico de
   exactamente eso documentado en el propio fichero. Otro sustrato sin cap convierte el modo
   autónomo en bucle infinito o en adorno.
4. **La cadena de 7 hooks `PreToolUse` y su contrato de salida.** Tres protocolos conviviendo
   (`hookSpecificOutput.permissionDecision`, `additionalContext`, `exit 2`) y **orden
   significativo sin sensor**. Y `smart_approve.py` no solo usa el DSL de permisos: lo
   **reimplementa leyendo `settings.json`** para descomponer comandos compuestos. Cambiar de
   DSL no es portarlo, es reescribirlo. Peor: `optional-hook.sh` existe porque Claude Code
   trata el `exit 2` como *blocking error*; un sustrato con otra semántica de códigos de
   salida convierte los guards en **fail-open** sin que nada se ponga rojo.
5. **Siete claves de `settings.json` sin destino** — `model: "opus[1m]"`, `enabledPlugins`,
   `extraKnownMarketplaces`, `effortLevel`, `autoUpdatesChannel`, `theme`,
   `skipAutoPermissionPrompt`, más `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` y `MAX_THINKING_TOKENS`
   — y el ecosistema de plugins (`superpowers`, `codex`, `understand-anything`) que el
   harness da por instalado.

### Pros y contras, sin adornos

**A favor de migrar**

- **Mecanismo de hooks superior**: cuatro tipos (`Command`, `Http`, `Prompt`, `Agent`),
  `block_on_failure` y `timeout_seconds` declarados **por hook**, orden de ejecución
  explícito y recarga en caliente. Aquí hay 14 cableados con `timeout: 10` copiado y el
  orden implícito en el JSON.
- **Un núcleo de denegación no anulable** (`SENSITIVE_PATH_PATTERNS`) que la configuración
  del usuario no puede pisar. Aquí *"nunca amplíes la allowlist"* es una frase.
- **Memoria indexada** con búsqueda, relevancia, contabilidad de uso y migración de esquema,
  frente a un `knowledge/` que se carga a mano.
- **Independencia de proveedor**: hoy, si Anthropic retira una bandera, un brazo deja de
  medir — y el repo lo dice en E23 en vez de taparlo.
- **`--dry-run`**: aquí el coste de una tirada está escrito a mano en el `Makefile`.
- **MIT, 15 548 ★**: si el proyecto reviviera, la comunidad sería mayor que la de este repo.

**En contra**

- **~3 400 líneas irreplicables**, y son justo las que sostienen la tesis: brazos, métricas,
  gate autónomo, contrato de guards.
- **El experimento muere el primer día y no vuelve durante 100 h.** Un harness que no puede
  medirse es exactamente lo que este repo existe para no ser.
- **Cambiar 25 suites en verde por cuatro bypasses de permisos públicos** (#310, #313, #348,
  #349) abiertos sin un comentario en un repo sin commits desde el 4 de junio.
- **La autenticación pasa por un bridge que lee las credenciales de Claude Code**: riesgo de
  cuenta asimétrico, encaje con los ToS sin verificar.
- **Se compran 480 ficheros para usar 20.** *Swarm*, gateway a Telegram, TUI, voz y temas no
  resuelven ningún problema de un usuario en WSL2 con presupuesto de ≤6 agentes, ≤6 skills
  y ≤3 hooks.
- **El instalador es peor**: 387 líneas sin pinning de checksums, sin backup, sin
  *diff-first* y con un solo test, frente a 448 con las cuatro cosas y ocho suites.
- **La telemetría es menos y está peor colocada**: `cost_tracker.py` son 24 líneas que suman
  tokens en memoria **dentro del engine** — o sea, dentro de lo observado, que es
  precisamente lo que E26 prohíbe.

**El desempate** no es ninguna de esas líneas: es que la migración **no responde a ninguna
pregunta abierta del repo**. Las preguntas abiertas hoy son si el conjunto discrimina, si el
corrector acierta y qué pieza aporta. Ninguna se contesta cambiando de CLI.

## Consecuencias

- Este repo sigue acoplado a Claude Code, y eso queda dicho: si el CLI retira una bandera,
  E23 se pone en rojo y el brazo correspondiente deja de medir. Es el precio aceptado a
  cambio de medir con las banderas reales del producto que se usa.
- Las cinco ideas robadas entran **una a una y con sensor**, no en un lote.
