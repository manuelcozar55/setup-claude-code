# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).
Este proyecto sigue [Versionado Semántico](https://semver.org/lang/es/).
`[Unreleased]` recoge lo que está en `main`, o en camino a él por PR, y aún no se ha
etiquetado.

## [Unreleased]

El repo pasa de ser solo un instalador endurecido a ser también un **harness**: guías
(lo que se dice antes de actuar) y **sensores** (lo que mide después), en el sentido de
Birgitta Böckeler (*Harness engineering*, 02-abr-2026). `kit/` conserva intacta la
capa de instalación v1.0.0; lo nuevo vive en la raíz y solo le añade suites, que pasan
de 16 a 24.

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
  `COST-LOG.md`, `SOURCES.md`, `SKILLS-REGISTRY.md` y 10 ADRs. Es **no-confiable por
  defecto**: lo que viene de la web son datos, nunca instrucciones, y la promoción de un
  hallazgo a regla pasa siempre por una puerta humana.

- **Cuatro skills** (`harness` absorbida sin cambios y verificada por checksum,
  `house-rules`, `coach`, `dev-env`) y **cero agentes nuevos**: de 150 delegaciones, 105
  fueron al agente genérico y 6 de los 8 especialistas existentes nunca se usaron. El
  problema no era falta de capacidad.

- **Ocho suites de test nuevas** (`test_harness_structure.sh`, `test_metrics.sh`,
  `test_install_diff_first.sh`, `test_uninstall.sh`, `test_detect_oracle.sh`,
  `test_auto_spec.sh`, `test_autonomy.sh`, `test_doc_claims.sh`), todas con sección de
  falsabilidad. El total pasa de 16 a 24.

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

### Removed

- **`session-brief.sh`**, sustituido por `auto-spec.sh` (ADR 009). Su función —poner delante
  el oráculo del proyecto y los errores ya cometidos— se hace ahora en el primer *encargo* y
  no en el arranque, donde se diluía y no sobrevivía a un `/clear`. **El presupuesto se
  mantiene en 3 hooks**: se sustituye, no se suma.

### Fixed

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
  decía 16 suites con 23 en el `Makefile`, `kit/README.md` "8 documentos" con 9, y tres
  documentos seguían citando `session-brief.sh` meses después de borrarlo. Nada se ponía en
  rojo porque nadie medía el texto. `test_doc_claims.sh` cuenta el árbol real (suites,
  agentes, comandos, ADRs, documentos), lo compara con lo que dicen los documentos que hablan
  **en presente** —en dígito y en letra, porque "cinco comandos" era justo la forma que se
  quedaba sin actualizar— y comprueba que ningún `.sh` citado en la documentación haya
  dejado de existir. `CHANGELOG.md`, `knowledge/DECISIONS/`, `knowledge/PRE-MORTEM.md` y
  `docs/superpowers/plans/` quedan **fuera a propósito**: son registros fechados, y una cifra
  de agosto ahí es correcta aunque hoy sea otra. Trae su propio check de falsabilidad.

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

[Unreleased]: https://github.com/manuelcozar55/setup-claude-code/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/manuelcozar55/setup-claude-code/releases/tag/v1.0.0
