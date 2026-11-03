# SCC 1.8.0 — guía de entrega

Para quien recibe el paquete. La versión es la de `VERSION` (1.8.0); `BUILD_ID` identifica
esta entrega. No se distribuyen credenciales ni configuración personal.

## Requisitos

Linux o WSL2, Bash, Git, jq, Python 3 y Claude Code autenticado. Para respaldos y
restauraciones, también `zip` y `unzip` (`sudo apt install zip unzip` en Debian).

## Instalar

Extrae el paquete en una carpeta permanente (por ejemplo `~/scc`) y, desde ella:

```
sha256sum -c SHA256SUMS      # si el paquete trae ese fichero de sumas
bash kit/install.sh          # muestra el plan si ~/.claude ya es un repo con remoto
bash kit/install.sh --apply  # instala; lo que pisa va a ~/.claude/backups/<fecha>/
```

## Comprobar

```
bash kit/doctor.sh
```

Resuelve cualquier `FAIL` antes de empezar. Un `WARN` pide lectura; no es un fallo de
instalación. Para probar instalación y continuidad en una carpeta aislada, sin tocar tu
`~/.claude`: `bash scripts/aceptacion-local.sh /ruta/nueva` (la carpeta no debe existir).

## Empezar

```
cd /ruta/al/proyecto
bash ~/scc/scripts/scc.sh
```

`scc.sh` carga el cockpit y las skills esenciales de esta carpeta, sin descargas. Con
`claude` a secas no se cargan. Tras el primer arranque comprueba `/plugin`, `/status` y
`/context`.

## Actualizar desde 1.7.x

1. Cierra las sesiones abiertas de Claude Code.
2. Guarda un respaldo: `bash scripts/backup.sh` (ZIP en `~/backups/`).
3. `bash kit/install.sh` para ver el plan, `bash kit/install.sh --apply` para aplicarlo,
   y `bash kit/doctor.sh`.

`CLAUDE.md` y `AGENTS.md` no se pisan si los has tocado. Desde 1.7.x el instalador no sabe
si los modificaste, así que los trata como tuyos: deja la versión nueva al lado como
`~/.claude/CLAUDE.kit.md` y `~/.claude/AGENTS.kit.md`. Compáralas con las tuyas; para
aceptar la del kit tal cual, cópiala sobre la tuya
(`cp ~/.claude/CLAUDE.kit.md ~/.claude/CLAUDE.md`). A partir de entonces el instalador
recuerda lo que escribió y actualiza solo lo que no hayas cambiado, con copia de seguridad.

Se conservan tu tema, statusline, modelo y variables propios.

## Restaurar

```
bash uninstall.sh --list                  # backups internos disponibles
bash uninstall.sh                         # dry-run: muestra qué se restauraría
bash uninstall.sh --apply                 # restaura el más reciente (con respaldo previo)
bash uninstall.sh --apply --from FICHERO  # restaura un ZIP de scripts/backup.sh o un backup concreto
```

Esto restaura archivos de un respaldo; no desinstala el kit. Cierra las sesiones antes.
Reinstalar un tag antiguo no devuelve su árbol exacto: conserva archivos de versiones
posteriores. No borres el directorio `.claude/estado/` de tus proyectos: contiene la
continuidad.

## Qué cambia en 1.8.0

El detalle está en `CHANGELOG.md`. En resumen, para quien usa el kit: el aviso de
contexto al 70 % pasa de consejo a orden (cierra la fase con `/handoff` y termina el
turno), los avisos de `/handoff` ya no se confunden con errores en el cockpit, el
instalador distingue tu `CLAUDE.md` del suyo, `doctor` falla si falta algún hook del kit y
los guards cubren más formas de push forzado y de «descarga y ejecuta».

## Continuidad entre sesiones

- `/handoff` guarda el estado y prepara el siguiente contexto; `/handoff solo` guarda sin
  limpiar; `/nueva` separa una tarea distinta.
- `/autonomo on` deja que la sesión continúe sola tras un handoff válido; `/autonomo off`
  lo retira. No amplía permisos ni autoriza acciones externas.
- Un mensaje nuevo, agentes vivos, un fallo de guardado o un dueño ajeno impiden la
  continuación automática: atiende el aviso, no fuerces un `/clear`.
- Usa una sesión escritora por tarea. Si otra sesión reclama el estado, el guardado se
  rechaza con código 5 en lugar de pisar el trabajo.

## Si trabajas sobre el propio repo del kit

`make test` ejecuta las suites Bash (necesita Git y el historial del repo; un paquete sin
`.git` se verifica con las sumas, `doctor.sh` y `aceptacion-local.sh`). `make test-cockpit`
ejecuta las pruebas del cockpit.
