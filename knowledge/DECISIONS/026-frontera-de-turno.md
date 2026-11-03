# ADR 026 — El handoff necesita una frontera de turno; el veto de compactación se retira

**Fecha:** 2026-11-03 · **Estado:** aceptada · **Sustituye a:** ADR 022

## Contexto

Medido sobre las transcripciones del 16-oct al 3-nov (informe de auditoría del 2026-11-03, `F-compactaciones.md`):
116 compactaciones automáticas del hilo principal. El 85 % ocurre a mitad de un turno largo, y el cockpit solo
puede hacer handoff al cerrar un turno (`/clear` no se lanza dentro de un turno). Desde el 21-oct no hubo ni un
veto: el binario de Claude Code 2.1.311 trae `cc-plugin-sec-default@builtin`, que en una máquina con ajustes
gestionados se sienta el primero («seated outermost … unless managed prependPlugins is set») y pasa
`session.compact` por encima de los plugins de usuario. El ADR 022 lo creyó ocasional; es permanente en las
máquinas de CIRCE, que tienen `/etc/claude-code`. Las demás causas: subagente vivo (40 de 77 desde el 21-oct),
sesión sin proyecto (14) y un aviso inocuo del CLI que dejaba el cockpit en fase `error` hasta un `/clear` manual.

## Decisión

1. **Se retira el veto** (`on('session.compact')`, `isVetoed`) del cockpit 0.7.0. Código que parece proteger y no
   corre, con tres fallos propios dentro (A2-A4 de la auditoría).
2. **La frontera de turno la crea el modelo:** el aviso del 70 % de `nucleo-nudge.sh` ordena cerrar la fase,
   escribir el handoff y terminar el turno. El `AGENTS.md` del kit declara esa parada válida bajo Never-Stop. Con
   `/autonomo on` la sesión nueva continúa sola tras el `/clear`.
3. **Un guardado correcto no es un error:** con `--json`, los avisos de `handoff` van al recibo (`avisos[]`) y
   stderr queda vacío; el cockpit los muestra como aviso y la fase `error` vuelve a idle al siguiente cierre de turno.
4. **Cada cierre de turno sobre el umbral sin handoff deja una línea de log con el motivo**, para que la próxima
   medición no tenga casos «sin causa observable».

La red de seguridad del ADR 022 sigue igual: `pre-compact.sh` deja el checkpoint, `post-compact-check.sh` mide lo
perdido y `session-start-compact` reinyecta el nucleo. La compactación queda como airbag para el turno que no llega
a cerrar (subagentes vivos, tarea indivisible).

## Descartado

- **Listar el cockpit en `prependPlugins` del managed settings.** Devolvería el veto, pero pide sudo, cambia la
  política de la organización y abre a un plugin de usuario lo que «Security default» protege. Es decisión de quien
  administra la máquina, no del kit.
- **Veto desde un hook `PreCompact` de shell:** rechazado en los ADR 013 y 022 (sin recuento de tokens, falla la
  petición si la compactación viene de un error de límite, y el hook es observacional por contrato).
- **Un canal propio entre sesiones para el handoff.** Claude Code ya trae mensajería entre sesiones
  (`ListAgents`/`SendMessage`), y un mensaje consume contexto en vez de liberarlo. Sirve para coordinar dueños
  (exit 5 de `handoff`), no para sustituir el handoff.
