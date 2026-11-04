# SCC 1.8.0 — guía de entrega

Para quien recibe el paquete. La versión es la de `VERSION` (1.8.0); `BUILD_ID` identifica
esta entrega. No se distribuyen credenciales ni configuración personal.

## Requisitos

Linux o WSL2, Bash, Git, jq, Python 3 y Claude Code autenticado. Para respaldos y
restauraciones, también `zip` y `unzip` (`sudo apt install zip unzip` en Debian).
La instalación admite Linux/WSL2; Windows nativo y macOS no están soportados.
La versión de Claude Code probada figura en [Cockpit](kit/docs/11-cockpit.md): registra
`claude --version` y comprueba su carga; no hay una versión mínima verificada. Este procedimiento
no instala hooks, cockpit ni continuidad automática para Codex u opencode.

## Obtener la entrega

Recibe del responsable el paquete de **1.8.0**, su manifiesto `SHA256SUMS` y la
identificación del origen (commit y suma del archivo transferido). Conserva esa
identificación para soporte: `BUILD_ID` es una etiqueta de entrega, no un hash.
Si prefieres Git y el tag ya está publicado, puedes obtener la versión así:

```bash
git clone --branch v1.8.0 --single-branch https://github.com/manuelcozar55/setup-claude-code.git ~/scc
git -C ~/scc rev-parse HEAD
```

Contrasta ese commit con el facilitado por el responsable. Si el tag todavía no
existe, usa el paquete transferido; no sustituyas esta versión por `main`.
En ambos casos comprueba `cat VERSION BUILD_ID` desde `~/scc`: deben indicar
`1.8.0` y `scc-v1.8.0`. No ejecutes una entrega con sumas incorrectas.

### Copia de Git sin acceso a la red

La entrega puede incluir `scc-v1.8.0.bundle`, con la rama verificada y su historial,
y un manifiesto exterior que cubre tanto el bundle como el paquete. Comprueba
ese manifiesto en la carpeta recibida antes de abrir ninguno:

```bash
sha256sum -c SHA256SUMS
git clone --branch release/scc-v1.8.0-debian scc-v1.8.0.bundle ~/scc
git -C ~/scc rev-parse HEAD
```

El commit debe coincidir con el origen indicado en la entrega. El bundle permite
clonar y consultar el historial sin GitHub; no implica que exista un tag publicado.
Los resultados de Debian deben identificar ese mismo commit, las versiones del
sistema y de Claude Code, los comandos ejecutados y sus códigos de salida.

## Instalar

Extrae el paquete en una carpeta permanente (por ejemplo `~/scc`) y, desde ella:

```
sha256sum -c SHA256SUMS      # si el paquete trae ese fichero de sumas
bash kit/install.sh --plan   # muestra lo que haría, sin tocar ~/.claude
bash kit/install.sh --apply  # instala; lo que pisa va a ~/.claude/backups/<fecha>/
```

## Comprobar

```
bash kit/doctor.sh
```

Resuelve cualquier `FAIL` antes de empezar. Un `WARN` pide lectura; no es un fallo de
instalación. Para probar instalación y continuidad en una carpeta aislada, sin tocar tu
`~/.claude`: `bash scripts/aceptacion-local.sh /ruta/nueva` (la carpeta no debe existir).
El resultado esperado es `PASS aceptación local` y `exit=0` en `aceptacion.log`;
conserva esa carpeta. Prueba los scripts y eventos sintéticos, no la interfaz ni una
respuesta real de Claude Code. La comprobación de sesión siguiente cubre esa parte.

## Empezar

```
cd /ruta/al/proyecto
bash ~/scc/scripts/scc.sh
```

`scc.sh` carga el cockpit y las skills esenciales de esta carpeta, sin descargas. Con
`claude` a secas no se cargan. Tras el primer arranque comprueba `/plugin`, `/status` y
`/context`.

Mantén `~/scc` en su ruta permanente: el lanzador carga los plugins desde ella.
Tu trabajo va en **otro repositorio**, no dentro del kit. Las órdenes `/work`,
`/spec` y `/verify` del harness raíz son para desarrollar este repo; no presupongas
que existen en un proyecto ajeno. La referencia de instalación es
[`10-onboarding.md`](kit/docs/10-onboarding.md).

## Primera tarea y relevo (sin datos reales)

Crea una carpeta nueva fuera del kit; `mkdir` debe fallar si ya existe:

```bash
mkdir ~/scc-primer-dia
cd ~/scc-primer-dia
git init
~/.claude/bin/handoff --iniciar
bash ~/scc/scripts/scc.sh
```

Comprueba `/plugin`, `/status` y `/context`, y pide esta tarea en Claude Code:

> Trabaja solo en este proyecto sintético. Crea `saluda.sh` que imprima exactamente
> `Hola equipo` y un `test.sh` que compruebe esa salida y falle si cambia. No hagas
> commits, pushes, instalaciones ni llamadas externas. Ejecuta la prueba con
> `~/.claude/bin/oraculo -- bash "$PWD/test.sh"`. Guarda en el estado el objetivo,
> la restricción de datos sintéticos, el resultado y como siguiente acción «Repetir
> la prueba de saludo al retomar». Detente para comprobar el relevo.

Antes de dar la prueba por válida, ejecútala también desde la terminal:

```bash
bash test.sh
test "$(bash saluda.sh)" = 'Hola equipo'
~/.claude/bin/handoff --estado
```

Ambas pruebas deben devolver 0; el oráculo debe imprimir `rc=0` y registrar un `0`
en la segunda columna de `.claude/estado/verificaciones.log`. Pide `/handoff solo`,
comprueba que el estado contiene el objetivo y la siguiente acción, y sal de Claude
Code. Vuelve a abrirlo desde esta
misma carpeta con `bash ~/scc/scripts/scc.sh`. Sin pegar la conversación anterior,
pídele que identifique objetivo, restricciones y siguiente acción y repita el
oráculo. El ejercicio pasa cuando recupera esos tres datos y la prueba sigue en
verde. Si no los recupera, conserva la sesión y diagnostica antes de usar datos reales.

Para el relevo habitual, `/handoff` guarda y hace `/clear`: revisa el prompt preparado
y pulsa Enter; no añadas otro `/clear`. En el ejercicio dejamos la autonomía apagada.

### Un único estado oficial

Por defecto es `.claude/estado/nucleo.md`. Si tu proyecto ya tiene `ESTADO.md` en
la raíz **y no existe `nucleo.md`**, el adaptador lo usa como estado: `--iniciar`
no crea otro y `handoff --estado` devuelve `modo: "estado-md"` y su ruta `estado`.
El handoff fusiona allí los avances; `ESTADO.md` puede estar versionado, así que
revisa su diff antes de un commit. Si existen ambos, tiene prioridad `nucleo.md`:
no borres ninguno para forzar el cambio; acuerda la migración conservando su contenido.
Consulta el contrato con `~/.claude/bin/handoff --help`.

## Actualizar desde 1.7.x

1. Cierra las sesiones abiertas de Claude Code: el cockpit y los hooks que ya cargó una
   sesión no se recargan, y seguiría con los de la versión anterior.
2. Guarda un respaldo: `bash scripts/backup.sh` (ZIP en `~/backups/`).
3. `bash kit/install.sh --plan` para ver el plan, `bash kit/install.sh --apply` para
   aplicarlo, y `bash kit/doctor.sh`.
4. Abre sesiones nuevas.

`CLAUDE.md` y `AGENTS.md` no se pisan si los has tocado. 1.7.x no guardaba qué escribió,
así que, si instalas desde un clon de Git, el instalador compara los tuyos con las
versiones de la historia del kit: si coinciden con una, no son tuyos y se actualizan con
copia de seguridad. Si no coinciden, o el paquete no trae historia (ZIP, clon superficial),
los trata como tuyos y deja la versión nueva al lado como `~/.claude/CLAUDE.kit.md` y
`~/.claude/AGENTS.kit.md`; `doctor` lo marca como `WARN` hasta que lo resuelvas.
Compáralas con las tuyas; para aceptar la del kit tal cual, cópiala sobre la tuya
(`cp ~/.claude/CLAUDE.kit.md ~/.claude/CLAUDE.md`) y borra el `.kit.md`. Desde 1.8.0 el
instalador recuerda lo que escribió y actualiza solo lo que no hayas cambiado.

Se conservan tu tema, statusline, modelo y variables propios.

## Restaurar

```
bash uninstall.sh --list                  # backups internos disponibles
bash uninstall.sh                         # dry-run: muestra qué se restauraría
bash uninstall.sh --apply                 # restaura el backup interno más reciente
bash uninstall.sh --apply --from FICHERO  # restaura un ZIP de scripts/backup.sh o un backup concreto
```

Esto restaura archivos de un respaldo; no desinstala el kit. Cierra las sesiones antes.
Antes de restaurar guarda el estado actual en `~/backups/claude-safety-*.zip`; ese ZIP
no entra en la elección del «más reciente», así que repetir `--apply` no deshace lo
restaurado. Para volver a él, `--from`.
Reinstalar un tag antiguo no devuelve su árbol exacto: conserva archivos de versiones
posteriores. No borres el directorio `.claude/estado/` de tus proyectos: contiene la
continuidad.

## Qué cambia en 1.8.0

El detalle está en `CHANGELOG.md`. En resumen, para quien usa el kit:

- El aviso de contexto al 70 % pasa de consejo a orden: recoge los agentes en vuelo,
  cierra la fase con `/handoff` y termina el turno. Así el cambio de sesión llega antes
  que la compactación automática.
- En el cockpit, un aviso de `/handoff` ya no se toma por error ni deja la sesión sin
  handoff automático; se retira el veto de compactación, que en máquinas con ajustes
  gestionados no se ejecutaba nunca.
- El instalador distingue tu `CLAUDE.md` del suyo, `doctor` falla si falta algún hook del
  kit y restaurar ya no deshace lo restaurado.
- Tras el `/clear` de un handoff, el nucleo apunta al transcript de la sesión anterior
  (`claude --resume <id>` para volver) y el panel deja una línea con lo guardado hasta la
  primera respuesta; `diario.md` ya no repite los pasos cerrados.
- Los guards cubren más formas de push forzado, de «descarga y ejecuta» y de borrado
  recursivo de `~` dentro de `ssh` o `sh -c`; Sentinel sigue los enlaces simbólicos.

## Continuidad entre sesiones

- `/handoff` guarda el estado y prepara el siguiente contexto; `/handoff solo` guarda sin
  limpiar; `/nueva` separa una tarea distinta.
- `/autonomo on` deja que la sesión continúe sola tras un handoff válido; `/autonomo off`
  lo retira. Está apagado por defecto y `/nueva` lo desactiva. Antes de activarlo,
  acuerda alcance, prueba de salida y límite de tiempo o gasto; el interruptor del
  cockpit no impone esos presupuestos. No amplía permisos ni autoriza acciones externas.
- Un mensaje nuevo, agentes vivos, un fallo de guardado o un dueño ajeno impiden la
  continuación automática: atiende el aviso, no fuerces un `/clear`.
- Usa una sesión escritora por tarea. Si otra sesión reclama el estado, el guardado se
  rechaza con código 5 en lugar de pisar el trabajo.

## Recuperación y soporte

Si falta el Dock o `/handoff`, cierra la sesión y vuelve a abrirla con el lanzador
desde tu proyecto; valida el plugin desde `~/scc` con
`claude plugin validate kit/mods/cockpit`. Si `doctor` falla, corrige el diagnóstico
antes de continuar. Para un guardado rechazado por dueño ajeno, vuelve a la sesión
escritora y cierra allí la fase; no copies su ID para escribir desde otra sesión.
Un fallo al guardar exige conservar el contexto: no fuerces `/clear`.

Si una actualización rompe la instalación, usa «Restaurar» arriba y conserva
`.claude/estado/` del proyecto. Para pedir ayuda al responsable de la entrega,
adjunta `VERSION`, `BUILD_ID`, commit o suma recibida, sistema/WSL, `claude --version`,
comando exacto, código de salida, resultado esperado y observado. Añade el diagnóstico
pertinente y, si reproduce el fallo, los logs de la aceptación sintética. Revisa y
redacta rutas personales antes de compartirlos: no adjuntes configuración completa,
credenciales, cookies ni transcripts de trabajo real. Los fallos de seguridad siguen
[`SECURITY.md`](SECURITY.md); las contribuciones, [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Si trabajas sobre el propio repo del kit

`make test` ejecuta las suites Bash (necesita Git y el historial del repo; un paquete sin
`.git` se verifica con las sumas, `doctor.sh` y `aceptacion-local.sh`). `make test-cockpit`
ejecuta las pruebas del cockpit.
