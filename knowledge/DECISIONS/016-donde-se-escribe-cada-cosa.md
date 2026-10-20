# ADR 016 — Dónde se escribe cada cosa: el estado y los informes, en el proyecto, siempre

**Fecha:** 2026-10-20 · **Estado:** aceptada · Amplía el ADR 014

## Contexto

Los informes, briefs, baterías y pruebas de rojo/verde acababan en el scratchpad de la sesión:
volátil, por sesión e invisible para las demás. De ahí se copiaban a mano fuera del repo, y un día
no hubo forma de saber si la batería de HEAD se había pasado. Además, `.claude/estado/` solo lo
ignoraba el `info/exclude` del clon, así que en el clon de otra persona `nucleo.md`, con el
encargo literal, aparecía como fichero nuevo listo para commitear. Y `test_doc_claims` barría
también lo ignorado: un informe guardado en su sitio rompía `make test`.

Requisito de la persona: «que se asegure que siempre exite el archivo y si no que lo cree para
poder guardarlo si o si».

## Decisión

Tres destinos:

| Qué | Dónde |
|---|---|
| Temporal de proceso | scratchpad o `mktemp`; se puede perder |
| Estado de la tarea, informes, checkpoints, registro de agentes | `<raíz>/.claude/estado/` |
| Lo privado de la máquina (transcripts, logs, índice de raíces) | `~/.claude` |

Lo compartido y curado (decisiones, oráculos, errores) sigue en `knowledge/`, versionado.

- **Siempre existe.** Una sola función de la lib, que usan todos los que escriben (hooks, `handoff`,
  registro de agentes), crea al vuelo `.claude/estado/{informes,checkpoints}` y un `.gitignore`
  interno con `*` si faltan. Si el proyecto no admite escritura, la escritura cae a
  `~/.claude/estado/<proyecto>/` y lo avisa: nunca se pierde.
- **Nunca va a git.** El `.gitignore` interno con `*` es el patrón de pytest, ruff, mypy y venv:
  funciona en cualquier clon sin tocar el `.gitignore` del dueño del repo. En este repo se añade
  además al `.gitignore` como refuerzo.
- **Informes con ruta fija:** `informes/AAAA-MM-DD-<tema>/`. `handoff --informe <tema>` la imprime
  y el brief del agente la lleva, así que no hay copia posterior.
- **Checkpoints con tope:** 5 ficheros y 14 días.
- `test_doc_claims` mira solo lo versionado; `doctor` avisa con WARN si el estado no está ignorado.

## Alternativas descartadas

- Seguir en el scratchpad y copiar a mano: es lo que fallaba.
- Todo en el usuario (`~/.claude` o `XDG_STATE_HOME` por proyecto): separa el estado del worktree
  (contra el ADR 014) y Codex y opencode no lo encuentran.
- Editar el `.gitignore` de proyectos ajenos: ensucia el diff de su equipo y exige su permiso.

## Consecuencias

- Los checkpoints guardan los 3 últimos prompts dentro del proyecto. Van ignorados y con tope;
  la variante estricta, moverlos a `~/.claude`, queda abierta si alguien lo pide.
