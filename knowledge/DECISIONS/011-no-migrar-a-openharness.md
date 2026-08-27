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

## Consecuencias

- Este repo sigue acoplado a Claude Code, y eso queda dicho: si el CLI retira una bandera,
  E23 se pone en rojo y el brazo correspondiente deja de medir. Es el precio aceptado a
  cambio de medir con las banderas reales del producto que se usa.
- Las cinco ideas robadas entran **una a una y con sensor**, no en un lote.
