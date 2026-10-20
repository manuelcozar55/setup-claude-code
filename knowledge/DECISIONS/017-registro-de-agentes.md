# ADR 017 — Registro de agentes: hooks mecánicos y RESULTADO.md

**Fecha:** 2026-10-20 · **Estado:** aceptada; campos fijados con el spike S0 (Claude Code 2.1.304)

## Contexto

El handoff guarda lo que sabe el hilo principal, no lo que un agente en segundo plano todavía no
ha contado. `nucleo.md` puede decir «agente lanzado», pero nunca «terminado, con este resultado»
ni «murió sin terminar». Tras `/clear`, una compactación o al reanudar, la sesión nueva no sabe si
debe recoger o relanzar, y relanzar deja dos agentes sobre la misma rama. Además:

- el kit no tenía ningún hook SubagentStart ni SubagentStop, y nada leía `background_tasks`;
- el `/handoff` manual y `/nueva` del cockpit hacían `/clear` con subagentes vivos;
- la documentación oficial no dice qué le pasa a un agente en segundo plano ante `/clear` o una
  compactación, ni si SubagentStart y SubagentStop se disparan en segundo plano o en `claude -p`.

## Decisión

- **Lo que mide el spike S0:**
  - SubagentStop marca el fin del *turno* del agente, no el de su *trabajo*: un subagente puede
    parar con un shell propio todavía en marcha, y ese shell muere al cerrar la sesión sin que
    ningún evento lo diga.
  - SubagentStop no trae ningún campo de resultado, y su `background_tasks` incluye al propio
    agente como `running`.
  - `SessionEnd` no trae `background_tasks`.
- **Registro mecánico:** un hook en SubagentStart, SubagentStop y SessionEnd añade una línea JSON por evento a
  `.claude/estado/agentes.jsonl`, con id, tipo, hora, transcript y el final del último mensaje.
  Filtra los agentes internos, falla en abierto, no llama a un modelo y rota con tope.
- **Foto de lo vivo:** el hook de Stop guarda `background_tasks`. Desde el 60 % del airbag avisa
  de que hay agentes en vuelo y pide `/handoff solo`, no `/clear`.
- **Contrato del brief:** cada agente deja `RESULTADO.md` en su carpeta de `informes/`, con la
  primera línea `estado: completado|fallido|parcial` y el comando que lo verifica.
- **Estado derivado** (el id propio se excluye siempre de `background_tasks`):
  - parado y con `RESULTADO.md` → el `estado:` de ese fichero (completado, fallido o parcial);
  - parado sin `RESULTADO.md` y con hijos en vuelo → **parado con trabajo pendiente**;
  - parado sin `RESULTADO.md` y sin hijos → terminado sin informe;
  - lanzado sin parada y vivo en la última foto de Stop → en vuelo;
  - en la última foto cuando llega SessionEnd → **cortado al cerrar**;
  - lanzado sin parada ni foto → **sin cierre**: comprobar antes de relanzar.
- **Reinyección:** SessionStart (clear, compact y resume) añade un bloque de agentes de 800
  caracteres como máximo, marcado como datos, dentro del tope de 9500: «recoge, no relances».
- **Cockpit:** `/handoff` y `/nueva` con agentes vivos guardan sin `/clear` y lo dicen.

## Alternativas descartadas

- Que el modelo lo apunte a mano en `nucleo.md`: falla en cuanto se olvida, y es lo que había.
- Solo hooks, sin `RESULTADO.md`: se sabe que terminó, pero no si salió bien ni dónde está.
- Esperar con `sleep` o con sondeo: gasta turnos y no sobrevive a `/clear`.

## Consecuencias

- Un hook nuevo, registrado en tres eventos: cabe en el presupuesto de complejidad.
- El agente que no termina se puede probar de forma determinista en `claude -p` con
  `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS`.
