# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).
Este proyecto sigue [Versionado Semántico](https://semver.org/lang/es/).
`[Unreleased]` recoge lo que está en `main`, o en camino a él por PR, y aún no se ha
etiquetado.

## [Unreleased]

## [1.1.0] - 2026-09-02

El repo pasa de ser solo un instalador endurecido a ser también un **harness**: guías
(lo que se dice antes de actuar) y **sensores** (lo que mide después), en el sentido de
Birgitta Böckeler (*Harness engineering*, 02-abr-2026). Lo nuevo vive en la raíz, pero
`kit/` no queda intacto: suma 38 ficheros nuevos —el subsistema de evals con sus casos
y sus pruebas— y 41 ficheros de v1.0.0 retocados, `install.sh` entre ellos. El árbol
corre hoy 27 suites de test, frente a las 16 de v1.0.0.

### Added

- **El hallazgo que reordenó el trabajo: el canal de Bash reescribe los comandos.**
  El hook `PreToolUse/Bash` sustituye el ejecutable en posición de comando — `rg` ejecuta
  `grep`, `python3 -m pytest` ejecuta `python3 -m rtk`. Bash acumula **6.093 llamadas a
  herramienta** en el snapshot del 2026-08-21 (2.410 en la sesión principal + 3.683 en
  subagentes, `tools_top.Bash` de cada mitad),
  así que casi todo sensor pasaba por un canal que altera la pregunta.
  Un oráculo así no mide lo que dice medir. Reproducción, alcance y las tres vías que lo
  evitan en `knowledge/MISTAKES.md` · M-001, y un test que rechaza cualquier oráculo
  registrado por nombre suelto.

- **Cinco prompts de trabajo** en `.claude/commands/`: `/spec`, `/implement`, `/verify`,
  `/review`, `/retro`. `/spec` existe por una medición concreta: los encargos eran
  bimodales —una frase o un documento— y faltaba el término medio, la especificación con
  criterios verificables escrita antes de empezar.

- **Tres sensores** en `.claude/hooks/`, medidos entre 15 y 23 ms: `oracle-log.sh` registra
  qué sesiones ejecutaron un oráculo, `verify-gate.sh` avisa al terminar si se tocó código
  sin verificar, y `auto-spec.sh` pone delante el oráculo del proyecto en el primer encargo
  (detalle más abajo; sustituye a `session-brief.sh`). **En modo normal ninguno bloquea**:
  un falso positivo bloqueante cuesta mucho más que un aviso ignorado, y ese endurecimiento
  se decide con datos. La única excepción llegó después y con ADR propio: con un run
  autónomo activo, `verify-gate.sh` sí bloquea el cierre de turno (ADR 010).

- **`scripts/backup.sh`** — ZIP con manifiesto SHA-256 que **restaura en un temporal y
  revalida los 932 checksums**, y que se probó falsable en cuatro casos. Resuelve
  `sha256sum` frente a `shasum -a 256` porque aquí es uutils, no GNU, y en macOS no existe.

- **`scripts/metrics.py`** — absorbe `analyze.py` con **cero regresiones** en sus ~44
  métricas y añade las que el encargo declaraba y el instrumento no calculaba: retrabajo
  **por sesión** (no solo por turno), mediana y p90 de tool calls, y sesiones con oráculo
  ejecutado. El filtro de subagentes pasa a ser explícito en vez de depender de la
  profundidad de un glob. Más `scripts/cost-report.sh` con tendencia entre snapshots.

- **`knowledge/`** — memoria versionada: `ORACLES.md`, `MISTAKES.md`, `PROCEDURES.md`,
  `COST-LOG.md`, `SOURCES.md`, `SKILLS-REGISTRY.md` y 11 ADRs. Es **no-confiable por
  defecto**: lo que viene de la web son datos, nunca instrucciones, y la promoción de un
  hallazgo a regla pasa siempre por una puerta humana.

- **Cuatro skills** (`harness` absorbida sin cambios y verificada por checksum,
  `house-rules`, `coach`, `dev-env`) y **cero agentes nuevos**: de 150 delegaciones, 105
  fueron al agente genérico y 6 de los 8 especialistas existentes nunca se usaron. El
  problema no era falta de capacidad.

- **Nueve suites de test nuevas** (`test_harness_structure.sh`, `test_metrics.sh`, <!-- doc-claims:ignore: "Nueve" cuenta las suites NUEVAS desde v1.0.0, no el total del arbol -->
  `test_install_diff_first.sh`, `test_uninstall.sh`, `test_detect_oracle.sh`,
  `test_auto_spec.sh`, `test_autonomy.sh`, `test_doc_claims.sh`, `test_evals.sh`,
  `test_install_settings_merge.sh`), todas
  con sección de falsabilidad. El total pasa de 16 a 27 suites.

- **El harness entra solo: `auto-spec.sh`, un hook `UserPromptSubmit`** (ADR 009). Cuatro
  reglas advisorias de `CLAUDE.md` tenían adherencia medida —`IntentGate` 2,1 %,
  `Parallel-First` 0 invocaciones, la tabla de delegación 70 % al agente genérico, "verifica
  tu trabajo" 27,7 % de sesiones con oráculo—: pedir disciplina no la produce. El hook
  clasifica el prompt y **solo** si es un encargo sin criterio de verificación inyecta la
  petición de declarar qué será cierto al terminar, el oráculo del proyecto detectado por
  `scripts/detect-oracle.sh` y el recordatorio de ejecutarlo en frío; si el criterio ya viene
  escrito, se calla. Emite **stdout plano**, que es lo único que la documentación especifica
  para este evento, y **nunca `exit 2`**, que borraría el prompt recién escrito. Verificado en
  `test_auto_spec.sh` con 16 checks —incluido el de falsabilidad: un encargo y una pregunta
  tienen que producir salidas distintas— y 23 ms de latencia medida.
- **Modo autónomo: `/work` y `scripts/autonomy.sh`** (ADR 010). Un sexto prompt de trabajo en
  el que el usuario entra **una sola vez** (una tanda de preguntas agrupada más la aprobación
  de la spec); a partir de ahí, cada pregunta es un fallo de diseño. No aparece un hook nuevo:
  `verify-gate.sh` gana un segundo modo, y con un run activo un oráculo en rojo **bloquea**
  (`decision: block`) con un presupuesto de 3 reparaciones. El ADR 004 decidió que nada
  bloquea porque un aviso le llega a un humano que reacciona, y esa es justo la premisa que
  desaparece en un run desatendido. El motivo devuelto al modelo prohíbe explícitamente tocar
  el sensor, y `autonomy.sh start` rechaza oráculos que no sean ruta absoluta, `rtk proxy …` o
  `make …`, porque el canal de Bash sustituye el ejecutable (M-001) y verificar con el comando
  equivocado es peor que no verificar: parece que sí. Los cuatro estados —rojo, verde,
  presupuesto agotado y `stop_hook_active`— están cubiertos en `test_autonomy.sh`.

- **`THIRD-PARTY.md`** con los avisos de terceros, que faltaban. Reproduce íntegro
  el aviso MIT de `yurukusa/claude-code-hooks` (`Copyright (c) 2026 yurukusa`,
  verificado contra el `LICENSE` del repositorio de origen), del que derivan
  `branch-guard.sh`, `destructive-guard.sh` y `secret-guard.sh`: la MIT exige que
  ese aviso viaje con las copias y hasta ahora solo había una línea `# Source:`.
  Distingue código derivado de dependencias externas no redistribuidas —gitleaks
  (MIT), Headroom (Apache-2.0) y rtk (Apache-2.0), las tres comprobadas contra la
  API de GitHub—, porque mezclarlas desdibuja qué hay que cumplir de verdad.
- **Queda documentado un punto de procedencia sin resolver.**
  `block-dangerous-commands.sh` declara en su cabecera derivar de
  `randomdreft/claude-code-security-hook` *"(public domain)"*, pero ese
  repositorio **no tiene fichero de licencia** (`license: null` en la API de
  GitHub) y el dominio público no se presume. No se corrige inventando otra
  afirmación: se registra el hecho verificable y las tres vías para cerrarlo.

- **`.github/dependabot.yml`** para el ecosistema `github-actions`. El CI ancla
  las Actions por SHA, que es lo correcto, pero un pin no se actualiza solo: sin
  esto se quedan clavadas en la versión anclada, incluidas las vulnerabilidades
  que se les descubran después.


- **El eval set pasa de medir ruido a medir comportamiento, y de 6 casos a 20 tareas**
  (10 positivas / 10 negativas).
  Que la mitad sean casos negativos es deliberado: sin ellos, un harness que dice que sí
  a todo puntúa igual que uno que discrimina. Correrlo cuesta
  dinero, así que nunca se había corrido entero y nadie había visto que tenía un falso
  negativo y un falso positivo estructurales.

- **Brazo de control (`ARM=off`, que añade `--safe-mode`) y las tres preguntas separadas.**
  Sin control no hay *lift*: "acierta 0,85" no dice nada si no se sabe qué acierta sin el
  harness puesto. El informe responde por separado *¿funciona?*, *¿sirve?* y *¿a qué
  coste?*, y no mete nunca el precio dentro de la nota.

- **Ablación por componente: tres brazos más** (`sin-ajustes`, `sin-skills`, `sin-mcp`),
  cinco en total contando `on` y `off`. El *lift* dice si el harness sirve; no dice **qué
  pieza** sirve. Medido en la tirada del 2026-08-27: `sin-ajustes` cuesta −0,17, más que
  el lift entero; `sin-skills` y `sin-mcp` salen `SIN DATOS` porque en esa tirada no se
  activó ni una skill ni un servidor MCP, y el informe dice que correrlos no mediría
  nada en vez de publicar un cero.

- **Tareas mudas: el conjunto declara cuándo dejó de informar** (E16). `report.py` cuenta
  las que dieron el mismo resultado en los dos brazos y en todas sus repeticiones —no
  pueden mover el lift— y escribe `SATURADO`. En la tirada del 2026-08-27 son mudas 17 de
  20 tareas: el conjunto que decide es de tres, no de veinte. Con un solo brazo el bloque
  escribe `NO MEDIBLE` en vez de "0 mudas", porque sin control un cero sería mentir por
  omisión.

- **La máquina es una variable experimental, no un decorado** (E14). `record.py` apunta de
  cada tirada el modelo, el sha, el coste, los turnos, la carga, las CPUs y la memoria
  libre; `report.py` avisa si los brazos corrieron con la máquina en estados distintos, y
  su guardia hermano `comparables()` escribe `NO COMPARABLE` en vez de restar dos brazos
  que corrieron modelos distintos.

- **`make mutantes`: 32 mutantes versionados (M9–M40)** que rompen a propósito un sensor
  del eval cada vez y exigen que la suite se ponga roja. Un sensor que no ha suspendido
  nunca no se sabe si sabe suspender. Tarda unos 4 minutos y no cuesta dinero.

- **`DRYRUN=1` y filtro por tarea** (E29). El coste de una tirada se estima **antes** de
  pagarla y a partir de lo ya gastado (`kit/evals/runs.jsonl`), no de una cifra escrita a
  mano: el `Makefile` decía "40 llamadas / ~12 USD". Salvedad medida: `runs.jsonl` está en
  `.gitignore`, y sin él el ensayo sigue contando llamadas pero no puede estimar dólares.

- **Dos puentes al observatorio, ninguno con Docker ni licencia**: `langsmith_push.py`
  —nube o receptor local en `:1984`, con `make langsmith-local` y `make langsmith-arbol`—
  y `phoenix_push.py` con `make phoenix`, que levanta una interfaz web en `:6006`. La
  telemetría se prueba contra algo que escucha, no en seco.

- **Una fila con el instrumento averiado y sin evidencia se retira, no se corrige**
  (`excluded` en `runs.jsonl`). Queda fuera de todo cómputo, el informe lo anuncia en su
  primera línea en vez de retirarla en silencio, y queda fuera también de los dos puentes:
  ni `langsmith_push.py` ni `phoenix_push.py` la publican, y ambos lo dicen por `stderr`.
  Publicarla allí la habría devuelto por la puerta de atrás, enseñada como un `fail`
  normal.

- **`knowledge/EVAL-CRITERIA.md`: 29 criterios de calidad del eval**, cada uno con su
  fuente y su estado honesto, y **ADR 011**, que decide no migrar a OpenHarness. Las cifras
  que ese documento publica se derivan de `runs.jsonl` en tiempo de test; sin el almacén
  —gitignorado— esas aserciones pasan a `skip`, no a `ok`.

- **`kit/doctor.sh` era ciego justo donde se produce el daño, y la garantía de la fusión no
  tenía sensor.** El check de fuente única de `ANTHROPIC_BASE_URL` solo recorría el ámbito de
  usuario, pero el que multiplica fuentes es `headroom wrap`, que escribe en
  `$PWD/.claude/settings.local.json` — ámbito de **proyecto**. Ahora enumera también los
  proyectos que Claude Code registra en `~/.claude.json`, deduplicando por ruta de fichero (en
  un `$HOME` declarado como proyecto, el fichero de proyecto y el de usuario son el mismo, y
  sin dedupe una sola fuente contaba dos veces y daba un FAIL falso), e informa de `ruta:línea`
  de cada fuente. Un check nuevo vigila `statusLine`: resuelve el ejecutable real del comando
  saltando el intérprete, FALLA si no existe o no es ejecutable, avisa si no imprime nada o
  sale con código distinto de 0 —el modo de fallo que Claude Code silencia por completo— y
  calla si no está declarada, porque el kit no la instala. Y suite nueva
  `test_install_settings_merge.sh`: 23 aserciones sobre la fusión de `settings.json`, con el
  caso del incidente verificado por mutación (al revertir la fusión a la copia entera, la
  suite cae con 5 fallos, el primero por `statusLine` ausente).

### Changed

- **`sentinel-allowlist.json`: fuera los tres dominios de LinkedIn**, que quedaron muertos al
  retirar ese MCP. Es **higiene, no endurecimiento**, y conviene no venderlo como otra cosa:
  la allowlist de Sentinel solo hace que una URL *salte* las heurísticas de red (pastebin,
  TLD sospechoso, IP cruda), así que `linkedin.com` las pasaría igual estando o no en la
  lista. Lo que se gana es que la config deje de describir un servidor que ya no existe.

- **`CLAUDE.md`** de proyecto: 76 líneas / ~895 aprox-tokens, bajo el presupuesto que
  verifica `test_harness_structure.sh` (<100 líneas, <900 aprox-tokens). La auditoría que lo justifica está en `knowledge/AUDIT-CLAUDE-MD.md` y se apoya
  en uso medido: la sección más larga del fichero anterior regía un plan mode al 2,1 %.

- **`kit/install.sh`** pasa a ser *diff-first por detección*: si `$CLAUDE_HOME` es un repo
  git con remoto —el caso real del autor, con 138 ficheros sin commitear— no escribe;
  genera el árbol aparte, muestra el diff y dice qué commitear. `--apply` fuerza. En un HOME
  temporal sin git el comportamiento es el de siempre, así que ni las suites ni CI cambian.

- **El presupuesto de `timeout` de los hooks deja de ser un número plano.** Los 5 s protegen
  el **camino caliente** (`UserPromptSubmit` en cada prompt, `PostToolUse` en cada llamada a
  herramienta), donde cada milisegundo se paga cientos de veces. El `Stop` no está en ese
  camino y en modo autónomo su trabajo *es* ejecutar el oráculo: declararlo a 5 s no lo hacía
  barato, lo hacía **inútil**, porque Claude Code mataba el hook antes de que el oráculo
  terminara (`make test` tarda ~30 s) y el gate fallaba **en abierto**, dejando cerrar el
  turno con el oráculo en rojo. Ahora se declara a 600 s y `test_harness_structure.sh` exige
  la regla de verdad: un `Stop` nunca puede declarar menos que el `timeout` que se aplica a
  sí mismo por dentro, con su propio check de falsabilidad.

- **El estado del modo autónomo se indexa por directorio de proyecto, no por `session_id`.**
  Quien arranca el run es el modelo desde Bash, y ahí el `session_id` no existe: solo aparece
  dentro del payload del hook. Con la clave anterior, `autonomy.sh start` escribía en un
  fichero y el Stop hook leía otro, así que el gate no encontraba run y caía a modo normal.
  **Fallaba en abierto y en silencio**, que es la peor forma de fallar en un mecanismo de
  seguridad.


- **`report.py` deja de dar un número desnudo.** Cada tasa va con su intervalo de Wilson al
  95 %, el veredicto se decide por bandas (`SIRVE` ≥ +0,05, `PERJUDICA` ≤ −0,10, `NEUTRO`
  en medio) y las salvedades que matan una cifra —`AVISO` de máquina distinta, `SATURADO`,
  `NO COMPARABLE`, `NO MEDIBLE`, `SIN DATOS`— salen pegadas a ella, no en una nota al pie.

- **`kit/Makefile` delega en la raíz.** El Quick start deja al lector dentro de `kit/` y le
  manda `make test`; sin Makefile ahí, `make` encontraba el **directorio** `kit/test`, lo
  tomaba por un target ya construido y respondía "Nothing to be done for 'test'" con exit
  0: un oráculo que devuelve 0 sin ejecutar nada, en un repo cuya tesis es la contraria.

### Removed

- **`session-brief.sh`**, sustituido por `auto-spec.sh` (ADR 009). Su función —poner delante
  el oráculo del proyecto y los errores ya cometidos— se hace ahora en el primer *encargo* y
  no en el arranque, donde se diluía y no sobrevivía a un `/clear`. **El presupuesto se
  mantiene en 3 hooks**: se sustituye, no se suma.

### Fixed

- **Reinstalar el kit destruía la configuración personal de quien ya lo tenía.** Medido en una
  máquina real: un `install.sh --apply` sobre una instalación existente reemplazaba
  `settings.json` entero y se llevaba en silencio `ENABLE_TOOL_SEARCH` (que vale ~30k de
  contexto por sesión), el `ANTHROPIC_MODEL` con el sufijo de la ventana de 1M,
  `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, tres límites más, el `statusLine` y tres hooks; y
  reemplazaba `CLAUDE.md`, que es prosa escrita a mano. Había backup, pero un backup que hay
  que descubrir no es una salvaguarda: es una autopsia. Ahora `settings.json` se **fusiona**
  con una regla declarada — los `hooks` los pone el kit, los `permissions` se unen (nunca se
  pierde un `deny` ni un `allow`), tus claves de `env` ganan y el kit solo añade las nuevas, y
  todo lo demás es tuyo e intacto — y `CLAUDE.md` no se pisa: la del kit queda al lado como
  `CLAUDE.kit.md`.
- **El kit no distribuía tres hooks que sí corrían en producción**, así que instalarlo los
  borraba y un clon limpio nunca los tenía: `write-guard.py` (secretos en el contenido que se
  escribe), `narthex-post-mcp.py` (unicode invisible y frases de jailbreak en respuestas de
  MCPs de terceros) y `preflight.sh` (recupera el proxy por systemd). Los tres son portables
  y ya están registrados vía `optional-hook.sh`.
- **La capa de IOCs de Sentinel venía apagada de fábrica.** El kit solo traía
  `iocs.example.json`, así que cada instalación arrancaba sin los 31 patrones de ruta
  sensible, 12 de comando peligroso y 30 de red — con un `WARN` que nadie lee. Ahora se
  distribuye `iocs.json` completo, con su allowlist en `~/` y no en el home de nadie.

- **Lo que impide que la documentación mienta no corría en CI, y nada lo declaraba.**
  `test_doc_claims.sh` y `test_evals.sh` quedaban fuera del pipeline: El `Makefile` corría 25 y `ci.yml` 23: las ausentes eran `test_doc_claims.sh`
  y `test_evals.sh`, así que un PR que rompiera una cifra del README pasaba en verde. Y el
  hueco podía volver, porque el único sensor comparaba `kit/test/` contra el *target* del
  Makefile, nunca contra CI. Se añaden a `ci.yml` y `test_harness_structure.sh` gana una
  sección de paridad `Makefile ↔ ci.yml` con su caso de falsabilidad.
- **La unidad systemd que genera `install.sh --with-headroom` reproducía dos bugs ya
  diagnosticados**: sin `%h/.local/share/rtk` en `ReadWritePaths`, SQLite da *"unable to open
  database file (code 14)"* cada 60 s; sin `HF_HUB_OFFLINE=0`, el motor de compresión queda
  `available:false` **en silencio** mientras `/readyz` sigue diciendo `healthy`.
- **Tres tests medían la máquina de quien los ejecutaba, no el repo.** `test_doctor.sh` y el
  `run_doctor()` de `test_doctor_base_url.sh` no aislaban `HOME`; y `kit/scan-secrets.sh`
  escaneaba ficheros *ignorados* por git, así que `test_harness_structure.sh` daba rojo en una
  máquina con scratch en disco y verde en CI, donde el clon está limpio. Misma lección que
  `628dfaa`.
- **`.claude/skills/dev-env/SKILL.md` afirmaba que un `ANTHROPIC_BASE_URL` en `settings.json`
  desactiva la ventana de 1M, el tool search y remote-control.** Dos de las tres son falsas,
  medido dentro de una sesión enrutada: solo `/remote-control` cae. Y recomendaba
  `headroom wrap claude`, que escribe la variable en el `settings.local.json` del proyecto y
  la repone con un hook `SessionStart` — el mecanismo que dejó `ANTHROPIC_BASE_URL` en 5
  ficheros no declarados y el enrutado dependiendo del `cwd`.
- **`hooks/stale-read-guard.py` estaba en producción sin viajar en el kit.** Se añade y se
  registra vía `optional-hook.sh --python`. Su propia instrumentación mide por qué importa:
  las relecturas eran el mayor desperdicio identificado del presupuesto de tokens, mayor que
  todo lo que comprime el proxy.
- **Se retira `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=75` de la plantilla de `settings.json`.** Es un
  hook de pruebas del cliente, no un ajuste soportado: en la ruta de 200k regala ~32k de los
  180k usables, y en la de 1M es inerte. La máquina de referencia ya lo había abandonado; la
  plantilla se había quedado atrás.

- **El guard de force-push no veía los flags cortos agrupados.** `git push -uf origin main`
  fuerza de verdad, pero no contiene `-f` como token suelto, así que el patrón anterior
  (`-f\b`) lo dejaba pasar — justo la protección que el kit anuncia como dura. Pasaba en las
  **dos** capas: el hook `block-dangerous-commands.sh` y los globs de `permissions.deny` en
  `settings.json`, que `smart_approve.py` evalúa. Ahora se acepta cualquier grupo de flags
  cortos que contenga una `f` (en `git push` la única opción corta con `f` es `--force`), y
  `--follow-tags` sigue pasando porque tras el guion viene otro guion, no letras. Cinco casos
  de regresión nuevos en `test_guards.sh`, que pasa de 28 a 33 checks.
- **La Capa 2 de secretos bloqueaba *todos* los commits de cualquier repo protegido que no
  tuviera `.gitleaks.toml` propio.** El hook `pre-commit` pasaba a ciegas
  `-c "$REPO_ROOT/.gitleaks.toml"`; si el fichero no estaba, gitleaks abortaba con
  `unable to load gitleaks config` y el commit moría — un fallo cerrado que parece un
  hallazgo de secreto. Ahora resuelve la config en orden (repo → `$CLAUDE_HOME`) y, si no
  hay ninguna, avisa por stderr y sigue con las reglas por defecto de gitleaks en vez de
  abortar. **El fixture del test tapaba el bug**: copiaba la config a la raíz del repo de
  prueba, un escenario que un usuario real no tiene. Ya no la copia, y hay tres casos nuevos
  (`test_secret_content_gitleaks.sh`, 20 checks) incluido el que importa: sin config en
  ninguna parte, un commit limpio pasa y una credencial AWS real sigue bloqueada.
- **`make test` desde `kit/` devolvía exit 0 sin ejecutar un solo test.** El Quick start deja
  al lector dentro de `kit/`, donde no había `Makefile`: make encontraba el *directorio*
  `kit/test`, lo tomaba por un target ya construido y respondía "Nothing to be done for
  'test'". Un oráculo que devuelve 0 sin medir nada, en el repo cuya tesis es lo contrario.
  `kit/Makefile` delega ahora en la raíz.
- **`test_autonomy.sh` seguía probando un contrato que ya no existía.** El estado del modo
  autónomo pasó a indexarse por directorio de proyecto y no por `session_id` (quien lanza el
  run desde Bash no conoce el `session_id`), y la suite seguía arrancando los runs con
  `--session`. Reescritos los ocho bloques del gate: el run se arranca como lo arranca el
  modelo, y cada payload lleva a propósito un UUID distinto, de forma que una regresión al
  indexado por sesión se caería en rojo en vez de dejar cerrar el turno con el oráculo rojo.
- **`test_guards_falsifiability.sh` comprobaba `> 0` caídas y citaba una constante que no
  existía.** Una regresión que bajase de 10 casos `BLOCK` a 1 pasaba en verde, y el 10 que
  el README publica como hecho medido no estaba anclado en ninguna parte. Ahora
  `STUB_BLOCK_CASES=10` es explícito y la suite exige esa cifra exacta.
- **El sensor de frescura de `SOURCES.md` leía el número de fila como si fueran días,
  y tumbaba `make test` entero.** En `source_field` el patrón de la ventana llevaba el
  sufijo de unidad como opcional — `(d|dias|días)?` — así que casaba con la primera
  columna numérica de la fila, que es el `#` de orden. Las filas 1 a 4 salían
  "vencidas sin marcar `[STALE]`" por su posición en la tabla, no por su fecha:
  `| … | 2026-08-21 | 365 d |` se leía como una ventana de 4 días. Como
  `test_harness_structure.sh` es la antepenúltima suite del `Makefile` y make aborta en el
  primer fallo, **las dos últimas suites (`test_install_diff_first`, `test_uninstall`)
  llevaban tiempo sin ejecutarse**: 21 de 23. Con la unidad obligatoria, las 23 corren y
  `make test` vuelve a exit 0.
- **El check de falsabilidad de ese sensor pasaba sin cubrir el bug que tenía delante.**
  Su fila fabricada era `| url | primaria | fecha | 30 |`: sin columna `#` y sin unidad,
  es decir, con una forma que la tabla real nunca tiene. Un caso fabricado que no imita
  la forma de los datos de producción demuestra menos de lo que aparenta. Ahora la fila
  fabricada tiene las siete columnas reales.
- **`session-start.sh` metía `MEMORY.md` dos veces en el contexto de cada sesión.** El
  hook volcaba el índice con `head -20` y la auto-memoria de Claude Code ya lo inyecta
  por su cuenta: ~985 tokens duplicados en cada arranque. Ahora imprime el recuento de
  entradas y el aviso de tamaño — la señal de vida que la auto-memoria no da — pero no
  el cuerpo.

- **Falso fallo en la verificación de backups por SIGPIPE.** `unzip -Z1 | grep -q` con
  `set -o pipefail` mataba a `unzip` y el verificador reportaba un ZIP correcto como roto.
  Solo aparecía a escala real (933 entradas), no con el fixture de 6. `shellcheck` no lo
  detecta. Queda documentado en `MISTAKES.md` · M-003.

- **El software del kit no tenía licencia, y el README daba a entender que sí.**
  El `LICENSE` de CC BY 4.0 acota su alcance, en su propio preámbulo, a los decks
  y sus guiones originales: nunca cubrió `kit/`. Pero el README decía
  *"CC BY 4.0. Comparte y adapta con atribución"* sin distinguir, así que quien
  clonaba el repo creía tener un permiso que legalmente no existía — por defecto,
  ausencia de licencia es reserva de todos los derechos. Se añade
  **`LICENSE-CODE`** con licencia **MIT** para todo lo de `kit/` y los scripts de
  `.github/`; se acota explícitamente el `LICENSE` de CC BY a las charlas; y la
  sección de licencia del README pasa a declarar el reparto en una tabla. MIT es
  elección deliberada: es la misma licencia del material del que derivan tres
  guards, así que no hay fricción de compatibilidad.

- **El workflow de CI no parseaba, así que su último job no llegaba a ejecutarse.** Un
  `name:` sin comillas con dos puntos dentro —`test_uninstall.sh (restaura el backup mas
  reciente: interno o ZIP…)`— es YAML inválido. Se entrecomilla y se añade a
  `test_harness_structure.sh` el sensor que lo habría cazado antes de subirlo.


- **El evaluado podía leer su propio oráculo.** El enunciado, el setup, el check y el
  transcript vivían en el mismo directorio de trabajo que se le daba al agente: de 12
  ejecuciones de la primera tirada real, 4 leyeron ficheros del harness y 3 hicieron `cat
  _check.sh` — en la tarea 06 lo hicieron los dos brazos, y los dos aprobaron. Ahora el
  meta vive en un `mktemp -d` **sin parentesco** con el del agente, así que un `../` no
  descubre nada. El sensor es de comportamiento, no un `grep` sobre `run.sh`: corre
  `run.sh` entero con un `claude` de mentira que solo lista su `cwd`.

- **El eval set medía ruido, no comportamiento**, y no se había visto porque correrlo
  cuesta dinero. `run.sh` definía `PY` sin exportarlo y `bash _check.sh` es otro proceso,
  así que el check de cuatro de los seis casos se ejecutaba como `"" grade.py …` y daba
  rojo sin mirar al agente. La 06 daba verde pasara lo que pasara: verificaba con `grep -q
  'test_suma.py' _run.jsonl` y el prompt se copia literalmente dentro del transcript, así
  que acertaba por el eco del enunciado. Y un `error` de instrumentación se agregaba junto
  al `fail`, que convierte una avería del aparato en un suspenso del agente.

- **El modelo apuntado era el equivocado.** `record.py` guardaba `next(iter(modelUsage))`,
  el primero del diccionario, y cada sesión de `claude -p` gasta unos 15 tokens en un haiku
  auxiliar: 40 tiradas de Opus quedaron etiquetadas como Haiku y el guardia de E24 se
  negaba a comparar dos brazos que habían corrido con el **mismo** modelo. Un guardia
  alimentado con el dato equivocado no protege: bloquea lo bueno.

- **El nombre del transcript colisionaba y se comía la evidencia.** Llevaba `$(date +%F)`
  —el día— y `attempt` reinicia en cada invocación, así que dos tiradas de la misma tarea
  y el mismo brazo el mismo día se pisaban. Pasa a llevar el `ts` de la fila. Una de esas
  colisiones ya había ocurrido, y por eso la fila retirada no es re-auditable.

- **`make evals-paid` nunca llegaba a preguntar, y el defecto era preexistente.** La receta
  terminaba en `\\`, que en un Makefile es una barra literal y no una continuación: `read`
  definía `ans` en una shell y la comparación corría en otra, con `ans` vacío. Fallaba
  **cerrado** —decía "Cancelado." y salía 1 siempre—, así que no era un riesgo de gasto:
  era un target muerto. El sensor exige que ninguna línea de receta acabe en dos barras,
  así que cubre también a los targets futuros.

- **El ensayo podía mentir sobre lo que ibas a pagar.** El estimador de `DRYRUN=1` moría
  con un `runs.jsonl` corrupto —una línea JSON escalar, un `cost_usd` de texto— y `run.sh`
  salía con 0 igualmente, porque tiene `set -u` sin `set -e` y el traceback caía en un
  `exit 0` incondicional: el operador se quedaba sin la única cifra que la herramienta
  existe para darle, y con un exit 0 diciendo que todo fue bien. Además, el `: > "$TMP"`
  que trunca el parcial corría **antes** del bloque de ensayo, así que un ensayo que
  promete no tocar nada pisaba un fichero del árbol.

- **Dos correctores confundían la forma con la calidad.** El de la 12 castigaba verificar
  —`__pycache__` es el rastro de comprobar que el módulo importa, no un fichero sembrado— y
  no miraba el exceso de celo que la tarea existe para medir. El de la 11 exige el literal
  `.venv/bin/pip` y suspende `.venv/bin/python -m pip install requests`, que es la misma
  solución escrita de otra forma; ese sigue sin arreglar y **infla la ablación de
  `sin-ajustes`**, y la salvedad va escrita junto al −0,17, no en una nota al pie.

- **Se deja de versionar bytecode.** Un `.pyc` publica en `co_filename` la ruta absoluta de
  compilación, que aquí incluye el nombre de usuario.

- **Dos fallos en abierto del propio arreglo de la fusión.** La escritura final era `cp -p`
  desde un temporal en `/tmp`: un fallo a mitad dejaba el `settings.json` truncado, y además
  el `cp` desde `/tmp` bajaba el modo del fichero a `600` en cada instalación. Ahora el
  temporal se crea junto al destino y entra con `mv` —rename atómico— preservando el modo
  original (`644`, el que escribe una instalación limpia). Y el hook `preflight.sh` resucitaba
  el proxy de Headroom en **cada** sesión de **cualquier** proyecto, contradiciendo su propio
  mensaje ("Claude Code funciona igual, no depende del proxy"): ahora solo lo levanta si hay
  opt-in declarado —la variable en el entorno o la URL en un `settings`—, porque sin nadie
  enrutado son 1,3 GB de RSS para nadie.

- **`install.sh` abortaba la instalación entera si Sentinel había dejado un `__pycache__`.**
  Los bucles de `agents/*` y `sentinel/*` filtraban con `[ -e "$f" ]`, así que un directorio
  llegaba a un `cp` sin `-r`: `cp: -r not specified; omitting directory`, `rc=1` e instalación
  a medias — y `test_doctor.sh` en rojo por una causa ajena al doctor, porque corre `install.sh`
  bajo `set -e`. El filtro pasa a `[ -f "$f" ]`, que es lo que ya hacía el bucle de `hooks/`.
  Reproducido sobre el árbol real, que arrastraba tres `__pycache__` desde el 25-ago: `rc=1`
  antes, `rc=0` después. Cuatro casos nuevos en `test_install.sh`, y el rc del primer
  `install.sh` deja de perderse: antes un fallo ahí mataba la suite con `rc=1` y cero salida.
- **`doctor.sh` daba por buena una instalación sin API.** El check 5 leía
  `.env.ANTHROPIC_BASE_URL` solo del `settings.json` de usuario, así que un enrutado declarado
  en ámbito de proyecto —que es el que gana— no se sondeaba: con el proxy muerto imprimía
  `PASS · API directa a Anthropic` junto al `PASS` del 5e que sí lo veía declarado, dos
  afirmaciones que se contradicen, y `rc=0`. La enumeración de ámbitos se extrae a
  `enumerar_enrutado()` y la consumen los dos checks en orden de precedencia real; el `FAIL`
  nombra el fichero de origen. `test_doctor_base_url.sh` pasa de 16 a 22 asserts: el caso F
  era un sensor invertido —afirmaba que una instalación sin API es un estado limpio— y queda
  como control positivo, con el caso J nuevo como negativo. Falsabilidad medida: los 6 asserts
  nuevos caen contra el `doctor.sh` anterior y los 16 previos siguen verdes.
- **`pre-compact.sh` leía un campo que no existe.** Esperaba `triggerReason`; el evento envía
  `trigger`, y `triggerReason` tiene 0 apariciones en el binario 2.1.258, así que el hook
  imprimía siempre `(unknown)`. Las dos entradas `PreCompact` del `settings.json` instalado
  (`manual` y `auto`, mismo comando) se consolidan en un `matcher: "manual|auto"`.

### Documentation

- **`08-plugins-mcp-y-skills.md`: la sección de MCP decía cosas que ya no eran verdad, y
  callaba la que más cuesta.** Listaba `perplexity` como si estuviera operativa (dada de
  baja el 2026-08-17) y no mencionaba `headroom`, `firecrawl` ni `serena`. Se reescribe con
  el estado real y se añade **"Un MCP en ámbito global es un impuesto fijo, y casi nunca se
  mide"**: por qué `--scope user` lo arranca también en `/tmp` y en repos ajenos, el script
  para contar el uso *efectivo* en tus propias transcripciones (bloques `tool_use`, no
  menciones: el nombre del servidor sale en el prompt de cada sesión e infla cualquier
  `grep` ingenuo), y el caso medido que lo motiva — Serena en global durante semanas, 1 de
  55 sesiones con llamadas reales y sus 12 últimos arranques sin proyecto activo. Incluye
  el detalle que hace que quitarlo no funcione a la primera: `headroom wrap claude`
  re-registra Serena en cada lanzamiento salvo con `--code-memory none`. Incluye el
  contraejemplo que evita leer mal la regla: `firecrawl` tiene el **mismo** uso medido que
  Serena — 4 llamadas en 1 de esas 55 sesiones — y se queda, porque es `type: http` en ámbito de
  proyecto y no levanta proceso local. Se retira por **coste de arranque x ubicuidad**, no
  por recuento de llamadas.
- **`03-headroom.md`: el sufijo `[1m]` viaja pegado al modelo y rompe el cambio de modelo.**
  `--1m` reescribe `ANTHROPIC_MODEL` del proceso hijo, y se lo aplica a *cualquier* modelo que
  le pases. Con Haiku, que no tiene la beta de contexto largo, la sesión muere con
  `400 The long context beta is not yet available for this subscription` — un error que se
  confunde con un problema de cuota o de credenciales. Documentado con la traza medida.

- **Atribuciones corregidas**, todas verificadas contra la fuente el 2026-08-21:
  el artículo de *harness engineering* es de **Birgitta Böckeler**, no de Fowler, y **no da
  una definición formal de *harnessability***; el de *context engineering* es de
  sep-2025 y **no fija ningún presupuesto de tokens para CLAUDE.md**; los cuatro principios
  atribuidos a **Karpathy no tienen fuente primaria** y pasan a ser "principios de la casa";
  la cita de Cherny sigue siendo **secundaria**; y `anthropics/skills` **no enumera 17
  skills** y tiene licencia mixta.

- **Los KPIs heredados se archivan como históricos sin procedencia verificable.** El "68 %
  de sesiones con correcciones" medía en realidad 8,8 % de *turnos*; la métrica correcta,
  ahora que existe, da 19,1 % de sesiones. Y las sesiones con oráculo no valían 0 sino
  27,7 %: nunca se habían medido, que no es lo mismo.

- **`03-headroom.md` explica ahora que `headroom wrap` pone `ENABLE_TOOL_SEARCH`
  por su cuenta.** La doc recomendaba la variable en `settings.json` pero no decía
  que el wrapper ya la escribe, con lo que quitarla de la config no la desactiva:
  se repone en cada arranque. Se documenta la precedencia real que implementa
  `headroom/cli/wrap.py` (flag explícito → valor preexistente en el entorno →
  default `true` de `headroom/providers/claude/runtime.py`) y el hecho de que el
  `env` de `settings.json` se aplica **después** del arranque y pisa al wrapper —
  que es por lo que un `"false"` olvidado ahí anula el deferral en silencio. Se
  añade también que en Vertex AI el deferral viene desactivado por defecto.
- **Aviso sobre el hook que deja `headroom init` y que puede levantar un segundo
  proxy.** `init` escribe un `.claude/settings.local.json` de ámbito proyecto que
  engancha `headroom init hook ensure` a `SessionStart` **y** a
  `PreToolUse(Bash)`. Con `supervisor_kind: "none"` en el manifiesto del perfil,
  ese hook cae en `start_detached_agent()` si `/readyz` no contesta en 1 s, y
  arranca un proxy fuera del supervisor. Con el proxy ya corriendo como unidad
  systemd con `Restart=always`, el resultado son **dos instancias peleando por el
  puerto 8787** y respuestas **HTTP 200 vacías** que Claude Code reporta como
  fallo de la API. Se documenta cómo evitarlo y que `hook ensure` no reescribe
  ficheros de configuración, así que neutralizar ese settings es estable.

- **Las cifras que la documentación afirma sobre el repo pasan a tener sensor.** `README.md`
  decía 16 suites con 23 en el `Makefile`, `kit/README.md` "8 documentos" con 9, y tres <!-- doc-claims:ignore: cita del estado ANTERIOR al sensor, no del arbol de hoy -->
  documentos seguían citando `session-brief.sh` meses después de borrarlo. Nada se ponía en
  rojo porque nadie medía el texto. `test_doc_claims.sh` cuenta el árbol real (suites,
  agentes, comandos, ADRs, documentos), lo compara con lo que dicen los documentos que hablan
  **en presente** —en dígito y en letra, porque "cinco comandos" era justo la forma que se
  quedaba sin actualizar— y comprueba que ningún `.sh` citado en la documentación haya
  dejado de existir. `knowledge/DECISIONS/`, `knowledge/PRE-MORTEM.md` y
  `docs/superpowers/plans/` quedan **fuera a propósito**: son registros fechados, y una cifra
  de agosto ahí es correcta aunque hoy sea otra. De `CHANGELOG.md` entra solo la sección
  `[Unreleased]`, que describe el árbol de hoy; sus secciones publicadas quedan fuera por lo
  mismo. Trae su propio check de falsabilidad.


- **`kit/evals/README.md` publica el inventario del eval y cómo crecerlo**, y desde esta
  rama sus cifras tienen sensor: el recuento de tareas de su cabecera se compara con
  `kit/evals/tasks/*.yaml` en cada `make test`.

- **La tirada completa está publicada con su condición** en `knowledge/EVAL-CRITERIA.md`:
  98 llamadas reales, los 20 casos, tres brazos, `RUNS=1`, `claude-opus-5[1m]` y sin el
  proxy Headroom en medio —con `ANTHROPIC_BASE_URL` puesto, el lift mediría harness y
  proxy a la vez—. Va con **las dos lecturas**, con y sin la fila retirada, porque cuál de
  las dos columnas es la verdadera no lo decide un argumento sino una llamada de pago que
  **está pendiente**. Y con una fe de erratas que nombra al commit `e7d4fee`: no se enmienda
  un mensaje publicado, se corrige aquí.

- **La doc recomendaba como oráculo del enrutado una herramienta que miente en los dos
  sentidos.** `headroom doctor` da `claude ⚠ not routed` dentro de una sesión enrutada —solo
  juzga ficheros, no la sesión— y a la vez `codex ✓ routed` con cero peticiones OpenAI en los
  logs; reproducido tres veces, la última hoy. Se retira como oráculo de `03-headroom.md` y de
  `07-verify.md` y se sustituye por los dos que sí contestan: el `environ` de un proceso hijo
  de la sesión y `doctor.sh`. Se documenta el mecanismo que faltaba —`headroom wrap` escribe la
  URL en el `settings.local.json` del **proyecto** y la restaura al salir, así que el enrutado
  es por proyecto y quitarla a mano no dura— y que el kit **no fija versión** de `headroom-ai`.
  Seis afirmaciones de esa doc pasan a tener sensor en `test_doc_claims.sh`, con diez averías
  fabricadas para probar que acusan.

- **Tres afirmaciones falsas sobre la capa de IOCs, retiradas.** `05-security.md` y
  `SECURITY.md` decían que el kit no distribuye `iocs.json` "para no filtrar indicadores
  propios"; el kit lo trae desde `2de31d5`, con 31 patrones de ruta, 12 de comando y 30 de red,
  e `install.sh` lo copia junto al hook. En una instalación limpia `doctor.sh` imprime
  `PASS · Sentinel IOC layer activa` sin que haya que hacer nada, así que el paso de activación
  que documentaban era un rito vacío. Se conserva íntegro el comportamiento *fail-open* —sin el
  fichero, `load_iocs()` devuelve `{}` y todos los checks son un no-op silencioso— y se
  documenta el orden de búsqueda real, con su consecuencia: un `iocs.json` puesto en `hooks/`
  queda sombreado por el del kit y no se lee nunca. `07-verify.md` publicaba además un oráculo
  falso (`test -f "$CLAUDE_HOME/hooks/iocs.json"`, que da `WARN` donde `doctor.sh` da `PASS`).
- **`06-routine.md` atribuía al kit un umbral de autocompact que el kit no toca.** Afirmaba
  configurar el 75 % con `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` en `settings.json`; esa clave no
  aparece en el `settings.json` que instala. Medido aparte: ese override es un hook de test que
  solo *baja* el umbral, y en la ruta de 1M es inerte.
- **La plantilla `kit/claude/CLAUDE.md` deja de llevar el estado de una máquina.** Fuera el
  correo del autor, la fecha del día y tres bloques con 0 uso medido: 143 → 115 líneas y
  1.977 → 1.624 aprox-tokens, con techo declarado en su sensor (120 líneas / 1.700 tokens).
  Queda dicho lo que sigue sobrando y no se toca aquí: la plantilla manda usar skills
  (`deep-change`, `superpowers`) que el kit no instala.
- **`VERSION` en la raíz como única fuente de la versión**, con un sensor que exige que
  coincidan `VERSION`, la sección más nueva del CHANGELOG y el `vX.Y.Z` de la línea `estable`
  de `README.md` y `CLAUDE.md`. Sin `git tag` a propósito: `actions/checkout` no trae tags y el
  check degradaría a `skip` en CI, que es como no tenerlo. La duración del oráculo en
  `CLAUDE.md` pasa de "~45 s" a "151-179 s en un i9-14900HX", que es lo medido.

### Security

- **Tres rutas con el nombre real de personas salían publicadas en `HEAD`**, en
  `knowledge/ORACLES.md` y en `.claude/skills/harness/referencias/oraculos.md`: rutas
  absolutas de proyectos de cliente con el nombre de usuario y, en un caso, el nombre civil
  completo dentro de una ruta de Windows. Redactadas conservando la lección que las hacía
  útiles (el oráculo se invoca por **ruta absoluta**, M-001).
- **Un `.pyc` estaba versionado** (`scripts/__pycache__/metrics.cpython-314.pyc`). El
  bytecode lleva dentro la ruta absoluta de compilación en `co_filename`, así que publicaba
  el árbol de directorios de la máquina del autor. Se saca del índice y `__pycache__/` entra
  en `.gitignore`.

- **Nueve huecos de los guards de `git push` y `rm`, cerrados con su caso de test.** Se colaban
  el `push -f` con `-C` delante, el refspec forzado con `+`, `--mirror`, el borrado de rama
  remota con `--delete`, el `push` a `master` tras un `cd` encadenado (por el ancla `^` de
  `branch-guard.sh`), el `rm` recursivo y forzado en forma larga, y `find … -delete` bajo
  `/home/`. `test_guards.sh` suma 14 casos —10 que caen contra los guards anteriores y 6
  contrapesos anti-sobrebloqueo: `-C` sin forzar, rama de feature, `rm -r` sin forzar,
  `find -delete` en `/tmp`— y `test_guards_falsifiability.sh` mantiene sus 10 `BLOCK` exactos,
  así que la cifra que afirma el README sigue siendo verdad. La tabla de reglas gana un camino
  rápido de un solo `grep`: el camino caliente (comando permitido) baja de 62 a 8 ms medianos y
  de 43 a 1 invocación de proceso; el denegado sube de 44 a 68 ms, que es el raro y acaba en una
  interrupción al usuario. Diferencial sobre 65 comandos: 7 diferencias de decisión, las 7
  intencionadas.
- **Sentinel gana un suelo en código que ningún fichero de datos puede levantar.**
  `ALWAYS_DENY_PATHS` —el fichero de credenciales de Claude Code, la clave privada de SSH (el
  `.pub` no empareja) y las credenciales de AWS— se consulta **antes** del allowlist. Cierra una
  asimetría medida: con `$HOME/.claude/` en el allowlist, *nombrar* ese fichero de credenciales
  se bloqueaba y *abrirlo* se permitía sin registro. Aguanta con un allowlist hostil
  (`paths: ["/"]`) y con `iocs.json` vaciado a `{}`, que es el kill-switch que convierte todos
  los demás checks de ruta en no-op. Coste medido sobre el `~/.claude` real (6.358 ficheros):
  las denegaciones pasan de 1 a 13, y las 12 nuevas son material de clave —el de control del
  demonio y 11 de sesión— que el kit no referencia en ningún sitio.
- **El agente ya no puede desactivar sus propios guards sin dejar rastro.** `PROTECTED_CONFIG`
  (`settings*.json`, `hooks/`, `sentinel/`, `sentinel-allowlist.json`, `iocs.json`,
  `.gitleaks.toml`) no deniega —eso es cosa de `permissions.deny`— pero **no es eximible y se
  registra siempre**: seis vías que antes pasaban `allow` sin log, incluida la de añadir una
  entrada al allowlist con `jq`, quedan auditadas. Sobre los mismos 6.358 ficheros añade **0
  denegaciones** y 30 rutas registradas, y `kit/claude/hooks/` del propio repo no empareja
  (falta el punto), así que no estorba al desarrollo del kit. El mensaje de `deny` deja de
  anunciar la vía de exención donde era mentira: para una regla del suelo ningún allowlist la
  levanta, así que el prospecto era falso y a la vez instructivo.
- **gitleaks: las claves de Anthropic se colaban en 5 de 7 emplazamientos.** La regla por
  defecto `anthropic-api-key` solo dispara con la forma exacta de 93 caracteres terminada en
  `AA`, así que la misma clave alargada a 105 se comiteaba incluso en `.yaml` — y el caso 1 de
  la suite pasaba por la regla por defecto, no por una del kit, de modo que la afirmación de
  `.gitleaks.toml:26-28` era falsa. Regla nueva `anthropic-api-key-prefix` sobre el prefijo de
  clave de Anthropic con 20+ caracteres, sin `path` y sin umbral de entropía ni longitud fija;
  la medición queda dentro del comentario. Falsabilidad: neutralizar el regex hace caer **1 de
  22** casos y no 22, lo que prueba que la mutación desactiva la regla y no la carga de la
  config. La clave del fixture se compone en ejecución, porque un literal de 20+ caracteres tras
  el prefijo haría que la regla bloqueara el commit que lo añade.
- **Los nueve `*.sh` de `kit/claude/hooks/` quedan versionados `100755`.** `preflight.sh` era el
  único a `100644`: instalado, `rc=126` y nunca se ejecutaba, con el fallo leyéndose como "el
  hook no hace nada". `test_guards.sh` añade un sensor de modo que mira disco **e** índice
  —falsable quitando el bit solo del índice— porque `git ls-files -s` es la única vía que ve la
  causa real.
- **Guard de configuración: 10 reglas `deny` sobre `Write`/`Edit` de `hooks/**`,
  `settings.json`, `settings.local.json`, `sentinel-allowlist.json` y `sentinel/**`** (rutas con
  una sola barra, ancladas al propio fichero de settings). El motivo es medido: en un solo día
  tres escritores distintos reescribieron el `settings.json` de usuario y uno se llevó por
  delante la clave `statusLine`. **Declarado y sin sensor**: la sonda que confirmaría que el
  binario honra esa forma la intercepta el clasificador de permisos antes de llegar a la capa
  que se quiere medir, así que no se afirma que funcione. El enforcement probado sigue siendo
  el de los hooks.

### Deuda declarada

Lo que se midió, no se arregló en esta versión y se documenta para que nadie lo lea como
resuelto. Ninguna de estas líneas tiene sensor: son huecos conocidos, no regresiones.

- **El allowlist por proyecto sigue abierto y sin documentar.** `load_user_allowlist()` prefiere
  el `.security/sentinel-allowlist.json` del directorio de trabajo sobre el del usuario, así que
  **un repo clonado puede traer sus propias exenciones**. Con el suelo en código ya no expone
  credenciales ni la config de los guards, pero todavía puede eximirse la config de npm, los
  certificados o la base de contraseñas del sistema. Seguimiento nº 1.
- **`block-dangerous-commands.sh` exime por igualdad exacta de cadena** (`index($cmd)` + `exit
  0`): una línea en el allowlist desactiva **todo** el blocklist, no un patrón. En Sentinel esa
  misma lista es más estrecha, porque solo exime el check de comandos.
- **Sentinel es fail-open por diseño** (`except: sys.exit(0)`): cualquier entrada que lo haga
  fallar es un bypass universal y silencioso.
- **Los guards leen el literal del comando, no el `argv`** que expandirá el shell: entrecomillar
  los flags o pasarlos por una variable derrota cualquier regex de flags. Está dicho en el
  comentario del hook y no se tapa con más regex, que daría una falsa sensación de cierre.
- **`dict-password-config-file` sigue acotada por extensión de config**, así que una contraseña
  en un `.txt` se comitea. Ampliarla reintroduce la clase de 18 falsos positivos ya medida.
- **`kit/docs/07-verify.md:84` sigue describiendo la fuente del check 5 como un `jq` sobre el
  `settings.json` de usuario**, que con la corrección de este release es incompleto: ahora es la
  enumeración de ámbitos. Ninguna suite grepea esa expresión, así que nada se pone rojo.

## [1.0.0] - 2026-08-05

Primera versión etiquetada. Recoge el kit completo: guards deterministas con
suite de test falsable, 8 agentes con tiering, dos capas de secretos, eval set
opt-in, y `install.sh`/`doctor.sh` como bucle de instalación y diagnóstico.

### Fixed

- **Una instalación limpia ya no puede quedarse sin API.** `kit/claude/settings.json`
  distribuía `ANTHROPIC_BASE_URL=http://127.0.0.1:8787` mientras `install.sh`
  declaraba Headroom como componente de terceros que el kit no instala: quien
  clonaba en limpio se quedaba con Claude Code enrutado a un puerto donde no
  escuchaba nadie, sin poder hablar con la API y con un síntoma que no parecía
  de configuración. La variable sale del `settings.json` distribuido; ahora la
  escribe `install.sh --with-headroom` y solo después de comprobar `/readyz`.
  **Cambio de config con impacto:** si dependías de que el kit enrutara al
  proxy, recupéralo con ese flag (o añade la variable a mano). Sigue yendo en
  `settings.json` y no en el shell, por el motivo que explica `03-headroom.md`.
  Cubierto por `kit/test/test_clean_install_resilience.sh`.
- **`doctor.sh` ya no aprueba una instalación inservible.** No comprobaba nunca
  el endpoint, así que salía con código 0 en una máquina cuyo Claude Code no
  podía conectar. Ahora, si algo enruta la API, ese endpoint tiene que contestar
  o es `FAIL`. Se consulta `/readyz` y no `/health`, que es agregado y se pone
  en rojo por subcomprobaciones que es legítimo no tener.
  Cubierto por `kit/test/test_doctor_base_url.sh`.
- **Los hooks ya no fallan por dependencias que el kit no instala.**
  `rtk hook claude` y los dos hooks Python del venv daban exit 127 en una
  máquina limpia — el preflight de Sentinel, con `matcher ""`, en *todas* las
  llamadas a tool. Ahora pasan por `optional-hook.sh`. Lo que el wrapper no hace
  es tragarse un bloqueo: si el guard está instalado y sale con código 2, ese 2
  se propaga, porque es así como se deniega una acción.
- **`headroom` y `rtk` se documentaban como una sola herramienta, y son dos
  proyectos independientes.** `kit/docs/03-headroom.md` titulaba "Instalar
  Headroom (`rtk`)" y verificaba el proxy con `rtk --version`; `doctor.sh`
  hacía `command -v rtk` y reportaba "Headroom presente". Son
  [headroomlabs-ai/headroom](https://github.com/headroomlabs-ai/headroom)
  (proxy HTTP en `127.0.0.1:8787`, Python, se cablea con `ANTHROPIC_BASE_URL`) y
  [rtk-ai/rtk](https://github.com/rtk-ai/rtk) (binario Rust que filtra la
  salida de los comandos de shell, se cablea con el hook `rtk hook claude`).
  Ninguna necesita a la otra. Con la comprobación anterior, tener `rtk` sin el
  proxy daba un `PASS` falso, y al revés. `doctor.sh` ahora las comprueba por
  separado, y se corrige también en `07-verify.md` y
  `08-plugins-mcp-y-skills.md`, con una tabla comparativa al principio de
  `03-headroom.md`.

### Added

- **`kit/claude/hooks/optional-hook.sh`**: ejecuta un hook solo si su dependencia
  existe. No-op silencioso si falta; `exec` con propagación literal del código de
  salida si está, incluido el 2 que bloquea. Modo `--python` que resuelve el
  intérprete (venv → `python3` del sistema), lo que además mejora la cobertura:
  en una máquina con Python pero sin venv, `smart_approve.py` y el preflight de
  Sentinel ahora sí corren, cuando antes daban 127.
  Contrato en `kit/test/test_optional_hook.sh` (9 asserts).
- **`install.sh --with-headroom`**: instala `headroom-ai[proxy]` en el venv,
  escribe la unidad de systemd de usuario con `--mode cache` explícito,
  `StartLimitIntervalSec=0` en `[Unit]` y el output-shaper por `ExecStartPost`,
  arranca, espera `/readyz` y **solo entonces** enruta la API. Si el proxy no
  arranca, sale con error y deja la config intacta.
  Cubierto por `kit/test/test_with_headroom.sh` (13 asserts, sin red ni systemd).
- **`kit/test/test_clean_install_resilience.sh`** (12 asserts): monta el kit en
  una máquina simulada sin ninguno de los componentes de terceros y exige las dos
  mitades del contrato — que ningún hook falle, y que un comando destructivo siga
  saliendo con el código que bloquea. Impide "arreglar" la primera mitad a base
  de `|| true`, que rompería la segunda en silencio.
- **`kit/docs/09-ssh-y-gitlab-privado.md`: guía completa de clave SSH y alta en
  un GitLab autoalojado, desde WSL2.** Ocho pasos con los comandos, pensada para
  que alguien de un equipo la siga de principio a fin sin saber de SSH: generar
  la clave (`ssh-keygen -t ed25519` con `-C`, `-f` y `-N ""`, cada flag
  explicado y con la contrapartida real de no poner passphrase en una tabla),
  permisos, copiar la `.pub`, darla de alta en la web de GitLab, el bloque de
  `~/.ssh/config`, `ssh-agent`, y probar con `ssh -T`. Todo genérico: el host va
  en una variable `GITLAB_HOST` y los ejemplos usan `@example.com`.

  Tres cosas que la hacen útil más allá de un copia-pega:

  - **El paso que casi nadie documenta.** Una clave con nombre no estándar
    (`-f id_ed25519_algo`) **no se usa** hasta configurarla, porque `ssh` solo
    prueba los nombres por defecto. Va con la salida real de `ssh -v`
    enseñándolo (`Trying private key: ~/.ssh/id_rsa`, `id_ecdsa`,
    `id_ed25519`… y la tuya no aparece). Es la causa nº 1 de
    `Permission denied (publickey)` con la clave perfectamente dada de alta.
  - **Diagnóstico por `Offering public key`.** Casi todos los fallos dan el
    mismo mensaje, así que el mensaje no informa: la guía enseña a distinguir
    "no se ofreció la clave" de "se ofreció y el servidor la rechazó" mirando
    esa línea de `ssh -v`, y una tabla con los ocho errores restantes.
  - **`IdentitiesOnly yes` explicado**, no copiado: sin él `ssh` ofrece todas
    las claves y el servidor corta por `MaxAuthTries`, con un
    `Too many authentication failures` que parece del servidor y es tuyo.

  Solo se citan mensajes de error **reproducidos**. En particular **no** se
  promete el clásico `UNPROTECTED PRIVATE KEY FILE`: se probó la clave privada
  en `640`, `644`, `660`, `666` y `777` y OpenSSH 10.2 no avisó en ningún caso,
  así que la guía dice que no te fíes de eso como red de seguridad.

- **La guía avisa de que los guards de este kit bloquean sus propios comandos.**
  Sentinel trata `~/.ssh/` como ruta sensible, así que bloquea incluso un `cat`
  de la clave **pública** (`SENTINEL BLOCKED [Bash]: [CRITICAL] sensitive path:
  ~/.ssh/`). No es un fallo: el guard no distingue `.pub` de la privada, y esa
  imprecisión es deliberada. La salida correcta es hacer este alta —tarea humana
  y de una sola vez— en una terminal normal, **no** añadir `~/.ssh/` al
  `sentinel-allowlist.json`, que abriría el acceso a las claves privadas de
  forma permanente para ahorrarse abrir una pestaña.
- `08-plugins-mcp-y-skills.md` explica ahora que un marketplace de plugins
  privado se da de alta por URL SSH y por tanto depende de esa guía y de la VPN,
  y que si la VPN está caída solo falla ese marketplace: el resto de Claude Code
  sigue igual.
- **Aviso de WSL2 al principio del `README.md`.** El requisito estaba, pero
  enterrado dentro de "Quick start". Ahora abre el documento, con el `wsl` que
  hay que ejecutar primero y dos avisos concretos para quien viene de Windows:
  clonar **dentro** de WSL y no en `/mnt/c/` (el `9p` es mucho más lento y
  complica el bit de ejecución), y el `.gitattributes` que ya evita que
  `core.autocrlf=true` convierta los scripts a CRLF.
- `kit/docs/03-headroom.md`, sección nueva: **lo que Claude Code desactiva por
  su cuenta cuando `ANTHROPIC_BASE_URL` apunta a un endpoint custom.** Son tres
  cosas y dos tienen arreglo: la **ventana de contexto de 1M** (topa en 200k;
  la selección del picker `/model` no sobrevive al endpoint custom, se recupera
  con `ANTHROPIC_MODEL=<modelo>[1m]`), la **carga de herramientas on-demand**
  (carga todos los schemas de golpe; se recupera con `ENABLE_TOOL_SEARCH=true`)
  y **Remote Control** (`/rc`, sin arreglo posible: es un gate del cliente). El
  primero es el que muerde en silencio: con `"model": "opus[1m]"` en
  `settings.json` nada indica que te han recortado el contexto. El kit no fija
  `ANTHROPIC_MODEL` a propósito — pinchar un modelo en la config de otra
  persona sería peor que el problema.
- `kit/docs/03-headroom.md`: **`ANTHROPIC_BASE_URL` tiene que ir en
  `settings.json`, no en el `.bashrc`/`.profile`.** Claude Code lee su entorno
  una sola vez al arrancar y las sesiones heredan un snapshot del shell: si el
  proxy no estaba arriba en ese instante, la sesión entera se queda sin enrutar,
  sin recuperación y sin avisar (`headroom doctor` → `savings: no tokens saved
  yet`). La disponibilidad se resuelve con `Restart=always` en systemd, no con
  un export condicional.
- `kit/docs/03-headroom.md`: **el motor de compresión puede estar apagado sin
  que nada lo diga** (`kompress` con `backend: null` en `/health`) y el proxy
  sigue sirviendo tráfico igual. Dos causas: el modelo ONNX (~260 MB) no
  descargado —el preload de arranque usa solo caché local a propósito, para no
  bloquear el bind del puerto—, o una unidad de systemd endurecida en la que
  `~/.cache/huggingface` no es escribible, que lo deja inutilizable para
  siempre.
- `kit/docs/03-headroom.md`: **cómo medir el ahorro sin engañarse.** `/stats`
  son contadores del proceso y se reinician con el servicio; `/stats-history`
  es el histórico durable. Y la única cifra que juzga si el modo `cache` hace
  su trabajo es `lifetime.cache_read_tokens / lifetime.total_input_tokens`, la
  proporción servida desde el prompt-caching de Anthropic.
- `kit/docs/03-headroom.md`: instalar con el extra **`[proxy]`, no `[all]`**
  (`[all]` arrastra `torch` y ~6 GB que el motor no usa: su backend es ONNX
  Runtime, ya incluido en `[proxy]`; el aviso `PyTorch was not found` es
  inocuo). Y `StartLimitIntervalSec` va en la sección **`[Unit]`**: en
  `[Service]` systemd lo ignora en silencio y deja el default de 5 arranques en
  10 s.
- Hash SHA-256 de `gitleaks` (x64 y arm64) fijado como constante dentro de
  `kit/install.sh`, verificado por el propio mantenedor contra la release
  oficial `v8.30.1` — ya no se confía en el `checksums.txt` servido por el
  mismo host que el tarball, que solo protegía contra corrupción en
  tránsito, no contra una release comprometida. Procedimiento de
  actualización documentado en `CONTRIBUTING.md` ("Actualizar gitleaks").
- Si el checksum de `gitleaks` no coincide con el fijado, la instalación ya
  no lo trata igual que "sin red": deja una marca persistente en
  `$CLAUDE_HOME/.gitleaks-checksum-mismatch` (con versión, arquitectura y
  hash esperado) que `doctor.sh` reporta como `FAIL` en instalaciones
  posteriores — sin romper el resto de la instalación (la Capa 1 de
  secretos sigue activa). Cubierto por
  `kit/test/test_install_gitleaks_checksum.sh` (9 casos).
- `.gitattributes` en la raíz: fuerza LF (`eol=lf`) en todo lo que se
  ejecuta o parsea (`*.sh`, `*.py`, `*.yml`/`*.yaml`, `*.toml`, `*.json`,
  `Makefile`, el hook sin extensión `kit/claude/hooks/git/pre-commit`,
  etc.). Protege a quien clona desde Windows/WSL2 con
  `core.autocrlf=true` (default de Git) de que un clon normal convierta LF
  a CRLF y rompa cada script (`bad interpreter: .../bash^M`). Cubierto por
  `kit/test/test_gitattributes.sh` (4 casos, con auto-falsación).
- `shellcheck` en un job nuevo de CI sobre los 20 scripts del kit (`kit/*.sh`,
  hooks, `kit/test/*.sh`, `.github/scripts/*.sh`).
- `doctor.sh` reporta ahora el estado de la Capa 2 de secretos: versión de
  `gitleaks` instalada, si `core.hooksPath` está configurado en el repo
  actual, y si quedó una marca de checksum-mismatch pendiente de revisar.
- Puerta de plataforma en `kit/install.sh`: comprueba `uname -s` y aborta con
  un mensaje claro (y sin dejar nada a medias) en cualquier plataforma que no
  sea Linux o WSL2, con detección informativa (no bloqueante) de WSL2. Es lo
  único que prueba la CI de este repo, así que es lo único que se promete.
- Instalación automática y opcional de `gitleaks` (versión fijada `8.30.1`)
  desde `kit/install.sh`: detecta si ya está en el sistema y, si no, ofrece
  descargar el binario oficial verificando su checksum SHA-256 contra el
  fichero de checksums publicado (nunca `curl | bash`). Si falla por
  cualquier motivo (sin red, checksum no coincide, sin permisos), degrada
  con un aviso claro en vez de romper el resto de la instalación — la Capa 1
  de secretos funciona igual sin `gitleaks`. `doctor.sh` ya lo reportaba.
- Subcomando `kit/install.sh --enable-secrets-layer2`: activa
  `core.hooksPath` de git (Capa 2 de secretos) solo en el repositorio desde
  el que se invoca explícitamente. `install.sh` sin flags nunca toca esta
  config por su cuenta, ni siquiera corriendo dentro de un repo git — ver
  `kit/docs/05-security.md` para el razonamiento. Complementa (no sustituye)
  el one-liner manual ya documentado.
- Tres suites de test nuevas: `test_install_platform_gate.sh` (4 casos),
  `test_install_gitleaks.sh` (6 casos) y `test_enable_secrets_layer2.sh`
  (6 casos), añadidas a `make test` y a `.github/workflows/ci.yml`.
- README.md reescrito como landing page de 30 segundos: qué hace el kit por
  delante de qué es, prerrequisitos explícitos (Linux/WSL2) en el quick
  start, y solo el badge de CI (sin badges decorativos).
- Integración continua (`.github/workflows/ci.yml`) con dos jobs: las suites
  de test completas (`kit/test/*.sh`, incluyendo la de falsabilidad de
  guards y `gitleaks dir` sobre el repo) y un smoke test en contenedor Debian
  limpio que instala el kit como usuario **no root**, corre `install.sh` dos
  veces para probar idempotencia, y asserta postcondiciones reales
  (ficheros, permisos de ejecución, JSON válido, `doctor.sh`) en vez de solo
  el código de salida. El eval set nunca se ejecuta en CI.
- Andamiaje de comunidad: `CONTRIBUTING.md`, `SECURITY.md` (documenta los
  límites conocidos de los guards de secretos en vez de esconderlos),
  `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1), plantillas de issue
  (bug/feature) y de PR, `Makefile` (`make install|test|doctor|help`,
  `evals-paid` opt-in y con confirmación), `.editorconfig`.
- Capa de contenido para secretos: `gitleaks` en un hook `pre-commit`
  (`kit/claude/hooks/git/pre-commit` + `kit/claude/.gitleaks.toml`), que
  escanea lo que de verdad queda staged en vez de adivinar el efecto de un
  comando por su texto. Complementa la Capa 1 existente
  (`secret-guard.sh`, por nombre de fichero).
- Eval set mínimo de 6 tareas (`kit/evals/`), opt-in y aislado por tarea en
  su propio directorio temporal. Documentado como que cuesta dinero real y
  que nunca se invoca desde `make test`, `doctor.sh` ni CI.
- Suite `test_guards_falsifiability.sh`: prueba que la suite de guards mide
  comportamiento real neutralizando un guard y comprobando que eso rompe
  casos BLOCK conocidos.

### Changed

- La regla propia de `kit/claude/.gitleaks.toml` (contraseñas de tipo
  diccionario en ficheros de config) ya no incluye `.json` en su path: la
  medición de 0 falsos positivos solo era válida para este repo pequeño y
  centrado en documentación, y en un proyecto Node real `.json` cubre
  `package-lock.json`/`tsconfig.json`/specs de OpenAPI, donde un
  `"token": "valor-interno"` inocuo dispararía la regla. Documentado con un
  fixture nuevo en `test_secret_content_gitleaks.sh` (caso 17).
- El badge de CI en `README.md` ya no apunta a `?branch=v2-autonomous`:
  refleja la rama por defecto una vez fusionada.

### Fixed

- Ancla del patrón `sk-` en la capa de nombre de secretos para evitar falsos
  positivos sobre texto kebab-case legítimo.
- `smoke-install-nonroot` fallaba en el primer step (`Illegal option -o
  pipefail`): dentro de un `container:`, Actions ejecuta `run:` con `sh -e
  {0}` sin importar el shell por defecto del runner, y el `sh` de
  `debian:12-slim` es `dash`, que no soporta `pipefail`. Fix: `defaults: run:
  shell: bash` a nivel de job (verificado que `debian:12-slim` trae bash de
  fabrica).
- `test_guards.sh` no era hermético: 3 casos (`rm -rf` en raíz, force push
  directo/compuesto) dependían de las reglas `permissions.deny` que
  `smart_approve.py` lee de `$HOME/.claude/settings.json` — con un `HOME`
  limpio pasaban 24/27, con el `HOME` real de esta máquina pasaban 27/27,
  sin que la suite lo detectara. Fix: la suite ahora construye su propio
  `$HOME` temporal con las reglas de `kit/claude/settings.json` antes de
  correr, y da el mismo resultado (28/0) con cualquier `HOME`. De paso,
  se añade un caso explícito que documenta como hallazgo de seguridad —no
  se oculta— que `smart_approve.py` falla abierto (permite todo) cuando no
  hay `settings.json`: no hay allowlist que cargar, así que no hay nada que
  bloquear. El resto de suites de `kit/test/` no tenían esta dependencia de
  `$HOME` (comprobado corriendo las 11 con `HOME` limpio).
- 8 ficheros invocados directamente por nombre (los hooks de
  `kit/claude/hooks/*.sh`, `kit/claude/hooks/git/pre-commit`) estaban
  commiteados con modo `100644` en vez de `100755` — git ignora en
  silencio, sin ningún error, un hook no ejecutable, así que cualquiera
  que clonase el repo y activase la Capa 2 de secretos (`core.hooksPath`)
  tendría el hook muerto. Invisible en local porque este repo vive en un
  montaje `/mnt/c` (9P) que reporta `rwx` para todo con
  `core.fileMode=false`, así que ninguna observación del bit de ejecución
  en el filesystem es fiable aquí; el único fix real es sobre el modo que
  git tiene REGISTRADO (`git update-index --chmod=+x`, no `chmod`).
  Nueva suite `kit/test/test_exec_modes.sh` (con auto-falsación) que
  comprueba estos modos vía `git ls-files -s`, añadida a `make test` y a
  `.github/workflows/ci.yml`.

### Documentation

- Documentado el modelo de dos capas de secretos (por nombre + por
  contenido), pasos de verificación y el porqué de mantener el eval set
  fuera de CI.

[Unreleased]: https://github.com/manuelcozar55/setup-claude-code/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/manuelcozar55/setup-claude-code/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/manuelcozar55/setup-claude-code/releases/tag/v1.0.0
