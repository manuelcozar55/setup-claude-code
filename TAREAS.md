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

## T-016 · primitivas de instalador cerradas, WAL, recuperacion y backup con integridad

- estado: hecha
- oráculo: `bash kit/test/test_txnwrite.sh`
- riesgo: medio
- clase: regresión
- timeout: 5min
- criterios:
  - [x] kit/lib/txnwrite.py: 4 primitivas cerradas + WAL + renameat2 + recovery (test_txnwrite.sh 26/0, incluye `recover` con tercer hash bloqueando)
  - [x] backup excluye secretos y el ZIP sale 0600 (F-11); restore exige manifiesto (F-21): test_backup_integrity.sh 12/0
  - [x] suite S completa sin rojos: 827 passed, 0 failed, 3 saltos preexistentes
  cierre retroactivo: el arreglo ya estaba commiteado cuando se cerro la tarea, asi que
  la sonda inicial de `start` sale VERDE y la clase baja de `sensor` a `regresion` (la
  salida que el propio mch prescribe). La prueba del ROJO no se pierde ni se inventa:
  esta en .omo/evidence/provider-agnostic-agent-harness/task-16-*/red.log y fue
  reproducida por el orquestador revirtiendo el arreglo en copia aislada.

  task-16 del plan provider-agnostic-agent-harness: kit/lib/txnwrite.py (4 primitivas cerradas + WAL + renameat2 + recovery); backup excluye secretos y ZIP 0600 (F-11); restore exige manifiesto (F-21)

## T-017 · un veredicto CRITICAL de Sentinel no lo puede levantar la allowlist

- estado: hecha
- oráculo: `bash kit/test/test_sentinel_critical_floor.sh`
- riesgo: medio
- clase: regresión
- sensor: kit/test/test_sentinel_critical_floor.sh
- timeout: 5min
- criterios:
  - [x] un comando CRITICAL sigue denegado con allowlist.commands=[cmd] y con allowlist.paths=['/']
  - [x] revertido el arreglo en copia aislada, el MISMO test da PASS=1 FAIL=1 rc=1: el sensor muerde
  - [x] la supresion por `paths` sigue viva para hallazgos no criticos
  cierre retroactivo: el arreglo ya estaba commiteado cuando se cerro la tarea, asi que
  la sonda inicial de `start` sale VERDE y la clase baja de `sensor` a `regresion` (la
  salida que el propio mch prescribe). La prueba del ROJO no se pierde ni se inventa:
  esta en .omo/evidence/provider-agnostic-agent-harness/task-17-*/red-boundary1-sentinel.log y fue
  reproducida por el orquestador revirtiendo el arreglo en copia aislada.

  check_dangerous_commands consultaba allowlist.commands antes de casar el patron CRITICAL; un repo clonado con su .security/sentinel-allowlist.json convertia un comando de destruccion de disco o reverse-shell en allow. Boundary F-13 del todo 17.

## T-018 · la CLAUDE.md proyectada declara opcionales las skills de terceros que prescribe

- estado: hecha
- oráculo: `bash kit/test/test_optional_capabilities.sh`
- riesgo: bajo
- clase: regresión
- sensor: kit/test/test_optional_capabilities.sh
- timeout: 5min
- criterios:
  - [x] la CLAUDE.md proyectada declara opcionales deep-change/superpowers y da camino sin ellas
  - [x] revertida al texto pre-arreglo (0 palabras de opcionalidad), el MISMO test da PASS=0 FAIL=1 rc=1
  cierre retroactivo: el arreglo ya estaba commiteado cuando se cerro la tarea, asi que
  la sonda inicial de `start` sale VERDE y la clase baja de `sensor` a `regresion` (la
  salida que el propio mch prescribe). La prueba del ROJO no se pierde ni se inventa:
  esta en .omo/evidence/provider-agnostic-agent-harness/task-17-*/red-boundary2-capabilities.log y fue
  reproducida por el orquestador revirtiendo el arreglo en copia aislada.

  F-03: el kit vendoriza un CLAUDE.md que en Operating loop ordena la skill deep-change componiendo superpowers, sin declararlas terceros opcionales ni ofrecer camino cuando faltan. La base (guards, Sentinel, agentes) funciona sin ellas. Boundary del todo 17.

## T-019 · la doc atribuye shellcheck a la CI, no al oraculo local make test

- estado: hecha
- oráculo: `bash kit/test/test_shellcheck_honest_gate.sh`
- riesgo: bajo
- clase: regresión
- sensor: kit/test/test_shellcheck_honest_gate.sh
- timeout: 5min
- criterios:
  - [x] make test NO invoca shellcheck; ci.yml SI lo corre como puerta; CLAUDE.md lo atribuye a la CI
  - [x] revertida CLAUDE.md al texto pre-arreglo, el MISMO test da PASS=2 FAIL=1 rc=1
  - [x] las 3 suites nuevas del todo 17 estan en ci.yml: paridad Makefile<->CI
  cierre retroactivo: el arreglo ya estaba commiteado cuando se cerro la tarea, asi que
  la sonda inicial de `start` sale VERDE y la clase baja de `sensor` a `regresion` (la
  salida que el propio mch prescribe). La prueba del ROJO no se pierde ni se inventa:
  esta en .omo/evidence/provider-agnostic-agent-harness/task-17-*/red-boundary3-shellcheck.log y fue
  reproducida por el orquestador revirtiendo el arreglo en copia aislada.

  F-25: CLAUDE.md listaba shellcheck -x junto a make test en Antes de commitear, como si el oraculo verde lo ejecutara. make test no corre shellcheck; quien lo hace como puerta es ci.yml sobre todo .sh versionado. Se atribuye a la CI. Boundary del todo 17.

## T-020 · define provider capability contract v1 (schema runtime + coordinador S->M)

- estado: hecha
- oráculo: `bash kit/test/test_profile_coordinator.sh`
- riesgo: bajo
- clase: regresión
- timeout: 10min
- criterios:
  - [x] el schema v1 rechaza un ciclo degradado que reclama lifecycle-enforced (ver task-18/red.log)
  - [x] el coordinador S maneja prepare/apply/query/compensate contra M real sin escribir targets ni receipt de M (ver task-18/qa.log)
  - [x] make test: 39 suites, 858 passed, 0 failed, 3 skipped (ver task-18/affected.log)

## T-021 · extrae installer-core: interprete de primitivas cerradas con envoltura install/doctor/diff/uninstall y recuperacion de conflicto de propiedad, sin cambiar a Claude

- estado: hecha
- oráculo: `bash kit/test/test_installer_core.sh`
- riesgo: medio
- clase: sensor
- timeout: 5min
- criterios:

  task-19 del plan provider-agnostic-agent-harness

## T-022 · empaqueta el perfil de referencia de Claude y el puente Stop verificado contra el gate v2 real de M, sin cambiar a Claude

- estado: hecha
- oráculo: `["bash", "kit/test/test_claude_stop_bridge.sh"]`
- riesgo: medio
- timeout: 5min
- criterios:

## T-023 · empaqueta el perfil nativo de Codex con limites de ciclo de vida honestos (profile-certified/degraded), AGENTS proyectado por M, fragmento TOML por diff-only, gate manual verificado contra el gate v2 real de M y cert offline (task-21)

- estado: hecha
- oráculo: `bash kit/test/test_codex_profile.sh`
- riesgo: medio
- clase: sensor
- timeout: 5min
- criterios:

## T-024 · el gate manual de Codex decide con stdin abierto en vez de colgarse leyendo hasta EOF

- estado: hecha
- oráculo: `bash kit/test/test_codex_profile.sh`
- riesgo: bajo
- clase: sensor
- timeout: 5min
- criterios:
  - [x] invocado con stdin abierto (terminal), devuelve veredicto en tiempo acotado
  - [x] no cambia el veredicto en ninguno de los casos ya cubiertos

## T-025 · empaqueta el perfil de Copilot (interactive PTY + -p) con ciclo de vida degradado por el tope de 8 bloqueos

- estado: bloqueada
- oráculo: `bash kit/test/test_copilot_profile.sh`
- riesgo: medio
- clase: regresión
- sensor: kit/test/test_copilot_profile.sh
- timeout: 5min
- criterios:

## T-026 · empaqueta el perfil de Copilot (interactive PTY + -p) con ciclo de vida degradado por el tope de 8 bloqueos

- estado: hecha
- oráculo: `bash kit/test/test_copilot_profile.sh`
- riesgo: medio
- clase: sensor
- timeout: 5min
- criterios:

## T-027 · verificacion read-only del gate cross-repo (todo 23): los 3 puentes S ligan el gate v2 del productor real M

- estado: bloqueada
- oráculo: `bash kit/test/task23_verdict_probe.sh`
- riesgo: bajo
- clase: regresión
- sensor: kit/test/task23_verdict_probe.sh
- timeout: 5min
- criterios:

  Dictamen de solo lectura. Verifica que claude-stop-bridge/codex-manual-gate/copilot-manual-gate fijan evidence_schema=mch-gate-evidence-v2, gate_body_contract=2, min_producer_version=0.2.0 coherente con el productor real. Commit: N en el plan.

## T-028 · verificacion read-only del gate cross-repo (todo 23): los 3 puentes S ligan el gate v2 del productor real M

- estado: hecha
- oráculo: `bash kit/lib/verify/task23_gate_contract_probe.sh`
- riesgo: bajo
- clase: regresión
- timeout: 5min
- criterios:

  Dictamen de solo lectura. Verifica que claude-stop-bridge/codex-manual-gate/copilot-manual-gate fijan evidence_schema=mch-gate-evidence-v2, gate_body_contract=2, min_producer_version=0.2.0 coherente con el productor real M. Commit: N en el plan.

## T-029 · matriz de conformidad estructural y mutacion adversaria (todo 24): cobertura del productor real gobernado + retiro de la sonda schema-only superviviente

- estado: bloqueada
- oráculo: `bash .agents/oracles/task24_conformance.sh`
- riesgo: medio
- clase: regresión
- sensor: .agents/oracles/task24_conformance.sh
- timeout: 5min
- criterios:

## T-030 · matriz de conformidad estructural y mutacion adversaria (todo 24): cobertura del productor real gobernado en los 3 puentes + retiro de la sonda schema-only superviviente

- estado: hecha
- oráculo: `bash .agents/oracles/task24_conformance.sh`
- riesgo: medio
- clase: sensor
- timeout: 5min
- criterios:

## T-031 · mata mutantes M2/M3: autoridad rota real en los 3 puentes

- estado: bloqueada
- oráculo: `bash .agents/oracles/task24_authbreak.sh`
- riesgo: medio
- clase: regresión
- sensor: .agents/oracles/task24_authbreak.sh
- timeout: 5min
- criterios:

## T-032 · mata mutantes M2/M3: autoridad rota real en los 3 puentes (TDD rojo-primero)

- estado: hecha
- oráculo: `bash .agents/oracles/task24_authbreak.sh`
- riesgo: medio
- clase: sensor
- timeout: 5min
- criterios:

## T-033 · mata mutantes M5/M7 (invalid_state, authority_missing) reales en los 3 puentes

- estado: hecha
- oráculo: `bash .agents/oracles/task24_missing_invalid.sh`
- riesgo: bajo
- clase: sensor
- timeout: 5min
- criterios:

## T-034 · certifica real Claude/Codex/Copilot por modo/tier: identidad congelada + gate de home efimero, BLOCKED honesto sin homes provistos

- estado: hecha
- oráculo: `bash kit/test/test_codex_profile.sh`
- riesgo: medio
- clase: sensor
- timeout: 5min
- criterios:

  Wave 5 todo 25. Arnes real-certify-profiles.sh consume la matriz normativa, congela realpath+version+sha256, limpia el proxy en el hijo, y sin home efimero cierra BLOCKED/missing_auth_home (cierre global bloqueado, honesto). Seccion 9 lo ejercita con binarios de mentira: cero coste, cero credenciales.

## T-035 · liga el recibo de smoke a la identidad congelada del binario: rechaza sha256 divergente (BLOCKED/receipt_identity_mismatch, nunca PASS)

- estado: hecha
- oráculo: `bash kit/test/test_codex_profile.sh`
- riesgo: medio
- clase: sensor
- timeout: 5min
- criterios:

  Wave 5 todo 25 cierre. El recibo de smoke hoy es falsificable: un JSON escrito a mano con canary_observed:true y un binary_sha256 CUALQUIERA sale PASS. Se anade el productor (smoke_executor.sh: canario+flujo con tope de tiempo/turnos/coste, ruta explicita de Codex, PTY+-p de Copilot) que ESCRIBE el recibo ligado a binary_sha256/realpath/version, y real-certify-profiles.sh RECHAZA un recibo cuya identidad no coincida con la que acaba de congelar: BLOCKED/receipt_identity_mismatch, jamas PASS.

