# 03 · Headroom: el proxy de contexto y coste

Headroom es de terceros: este kit **no** lo redistribuye. No hay binario, no hay base de datos de ahorro en este repo. Lo que sigue es cómo instalarlo y, sobre todo, cómo se cablea con la config que sí instala este kit.

## Qué es (y qué NO es)

Headroom es un **router de contenido**: un proxy local que se sitúa entre Claude Code y la API de Anthropic. Cuando una tool call devuelve un resultado grande (un `grep` con cientos de líneas, un listado de directorio enorme, un fichero largo), Headroom lo comprime **antes** de que ese resultado entre en el contexto del modelo.

Lo importante es lo que no hace: **no resume con otro LLM**. No añade una llamada extra a un modelo para "hacer un resumen"; aplica lógica determinista de compresión sobre el resultado de la tool. Esto importa por dos razones: no mete coste ni latencia de un segundo modelo, y su trabajo no debe romper el prompt-caching nativo de Anthropic, que es el que de verdad protege la factura. El mérito de Headroom no está en sustituir esa caché, está en comprimir sin pisarla.

## Instalar Headroom (`rtk`)

Como es de terceros, la vía de instalación depende de dónde lo obtengas (build desde el repo del proyecto, paquete interno de tu organización, binario ya empaquetado). Este documento no fija un origen concreto porque el kit no lo controla; lo que sí controla es la integración descrita más abajo. El único requisito verificable es tener el ejecutable `rtk` en el `PATH`:

```bash
rtk --version
```

Si el comando no existe, instala primero el proyecto Headroom (consulta su propio repo o el paquete que use tu organización) antes de continuar.

## Arrancar el proxy local

Con `rtk` en el `PATH`, arranca el proxy (normalmente con el subcomando de arranque que documente tu instalación de Headroom, o como servicio de usuario si tu organización lo empaqueta así) hasta que quede escuchando en `127.0.0.1:8787`. Ese puerto no es arbitrario: es el que ya espera la config de este kit.

## Cómo se cablea en `settings.json`

El kit instala (`claude/settings.json`) dos piezas ya conectadas a Headroom, ninguna de las cuales necesitas tocar si el proxy está arriba en el puerto por defecto:

1. **La variable de entorno** que redirige el cliente de Anthropic al proxy en vez de a la API real:

```json
"env": {
  "ANTHROPIC_BASE_URL": "http://127.0.0.1:8787"
}
```

El proxy recibe la llamada de Claude Code, comprime lo que corresponda, y reenvía a la API real de Anthropic.

2. **El hook `PreToolUse` sobre `Bash`**, que conecta el ciclo de vida de cada comando con el router:

```json
{
  "matcher": "Bash",
  "hooks": [{ "type": "command", "command": "rtk hook claude", "timeout": 10 }]
}
```

`rtk hook claude` se ejecuta antes de cada llamada a Bash. No necesitas escribirlo tú: ya viene en el `settings.json` que instala `install.sh`.

## Endpoint de salud

Para comprobar que el proxy está vivo:

```bash
curl -s 127.0.0.1:8787/readyz
```

Ten cuidado con este comando: Sentinel (ver `05-security.md`) trata las IP en crudo dentro de una URL como un patrón sospechoso, y puede bloquear ese `curl` aunque el destino sea inofensivo y local. El allowlist que este kit instala (`sentinel-allowlist.json`) ya incluye `127.0.0.1` y `localhost` como dominios permitidos, así que el comando de arriba debería pasar sin fricción tras `install.sh`. Si partes de un allowlist propio construido desde cero y no lo has incluido, tienes dos salidas: añadirlo al allowlist, o usar directamente el CLI que la propia instalación de Headroom exponga para estadísticas (por ejemplo `headroom_stats`, si tu instalación lo provee), que no contiene una URL y por tanto no dispara esa regla.

## Sin DBs ni cifras de ahorro

Este kit no versiona ni gestiona ningún fichero de ahorro que Headroom pueda mantener en tu máquina (típicamente algo bajo tu directorio de usuario, propio de tu instalación). Es estado local del proxy, no config del kit: si quieres consultarlo, es cosa de la documentación de tu instalación de Headroom, no de este repo.
