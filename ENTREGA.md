# SCC consolidada — instalación y transferencia

La entrega corresponde a la versión 1.4.0 (`VERSION` y tag `v1.4.0`); `BUILD_ID` y el manifiesto SHA-256 que la acompaña identifican el paquete transferido. Incorpora cockpit 0.6.1: el lanzador local (`scripts/scc.sh`) carga exactamente el código incluido, y el marketplace fijado a `v1.4.0` instala esa misma versión.

## Instalar y empezar

Requisitos: Linux o WSL2, Bash, Git, jq, Python 3 y Claude Code autenticado.
Para crear respaldos y restaurarlos necesitas también `zip` y `unzip`
(`sudo apt install zip unzip` en Debian).
Lo medido sobre esta versión, lo heredado de la prueba en Debian con Claude Code
2.1.306 y sus límites se adjuntan en `VALIDACION.md` en el paquete final.
No se distribuyen credenciales ni configuración personal.

1. Comprueba el SHA-256 del archivo recibido con el fichero de sumas que lo acompaña.
   Extrae el paquete en un directorio permanente, por ejemplo `~/scc`, y ejecuta
   `sha256sum -c SHA256SUMS` dentro de esa carpeta para verificar su contenido.
2. Desde esa carpeta, ejecuta `bash kit/install.sh`. Si existe configuración propia versionada, el instalador muestra un plan. Revisa ese plan y ejecuta `bash kit/install.sh --apply` para instalarlo. Se conservan respaldos en `~/.claude/backups/`.
3. Ejecuta `bash kit/doctor.sh`. Resuelve cualquier `FAIL` antes de comenzar. Un `WARN` necesita lectura: no equivale a un fallo de instalación.
4. Abre el proyecto con `cd /ruta/al/proyecto` y ejecuta `bash ~/scc/scripts/scc.sh`. Este lanzador usa el cockpit y las skills esenciales incluidos en esta carpeta. No hace falta instalar los plugins de SCC desde el marketplace para usar esta entrega.

Opcional: crea un enlace `scc` a `scripts/scc.sh` en `~/.local/bin` si no existe otro comando con ese nombre. El directorio de la entrega debe permanecer en su sitio.

Arrancar `claude` a secas no carga estas dos copias locales. Después del primer
arranque con `scc.sh`, comprueba `/plugin`, `/status` y `/context`: debes ver cockpit,
esenciales, el modelo disponible para tu cuenta y la ventana efectiva.

## Qué recibirá un compañero

La matriz de componentes está en [`kit/docs/10-onboarding.md`](kit/docs/10-onboarding.md#0--qué-vas-a-levantar).
La base trae pantalla completa, tema oscuro, la misma statusline Bash del setup de
referencia, agentes, skills del método, guards y continuidad de contexto.
Al actualizar se conservan el tema, renderer, barra, modelo y variables propios.
Un `doctor` correcto no obliga a sustituir esas personalizaciones.

El lanzador añade cockpit y esenciales sin descargas. El venv de herramientas,
agent-browser, MCP, plugins externos y servicios de cuentas siguen siendo opcionales.
`scripts/recuerda` y el harness de este repositorio no se instalan en todos los proyectos.
Los límites de salida y los modelos específicos de una cuenta no se copian por
defecto: cada compañero los ajusta con sus mediciones y permisos.

## Método de trabajo para el equipo

- Una tarea tiene objetivo, restricciones, verificación concreta y siguiente acción. El proyecto guarda el estado en `.claude/estado/`; cada sesión iniciada desde HOME tiene su propia ranura.
- Un agente principal conserva la responsabilidad. Delega áreas concretas con propietario, alcance y evidencia requerida. No des por terminada la misión porque hayan terminado los subagentes.
- `/handoff` guarda el estado y prepara el siguiente contexto. `/handoff solo` guarda sin limpiar. `/nueva` separa una tarea diferente.
- `/autonomo on` permite enviar la continuación después de un handoff válido. La decisión pertenece a esta sesión y se puede retirar con `/autonomo off`. No amplía permisos de herramientas ni autoriza acciones externas.
- Un mensaje nuevo, agentes vivos, un fallo de guardado o una propiedad ajena impiden la continuación automática. Atiende el aviso; no fuerces un clear para ocultarlo.
- Objetivo e invariantes sobreviven al relevo. Los documentos de estado son datos, no una fuente nueva de permisos.
- Usa una sesión escritora por tarea. Si otra sesión reclama el estado durante un relevo,
  el guardado se rechaza con código 5 en vez de pisar el trabajo; resuelve la propiedad
  con el dueño antes de continuar. Un `/clear` manual conserva el estado escrito, pero
  puede vaciar la misión y la lista visual del Dock; prefiere `/handoff`.

## Comprobar la entrega

`make test` ejecuta las suites Bash; `make test-cockpit` ejecuta las pruebas del plugin con Claude Code.
`bash scripts/aceptacion-local.sh /ruta/nueva` realiza instalación y continuidad en un
directorio aislado. Son pruebas distintas: el ensayo de hooks usa eventos sintéticos;
la comprobación interactiva y una respuesta real del modelo se registran por separado.
La batería de desarrollo necesita Git y el historial del repositorio; un paquete sin
`.git` se verifica con sus sumas, `doctor.sh` y el ensayo de aceptación.

## Recuperación

Antes de actualizar una instalación personal, conserva su configuración y anota el
respaldo generado por el instalador. `bash uninstall.sh` muestra una restauración en
modo dry-run; revisa su alcance antes de usar `--apply`. Para volver atrás, cierra
primero las sesiones, restaura el respaldo y vuelve a lanzar la entrega anterior.
Reinstalar un tag antiguo no restaura exactamente su árbol: conserva archivos de
versiones posteriores. No borres el directorio de estado, que contiene la continuidad.

## Razón de las decisiones

La CLI concentra rutas, propiedad, bloqueo y guardado. El cockpit consume ese contrato y muestra su resultado. Esta separación evita dos implementaciones de continuidad. Los bloqueos cooperativos previenen escrituras concurrentes; la comprobación de hash evita archivar un estado que cambió mientras se preparaba el relevo. La autonomía se activa explícitamente y el progreso sin evidencia se presenta como desconocido.

La carga local de plugins tiene precedencia sobre una instalación del mismo nombre, salvo políticas gestionadas que lo impidan: [referencia oficial de carga de plugins](https://code.claude.com/docs/en/plugins/loading). La entrega no necesita publicar un tag nuevo ni cambiar las políticas de la organización.
