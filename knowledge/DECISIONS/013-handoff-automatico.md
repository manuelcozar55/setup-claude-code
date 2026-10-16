# ADR 013 — El cockpit lanza el handoff solo, entre turnos

**Fecha:** 2026-10-16 · **Estado:** aceptada

## Contexto

Nada ejecutaba el handoff. Los avisos de contexto (vigía, nudge, toast) solo avisaban, y
`/handoff` es un comando de mod que el modelo no puede invocar. Lo único automático era la
autocompactación: 511 en los logs, todas `auto`, casi todas a mitad de un turno autónomo, donde
nadie puede escribir `/handoff`. Además el aviso pedía cerrar el turno y Never-Stop decía lo
contrario: ganaba Never-Stop. Y `nucleo_ctx` medía sobre 200k sin `[1m]`, con lo que el aviso
llegaba hasta un 30 % de más.

## Decisión

El mod `cockpit` (0.4.0) hace el trabajo, porque su API es la única que puede cerrar el ciclo:

- **Disparo.** Al cerrar un turno del bucle principal con el contexto en o por encima del umbral
  (70 % del límite de autocompactación; `COCKPIT_AUTO_HANDOFF=off` o un entero 50-95), guarda con
  el handoff de siempre, hace `/clear` desde `$.clock.after` y deja «sigue…» en el prompt con
  `$.prompt.fill`, sin enviarlo.
- **Veto acotado.** `session.compact` auto se pospone hasta `min(1,5 × límite, 0,5 × ventana real
  del modelo)`, para que el handoff llegue al cerrar el turno. Cede en subagentes, con `off`, con
  el handoff en error y si la lectura del contexto falla.
- **`/nueva <tarea>`** archiva el `nucleo.md`, limpia y deja la tarea nueva en el prompt.
- **Solo donde el estado es de la tarea:** un repo que no es `$HOME`.
- La capa de Claude Code declara el fin de fase al 70 % como excepción a Never-Stop, y
  `nucleo_ctx` mide sobre la ventana real del modelo.

Documentado en `kit/docs/11-cockpit.md`.

## Consecuencias

- Las sesiones en repo cierran fase y limpian solas; la persona solo pulsa Enter.
- El resto de un turno vetado se paga con más contexto, acotado por el techo.
- En `$HOME` no hay handoff automático hasta el plan v3 (nucleo por worktree, «`~` sin estado»).
- Sin verificar en vivo: `/clear` desde el temporizador, el relleno del prompt tras él, el motor
  tras varios vetos seguidos y el coste del fork al 70 %. Los 21 tests nuevos usan el arnés.

## Rechazado

- **Hook `PreCompact` de shell que bloquee:** sí puede bloquear la compactación, pero un hook no
  puede lanzar `/clear` ni rellenar el prompt.
- **Adoptar ruflo:** choca con la política (instalador pipe-a-shell, `npx` sin versión,
  `--dangerously-skip-permissions`), y su autopilot solo avisa.
- **`prompt.submit` tras `/clear`:** el prompt enviado se perdía (14-oct); por eso `prompt.fill`.
- **Detectar la tarea nueva con un clasificador y `{drop}`:** un falso positivo borraría el
  contexto a mitad de tarea.
- **Activarlo en `$HOME` antes del plan v3:** el `nucleo.md` es compartido y el handoff
  fusionaría en él el estado de otra tarea.
