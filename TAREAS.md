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

- estado: hecha
- oráculo: `make test`
- riesgo: bajo
- clase: sensor
- sensor: kit/test/test_install_diff_first.sh
- timeout: 15min
- criterios:
  - [x] dos --plan seguidos dejan un solo arbol cckit-diff, no uno por invocacion
  - [x] el arbol sigue existiendo tras salir el proceso para que el usuario copie de el

## T-005 · doctor reporta el fork de la skill harness

- estado: hecha
- oráculo: `make test`
- riesgo: bajo
- clase: sensor
- sensor: kit/test/test_skill_fork.sh
- timeout: 15min
- criterios:
  - [x] dos copias divergentes se reportan
  - [x] copias identicas no se reportan (falsabilidad)

## T-006 · verify-gate consulta 'mch task gate'

- estado: hecha
- oráculo: `make test`
- riesgo: bajo
- clase: sensor
- sensor: kit/test/test_verify_gate.sh
- timeout: 15min
- criterios:
  - [x] A6: sin mch en PATH no bloquea nunca
  - [x] A7: rc=1 bloquea con motivo, tarea e intentos
  - [x] ausencia de autoridad no bloquea; autoridad muda si

## T-007 · retirar oracle-log.sh y la via de desarme de autonomy.sh

- estado: hecha
- oráculo: `make test`
- riesgo: bajo
- clase: sensor
- sensor: kit/test/test_verify_gate.sh
- timeout: 15min
- criterios:
  - [x] verify-gate no menciona MCHARNESS_STATE ni autonomy.sh
  - [x] oracle-log.sh no existe ni esta registrado en ningun settings
  - [x] lo borrado de test_autonomy.sh tiene reemplazo nombrado

## T-008 · realinear la instalacion de ~/.claude con el kit

- estado: bloqueada
- oráculo: `bash kit/doctor.sh`
- riesgo: alto
- clase: sensor
- timeout: 5min
- criterios:
  - [ ] doctor deja de reportar hooks desplegados como version antigua
  - [ ] los nueve huecos de 69db95d quedan cerrados en la maquina

## T-009 · el CHANGELOG del kit deja de abstenerse justo cuando va por detras

- estado: hecha
- oráculo: `bash kit/test/test_doc_claims.sh | tail -1 | grep -q "0 failed =="`
- riesgo: bajo
- clase: sensor
- timeout: 25min
- criterios:
  - [x] [Unreleased] vacia deja de ser skip cuando kit/ cambio despues del CHANGELOG
  - [x] [Unreleased] recoge lo que la rama anade, con sus cifras reales
  - [x] la suite deja de saltarse el bloque y el agregado puede dar veredicto

## T-010 · make test no puede dar veredicto cuando mas falta hace

- estado: hecha
- oráculo: `bash kit/test/test_make_test_verdict.sh`
- riesgo: bajo
- clase: sensor
- timeout: 25min
- criterios:
  - [x] una suite roja ya no aborta el target antes del agregado
  - [x] el agregado decide el codigo de salida, con sus tres veredictos
  - [x] una suite que muere DESPUES de imprimir su resumen deja de contarse como verde

## T-011 · install_settings reemplaza tu settings.json cuando falta jq

- estado: hecha
- oráculo: `bash kit/test/test_install_settings_merge.sh`
- riesgo: medio
- clase: sensor
- timeout: 30min
- criterios:
  - [x] sin jq pero con python3, fusiona en vez de reemplazar
  - [x] sin jq NI python3, deja tu fichero intacto en vez de reemplazarlo
  - [x] los dos motores producen el mismo resultado, comprobado sobre la misma entrada

## T-012 · una suite que se omite a si misma cuenta como aprobada

- estado: hecha
- oráculo: `bash kit/test/test_harness_structure.sh`
- riesgo: bajo
- clase: sensor
- timeout: 25min
- criterios:
  - [x] ninguna suite imprime 'ok' por trabajo que decidio no hacer
  - [x] omitida de verdad, test_doctor_drift declara skip y el agregado lo ve
  - [x] el detector demuestra que sabe decir que no

## T-013 · la puerta de PII no ve el nombre de la cuenta a secas

- estado: hecha
- oráculo: `bash kit/test/test_scan_secrets.sh`
- riesgo: bajo
- clase: sensor
- timeout: 25min
- criterios:
  - [x] el nombre de la cuenta sin ruta delante se detecta
  - [x] un nombre generico o corto no convierte la puerta en ruido, y se dice cuando no se comprueba
  - [x] el escaner demuestra que sabe decir que no

## T-014 · las huellas del journal de mch enrojecen el gate de gitleaks

- estado: hecha
- oráculo: `bash kit/test/test_secret_content_gitleaks.sh`
- riesgo: bajo
- clase: sensor
- timeout: 25min
- criterios:
  - [x] una huella sellada por mch task start no bloquea el commit
  - [x] una clave real dentro del propio journal sigue bloqueando
  - [x] el repo se mide con la config que el propio kit distribuye, no con la que haya instalada

## T-015 · nadie cubre el hueco que cede la excepcion de gitleaks

- estado: hecha
- oráculo: `bash kit/test/test_scan_secrets.sh`
- riesgo: bajo
- clase: sensor
- timeout: 20min
- criterios:
  - [x] API_KEY=<64 hex> en un fichero de config lo caza el escaner
  - [x] la mencion de API_KEY sin valor detras no enrojece
  - [x] las huellas del propio journal no lo disparan

