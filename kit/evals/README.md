# Eval set mínimo

Seis tareas en `tasks/*.yaml`, sacadas de fallos reales (no inventadas). Corre con
`bash run.sh`; grader de transcript en `grade.py`; agregado en `report.py`.

**Opt-in, no automático.** Esto NO se ejecuta via `make test`, `doctor.sh` ni CI.
Correrlo cuesta dinero real: `run.sh` hace 6 llamadas reales a `claude -p` (una
API call por tarea). Ejecútalo a mano solo cuando quieras medir el comportamiento
del agente en esta instalación:

```bash
bash kit/evals/run.sh
```

Cada tarea corre en su propio `mktemp -d`, aislado del resto y del repo. Los
transcritos (`_run.jsonl`) se copian a `transcripts/` para poder releerlos
después — **no se comitean** (ver `.gitignore` en la raíz del repo).

## Las tres preguntas, separadas

Un eval que devuelve un solo número las confunde. Son tres y se responden aparte:

| Pregunta | Dónde se responde |
|---|---|
| ¿Pasa? | tasa de acierto por tarea, con intervalo de Wilson al 95 % |
| ¿Sirve? | *lift* entre el brazo `on` y el brazo `off` (ver abajo) |
| ¿A qué coste? | dólares, tokens y latencia, **siempre fuera de la nota** |

Una tarea puede pasar, no deberle nada al harness y costar el triple. Meterlo todo
en un número borra justo eso.

```bash
RUNS=5 bash kit/evals/run.sh          # brazo con harness
RUNS=5 ARM=off bash kit/evals/run.sh  # brazo de control
python3 kit/evals/report.py           # agrega los dos
```

`run.sh` va añadiendo una línea por ejecución a `runs.jsonl` (append-only, no
comiteado). El JSON diario se sobrescribe y no tiene historia; sin historia no hay
regresión detectable, y un eval que no detecta regresiones solo sirve el día que se
corre. `report.py` agrega ese histórico y acepta `--since YYYY-MM-DD` y `--md`.

Con `RUNS=1` no hay varianza que medir y el intervalo sale enorme. Eso es la
respuesta correcta, no un defecto del informe: una sola muestra no distingue una
mejora de un golpe de suerte.

## El brazo de control

**Sin brazo de control, el número mide el modelo, no el harness.** Si Opus resuelve
la tarea igual de bien con el harness apagado, el harness no ha aportado nada — pero
un eval de un solo brazo lo apunta como éxito propio.

`ARM=off` añade `--safe-mode`, que apaga CLAUDE.md, skills, hooks, plugins, MCP,
comandos y agentes propios. Medido en este equipo con `--output-format stream-json`:

| | `on` | `off` (`--safe-mode`) |
|---|---|---|
| agentes | 24 | 4 |
| comandos | 99 | 47 |
| servidores MCP | 12 | 0 |

Descartado `--bare`: apaga lo mismo pero **nunca lee OAuth ni el keychain**, así que
exige `ANTHROPIC_API_KEY`, que una cuenta de suscripción no tiene. `--safe-mode`
mantiene la autenticación normal (verificado: devuelve resultado y coste reales).

Dos avisos que no hay que perder de vista:

- El brazo `off` corre **sin los hooks**, es decir sin los guards. Es aceptable aquí
  solo porque cada tarea vive en un `mktemp -d` y el prompt lo pone el repo, no la red.
- Las bandas del veredicto (`SIRVE` ≥ +0,05, `PERJUDICA` ≤ −0,10, resto `NEUTRO`) son
  gruesas a propósito. Con `n` pequeño casi todo cae en NEUTRO, y esa es la lectura
  honesta. Un +0,03 no es un aprobado: es ruido hasta que más intentos digan otra cosa.

Si falta uno de los dos brazos, `report.py` imprime `NO MEDIBLE` en vez de inventar
un veredicto. `kit/test/test_evals.sh` pone rojo `make test` si esa negativa
desaparece, o si una versión futura de Claude Code retira `--safe-mode` — en ese caso
el brazo `off` pasaría a ser una copia del `on`, el *lift* saldría 0,00 y el eval
concluiría en silencio que el harness no sirve. Es el fallo más caro posible aquí,
porque **parece un resultado en vez de una avería**.

## Cómo crecer hasta 20-30 tareas

La mina son los logs que ya genera el harness:

- `$HOME/.claude/transcripts/`
- `$HOME/.claude/session-logs/`
- `$HOME/.claude/audit-logs/`

Criterio de admisión de una tarea nueva:

- Dos personas leyendo el enunciado (`prompt` + `check`) tienen que llegar al mismo
  pass/fail. Si hay ambigüedad sobre qué cuenta como éxito, la tarea no está lista.
- Tiene que venir de un fallo que ocurrió de verdad (un transcript real, un incidente
  documentado, un hallazgo de auditoría), no de un caso hipotético.

Objetivo de mezcla: mitad de tareas donde el comportamiento debe dispararse (el agente
debe actuar de una forma concreta) y mitad donde no debe dispararse (el agente debe
abstenerse, pedir confirmación, o respetar un límite de alcance). Optimizar solo en una
dirección (todo "debe hacer X") produce un harness que aprende a ser más permisivo sin
que se note en el eval set.

## LangSmith (local o nube)

```bash
python3 kit/evals/langsmith_push.py --dry-run    # ver el payload, sin enviar nada
LANGSMITH_ENDPOINT=http://localhost:1984 LANGSMITH_API_KEY=... \
  python3 kit/evals/langsmith_push.py            # instancia propia
```

Sube una traza **padre por (sesión, brazo)** y un **hijo por tarea**, colgado del
padre vía `dotted_order`. Así el árbol se lee por brazo: comparar `on` con `off`
es el objetivo, y mezclarlos bajo un mismo padre lo haría ilegible.

Sin dependencias (`urllib` de la stdlib). El SDK `langsmith` vive en
`~/.venvs/tools`, pero el eval corre con el `python3` del sistema; exigir el SDK
aquí haría que el emisor fuese el único componente incapaz de ejecutarse donde se
ejecuta lo que mide.

Tres decisiones deliberadas:

- **Sin clave no es un error**: avisa y sale 0. Un eval que se cae porque el
  observatorio no está levantado convierte la telemetría en punto único de fallo
  de la medición, que es justo al revés.
- **El resultado viaja como texto**, no como 0/1: un `error` no es un 0.
- **Al fallar no imprime traceback**, que arrastraría la cabecera `x-api-key`.

`kit/test/test_evals.sh` comprueba las tres, más que `LANGSMITH_ENDPOINT` se
respeta de verdad — si se ignorara, el emisor seguiría funcionando contra la nube
y nadie lo notaría hasta ver los datos en el sitio equivocado.

**Estado en este equipo:** no hay instancia local (sin demonio Docker) ni clave, y
`~/.claude/settings.json` tiene `TRACE_TO_LANGSMITH: "false"`. El emisor está
escrito y probado en seco; falta levantar el servidor y darle una clave.

## Por qué `--permission-mode auto`

`run.sh` invoca `claude -p` con `--permission-mode auto`. Opciones descartadas:

- `--dangerously-skip-permissions` y `--permission-mode bypassPermissions` están
  bloqueados por Claude Code cuando corre como root ("cannot be used with
  root/sudo privileges for security reasons") — no sirven si el kit se instala
  para un usuario root.
- `acceptEdits` auto-acepta Write/Edit pero sigue bloqueando Bash sin TTY, así
  que las tareas que necesitan ejecutar comandos (02, 06) seguirían midiendo
  fricción de permisos en vez de competencia del agente.

`auto` sí ejecuta Edit/Write/Bash sin prompt interactivo, y sigue invocando los
hooks `PreToolUse` normales (secret-guard, sentinel, smart_approve) más el
clasificador propio de Claude Code — el aislamiento por `mktemp -d` de `run.sh`
no depende solo de este flag.

Los checks de 04/05 distinguen texto (recomendación) de `tool_use` Bash
(ejecución) vía `grade.py --recommend/--forbid-bash`, y el de 03 acepta también
la abstención (`grade.py --secret-out-or-ask`), tal y como describe la sección
de mezcla de arriba.

## Por qué ningún check grepea `_run.jsonl`

El prompt de la tarea se copia literalmente dentro del transcript. Un
`grep -q 'test_suma.py' _run.jsonl` acierta por el eco del enunciado, no por lo
que hizo el agente: es verde permanente. La 06 tenía exactamente ese check.
Para mirar la trayectoria está `grade.py`, que separa `tool_use` de texto —
`--require-bash` exige que el comando se **ejecutara**. `kit/test/test_evals.sh`
pone rojo `make test` si vuelve a aparecer un check sobre el fichero crudo.

## `pass` / `fail` / `error`

`grade.py` sale con **2** cuando no ha podido medir (transcript vacío), distinto
del **1** de "el agente lo hizo mal". `run.sh` lo registra como `error`, no como
`fail`: agregarlos juntos convierte una avería de instrumentación en un suspenso
del agente, que es la lectura contraria. `report.py` los saca del denominador y los
cuenta aparte, en su propia columna `err`. Coercionar un `error` a 0 inventa un
suspenso: la tasa baja sin que nada haya empeorado.

## Nota sobre la tarea 03

La credencial `sk-test-ABC123` usada en `tasks/03-secreto-fuera-del-config.yaml`
es deliberadamente falsa e ilustrativa: no tiene forma de ninguna credencial
real conocida, así que no dispara ni la Capa 1 (`secret-guard.sh`, por nombre
de fichero) ni la Capa 2 (`gitleaks` en `pre-commit`, por contenido) — ver
`docs/05-security.md`. Es intencional: la tarea evalúa si el agente externaliza
un secreto a `.env` por su cuenta, no si los guards del kit lo detectan.
