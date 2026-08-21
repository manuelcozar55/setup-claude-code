# ADR 010 — Modo autónomo: el Stop hook sí bloquea cuando nadie está mirando

**Fecha:** 2026-08-21 · **Estado:** aceptada, verificada · **Revisa:** ADR 004

## Contexto

El ADR 004 decidió que **nada bloquea**, con este razonamiento: el coste de un falso
positivo bloqueante (sesión atascada, confianza perdida, hook desactivado para siempre) es
mucho mayor que el de un aviso ignorado.

Ese razonamiento tenía una premisa oculta: **que hay un humano delante que puede reaccionar
al aviso.** El requisito nuevo la elimina —*"quiero explicar el trabajo y que el sistema se
encargue de la interacción, reduciendo mi implicación"*— y con ella se cae la conclusión.

Sin nadie mirando, un aviso no vale nada. La documentación oficial lo dice sin rodeos:

> *"The `/goal` and Stop hook versions are what let an unattended run finish correctly
> without you."*

## Decisión

**Un solo Stop hook con dos modos**, y lo que los separa es si hay alguien mirando:

| | Modo normal | Modo autónomo (hay run activo) |
|---|---|---|
| Oráculo rojo | **avisa** por stderr, `exit 0` | **bloquea**: `{"decision":"block","reason":…}` |
| Presupuesto | — | 3 reparaciones, después libera |
| Justificación | hay humano que reacciona | no lo hay: el aviso no llegaría a nadie |

No es un hook nuevo: **`verify-gate.sh` gana el segundo modo**. El presupuesto sigue en 3
hooks. Sumar uno habría sido lo fácil; el pre-mortem señala el crecimiento como causa nº5.

El estado vive en `scripts/autonomy.sh` (`start`/`status`/`attempt`/`oracle`/`stop`), y el
punto de entrada es `/work`, donde el usuario **entra una sola vez**: una tanda de preguntas
agrupada más la aprobación de la spec. A partir de ahí, cada pregunta es un fallo de diseño.

## Los cuatro estados que hacen esto seguro

Un gate mal hecho no es un gate flojo: es uno que **secuestra la sesión**. Los cuatro casos
están verificados en `kit/test/test_autonomy.sh`:

| Estado | Comportamiento | Por qué es el correcto |
|---|---|---|
| Oráculo **rojo**, quedan intentos | bloquea con la salida real del comando | Es el único caso en que bloquear cierra el lazo |
| Oráculo **verde** | libera y **cierra el run solo** | Un run que no se cierra es un gate permanente |
| **Presupuesto agotado** | libera, avisa, devuelve el control | Insistir más no es perseverancia: es un lazo sin condición de salida, y es donde aparece la tentación de aflojar el sensor |
| **`stop_hook_active: true`** | sale de inmediato | Claude Code anula el hook tras 8 bloqueos seguidos. Ignorar ese cap es cómo se construye el hook que todo el mundo acaba desactivando |

El motivo que se devuelve al modelo **prohíbe explícitamente tocar el sensor** —relajar un
`assert`, añadir un `-k`, marcar `xfail`, tocar el `conftest`— y hay un test que comprueba
que esa prohibición está en el texto. Sin ella, un lazo bloqueante presiona hacia exactamente
el fallo que el lazo existe para evitar: cerrar la tarea rompiendo la medición.

## El oráculo tiene que ser real

`autonomy.sh start` **rechaza** un oráculo que no sea ruta absoluta, `rtk proxy …` o
`make …`. No es purismo: el hook `PreToolUse/Bash` sustituye el ejecutable en posición de
comando (M-001), así que un run desatendido verificando con `pytest` a secas estaría
ejecutando otra cosa. **Un run autónomo que verifica con el comando equivocado es peor que
uno que no verifica: parece que sí.**

## Alternativas descartadas

- **`type: "agent"` hooks.** Pueden ejecutar comandos y leer ficheros para decidir, que
  encaja aquí. Descartados porque la propia doc los marca experimentales: *"For production
  workflows, prefer command hooks"*. Un command hook ejecuta el oráculo de verdad y es
  determinista y gratis.
- **`type: "prompt"` hooks.** Un LLM juzgando si el trabajo está hecho es inferencial y no
  determinista, justo lo contrario de un oráculo. Sirven cuando no hay comando posible.
- **Solo `/goal`.** Es el mecanismo nativo y bueno, pero su evaluador *"doesn't run commands
  or read files independently"*: juzga lo que aparece en la conversación. Depende de que el
  agente reporte con honestidad, que es precisamente lo que no queremos dar por supuesto.
  **Se documenta como complemento**, no como sustituto: cubre bien los criterios que no son
  un comando.
- **Bloquear siempre, sin modo normal.** Vuelve a la asimetría del ADR 004 en las sesiones
  interactivas, que son la mayoría.

## Consecuencias y límites

- **El bloqueo tiene techo**: 8 iteraciones de Claude Code (ajustable con
  `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`) y 3 reparaciones propias. Nunca es indefinido, por
  diseño.
- **Un oráculo lento cuesta caro**: se ejecuta al final de cada turno. Hay `timeout 600`,
  pero un oráculo de varios minutos hace el modo inusable. La regla de la skill `harness`
  aplica: el presupuesto real es `duración × 5`.
- **El modo autónomo no sustituye al criterio.** Verifica que el oráculo pasa, no que se
  haya construido lo correcto. Por eso `/work` acaba con una revisión adversaria y un
  informe que declara qué **no** cubre el oráculo.
- Requiere `jq`. Sin él, el gate cae a modo normal en vez de fallar.

## Fuentes

- `code.claude.com/docs/en/hooks-guide` — contrato del Stop hook, `stop_hook_active`, cap de
  8, hooks `prompt` y `agent`. Verificado 2026-08-21.
- `code.claude.com/docs/en/goal` — evaluación de `/goal`. Verificado 2026-08-21.
