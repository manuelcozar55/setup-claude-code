# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).
Este proyecto aún no publica versiones etiquetadas; las entradas se agrupan
bajo `[Unreleased]` hasta el primer tag.

## [Unreleased]

### Fixed

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
