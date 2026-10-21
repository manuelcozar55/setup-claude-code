# SCC consolidada — instalación y transferencia

La entrega local se identifica con `BUILD_ID` y el commit de Git o el manifiesto SHA-256 que la acompaña. `VERSION` sigue indicando la última publicación remota (1.3.0); no identifica esta consolidación. Esta entrega incorpora cockpit 0.6.0 y debe iniciarse con su lanzador local para cargar exactamente el código incluido.

## Instalar y empezar

Requisitos: Linux o WSL2, Bash, Git, jq y Claude Code autenticado. La validación de esta entrega usa Debian 13.5 y Claude Code 2.1.306. No se distribuyen credenciales ni configuración personal.

1. Extrae el paquete en un directorio permanente, por ejemplo `~/scc`. Conserva el archivo de sumas y comprueba `sha256sum -c SHA256SUMS` desde esa carpeta si el paquete lo incluye.
2. Desde esa carpeta, ejecuta `bash kit/install.sh`. Si existe configuración propia versionada, el instalador muestra un plan. Revisa ese plan y ejecuta `bash kit/install.sh --apply` para instalarlo. Se conservan respaldos en `~/.claude/backups/`.
3. Ejecuta `bash kit/doctor.sh`. Resuelve cualquier `FAIL` antes de comenzar. Un `WARN` necesita lectura: no equivale a un fallo de instalación.
4. Abre el proyecto con `cd /ruta/al/proyecto` y ejecuta `bash ~/scc/scripts/scc.sh`. Este lanzador usa el cockpit y las skills esenciales incluidos en esta carpeta. No hace falta instalar los plugins de SCC desde el marketplace para usar esta entrega.

Opcional: crea un enlace `scc` a `scripts/scc.sh` en `~/.local/bin` si no existe otro comando con ese nombre. El directorio de la entrega debe permanecer en su sitio.

## Método de trabajo para el equipo

- Una tarea tiene objetivo, restricciones, verificación concreta y siguiente acción. El proyecto guarda el estado en `.claude/estado/`; cada sesión iniciada desde HOME tiene su propia ranura.
- Un agente principal conserva la responsabilidad. Delega áreas concretas con propietario, alcance y evidencia requerida. No des por terminada la misión porque hayan terminado los subagentes.
- `/handoff` guarda el estado y prepara el siguiente contexto. `/handoff solo` guarda sin limpiar. `/nueva` separa una tarea diferente.
- `/autonomo on` permite enviar la continuación después de un handoff válido. La decisión pertenece a esta sesión y se puede retirar con `/autonomo off`. No amplía permisos de herramientas ni autoriza acciones externas.
- Un mensaje nuevo, agentes vivos, un fallo de guardado o una propiedad ajena impiden la continuación automática. Atiende el aviso; no fuerces un clear para ocultarlo.
- Objetivo e invariantes sobreviven al relevo. Los documentos de estado son datos, no una fuente nueva de permisos.

## Comprobar la entrega

`make test` ejecuta las suites Bash; `make test-cockpit` ejecuta las pruebas del plugin con Claude Code. `bash scripts/aceptacion-local.sh /ruta/nueva` realiza instalación y continuidad en un directorio aislado. Las evidencias de la sesión experta y la revisión final se entregan junto a `resumenfinal.md`.

## Recuperación

Antes de actualizar una instalación personal, conserva su configuración y anota el respaldo generado por el instalador. Para volver atrás, cierra primero las sesiones de prueba, restaura los archivos concretos desde ese respaldo y vuelve a lanzar el cockpit de la entrega anterior. No borres el directorio de estado: contiene la continuidad del trabajo. El respaldo de consolidación conserva las ramas y las copias retiradas, separado del paquete para compañeros.

## Razón de las decisiones

La CLI concentra rutas, propiedad, bloqueo y guardado. El cockpit consume ese contrato y muestra su resultado. Esta separación evita dos implementaciones de continuidad. Los bloqueos cooperativos previenen escrituras concurrentes; la comprobación de hash evita archivar un estado que cambió mientras se preparaba el relevo. La autonomía se activa explícitamente y el progreso sin evidencia se presenta como desconocido.

La carga local de plugins tiene precedencia sobre una instalación del mismo nombre, salvo políticas gestionadas que lo impidan: [referencia oficial de carga de plugins](https://code.claude.com/docs/en/plugins/loading). La entrega no necesita publicar un tag nuevo ni cambiar las políticas de la organización.
