# SCC 2.0.0 — guía de entrega

Para quien recibe el paquete. La versión es la de `VERSION` (2.0.0); `BUILD_ID` identifica esta entrega.
No se distribuyen credenciales ni configuración personal. Instalar, usar y desinstalar se explica en
[`README.md`](README.md); este documento solo cubre lo que es propio de una entrega transferida.

## Qué se entrega

Una carpeta `scc-v2.0.0/` con lo que necesita quien usa el kit: `kit/` (sin tests ni evaluaciones), `uninstall.sh`,
`scripts/{backup,scc,aceptacion-local}.sh`, `README.md`, `SECURITY.md`, `CHANGELOG.md`, `THIRD-PARTY.md`, `LICENSE`,
`NOTICE`, `VERSION` y `BUILD_ID`. Junto a la carpeta llegan el manifiesto `SHA256SUMS`, el archivo ZIP, el bundle de
Git `scc-v2.0.0.bundle`, `PROCEDENCIA.json` (commit, fecha y si el árbol estaba limpio) y `VALIDACION-DEBIAN.md`
(qué se ejecutó en Debian, con sus códigos de salida). Esos recibos se generan al preparar la entrega y no forman
parte del árbol de Git.

## Verificar la integridad

Antes de abrir nada, en la carpeta recibida:

```bash
sha256sum -c SHA256SUMS                       # cubre el paquete y el bundle; todo debe decir OK
cd scc-v2.0.0 && cat VERSION BUILD_ID        # 2.0.0 y scc-v2.0.0
```

La suma del ZIP exterior se entrega aparte, por otro canal, para comprobar primero la transferencia. No ejecutes una
entrega con sumas incorrectas. Conserva la identificación del origen (commit y suma) para soporte.

Si prefieres un clon con historial, sin red ni GitHub:

```bash
git clone --branch release/scc-v2.0.0-debian scc-v2.0.0.bundle ~/scc
git -C ~/scc rev-parse HEAD                   # debe coincidir con el commit de PROCEDENCIA.json
```

El bundle permite clonar y consultar el historial; no implica que exista una etiqueta publicada. No sustituyas esta
versión por `main`. Mantén la carpeta (`~/scc`) en su sitio: `scc` carga los plugins de la copia que `install.sh`
hace en `~/.claude/scc/`, y `uninstall.sh` y `scripts/backup.sh` se ejecutan desde ella.

## Instalar y comprobar

Los mismos pasos que el README, desde la carpeta extraída: `bash kit/install.sh --plan`, `--apply` y
`bash kit/doctor.sh`. Para probar instalación y continuidad en una carpeta aislada, sin tocar tu `~/.claude`:

```bash
bash scripts/aceptacion-local.sh /ruta/nueva     # la carpeta no debe existir
```

Esperado: `PASS aceptación local` y `exit=0` en `aceptacion.log`. Prueba scripts y eventos sintéticos, no la
interfaz ni una respuesta real de Claude Code; para eso, el ejercicio siguiente.

## Primera tarea y relevo, con datos sintéticos

```bash
mkdir ~/scc-primer-dia && cd ~/scc-primer-dia && git init
~/.claude/bin/handoff --iniciar     # crea .claude/estado/nucleo.md
scc
```

En Claude Code pide: «Trabaja solo en este proyecto sintético. Crea `saluda.sh` que imprima exactamente `Hola equipo` y
un `test.sh` que lo compruebe y falle si cambia. Sin commits, pushes ni llamadas externas. Ejecuta la prueba con
`~/.claude/bin/oraculo -- bash "$PWD/test.sh"`. Guarda en el estado el objetivo, la restricción de datos sintéticos,
el resultado y como siguiente acción «Repetir la prueba de saludo al retomar»».

Comprueba desde la terminal que `bash test.sh` y `test "$(bash saluda.sh)" = 'Hola equipo'` devuelven 0, y que el oráculo
imprimió `rc=0`. Pide `/handoff solo`, sal, vuelve a abrir `scc` en la misma carpeta y, sin pegar la conversación
anterior, pídele objetivo, restricciones y siguiente acción. Pasa si los recupera y la prueba sigue en verde. Si no,
conserva la sesión y diagnostica antes de usar datos reales.

## Soporte

Para pedir ayuda al responsable de la entrega, adjunta: `VERSION`, `BUILD_ID`, commit o suma recibida, sistema o WSL,
`scc --version`, el comando exacto, su código de salida, lo esperado y lo observado, y la salida de `bash kit/doctor.sh`.
Revisa y redacta rutas personales antes de compartir nada: no adjuntes configuración completa, credenciales, cookies ni
transcripts de trabajo real. Los fallos de seguridad siguen [`SECURITY.md`](SECURITY.md). Qué hacer si algo se rompe
tras actualizar Claude Code o el kit: [`kit/docs/OPERAR.md`](kit/docs/OPERAR.md).

## Límites

- Solo Linux y WSL2; Windows nativo y macOS no están soportados.
- La versión mínima de Claude Code es la que figura en el README. Con una anterior, `doctor.sh` avisa; con una
  posterior no hay garantía, solo la prueba de la CI.
- Esta entrega no instala hooks, cockpit ni continuidad automática para Codex u opencode.
- Un paquete sin `.git` no ejecuta `make test`: se verifica con las sumas, `doctor.sh` y `aceptacion-local.sh`.
- Restaurar un respaldo (`bash uninstall.sh --list` y `--apply`) devuelve archivos, no desinstala; para quitar el
  kit, `uninstall.sh --kit`. No borres `.claude/estado/` de tus proyectos: contiene su continuidad.
