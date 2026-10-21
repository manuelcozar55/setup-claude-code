# ADR 019 — Sesiones en `~`: una ranura por proceso de Claude

**Fecha:** 2026-10-21 · **Estado:** aceptada; enmienda a 014 solo para `~`

## Contexto

La ADR 014 dejó `~` sin estado propio: no es proyecto, así que `handoff` salía con 3 y el nucleo de una
sesión abierta en `~` no sobrevivía a `/clear`. Pero se trabaja en `~` (consultas largas, mantenimiento de
la configuración) y esas sesiones también necesitan retomar. El fallo original, varias sesiones sobre un
mismo nucleo, no puede volver.

## Decisión

- **Clave = el proceso de Claude**, no el proyecto ni la sesión. Ranura
  `~/.claude/estado/sesiones/<AAAAMMDD-HHMM de creación>-<pid>/` con su `nucleo.md`. `/clear` y `resume`
  dentro del mismo proceso la reencuentran; dos sesiones simultáneas tienen ranuras distintas.
- **Identidad del proceso por ticks de arranque** (campo 22 de `/proc/<pid>/stat`, tras el último `) `), guardada
  en `.proceso`; sin `/proc`, `ps -o lstart=`. No `lstart` ni `btime + ticks`: dependen de `btime`, que el
  kernel recalcula cuando salta el reloj de pared (WSL2 lo salta al volver de suspensión) y el nombre de la
  ranura cambiaría con la sesión viva. Un pid reutilizado tiene otra identidad y recibe ranura nueva.
- **Solo donde no hay proyecto y sin `--raiz`.** `handoff --estado`, `--iniciar`, `--informe` y `--desde` usan
  la ranura; `--commit` sale con 3; con `--raiz` explícito que no es proyecto, o sin ranura, todo sigue en 3.
  Sin dueño ni registro de proyecto. El cockpit no calcula nada: pregunta a `handoff --estado`.
- El índice de `~` lista las ranuras con nucleo («sesión en ~») junto a los proyectos, dentro del mismo tope.
- `sesiones/.gitignore` con `*`: `~/.claude` suele ser un repo de configuración.

## Alternativas descartadas

- **Un nucleo compartido en `~`**: es el fallo de 014.
- **Clave por `session_id`**: cambia con `/clear`, justo cuando hay que retomar.
- **«El handoff más reciente»**: con dos sesiones, una recibe el estado de la otra.

## Consecuencias

- `claude --resume` en otro proceso arranca una ranura nueva; la vieja sigue en el índice y se retoma a mano.
- El handoff automático del cockpit sigue limitado a proyecto (la ranura es de la sesión, pero no hay
  validación en vivo de ese camino todavía).
- Sin validar en vivo: que los hijos de `$.process.run` (el cockpit) y un `claude -p` anidado hereden el
  `CLAUDE_PID` del claude de la sesión. Los tests fijan `CLAUDE_PID` a mano.
- No hay purga: las ranuras de procesos muertos se quedan en `sesiones/` y en el índice hasta borrarlas a mano.
- En clear y resume la ranura propia sale dos veces: inyectada como `<nucleo-datos>` y como línea del índice.
