# 03 · Headroom: el proxy de contexto y coste

Headroom es de terceros: este kit **no** lo redistribuye. No hay binario, no hay base de datos de ahorro en este repo. Lo que sigue es cómo instalarlo y, sobre todo, cómo se cablea con la config que sí instala este kit.

## Antes de nada: `headroom` y `rtk` son DOS herramientas distintas

Versiones anteriores de este documento las trataban como una sola (titulaban "Instalar Headroom (`rtk`)" y verificaban Headroom con `rtk --version`). **Es un error**: son dos proyectos independientes, en repos distintos, con instaladores distintos y que actúan en capas distintas. Este kit los usa a la vez porque se complementan, no porque sean lo mismo.

| | `headroom` | `rtk` |
|---|---|---|
| Qué es | proxy HTTP local entre Claude Code y la API de Anthropic | proxy de CLI que filtra la salida de los comandos |
| Repo | [headroomlabs-ai/headroom](https://github.com/headroomlabs-ai/headroom) | [rtk-ai/rtk](https://github.com/rtk-ai/rtk) |
| Se instala con | `pip install 'headroom-ai[proxy]'` (Python) | `cargo install` desde su repo (binario Rust) |
| Cómo se cablea | `ANTHROPIC_BASE_URL` → `127.0.0.1:8787` | nada del kit lo cablea: se invoca a mano (`rtk proxy <comando>`) |
| Dónde actúa | sobre las peticiones a la API | sobre la salida de `ls`, `grep`, `git`, `docker`… antes de que entre en contexto |
| Se verifica con | `headroom --version` · `headroom doctor` | `rtk --version` · `rtk gain` |

Ninguna necesita a la otra: puedes tener una, la otra o ambas. Comprobarlas por separado no es pedantería — con el `command -v rtk` de antes, una instalación con `rtk` pero **sin** el proxy daba "Headroom presente" siendo mentira, y al revés.

Cuidado además con el choque de nombres que avisa `rtk` mismo: existe otro proyecto llamado `rtk` (*Rust Type Kit*). Si `rtk gain` falla, probablemente tengas ese otro.

## Qué es (y qué NO es)

Headroom es un **router de contenido**: un proxy local que se sitúa entre Claude Code y la API de Anthropic. Cuando una tool call devuelve un resultado grande (un `grep` con cientos de líneas, un listado de directorio enorme, un fichero largo), Headroom lo comprime **antes** de que ese resultado entre en el contexto del modelo.

Lo importante es lo que no hace: **no resume con otro LLM**. No añade una llamada extra a un modelo para "hacer un resumen"; aplica lógica determinista de compresión sobre el resultado de la tool. Esto importa por dos razones: no mete coste ni latencia de un segundo modelo, y su trabajo no debe romper el prompt-caching nativo de Anthropic, que es el que de verdad protege la factura. El mérito de Headroom no está en sustituir esa caché, está en comprimir sin pisarla.

## Instalar Headroom

Es de terceros, así que la vía depende de dónde lo obtengas (PyPI, build desde su repo, paquete interno de tu organización). Este documento no fija un origen porque el kit no lo controla; lo que sí controla es la integración de más abajo. Si vas por PyPI, **el extra que hace falta es `[proxy]`, no `[all]`**:

```bash
python3 -m venv ~/.venvs/tools                  # o el venv que ya uses
~/.venvs/tools/bin/pip install 'headroom-ai[proxy]'
headroom --version
```

**No instales `[all]` "por si acaso".** `[all]` expande a trece extras, y entre ellos está `[ml]`, que es `torch` + `huggingface-hub`. En una medición real sobre el mismo venv, la diferencia fue de **~900 MB con `[proxy]` frente a 7,2 GB con `[all]`**. Y no compra nada para esto: el motor de compresión de Headroom usa **ONNX Runtime**, que ya viene en `[proxy]`. Verás un aviso `PyTorch was not found` en el log y es inocuo — la compresión funciona igual.

Sin el extra `[proxy]` el proxy no arranca y falla con `No module named 'httpx'`.

**No hay pin de versión**, ni aquí ni en `install.sh`, que instala con `pip install -q --upgrade 'headroom-ai[proxy]'`: te llevas la última publicada, y este kit **no espera una versión concreta** — lo que el kit fija es el cableado, no el número. Las conductas de la herramienta que describe este documento se midieron sobre la **0.36.2**; si tu versión hace otra cosa, manda lo que veas en tu máquina.

### O con un flag, si prefieres que lo haga el kit

Todo lo de este documento —el extra `[proxy]`, la unidad de systemd con sus tres detalles, el modo `cache`, el output-shaper y el cableado— lo automatiza:

```bash
bash install.sh --with-headroom
```

El orden en que lo hace es deliberado: instala, escribe la unidad, arranca, **espera a que `/readyz` conteste**, y solo entonces escribe `ANTHROPIC_BASE_URL` en tu `settings.json`. Si el proxy no llega a responder, sale con error y **no toca tu config** — porque cablear la API a un proxy que no contesta es peor que no cablearla. Con `HEADROOM_PORT=9999` usas otro puerto.

Para deshacerlo: `systemctl --user disable --now headroom-proxy` y quita `ANTHROPIC_BASE_URL` de `settings.json`, en ese orden.

## Arrancar el proxy local

Arranca el proxy hasta que escuche en `127.0.0.1:8787`. Ese puerto no es arbitrario: es el que ya espera la config de este kit.

```bash
headroom proxy --port 8787 --mode cache --no-telemetry
```

Como servicio de usuario de systemd es más cómodo (sobrevive a reinicios). Tres cosas que conviene fijar en la unidad, cada una porque falla de forma poco obvia si no lo haces:

```ini
[Unit]
# En [Unit], NO en [Service]: puesto en [Service] systemd lo ignora en silencio y
# se queda el default (5 arranques en 10 s y luego la unidad muere en `failed`).
# Compruébalo con: systemctl --user show <unidad> -p StartLimitIntervalUSec
StartLimitIntervalSec=0

[Service]
# Ruta absoluta al binario del venv donde lo instalaste (systemd no hereda tu PATH).
ExecStart=%h/.venvs/tools/bin/headroom proxy --port 8787 --mode cache --no-telemetry
# En cuanto ANTHROPIC_BASE_URL apunte aquí, el proxy pasa a ser dependencia dura
# del cliente: que reintente indefinidamente. (El kit ya NO distribuye esa
# variable; se escribe solo con --with-headroom y tras comprobar /readyz.)
Restart=always
RestartSec=3

# Si endureces la unidad, la caché de HuggingFace TIENE que ser escribible: el
# motor de compresión descarga ahí su modelo ONNX (~260 MB). Sin esa ruta se
# queda inutilizable en silencio — ver más abajo.
ReadWritePaths=%h/.headroom %h/.cache/huggingface
```

Y una advertencia si tu instalación trae un subcomando tipo `install`/`deploy` que crea su propia unidad: **no lo mezcles con una unidad hecha a mano**. Dos unidades habilitadas peleando por el 8787 es un fallo real y difícil de ver — la que pierde el bind entra en bucle de reinicio (se han observado más de 20.000 reinicios en una sola sesión), y como su `ExecStart` falla, systemd tumba el cgroup y cualquier `ExecStartPost` de esa unidad nunca llega a ejecutarse. Peor aún: el health-check de la propia herramienta dice "healthy" porque le responde el proxy equivocado. Una sola unidad, y que sea la fuente de verdad.

## Cómo se cablea en `settings.json`

Una sola pieza conecta el kit con Headroom, y **ya no viene puesta**; el motivo es el fallo que corrigió ese cambio: el kit distribuía `ANTHROPIC_BASE_URL` apuntando al proxy mientras Headroom seguía siendo un tercero que el kit no instala, así que quien clonaba en limpio se quedaba con Claude Code enrutado a un puerto donde no escuchaba nadie — sin API, y con un síntoma que no se parecía a un problema de configuración. Ahora la escribe `install.sh --with-headroom` tras comprobar `/readyz`, o la pones tú a mano.

**La variable de entorno** que redirige el cliente de Anthropic al proxy en vez de a la API real:

```json
"env": {
  "ANTHROPIC_BASE_URL": "http://127.0.0.1:8787"
}
```

El proxy recibe la llamada de Claude Code, comprime lo que corresponda, y reenvía a la API real de Anthropic.

**Tiene que ir en `settings.json`, no en tu `.bashrc`/`.profile`.** Parece equivalente y no lo es. Claude Code lee su entorno **una sola vez, al arrancar**, y las sesiones heredan un snapshot del shell: si el proxy no estaba arriba en ese instante exacto, la sesión entera se queda fuera del proxy, sin recuperación posible y **sin decir nada**. Es fácil llegar a ese estado si intentas hacer el export condicional (`solo si /readyz responde`) para que un proxy caído no te deje sin arrancar: el resultado medido es `headroom doctor` → `savings: no tokens saved yet`, cero tokens comprimidos durante toda la sesión mientras tú crees que está funcionando. Perder la función entera en silencio es peor que un error de conexión visible. La disponibilidad se resuelve en systemd (`Restart=always`), no con condicionales en el shell.

**La pieza que hubo y ya no hay: el hook `rtk hook claude`.** Hasta el 2026-09-02 el `settings.json` del kit cableaba un segundo hook `PreToolUse` sobre `Bash` que pasaba cada comando por `rtk`. Se retiró y no se ha repuesto: el filtro reescribía la salida del comando y eso fabricaba falsos negativos silenciosos — un `grep` con un paréntesis literal contestaba «0 matches», `head -N` entregaba la mitad de las líneas descartando el interior, `diff` a secas salía con 0 sobre ficheros distintos y `python3 -m pytest` acababa en un módulo `rtk` inexistente —, y el ahorro marginal medido era nulo. Un filtro que miente sobre la salida de un comando no ahorra: obliga a repetir la medición. Hoy ningún hook del kit invoca `rtk`; lo único que queda de él en `settings.json` es `Bash(rtk *)` en `permissions.allow`, para que puedas llamarlo tú (`rtk proxy <comando>`). Por eso `doctor.sh` solo comprueba su presencia, y con `WARN`, no con `FAIL`.

Lo que sí sigue en pie es `optional-hook.sh`, el envoltorio que nació de ese cableado: los hooks Python del kit (Sentinel, `smart_approve.py`, `stale-read-guard.py`, `write-guard.py` y `narthex-post-mcp.py`) se invocan a través de él, así que si el intérprete del venv no está, el hook **no falla, no hace nada** (exit 0 y sin ruido). Antes se invocaban a pelo y una máquina sin esa dependencia se comía un exit 127 en cada llamada a tool. Lo que el wrapper **no** hace es tragarse un bloqueo: si el programa envuelto sale con código 2, ese 2 se propaga tal cual, porque es así como un guard le dice a Claude Code "no ejecutes esto". Contrato en `kit/test/test_optional_hook.sh`.

## El precio oculto de `ANTHROPIC_BASE_URL`: lo que Claude Code apaga al ver un endpoint custom

Esto es lo menos conocido de todo el documento y lo que más caro sale. En cuanto `ANTHROPIC_BASE_URL` apunta a algo que no es la API oficial, **Claude Code desactiva por su cuenta tres cosas**. Lo reporta `headroom doctor` al pie de su informe, y no es un aviso cosmético:

| Qué se apaga | Efecto | Se recupera |
|---|---|---|
| **Ventana de contexto de 1M** ([#1158](https://github.com/headroomlabs-ai/headroom/issues/1158)) | el contexto **topa en 200k** | `ANTHROPIC_MODEL=<modelo>[1m]` |
| **Carga de herramientas on-demand** ([#746](https://github.com/headroomlabs-ai/headroom/issues/746)) | carga **todos** los schemas de tools de golpe e infla el contexto local | `ENABLE_TOOL_SEARCH=true` |
| **Remote Control** (`/rc`) | el comando desaparece | no se puede: es un gate del cliente |

El de la ventana de 1M es el que muerde en silencio. Lo explica el comentario del propio código de Headroom que implementa el arreglo (`headroom/cli/wrap.py`, textual):

> Claude Code only sends the `context-1m` beta header — unlocking the 1M window for entitled subscription users — when the model id carries the `[1m]` suffix. Behind a custom `ANTHROPIC_BASE_URL` (the proxy) its `/model` picker selection does not survive, so `--1m` forces the suffix via `ANTHROPIC_MODEL` on the launched process.

Es decir: si tienes `"model": "opus[1m]"` en `settings.json` y crees que estás con 1M de contexto, **detrás del proxy no lo estás**. La selección del picker no llega, y como el modelo sigue apareciendo como el correcto, no hay ninguna señal de que te han recortado a 200k. La forma de recuperarlo es forzar el sufijo por entorno:

```json
"env": {
  "ANTHROPIC_BASE_URL": "http://127.0.0.1:8787",
  "ANTHROPIC_MODEL": "claude-opus-5[1m]",
  "ENABLE_TOOL_SEARCH": "true"
}
```

`ANTHROPIC_MODEL` con el sufijo es exactamente lo que hace `headroom wrap claude --1m`; ponerlo en `settings.json` consigue lo mismo sin cambiar cómo lanzas Claude. Ajusta el id al modelo que uses. Si prefieres no fijar el modelo por entorno, la alternativa es lanzar siempre con `headroom wrap claude --1m`.

Este kit **no** fija `ANTHROPIC_MODEL` en el `settings.json` que instala, a propósito: pinchar un modelo concreto en la config de otra persona sería peor que el problema que resuelve. Si usas el proxy con un modelo `[1m]`, añádelo tú.

### El sufijo `[1m]` viaja pegado al modelo, y eso rompe el cambio de modelo

`--1m` no activa una opción: **reescribe `ANTHROPIC_MODEL` del proceso hijo** con el sufijo
pegado — `claude-opus-5[1m]`. Consecuencia que no es evidente hasta que la sufres: el sufijo
se aplica a **cualquier** modelo que le pases, tenga o no derecho a la ventana de 1M en tu
suscripción. Medido el 2026-08-25:

```
$ headroom wrap claude --1m -- -p "..." --model claude-haiku-4-5-20251001
  --model claude-haiku-4-5-20251001[1m] (1M context window; issue #1158)
API Error: 400 The long context beta is not yet available for this subscription.
```

No es un fallo del proxy ni de tu configuración: Haiku no tiene la beta de contexto largo, y
`--1m` se la pide igual. Si trabajas con modelos mixtos, lanza **sin** `--1m` para esa sesión
(el alias `claude-directo` ya sirve) o quédate en el modelo que sí tiene la ventana. El fallo
llega como un `400` de la API, así que es fácil confundirlo con un problema de cuota o de
credenciales.


### `ENABLE_TOOL_SEARCH` ya la pone `headroom wrap`: no la dupliques a ciegas

La fila de la tabla de arriba es correcta pero incompleta en un punto que sale caro
averiguar por tu cuenta: si lanzas Claude con `headroom wrap`, **la variable ya se
pone sola**. En `headroom/cli/wrap.py` el valor se resuelve con esta precedencia:

1. el flag explícito `--tool-search`, si lo pasas;
2. un valor **preexistente en el entorno**, que se respeta y no se toca;
3. y si no hay ninguno, el default incorporado, que es `true`
   (`headroom/providers/claude/runtime.py`).

De ahí salen dos consecuencias que conviene tener claras antes de tocar nada:

- **Quitarla de `settings.json` no la desactiva** cuando lanzas con el wrapper: se
  repone en cada arranque. Para apagarla de verdad hay que preponerla al comando
  (`ENABLE_TOOL_SEARCH=false headroom wrap claude`) o pasar el flag.
- El `env` de `settings.json` se aplica **después** de arrancar el proceso, así que un
  valor ahí **pisa** el del wrapper. Es el canal fiable si quieres fijarla, y es
  también por lo que un `"false"` olvidado ahí anula el deferral en silencio aunque
  uses el proxy.

Dato relacionado, del changelog de Claude Code: en **Vertex AI** el deferral viene
**desactivado** por defecto —la cabecera beta no está soportada ahí— y hay que optar
por él con esta misma variable.

## Cuidado con `headroom init`: el hook que puede levantar un segundo proxy

`headroom init` deja, en el directorio donde lo ejecutas, un
`.claude/settings.local.json` de ámbito proyecto que engancha
`headroom init hook ensure` a **dos** eventos: `SessionStart` y `PreToolUse(Bash)`.
Ese hook es best-effort: llama a `_ensure_profile_running()`, que consulta `/readyz`
con **1 segundo** de timeout y, si no contesta, arranca el runtime.

El problema no es que arranque, es **cómo**. Si el manifiesto del perfil
(`~/.headroom/deploy/<perfil>/manifest.json`) tiene `supervisor_kind: "none"` —que es
lo que deja `init` cuando no instala un servicio—, la rama que se ejecuta en
`headroom/cli/init.py` es `start_detached_agent()`: un proxy **suelto, fuera del
supervisor**. Si además tienes el proxy como unidad systemd con `Restart=always`,
acabas con **dos instancias peleando por el puerto 8787**, y el síntoma es el peor
posible de diagnosticar: respuestas **HTTP 200 vacías**, que Claude Code reporta como
*"API returned an empty or malformed response"*. Parece un fallo de la API, y no lo es.

Cómo evitarlo:

- Si gestionas el proxy con systemd, **no dejes ese hook activo**: borra o renombra el
  `.claude/settings.local.json` que `init` dejó en ese directorio. Solo afecta a
  sesiones cuyo directorio de trabajo sea ese, así que puede pasar desapercibido
  durante semanas y aparecer justo cuando trabajas ahí.
- Reinicia **siempre** por el supervisor (`systemctl --user restart <unidad>`).
  Terminar el proceso a mano y relanzarlo deja que el supervisor levante el suyo, y
  vuelves a tener dos.
- `headroom init hook ensure` **no** reescribe ficheros de configuración —solo arranca
  el runtime—, así que neutralizar ese `settings.local.json` no se deshace por sí solo
  en el siguiente arranque.

## `headroom wrap` sí reescribe tu config: la URL del proxy en el `settings.local.json` del proyecto

Ojo con la distinción, porque son dos vectores distintos y la frase de arriba solo cubre uno:
«`headroom init hook ensure` **no** reescribe ficheros de configuración» es cierto de `hook
ensure`, y **no** vale para `wrap`. Medido en la 0.36.2: `_write_claude_wrap_base_url()`
(`headroom/cli/wrap.py`) escribe `ANTHROPIC_BASE_URL` en
`Path.cwd()/.claude/settings.local.json` —el del **proyecto**, no el global—, guarda el valor
anterior en su marker y lo restaura al salir.

Tres consecuencias, sin adornos:

- **Quitar la URL a mano no dura.** Si queda un `wrap` huérfano, o el hook `wrap selfheal` que
  la propia herramienta instala, la repone en el siguiente arranque. Comprueba el fichero, no
  tu recuerdo de haberlo editado: `jq -r '.env.ANTHROPIC_BASE_URL' .claude/settings.local.json`
  en la raíz del proyecto.
- **El enrutado resultante es por proyecto, no global.** Solo lo cargan las sesiones cuyo
  directorio de trabajo sea la raíz de ese proyecto. De ahí un síntoma que no se parece a un
  problema de configuración: el proxy "parece" apagado en unos proyectos y encendido en otros,
  con la misma instalación y el mismo `settings.json`.
- **Una comprobación global no lo ve** — es el ámbito que las del kit no cubrían. Fue el
  escondite del incidente que `doctor.sh` documenta en su propio código: la URL vivía en cinco
  `settings.local.json` de proyecto, cada uno con su hook `wrap selfheal` reponiéndola, y el
  94 % del trabajo de un día salió sin pasar por el proxy.

## Modo del proxy: `cache` vs `token`

Headroom arranca en uno de dos modos, y la diferencia importa para la factura, no solo para el tamaño del contexto:

- **`cache`**: los turnos anteriores de la conversación quedan congelados. Al no tocar el prefijo de la conversación, el prompt-caching nativo de Anthropic sigue funcionando turno a turno.
- **`token`**: Headroom puede reescribir turnos anteriores para ahorrar tokens de contexto. Al reescribir el prefijo, invalida el caché de Anthropic desde ese punto en adelante: lo que ganas en tokens de contexto lo puedes perder, y de sobra, en cache misses.

**Ojo con el default**: la propia herramienta se ha visto contradecirse sobre cuál es. La ayuda del subcomando que arranca el proxy puede mostrar `cache` como default, mientras que la ayuda del subcomando de instalación (y la documentación online del proyecto) dicen `token`. No asumas cuál tienes activo: compruébalo explícitamente en tu instalación en vez de fiarte del default. Si tu instalación usa perfiles de ahorro predefinidos, el perfil se suele aplicar con algo equivalente a `setdefault()` (lo que fijes tú explícitamente manda sobre el perfil), y no todos los perfiles usan `cache` por defecto: verifica el que tengas activo, no solo el que crees haber elegido.

Si decides enrutar la API por el proxy (`install.sh --with-headroom`, o a mano), fija el modo explícitamente a `cache` en vez de confiar en el default, y vuelve a comprobarlo tras cada actualización de Headroom: es lo que evita que el proxy te rompa el caché de Anthropic. Y no des por hecho que la compresión de Headroom es lo que te ahorra dinero: en la práctica, el ahorro grande suele venir del prompt-caching nativo de Anthropic (que `cache` protege); la compresión aporta encima, pero como un extra menor, no como el mecanismo principal.

## Endpoint de salud

Para comprobar que el proxy está vivo:

```bash
curl -s 127.0.0.1:8787/readyz
```

Ten cuidado con este comando: Sentinel (ver `05-security.md`) trata las IP en crudo dentro de una URL como un patrón sospechoso, y puede bloquear ese `curl` aunque el destino sea inofensivo y local. El allowlist que este kit instala (`sentinel-allowlist.json`) ya incluye `127.0.0.1` y `localhost` como dominios permitidos, así que el comando de arriba debería pasar sin fricción tras `install.sh`. Si partes de un allowlist propio construido desde cero y no lo has incluido, tienes dos salidas: añadirlo al allowlist, o usar directamente el CLI que la propia instalación de Headroom exponga para estadísticas (por ejemplo `headroom_stats`, si tu instalación lo provee), que no contiene una URL y por tanto no dispara esa regla.

**Lo que `headroom doctor` NO es: el oráculo del enrutado.** Su tabla sirve para lo demás —que el proxy corra, que la versión del proceso coincida con la instalada, qué apaga el endpoint custom—, pero la fila que dice si tu cliente está enrutado **miente en los dos sentidos**, porque no juzga la sesión: juzga un fichero. Medido el 2026-09-01 y el 2026-09-02:

- **Falso negativo.** `claude ⚠ not routed (no ANTHROPIC_BASE_URL in settings env)` dentro de una sesión que sí estaba pasando por el proxy, porque la URL no venía del `settings.json` que él mira, sino del `settings.local.json` de proyecto que escribe `headroom wrap` (ver arriba) o del entorno heredado del shell. Tres filas más abajo, en la misma tabla, `shell env ✓ routed via ANTHROPIC_BASE_URL`: se contradice consigo mismo.
- **Falso positivo.** `codex ✓ routed` con **cero** peticiones OpenAI (`/v1/responses`, `/v1/chat/completions`) en todos los logs vigentes del proxy. Que un fichero de config lo declare no significa que haya pasado tráfico.

Los dos oráculos que sí contestan a "¿está *esta* sesión pasando por el proxy?":

```bash
# 1. El entorno de un proceso HIJO de la sesión —vale cualquier servidor MCP—, que es lo
#    que la sesión usa de verdad. Mirar el `environ` del propio `claude` no basta: es el
#    de su exec, y lo que entra por `settings.json` se aplica ya en proceso.
pgrep -a -f 'mcp' | head
tr '\0' '\n' < /proc/<pid-del-hijo>/environ | grep ANTHROPIC_BASE_URL

# 2. El del kit, que además falla si el enrutado está declarado en dos sitios a la vez.
bash doctor.sh
```

El contador de ahorro de su informe sí vale como señal de humo: `savings: no tokens saved yet` con el proxy vivo significa que por ahí no ha pasado nada, que es precisamente el estado que un `curl /readyz` te reporta como correcto. Para las cifras, el histórico durable es `/stats-history` (más abajo), no esa fila.

Un `200 OK` en `/readyz` confirma que *algo* responde en ese puerto, no que sea tu proxy. Un healthcheck que solo mira el puerto no distingue una instancia vieja o a medio configurar (por ejemplo, un servicio anterior que quedó ocupando el 8787) de la que tú acabas de arrancar; puede darte "vivo" mientras la que responde de verdad no es la tuya. Si algo no cuadra (el proxy no aplica el modo que configuraste, o los resultados no parecen pasar por él), comprueba qué proceso tiene el puerto realmente abierto (`lsof -i :8787` o equivalente) antes de fiarte solo del curl.

## El motor de compresión puede estar apagado sin que nada lo diga

El proxy sirve tráfico perfectamente con su motor de compresión muerto. Esa es la trampa. El indicador está en `/health`:

```
"kompress": { "enabled": true, "ready": false, "status": "unhealthy", "backend": null }
```

`backend: null` significa que no ha cargado su modelo, así que **no comprime nada** aunque el proxy responda `200` en todo. Dos causas, las dos silenciosas:

1. **El modelo no está descargado.** El motor necesita un modelo ONNX (~260 MB) en la caché de HuggingFace. La descarga **no ocurre al arrancar**: el preload usa deliberadamente "solo caché local", para que una caché fría no bloquee el bind del puerto. La descarga real la dispara la primera petición que se pueda comprimir. Si quieres evitar que las primeras peticiones pasen sin comprimir, precaliéntalo a mano una vez.
2. **La unidad de systemd está endurecida y la caché no es escribible.** Si usas `ProtectHome=read-only` con `ReadWritePaths=%h/.headroom`, la descarga no puede escribir y el motor se queda `unhealthy` **para siempre**. Añade `%h/.cache/huggingface` a `ReadWritePaths`.

Por eso conviene que `/health` no sea el healthcheck automático: es **agregado**, y se pone en rojo si cualquier subcomprobación falla. Para "¿puede atender tráfico?" usa `/readyz`; para "¿está comprimiendo?" mira `checks.kompress.ready` en `/health`. Son preguntas distintas.

## Medir el ahorro sin engañarte

Dos endpoints y no son intercambiables:

- **`/stats`** — contadores **del proceso actual**. Se reinician cada vez que reinicias el servicio. No sirven para asertar en un test ni para comparar entre días.
- **`/stats-history`** — histórico **durable** (`lifetime.*`), respaldado en un fichero bajo tu directorio de usuario. Es el que hay que mirar.

Y la única cifra que de verdad juzga si el modo `cache` está haciendo su trabajo:

```
lifetime.cache_read_tokens / lifetime.total_input_tokens
```

Es la proporción de tokens de entrada servidos desde el prompt-caching de Anthropic. Si está alta (en una máquina de trabajo real, del orden del 90 %), el proxy no está rompiendo la caché. Si se hunde, el modo está mal configurado — y eso cuesta mucho más de lo que ahorra la compresión, así que merece una assert propia en tu verificación, no una mirada de reojo.

Contexto para no perder la perspectiva: en una medición real sobre esta misma configuración, el ahorro por prompt-caching fue de dos órdenes de magnitud más que el de la compresión de Headroom. La compresión aporta encima; la caché es la que paga la factura.

## Sin DBs ni cifras de ahorro

Este kit no versiona ni gestiona ningún fichero de ahorro que Headroom pueda mantener en tu máquina (típicamente algo bajo tu directorio de usuario, propio de tu instalación). Es estado local del proxy, no config del kit: si quieres consultarlo, es cosa de la documentación de tu instalación de Headroom, no de este repo.
