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
  - [x] una version antigua del kit sale como FAIL y doctor rc!=0
  - [x] una personalizacion sale como WARN y no se llama rancia

## T-002 · T-002: test_doctor_drift.sh corre de verdad en CI

- estado: hecha
- oráculo: `make test`
- riesgo: bajo
- clase: regresión
- sensor: kit/test/test_doctor_drift.sh,.github/workflows/ci.yml
- timeout: 15min
- criterios:
  - [x] un checkout de git shallow hace FAIL ruidoso (rc!=0), nunca skip silencioso
  - [x] preparar_home() escribe settings.json valido: el rc!=0 de la instalacion rancia lo causa el discriminador, no un FAIL ajeno
  - [x] una copia del kit sin git (tiene_git=n) clasifica como personalizacion local, nunca como rancio
  - [x] ci.yml hace fetch-depth: 0 en el checkout de test-suites

  T-001 quedo con un falso verde en CI: shallow clone -> ningun hook con 2 versiones -> suite omitida en silencio -> revert completo del discriminador pasaria sin detectar

## T-003 · el arbol de diff deja de persistir en el repo

- estado: hecha
- oráculo: `make test`
- riesgo: bajo
- clase: sensor
- sensor: kit/test/test_install_diff_first.sh
- timeout: 15min
- criterios:
  - [x] sin MCHARNESS_OUT el arbol va a un temporal
  - [x] la instantanea rancia .mcharness-out desaparece del arbol de trabajo

## T-004 · el arbol de diff deja de fugarse en /tmp

- estado: en-curso
- oráculo: `make test`
- riesgo: bajo
- clase: sensor
- sensor: kit/test/test_install_diff_first.sh
- timeout: 15min
- criterios:
  - [ ] dos --plan seguidos dejan un solo arbol cckit-diff, no uno por invocacion
  - [ ] el arbol sigue existiendo tras salir el proceso para que el usuario copie de el

