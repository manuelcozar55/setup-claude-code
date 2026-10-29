# ADR 022 — El veto de la compactación automática se queda en el cockpit

**Fecha:** 2026-10-29 · **Estado:** aceptada

## Contexto

El cockpit veta la compactación automática para que actúe el handoff (`kit/mods/cockpit/hooks/register.tsx:742`,
`on('session.compact', { trigger: 'auto' }, …)`): por debajo del techo `min(1,5 × límite, 0,5 × ventana)` devuelve
`skip` y el handoff corre al cerrar el turno. El 29-oct, en dos sesiones (Claude Code 2.1.308, cockpit 0.6.0), el
runtime avisó «cockpit: its session.compact hook was skipped. "cc-plugin-sec-default" runs first and sent the
event on past it», y la compactación ocurrió sin veto. Diagnóstico (rama `feat/v170-handoff-b3`, evidencia en el
informe del flujo B): los handlers corren por tier `prepend|user|builtin|core|append`; un plugin gestionado puede
llamar `next.to(e, tier)` y saltarse los de menos autoridad. El cockpit es tier `user`: ningún orden ni prioridad
lo protege. `cc-plugin-sec-default` no está en `~/.claude/plugins` ni en `/etc/claude-code`: no es de scc.

## Decisión

El veto sigue en el cockpit y no se porta. Cuando un plugin de más autoridad lo salta, la red de seguridad es la
que ya existe: `pre-compact.sh` deja el checkpoint, `post-compact-check.sh` mide lo perdido y `session-start-compact`
reinyecta el nucleo. El aviso del runtime ya hace visible el salto. La causa la corrige el dueño del otro plugin
(pasar el evento con `next(e)`) o el administrador: se le comunica a la persona y no se tapa desde scc.

## Descartado

- Veto desde un hook `PreCompact` de shell. La doc oficial (code.claude.com/docs/en/hooks) permite bloquear con
  exit 2 o `{"decision":"block"}`. No se implementa por tres razones: `PreCompact` no recibe tokens, así que no
  puede aplicar el techo y vetaría sin límite; si la compactación viene de un error de límite, bloquear hace
  fallar la petición; y `pre-compact.sh` es observacional por contrato (`exit 0` siempre, línea 9).
- Toast del cockpit cuando el contexto cae más de un 50 % sin handoff propio (commits 2cd758e y ace1674 en
  `feat/v170-handoff-b3`, que no se fusiona). Duplica el aviso del runtime, da falsos positivos con `/compact`
  manual y con `/clear` desde encima del umbral, y atribuye una causa que no comprueba.
