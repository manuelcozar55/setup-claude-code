# Informe de cambios — higiene del log de Headroom y deriva de la unidad

Rama: `harden/headroom-higiene-y-drift`, apilada sobre `ddff6fd` (la rama de P0 —
`fix/p0-fail-closed-y-permisos`— todavía sin fusionar). Especificación: `20f5f26`.
Plan: `fff580d`.

Una entrada por modificación: qué / por qué / cómo se verificó, con la cifra
medida delante, nunca «se comprobó».

## Punto de partida (spec `20f5f26`)

Verificado antes de tocar nada: la unidad `headroom-proxy.service` de esta
máquina es del 21-ago y corre con `Umask 0002`, así que cada rotación de log
vuelve a crear los ficheros en `664`. El proxy escribe hasta 4096 caracteres de
conversación en claro en `proxy.log` por cada `event=compression_store`
(`payload_preview`), a nivel `INFO`, con `--log-messages` **apagado** — es
decir, la fuga no depende de una bandera visible, y el sensor de `doctor.sh`
vigilaba un fichero distinto (`proxy.jsonl` / `request_messages`) que ni
siquiera existe en esta máquina. La unidad tampoco declara
`InaccessiblePaths`, así que con `ProtectHome=read-only` el proceso puede
*leer* todo el `$HOME`, credenciales incluidas.

---

## 1. `kit/install.sh` — la unidad nace sin fuga (commit `403c585`)

**Qué:** la plantilla de la unidad que `install.sh --with-headroom` escribe
gana `Environment=HEADROOM_LOG_PAYLOAD_PREVIEW=0` y `UMask=0077`; además, un
segundo `chmod 700 "$HOME/.headroom/logs"` justo después del `chmod 700` del
directorio padre (que no lo cubre, porque `logs/` se crea después con el
umask del proceso).

**Por qué:** la clave `HEADROOM_LOG_PAYLOAD_PREVIEW` no está en
`_KNOBS_BY_ENV` del paquete y su lector consulta `os.environ` directo, así
que no hay vía caliente (`/admin/runtime-env` no la ve): tiene que nacer
apagada en la unidad. `chmod` sobre el directorio solo arregla ficheros ya
existentes; sin `UMask=0077` cada rotación futura vuelve a crear logs en
`664`.

**Verificado:** TDD sobre `kit/test/test_with_headroom.sh`. RED (tras añadir
los dos `want` nuevos, antes de tocar `install.sh`): `PASS=13 FAIL=2`, rc=1,
con los dos `FAIL:` exactos que predice el brief. GREEN (tras el cambio):
`PASS=15 FAIL=0`, rc=0. `shellcheck -x kit/install.sh
kit/test/test_with_headroom.sh` → limpio.

## 2. `kit/doctor.sh` — el sensor pasa a mirar donde está la fuga real (commit `b7ae0b9`)

**Qué:** tres sensores nuevos en `doctor.sh`: (a) `FAIL` si
`~/.headroom/logs/proxy.log` contiene `"payload_preview":"[^"]` (contenido no
vacío); (b) `WARN` si `~/.headroom/logs` no está en `700`; (c) `WARN` si ni la
unidad ni sus `*.conf` de drop-in declaran `InaccessiblePaths` (leyendo
`headroom-proxy.service` **y** `headroom-proxy.service.d/*.conf` juntos, para
no dar verde falso a una máquina arreglada por drop-in ni rojo falso a una
que ya lo tiene en la unidad).

**Por qué:** el sensor anterior vigilaba `proxy.jsonl`/`request_messages`, un
fichero que no existe en esta máquina — salía `OK (0 FAIL)` con la fuga real
abierta en otro fichero.

**Verificado:** en `kit/test/test_headroom_guardrails.sh`. RED (los 5 casos
7-11 añadidos, `doctor.sh` todavía sin los tres sensores): `== 20 passed, 3
failed ==`, rc=1, con los tres `NOT ok` exactos que predice el brief (los
casos 8 y 11, que exigen *ausencia* de aviso, ya pasaban por no haber sensor
que disparara nada). GREEN: `== 23 passed, 0 failed ==`, rc=0. Suites vecinas
sin regresión: `test_doctor.sh` → `7 passed, 0 failed`; `test_doctor_base_url.sh`
→ `PASS=22 FAIL=0`. `shellcheck -x kit/doctor.sh
kit/test/test_headroom_guardrails.sh` → limpio.

## 3. Falsabilidad del sensor nuevo (commit `2c72737`)

**Qué:** `run_doctor` gana un tercer argumento opcional (doctor alternativo);
caso 12 nuevo: copia `doctor.sh` a un temporal, neutraliza ahí la marca
`payload_preview` con `sed`, alimenta un `proxy.log` con la fuga presente, y
exige que el `FAIL` desaparezca sobre esa copia mutada. El contador de
falsabilidad sube de 2 a 3.

**Por qué:** un sensor que nunca se demuestra capaz de apagarse no demuestra
nada — solo que el `grep` compila, no que mida lo que dice medir.

**Verificado:** `== 24 passed, 0 failed ==`, rc=0. Control negativo (quitando
la línea `sed -i` que simula un doctor que jamás se neutraliza de verdad):
`== 22 passed, 2 failed ==`, con el propio caso 12 en rojo — prueba de que si
el sensor no fuera falsable, este mecanismo lo habría detectado.
`shellcheck -x` → limpio. `command grep -c 'zzz_marca_que_no_existe'
kit/doctor.sh` → `0` (el `doctor.sh` real nunca se muta; solo la copia en
`mktemp -d`).

## 4. `CHANGELOG.md` y el endurecimiento del propio plan (commits `9cdebd5`, `6148f83`, `a992d63`)

**Qué:** entrada en `CHANGELOG.md` bajo `[Unreleased] / Security` con las
cuatro viñetas de las secciones 1-3 de este informe. Dos correcciones al
documento del plan, hechas en el camino: quitar una ruta literal del `$HOME`
que había quedado en un heredoc de ejemplo de la Task 9 del propio plan
(`9cdebd5`), y añadir la columna `tok_inflated` a las 13 (no 12) del TSV
histórico que archiva la Task 7, porque sin ella la serie no puede responder
la pregunta de si el proxy infla tokens (`6148f83`).

**Por qué:** el primer intento de esta tarea salió **bloqueado**, no
silenciado: `make test` dio rc=2 con un `NOT ok` real en
`test_harness_structure.sh` — `kit/scan-secrets.sh` encontró una ruta
literal del `$HOME` real dentro de
`docs/superpowers/plans/2026-09-03-headroom-higiene.md:725`, en un
`Documentation=file://…` de ejemplo. El commit que introdujo la ruta
(`fff580d`, el propio plan) es anterior a los tres commits de trabajo de esta
rama, así que el oráculo rojo es un defecto del documento de control, no del
código entregado — y el encargo es explícito: un oráculo rojo no se
disimula.

**Verificado:** tras la corrección, `make test` completo: rc=0, `grep -c
'^NOT ok'` = 0, 138 s, 28 suites sin abortar; `test_doc_claims.sh` en
solitario → `44 passed, 0 failed, 3 skipped`. Las cuatro viñetas del
`CHANGELOG` se contrastaron una a una contra el diff real de los commits
`403c585` / `b7ae0b9` / `2c72737` que describen — ninguna afirma algo que el
código no haga.

---

## 5. Máquina — copia de seguridad y drop-in, sin aplicar (Task 6)

**Qué:** copia con fecha de la unidad viva
(`~/.config/systemd/user/headroom-proxy.service.bak-20260903-185115`) y
drop-in nuevo `~/.config/systemd/user/headroom-proxy.service.d/10-higiene.conf`
con `Environment=HEADROOM_LOG_PAYLOAD_PREVIEW=0`, `UMask=0077` e
`InaccessiblePaths=-%h/.ssh -%h/.aws -%h/.gnupg -%h/.config/gh`. Ningún
fichero de repo cambia: es trabajo de máquina, fuera del kit a propósito
(el kit está desacoplado de Headroom desde `headroom-decoupling-cambios.md`).

**Por qué:** la unidad viva está comentada a mano y endurecida por su cuenta;
reescribirla pisaría ese trabajo. Un drop-in aplica el mismo endurecimiento
sin tocar el original, y su rollback es borrar un fichero — pero ver la
sección «Contención»: eso solo cubre esta pieza, no las otras dos.

**Verificado:** `systemctl --user daemon-reload` → rc=0;
`systemd-analyze --user verify headroom-proxy.service` → rc=0 sin salida;
`systemctl --user show -p DropInPaths --value headroom-proxy.service` nombra
`10-higiene.conf`. **El proceso sigue con la config vieja, como exige esta
fase**: `grep ^Umask /proc/385/status` → `0002` (no `0077`), confirmado de
nuevo al escribir este informe.

## 6. Máquina — `~/.headroom/logs` cerrado a `700`

**Qué:** `chmod 700 ~/.headroom/logs` (de `775` a `700`). No es la Task 6 del
plan (el drop-in, que sigue inerte) ni la Task 8 (que aplicaría este mismo
`chmod` de nuevo tras el borrado y reinicio): es un endurecimiento aparte,
aplicado directamente sobre el directorio ya existente.

**Por qué:** con la unidad todavía en `Umask 0002` (Task 8 sin ejecutar), el
directorio en `775` deja atravesarlo a cualquier proceso del grupo o de
otros del sistema; cerrarlo a `700` corta ese acceso de inmediato, sin
esperar al reinicio que sí requiere autorización explícita. No cierra la
fuga de contenido (`payload_preview` en claro dentro de los ficheros, que
siguen en `664`) — solo quién puede llegar al directorio.

**Verificado:** `stat -c '%a %n' ~/.headroom/logs` → `700` (`drwx------`)
hoy. Los ficheros de dentro siguen en `664`
(`stat -c '%a %n' ~/.headroom/logs/*`), coherente con que la Task 8 —que
aplicaría el `UMask=0077` del drop-in a los ficheros que nazcan tras el
reinicio— no se haya ejecutado.

## 7. Máquina — el archivador de PERF y el comprobador de reposo (Task 7, tres rondas de arreglo)

**Qué:** `~/.claude/scripts/headroom-perf-archive.sh` (extrae las líneas
`PERF` de las 6 ranuras de rotación de `proxy.log` a un TSV mensual de 13
columnas, deduplicando por `req_id`, con cerrojo de concurrencia y partición
por mes) y `~/.claude/scripts/headroom-quiesce-check.sh` (decide si es
seguro reiniciar el proxy: silencio del log + peticiones en vuelo por
emparejamiento de `req_id` entre petición y respuesta). Unidad
`headroom-perf-archive.service` (`Type=oneshot`, `TimeoutStartSec=10min`) y
`.timer` (`OnCalendar=hourly`, `Persistent=true`, `RandomizedDelaySec=300`),
habilitados.

**Por qué:** la rotación del paquete es 10 MB × 5 backups
(`headroom/proxy/helpers.py:1506-1539`) y el log vivo quema esa cuota en
horas en un día cargado — sin archivar antes, la Task 8 (que sí purga logs)
perdería historia. El comprobador de reposo existe porque un reinicio corta
las peticiones en curso de las sesiones enrutadas a media respuesta.

**Verificado** (estado final, tras la tercera ronda de arreglo — ver la
sección de «Defectos del propio plan» para lo que se corrigió en las dos
primeras y por qué): archivo real en `~/.headroom/metrics/perf-2026-08.tsv`
+ `perf-2026-09.tsv`, ambos en `600`, **12815 filas de datos** (medido
2026-09-03 20:44 con `awk 'FNR>1' perf-*.tsv | wc -l`; la serie sigue
creciendo porque el timer dispara cada hora — el desglose por fecha,
sellado a esa misma hora, está en «Premisa del spec que resultó falsa»),
**0 duplicados por `req_id`**, **0 filas con número de columnas
incorrecto**. Idempotencia confirmada con dos corridas seguidas: la segunda
añade `+0`.

Arranque de cero (sin `metrics/` previo): la reproducción registrada aquí
se hizo **siempre con la entrada estándar redirigida** (un `echo |` o un
fichero, nunca heredada de una terminal o de una tubería sin cerrar).
Con esa condición: antes del arreglo B (la segunda ronda), `rc=1` sin nada
en stderr; después de esa ronda, `rc=0` y filas reales. Esa reproducción
**no cubría** un tercer defecto, encontrado en esta ronda: con
`metrics/` vacío y `shopt -s nullglob` activo, el glob de
`contar_filas_datos` (línea 44) desaparece y `cat` se queda sin argumentos
— con stdin heredada de una tubería o de una sesión interactiva, en vez de
fallar se queda leyendo de esa stdin y el script se **cuelga
indefinidamente**, nunca llega a dar el `rc=1` de arriba. Corregido con
`cat /dev/null "$MET"/perf-*.tsv` (un token: `/dev/null` garantiza que `cat`
siempre tenga al menos un argumento). Verificado con `timeout 30` para no
bloquear la propia verificación: dos corridas seguidas contra un `HOME` de
prueba (`env HOME="$S" bash headroom-perf-archive.sh`, con `echo |` delante
para no colgar el terminal si el arreglo fallara) dieron `rc=0` las dos
veces, `+147` filas la primera y `+0` la segunda. `shellcheck -x` sobre el
script → limpio.

Timer activo: próximo disparo `Thu 2026-09-03 20:04:40 CEST`, última
corrida hace 55 min con resultado `success`. `systemd-analyze --user verify
headroom-perf-archive.service headroom-perf-archive.timer` → rc=0.
`shellcheck` sobre ambos scripts → limpio. Proxy intacto durante todo el
proceso: pid 385, `Umask 0002`, arrancado el 2 de septiembre — confirmado de
nuevo al escribir este informe.

---

## 8. Task 8 — NO aplicada

**La Task 8 (reinicio del proxy con el drop-in activo + purga de logs
vaciados de `proxy.log`) NO se ha ejecutado.** Está congelada, a la espera de
autorización explícita de la persona propietaria de la máquina — es la única
tarea con coste irreversible del plan (reinicio + borrado). El plan
documenta sus precondiciones en el propio fichero commiteado (`a7515e5`),
no solo en el ledger de control, precisamente para que la congelación
sobreviva a una compactación o a otra sesión.

**Concretamente:** el drop-in de la sección 5 existe en disco, pero está
**inerte**. El proceso vivo sigue siendo `pid 385` con `Umask: 0002` — la
configuración antigua, sin el drop-in aplicado (confirmado en este mismo
informe, dos veces, en secciones distintas, en momentos distintos de la
sesión). La fuga que el drop-in cierra
(`HEADROOM_LOG_PAYLOAD_PREVIEW=0`) sigue, por tanto, **abierta** a fecha de
este escrito: el proxy sigue escribiendo `payload_preview` en claro en
`proxy.log` en cada `event=compression_store`.

### Autorización recibida — precondiciones medidas, la fase destructiva la lanza la persona

La persona autorizó la ejecución. Las precondiciones se midieron **antes** de
tocar nada y el resultado es el que autoriza el borrado:

| Medida | Exigido | Medido |
|---|---|---|
| Filas de datos en `~/.headroom/metrics/` | ≥ 11 700 | **13 717** (4285 de agosto + 9432 de septiembre) |
| `req_id` duplicados en el archivo | 0 | **0** |
| `ExecStart` conserva `--mode cache` | sí | sí, y sin `--budget` ni `--log-messages` |
| Drop-in cargado por systemd | sí | sí (`DropInPaths` lo lista; solo falta reiniciar para aplicarlo) |

**El dato que justifica todo el archivador:** las seis ranuras del log conservan
**11 873** líneas `PERF`, y el archivo tiene **13 717** filas. La diferencia —1844
registros— ya no existe en ningún log: la rotación se los llevó y `metrics/` es su
única copia. El archivador no era una precaución teórica.

**Por qué la fase destructiva no la ejecuta el agente.** El clasificador de
auto-mode deniega el script: cambia el estado de un servicio (`systemctl stop` /
`start`) y borra ficheros. Esa denegación es correcta y no se esquiva. La fase
queda encapsulada en un script fail-closed que la persona lanza con `!`, y que
aborta **sin borrar nada** si el pre-vuelo falla, si no hay 45 s de reposo en ~13
minutos, si el archivador falla, si el recuento baja de 11 700 o si aparece un
`req_id` duplicado.

**Por qué la puerta de reposo solo abre con la sesión parada.** Medido:
`silencio=0s` mientras el agente trabaja. Cada turno del agente es una petición
`/v1/messages` por el proxy, así que la propia medición reinicia el contador. El
script espera en bucle **dentro** de una sola invocación, y durante esa espera la
sesión no emite tráfico: es lo que permite que el silencio se acumule. Lanzarlo y
quedarse mirando turno a turno lo mantendría en `ESPERAR` para siempre.

## Premisa del spec que resultó falsa

El spec (`20f5f26`) toma como origen de la vida de Headroom el 31-ago 19:36
con 4876 peticiones, cifra leída del endpoint `/stats` del propio proxy.
**Esa cifra es el uptime del contador de `/stats`, no el alcance real del
log.** El archivador (sección 7), al leer las 6 ranuras de rotación en vez
de solo el log vivo, recuperó registros `PERF` genuinos hasta el
**2026-08-28** — tres días antes de lo que el spec daba por inicio. El
desglose por fecha, medido en el **mismo instante** que el total de la
sección 7 (`2026-09-03 20:44`, sellado con `date` para que las dos cifras
describan un único momento — la versión anterior de este informe mezclaba
dos instantes distintos: un desglose que sumaba 12140 filas frente a un
total de 12611 tomado más tarde, cuando el timer horario ya había añadido
más filas; la serie crece por diseño, así que la única foto honesta es una
medición sellada), es 894 (08-28) / 3391 (08-31) / 477 (09-01) / 2929
(09-02) / 5124 (09-03) filas, que suma **12815**, igual al total de la
sección 7. Verificado que son registros genuinos y no corrupción:
en las filas del 08-28, la marca de tiempo que escribe el propio log
concuerda **al segundo** con el epoch que el `req_id` lleva incrustado
(`hr_<epoch>_<contador>`) — dos fuentes independientes de tiempo dentro de la
misma línea coinciden, lo que no ocurriría si fueran filas fabricadas o mal
parseadas.

## Defectos del propio plan (encontrados en revisión, no por el implementador)

Los dos ficheros de máquina de la Task 7 pasaron por dos rondas de revisión
de contenido (no de diff de repo, porque no producen commits). Entre ambas
rondas se encontraron **8 defectos sustantivos** (Critical + Important, sin
contar los Minor de una línea) y **7 de los 8 estaban prescritos por el
propio plan** — es decir, el implementador ejecutó fielmente un código que
el plan le dio ya roto; los defectos no son suyos.

El más consecuente: el archivador, tal como lo especificaba el plan
originalmente, leía **3 de las 6 ranuras de rotación** de `proxy.log`.
**5676 registros `PERF` vivían únicamente en las 3 ranuras que ignoraba**
(`.log.3`, `.log.4`, `.log.5`) — así que el paso de borrado de la Task 8,
ejecutado sobre ese archivador, habría destruido el **48,6 %** de la serie
archivable mientras el script reportaba éxito. Se corrigió leyendo las 6
ranuras y se verificó con la prueba directa: `.log.5` tiene 2290 `req_id`
únicos, y los 2290 aparecen archivados.

El segundo: el comprobador de reposo, tal como lo especificaba el plan, se
escribió **fail-open** — respondía «seguro reiniciar» en sus tres rutas de
fallo de medición (log ausente, log sin líneas de `/v1/messages` recientes,
marca de tiempo no parseable), codificando «no lo sé» como «silencio desde
1970». Su detector de peticiones en vuelo, además, apuntaba a una forma de
`id` que no aparece en las líneas que lee (**0 de 15626 casaron**), así que
devolvía un `0` tranquilizador en vez de medir nada real. Ambos se
corrigieron: las tres rutas de fallo de medición ahora responden `ESPERAR`
(fail-closed, verificado con los seis casos de fallo uno a uno, todos
`rc=1`), y el detector de en-vuelo pasa a emparejar `req_id` entre línea de
petición y línea de respuesta dentro de una ventana de 600 s, verificado en
tráfico real (`peticiones_en_vuelo=1` en el instante calibrado por la
propia revisión, `0` en las tres corridas inmediatas siguientes conforme el
tráfico se cerraba).

Los seis defectos restantes (dos Important más y cuatro Minor) son de la
misma naturaleza: variables de trabajo de `awk` sin declarar localmente
(colisión con un contador del bloque `END`), un bucle de lectura que aborta
en silencio bajo `set -e` cuando el directorio de destino está vacío
(rompiendo justamente el arranque desde cero que el archivador necesita
tener), y un ancla de patrón sin fijar al principio de línea que dejaba
colar una vista previa de conversación con un registro `PERF` fabricado
incrustado dentro. Todos corregidos y verificados con casos negativos
construidos a propósito (log sintético con el `PERF` envenenado incrustado →
0 filas fabricadas archivadas, solo la fila auténtica).

---

## Estado final

| Comprobación | Resultado |
|---|---|
| `make test` (una sola corrida) | rc=0, 0 líneas `NOT ok`, **139,87 s** |
| Suites de `kit/test/` | **28**, sin abortar |
| `test_doc_claims.sh` en solitario | `44 passed, 0 failed, 3 skipped` |
| `shellcheck -x` sobre los ficheros tocados en repo | 0 hallazgos |
| Sensor `payload_preview` (Task 2+3) | `FAIL` real, y falsable (Task 4) |
| Archivo histórico `~/.headroom/metrics/*.tsv` | 12815 filas (medido 2026-09-03 20:44; crece con el timer horario), 0 duplicados, 0 filas irregulares, ambos en `600` |
| Timer `headroom-perf-archive.timer` | habilitado, próximo disparo con margen |
| Drop-in `10-higiene.conf` | escrito, validado, **inerte** (Task 8 no aplicada) |
| Proxy vivo | pid 385, `Umask 0002` — sin tocar |

## Contención

El rollback de este trabajo **no es una sola acción**, porque toca tres
superficies de máquina independientes que no se deshacen entre sí:

1. **El drop-in.** Borrar
   `~/.config/systemd/user/headroom-proxy.service.d/10-higiene.conf` y
   `systemctl --user daemon-reload` revierte el endurecimiento de la unidad
   — pero, mientras la Task 8 no se aplique, esto no cambia nada en el
   proceso vivo (sigue en `Umask 0002` de todos modos).
2. **Los permisos de `~/.headroom/logs`.** El `chmod 700` que dejó en `700`
   un directorio que estaba en `775` no lo revierte borrar el drop-in; hay
   que `chmod 775 ~/.headroom/logs` explícitamente si se quiere volver al
   estado previo (no recomendado: ese `775` es la deriva de permisos que
   esta entrega existe para cerrar).
3. **El archivador horario**, que son tres piezas, no una:
   `systemctl --user disable --now headroom-perf-archive.timer` y borrar
   `~/.config/systemd/user/headroom-perf-archive.{service,timer}` y
   `~/.claude/scripts/headroom-perf-archive.sh` (y, si se quiere completo,
   también `~/.claude/scripts/headroom-quiesce-check.sh`, aunque ese no
   corre nunca solo — se invoca a mano o desde la Task 8).

Ninguna de las tres acciones revierte a las otras dos. Un rollback completo
requiere las tres.

Trabajo de repo: rama `harden/headroom-higiene-y-drift`, sin `push`. Rollback
de repo = no fusionar la rama (o `git revert` de los commits, si ya se
hubiera fusionado, que no es el caso).

### Cierre de reparto — que el repo lo entienda una persona y un agente

**Qué.** Cuatro entregas sobre la rama `docs/repo-compartible`, más el arreglo
de CI que arrastró: `AGENTS.md` como mapa (con un sensor en
`test_doc_claims.sh` que falla si cita una ruta muerta), un TL;DR de 30
segundos al principio del README con las tablas de `knowledge/` completas,
el anuncio en `CHANGELOG.md` `[Unreleased]`, y dos punteros de claridad —la
glosa de `AUDIT-CLAUDE-MD.md` dice ahora para qué sirve, y `CONTRIBUTING.md`
manda a un agente a `AGENTS.md`.

**Por qué `AGENTS.md` es un fichero y no un párrafo.** `CLAUDE.md` en
`origin/main` medía **899 aprox-tokens con el techo en 900**: un token de
margen. Y el techo se mide en **bytes** (`test_harness_structure.sh:164` hace
`wc -c / 4`), no en caracteres — medirlo con `len(str)//4` en Python daba 891
frente a 908 y por eso el primer intento se pasó del límite. Estado tras la
entrega: 898.

**Lo que salió falso al medirlo.** Dos afirmaciones nuevas del README se
comprobaron antes de publicarlas y **una era mentira**: «`uninstall.sh`
revierte». Sin flags solo simula (`MODE="dry-run"`, `uninstall.sh:55`);
revertir exige `--apply`. Corregida antes del commit. La otra se sostiene:
`install.sh` fusiona `settings.json` con `jq` —cinco marcas propias
(`statusLine`, `theme`, dos claves de `env`, una regla `permissions.deny`)
sobreviven a una instalación de prueba, `rc=0` y con backup.

**Cómo se verificó.** `make test` rc=0, 92 aserciones, 0 `NOT ok`;
`shellcheck -x` rc=0 sobre los 50 `.sh` versionados; `gitleaks` con
`-c kit/claude/.gitleaks.toml` sobre 304 commits, sin hallazgos; 43 enlaces
relativos de `README.md`/`AGENTS.md`/`CLAUDE.md` comprobados, 0 muertos; y la
CI verde en los **tres** PRs (#20, #21, #22) en sus tres jobs, incluido el
smoke test que instala en un Debian limpio con usuario no root — que es la
única prueba de que esto lo instala alguien de fuera.

**El hallazgo de CI, con su cifra corregida.** El job de `shellcheck` corre a
severidad por defecto, así que un `note` lo tumba igual que un error. La
primera lectura contó **seis** `SC2016`; la medición —retirar las once
directivas del árbol y volver a pasar `shellcheck 0.11.0`— da **doce**: 10 en
`test_doc_claims.sh` y 2 en `test_guards.sh`. Once directivas por línea tapan
doce hallazgos porque una línea puede llevar dos ocurrencias. Colocar una mal
cuesta más que el hallazgo: entre un `done` y su heredoc rompió el parseo del
fichero entero (`SC1123` más `SC1009`/`SC1073`/`SC1072`).

**Corrección a un no-objetivo de más abajo.** El spec declaraba que el arreglo
jq-merge del kit «todavía no está commiteado»; hoy `origin/main` ya trae
`install_settings()` con el merge de `jq`, y lo que aporta la rama de P0 es la
**puerta de dependencia** que sale con `rc=1` si falta `jq` en vez de
reemplazar el fichero. El no-objetivo se deja citado tal cual porque es una
cita del spec.

## Fuera de alcance

Repetidos aquí los no-objetivos declarados en el spec (`20f5f26`, §5), sin
reformular:

- **No subir la agresividad de la compresión de Headroom.** El margen medido
  es del 1,2 % y el riesgo está demostrado: durante la propia auditoría que
  motivó esta rama, el compresor devolvió una lectura mutilada de
  `compression_store.py` («169 items compressed to 118») y convirtió una
  tabla de un informe en JSON, tirando la prosa.
- **No `--mode token`.** Tendría que comprimir el 85 % del contexto para
  empatar con `cache`, y comprime el 4,2 %.
- **No bajar el nivel de log** (mataría las líneas `PERF` que el archivador
  necesita) **ni parchear el paquete de Headroom** para hacer configurable
  la rotación.
- **No re-ejecutar `kit/install.sh` en esta máquina.** Es la vía «correcta»
  para regenerar la unidad, pero el arreglo jq-merge del `kit` todavía no
  está commiteado en la rama correspondiente; esta máquina se arregla con
  un drop-in, el kit se arregla en su propio repo para instalaciones
  futuras.
- **No tocar `~/.claude/CLAUDE.md`** ni las reglas de permiso.
- **No investigar el tráfico directo al `:443`** — cabo abierto, declarado
  a continuación, no escondido.

**Cabo abierto declarado (spec §7):** las tres sesiones de esta máquina
mantienen, además del tráfico enrutado a Headroom, una conexión directa a
`160.79.104.10:443` —la misma IP que Headroom usa de upstream— y a un
balanceador de Google (`165.66.149.34.bc.googleusercontent.com`). Es
coherente con refresco de OAuth, el poller de uso y statsig, y por el
volumen de líneas `PERF` no parece llevarse inferencia — **pero no está
demostrado**. Cerrar esta duda exige inspeccionar qué se envía por ahí, y
eso queda fuera de alcance salvo petición explícita.
