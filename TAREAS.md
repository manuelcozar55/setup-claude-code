# TAREAS · setup-claude-code

Estados: pendiente · en-curso · hecha · bloqueada

<!--
## T-NNN · Título corto en imperativo

- estado: pendiente
- oráculo: `comando`
- clase: sensor
- riesgo: bajo
- timeout: 5min
- depende-de: T-001 (opcional; acepta lista separada por comas)
- criterios:
  - [ ] criterio observable

Prosa libre. (clase: sensor si el oráculo aún no pasa; regresión si el
oráculo ya pasa y esta tarea solo debe seguir pasando. riesgo: bajo,
medio o alto — alto exige confirmación humana antes de ejecutar.)
-->

## T-001 · doctor distingue instalacion rancia de personalizada

- estado: hecha
- oráculo: `make test`
- riesgo: bajo
- clase: sensor
- sensor: kit/test/test_doctor_drift.sh
- timeout: 15min
- criterios:
  - [ ] una version antigua del kit sale como FAIL y doctor rc!=0
  - [ ] una personalizacion sale como WARN y no se llama rancia

