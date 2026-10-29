# ADR 020 — Compuerta de frescura del nucleo (PreToolUse)

**Fecha:** 2026-10-26 · **Estado:** aceptada, a prueba; se retira si no gana (ver abajo)

## Contexto

`nucleo-nudge.sh` avisa «nucleo viejo» una vez por banda (50/70/85 % del airbag). Sobre 186 avisos, solo el
47 % se cumple en 3 turnos y en el 22 % se compacta antes. Pedir no basta, y dentro de un turno autónomo no hay
Stop que lo fuerce.

## Decisión

`nucleo-gate.sh` en `PreToolUse` (todas las herramientas, timeout 5 s). Se arma cuando el nudge avisó de la banda
70 u 85 con el nucleo viejo; cuenta las llamadas del hilo principal y deniega la 4.ª con el motivo accionable
(actualizar el nucleo o `handoff --desde`). Una denegación por banda y sesión. Pasan siempre `.claude/estado/` y
`handoff`; un nucleo escrito tras el aviso la desarma; los subagentes (`agent_id`) no cuentan; falla en abierto;
opt-in desde v1.6.1: solo actúa con `env.CC_NUCLEO_GATE=1` (sin A/B no se impone). El nudge deja `nudge-<sid>.nucleo` (ruta que miró; su mtime es la hora del aviso).
Desde `~` mira el nucleo de la ranura de la sesión, si se conoce su pid; sin ranura no hay compuerta (v1.6.1). Cada
denegación deja una línea en `session-logs/gate-denegaciones.log` (fecha, sesión, banda, herramienta, nucleo) para medirla.

## Por qué PreToolUse

- **No Stop**: en un turno autónomo el Stop llega tarde o no llega; es donde ocurre el 63 % de las compactaciones.
- **No PreCompact**: bloquearlo está rechazado (ADR 015); además llega cuando ya no hay margen.
- PreToolUse es la única señal que ve el modelo a mitad de turno y que puede cambiar su siguiente acción sin llamar a un modelo.

## Por qué una denegación por banda

Cada denegación cuesta una llamada. Una sola da el empujón y vuelve a confiar en el aviso; denegar sin límite
convertiría la compuerta en un bloqueo que quien no puede escribir el nucleo (permisos, sesión ajena) no resuelve.

## Métrica de éxito

Medida con `frescura.py` y `nudge.py` de la base, tras dos semanas de uso:
- Nucleo escrito en los 20 turnos previos a una compactación: de 47 % a ≥ 80 %.
- Cumplimiento del aviso en 3 turnos: de 47 % a ≥ 90 %.

## Retirada

Si no se alcanzan, o si genera denegaciones que la persona sufre sin ganancia: quitar la entrada de `PreToolUse` en
`kit/claude/settings.json` y borrar `nucleo-gate.sh`; el nudge sigue valiendo solo (el fichero `.nucleo` es inocuo).
Apagado sin código: es el valor por defecto; se activa con `env.CC_NUCLEO_GATE=1` (v1.6.1).
