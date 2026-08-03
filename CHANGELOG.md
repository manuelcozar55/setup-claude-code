# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).
Este proyecto aún no publica versiones etiquetadas; las entradas se agrupan
bajo `[Unreleased]` hasta el primer tag.

## [Unreleased]

### Added

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

### Documentation

- Documentado el modelo de dos capas de secretos (por nombre + por
  contenido), pasos de verificación y el porqué de mantener el eval set
  fuera de CI.
