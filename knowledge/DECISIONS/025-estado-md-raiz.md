# ADR 025 — `ESTADO.md` en la raíz como estado del proyecto, y quién manda si hay dos

**Fecha:** 2026-10-29 · **Estado:** aceptada

## Contexto

El estado de un proyecto vive en `.claude/estado/nucleo.md`: privado, ignorado por git, escrito por `handoff`.
Un proyecto que arranca desde una plantilla de equipo (`circe-proyecto-base`) lleva en su lugar un `ESTADO.md` en
la raíz: versionado, con viñetas (`Objetivo`, `Paso actual`, `Siguiente acción`) y las secciones `Decisiones`,
`Pendientes y riesgos` y `Cómo se comprueba`. Sin soporte en el kit, ese proyecto no recibía inyección en
SessionStart, los avisos pedían crear un `nucleo.md` en paralelo y `handoff` fallaba, con lo que el cierre
automático del cockpit no guardaba nada.

## Decisión

- `nucleo_modo_estado_md <raíz>` (`hooks/lib/nucleo.sh`) es la única puerta: hay modo ESTADO.md si existe
  `<raíz>/ESTADO.md` (fichero normal, no un enlace) y no existe `nucleo.md` propio. Desde `~` nunca.
- **Con los dos ficheros manda `nucleo.md`**. Es el que el kit crea, valida, recorta y protege con dueño y lock; tiene
  contrato de forma y tope. `ESTADO.md` puede venir de un tercero y sin esas garantías: si nos dejara de mandar a nosotros, un `ESTADO.md` añadido a un repo con
  trabajo en curso desviaría la inyección de una tarea ya guiada. Y tener `nucleo.md` es una acción deliberada del
  kit; tener `ESTADO.md` no lo es. Así quien ya usaba `nucleo.md` no cambia nada.
- Un `ESTADO.md` enlazado no cuenta: el repo decidiría qué fichero de fuera se inyecta.
- Los hooks leen la raíz por `nucleo_raiz` y solo cambian el nombre del fichero en sus textos; el tope de
  inyección es el mismo.
- `handoff --desde` fusiona en `ESTADO.md` (nunca crea `nucleo.md`): las secciones del borrador con equivalente
  sustituyen a su viñeta o a la **primera** sección de esa clave; las demás (Plan, Invariantes, Ficheros tocados)
  se añaden y se informan. Lo que el borrador no trae sale tal cual (CRLF, líneas en blanco y todo). La copia previa
  va a `.claude/estado/ESTADO.prev-*` (3, por mtime) y solo si el texto cambia; un handoff repetido no toca nada.
  `--iniciar` no crea nada y sale 0. `--estado` añade `modo` y `estado`.
- **El tope nunca borra lo que es de la persona.** `ESTADO.md` es suyo y versionado: el tope solo puede mandar a
  `diario.md` las secciones que el propio borrador añadió sin equivalente (y los `[x]` del Plan). Si aun así
  `ESTADO.md` pasa del tope, se escribe igual, rc 0, y se avisa por stderr de que conviene recortarlo a mano; la
  inyección de SessionStart ya lo recorta. Se descartó omitir Decisiones, Pendientes o secciones ajenas (la primera
  versión lo hacía: un borrador de una línea dejó un fichero de 8 KB en 893 B con sus notas en un diario que nunca se
  inyecta) y se descartó fallar con rc 1 (el cierre automático no guardaría nada). Pérdida cero antes que tope exacto.

## Descartado

- Que `ESTADO.md` mande con los dos: pisaría el estado de quien ya trabaja con `nucleo.md`.
- Migrar o fusionar los dos ficheros: dos fuentes de verdad es justo lo que esto evita.
- Dejar `handoff` fuera: rompe el ciclo automático (cierre, `/clear`, reinyección) en la plantilla de equipo.
