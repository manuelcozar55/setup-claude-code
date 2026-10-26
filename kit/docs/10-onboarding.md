# 10 · Primer día: de cero a tu primera sesión

Guía para quien llega nuevo y solo quiere usar el kit. Está pensada para **WSL2 con Ubuntu o Debian**. Dura unos diez minutos. El procedimiento completo y lo opcional está en [`02-install.md`](02-install.md).

**Si recibiste una consolidación local**, empieza por [`ENTREGA.md`](../../ENTREGA.md).
Instala la base como se explica aquí y arranca con `bash /ruta/a/scc/scripts/scc.sh`.
Ese lanzador carga las copias incluidas de cockpit y esenciales; no necesitas instalarlas
desde el marketplace. El paso 4 de esta guía es la alternativa para una release publicada.

Seis palabras que verás enseguida:

- **Guard**: un script que corre antes de cada comando y lo bloquea si es peligroso. No depende del modelo.
- **Oráculo**: la orden que decide si el trabajo está hecho (por ejemplo, tus tests). Se ejecuta con `oraculo -- <orden>`.
- **`nucleo.md`**: el fichero `.claude/estado/nucleo.md` donde vive el estado de la tarea: objetivo, plan y siguiente paso.
- **Handoff**: guardar ese estado al cerrar una fase, para que la sesión siguiente lo reciba sola.
- **Dueño**: la sesión que ha reclamado `nucleo.md` y es la única que lo escribe.
- **Diff-first**: si tu `~/.claude` es un repo con remoto, el instalador no escribe nada: te enseña el diff y copias tú lo que quieras.

Si eres Claude Code leyendo esto en una máquina nueva: los pasos 2 a 4 son el arranque y el paso 7 es el diagnóstico cuando algo no cuadra.

---

## 0 · Qué vas a levantar

| Capa | Qué recibes | Cómo se activa |
|---|---|---|
| Base `kit/` | Guards, Sentinel, 7 agentes, skills del método, `handoff`, `oraculo` y plantilla de estado | `bash kit/install.sh` |
| Aspecto y continuidad | Pantalla completa, tema oscuro, statusline, ventana de autocompactación, checkpoint y reinyección del estado | Se instalan con la base; se conservan los ajustes visuales propios |
| Cockpit y esenciales incluidos | Dock de agentes, vigía, `/handoff`, `/nueva`, `/simple`, `/autonomo` y skills del plugin | `scripts/scc.sh` en la consolidación; marketplace como alternativa |
| Harness y memoria del repo | `/work`, sensores del repo, `knowledge/` y `scripts/recuerda` | Solo al trabajar en este repo; `recuerda` requiere enlace manual |
| Herramientas externas | `gitleaks`, venv de tools, agent-browser, MCP y plugins de terceros | Opcionales; ver [`08-plugins-mcp-y-skills.md`](08-plugins-mcp-y-skills.md) |

Nada del kit da por supuesto lo opcional, y hay un test que lo demuestra en una máquina pelada: `kit/test/test_clean_install_resilience.sh`.

## 1 · Antes de empezar (WSL2 Ubuntu o Debian)

Necesitas Linux o WSL2 con una distribución Ubuntu o Debian y acceso a Claude Code.
Abre la terminal de tu distribución y trabaja dentro de ella. Clona o extrae el paquete
en tu carpeta personal (`~/`), no en `/mnt/c/`. Una cuenta de GitHub solo hace falta
para colaborar en repositorios que la requieran, no para extraer e instalar el paquete.

Instala los paquetes base. Esto lo lanzas tú, el kit no instala paquetes de sistema:

```bash
sudo apt update
sudo apt install git jq make curl ca-certificates python3 python3-venv zip unzip
```

`curl` lo usa el instalador para descargar `gitleaks` (opcional). Comprueba que están:

`zip` y `unzip` permiten crear la copia de seguridad que exige la restauración.

```bash
git --version && jq --version && make --version && python3 --version
```

También necesitas Claude Code instalado y con sesión iniciada: `claude --version`. El kit se probó con la versión 2.1.292. No hay una versión mínima comprobada: si algo falla con otra, indícalo al abrir el problema.

## 2 · Instalar

```bash
git clone https://github.com/manuelcozar55/setup-claude-code.git
cd setup-claude-code
bash kit/install.sh
```

No uses `make bootstrap`: ejecuta además la suite de tests y crea un perfil que no necesitas. Lee la salida del instalador hasta el final. Te puede avisar de dos cosas:

- **Ya tenías un `CLAUDE.md`.** No lo toca. Añade la línea `@AGENTS.md` a tu `CLAUDE.md`; la plantilla del kit quedó en `CLAUDE.kit.md`.
- **`~/.local/bin` no está en tu `PATH`.** El instalador enlaza `handoff`, `oraculo` y `cupo` ahí. Abre una terminal nueva antes de seguir.

Al final el instalador imprime «Rellena tus claves: cp … .env.example …». Es **opcional**: solo hace falta si vas a usar servicios externos con clave; el kit funciona sin ese fichero.

Si ya tenías hooks propios en `settings.json`, los del kit los sustituyen. Los tuyos quedan en la copia de seguridad de `~/.claude/backups/`.

## 3 · Verificar la instalación

```bash
bash kit/doctor.sh
command -v handoff oraculo cupo   # deben salir tres rutas
```

Cómo leer `doctor.sh`:

- **`FAIL`**: algo está roto o es inseguro. Sale con código distinto de 0. No lo ignores.
- **`WARN`**: un componente opcional que no instalaste, o un aviso como «falta `@AGENTS.md`». Léelo antes de seguir.
- Cada `PASS` dice de dónde sale el dato (`(fuente: …)`). Si un check no puede decir su fuente, no es un check.

Debe acabar en `OK (0 FAIL)`. Los `WARN` del venv de herramientas o de la Capa 2 de secretos son normales.

Este diagnóstico comprueba la base instalada, no una respuesta del modelo ni los plugins
cargados. En la sesión real, usa `/status`, `/context` y `/plugin`; comprueba también que
ves la barra y el Dock. Una entrada en `enabledPlugins` declara una preferencia:
no demuestra por sí sola que el plugin esté instalado o cargado.

## 4 · El mod `cockpit` (opcional, recomendado)

Da `/handoff`, `/nueva`, `/simple`, `/autonomo`, el Dock de agentes y el vigía de contexto.
Para la consolidación local basta el lanzador indicado arriba. Para una release publicada:

```bash
claude plugin marketplace add "manuelcozar55/setup-claude-code@v$(cat VERSION)"
claude plugin install cockpit@setup-claude-code
```

`install.sh` ya declara el marketplace (fijado a `v<VERSION>`) y habilita `esenciales@setup-claude-code` en `settings.json` antes de que ejecutes nada de esto; estas dos órdenes instalan el cockpit, y `doctor.sh` no mira plugins. El `ref` es una etiqueta de git, mutable: Claude Code no admite `sha` en la fuente de un marketplace (sí en la de cada plugin), así que protege la etiqueta en tu remoto si te importa. Queda fijado al tag de tu versión del kit: al actualizar, repite estas dos órdenes y `claude plugin update cockpit@setup-claude-code` (ver «Actualizar» en [`02-install.md`](02-install.md)). Detalle en [`11-cockpit.md`](11-cockpit.md). Sin el mod puedes guardar el estado con la CLI, pero no tienes Dock ni handoff automático.

## 5 · Tu primer proyecto

El estado de una tarea vive en `.claude/estado/nucleo.md` dentro de la **raíz git** del proyecto. Una carpeta sin git no es proyecto, ni tampoco tu `~`. Para una carpeta de documentos, empieza con `git init`. En `~` el estado de la sesión va a su propia ranura en `~/.claude/estado/sesiones/` y `handoff` la usa solo; sigue sin haber `--commit` ni registro de proyecto.

```bash
cd tu-proyecto
git init              # solo si aún no es un repo
handoff --iniciar     # crea .claude/estado/nucleo.md desde la plantilla
```

Abre `nucleo.md` y rellena **Objetivo** (las palabras de quien pidió la tarea) e **Invariantes** (lo que no se toca y por qué). Después abre `bash /ruta/a/scc/scripts/scc.sh` en la raíz del proyecto si usas la consolidación, o `claude` si instalaste los plugins globalmente. El hook de arranque te reclama como dueño del estado y se lo entrega al modelo.

`handoff --iniciar` nunca sobrescribe: si el fichero existe, lo dice y sale sin tocarlo.

**Dónde va cada cosa.** Lo temporal, en el scratchpad o un `mktemp`. El estado, los informes y los checkpoints, en `.claude/estado/` del proyecto: el kit lo crea si falta y lo deja ignorado por git (un `.gitignore` interno con `*`), así que nunca llega a un commit. Lo privado de tu máquina, en `~/.claude`. Para el informe de una tarea, `handoff --informe <tema>` crea `informes/AAAA-MM-DD-<tema>/` y te da su ruta.

## 6 · El bucle diario

1. **Trabaja y verifica con `oraculo`.** Ejecuta tus pruebas así:

   ```bash
   oraculo -- <tu comando de test>
   ```

   Claude Code te pedirá permiso en cada `oraculo --`. Apruébalo cada vez (solo esta vez) y no elijas «permitir siempre»: una regla permanente sobre `oraculo` dejaría pasar sin preguntar cualquier orden que se ejecute a través de él.

   Imprime las últimas 40 líneas y `rc=N`, sale con ese código y lo anota en `.claude/estado/verificaciones.log`. Así el estado guarda qué se verificó y con qué resultado.
2. **Cierra la fase.** Con el mod: `/handoff`. Sin el mod (el defecto): checkpoint + reinyección + aviso; `/handoff` es manual, así que pide al modelo un borrador de las secciones que cambian y ejecuta `handoff --desde borrador.md`; el cockpit es la opción automática. `handoff --estado` te dice cuánto del tope ocupa el estado.
3. **Retoma el trabajo.** `/handoff` ya hace el clear y prepara la continuación:
   revísala y pulsa Enter; no hagas otro `/clear` detrás. Si guardaste con la CLI o
   con `/handoff solo`, puedes ejecutar `/clear` cuando quieras relevar el contexto.
   La sesión nueva recibe el estado escrito. Para cambiar de tarea, usa `/nueva <tarea>`
   con el mod.

Una sesión por tarea. Esperar a la compactación automática pierde contexto; este bucle conserva lo que tú dejaste escrito. Para el hábito día a día, sigue la [ruta de 7 días](guia/00-ruta-7-dias.md).

## 7 · Si algo falla

| Síntoma | Qué hacer |
|---|---|
| `handoff: command not found` | Abre una terminal nueva. Si sigue igual, `~/.local/bin` no está en el `PATH`: añádelo a `~/.bashrc`, o usa la ruta completa `~/.claude/bin/handoff`. |
| `doctor.sh` marca `FAIL` por `bin/handoff`, `bin/oraculo` o la plantilla | Falta algo de la instalación. Repite `bash kit/install.sh`. |
| `doctor.sh` marca `WARN` por `@AGENTS.md` | Tu `CLAUDE.md` no importa las reglas del kit. Añade esa línea (paso 2). |
| `handoff --iniciar` sale con error (exit 3) | No estás dentro de un repo git. Haz `git init` en la raíz del proyecto. |
| Un hook «no hace nada» | CRLF en el fichero o sin bit de ejecución. `kit/test/test_gitattributes.sh` y `kit/test/test_exec_modes.sh` lo cubren en el repo. |
| Un guard bloquea algo legítimo | Reformula el comando. **No amplíes la allowlist para esquivarlo**: los guards bloquean por el literal, así que nombrar un fichero de credenciales, aunque sea para excluirlo, dispara. |

## 8 · Si vas a contribuir al repo

Esto es solo para quien cambia el propio kit. Antes de tu primer commit:

```bash
make test                  # 45 suites en bash puro, sin red, unos 7 min. exit 0 o no está hecho.
bash kit/scan-secrets.sh   # secretos y PII en el árbol
shellcheck -x <tus .sh>
```

Si `make test` termina con el bloque «verde, pero con capas SALTADAS» (sin `gitleaks`, sin `claude` en el PATH, sin `kit/evals/runs.jsonl`), el rc es 0 pero esa capa **no se ha verificado**: instala la herramienta y repite antes de darlo por hecho. No lances dos `make test` a la vez: las pruebas de rendimiento miden tiempo de CPU y fallan por carga.

Los guards no se prueban solo con leer el README: `bash kit/test/test_guards_falsifiability.sh` desactiva un guard real y exige que eso rompa exactamente 28 casos `BLOCK` conocidos. Si desactivarlo no rompiera nada, la suite no estaría midiendo nada.

Rama y PR, nunca directo a `main`. Y si tu cambio toca una cifra que la documentación afirma, `kit/test/test_doc_claims.sh` te pondrá en rojo: eso no es un obstáculo, es el punto.
