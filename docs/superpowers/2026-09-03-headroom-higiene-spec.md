# Spec — higiene del log de Headroom y deriva de la unidad viva

**Fecha:** 2026-09-03
**Autor de la medición:** sesión de auditoría `7a6841ca` sobre la máquina viva.
**Estado:** aprobado para planificar. Plan derivado:
`docs/superpowers/plans/2026-09-03-headroom-higiene.md`.

## 1. Por qué ahora

Una auditoría del proxy pedida para responder "¿de verdad funciona bien?" encontró
que **sí funciona** —las tres sesiones vivas enrutan, el ahorro es real y no hay
inflación— pero que el sistema **registra conversación en claro**, **corre con
permisos más laxos de lo que el propio kit publica** y **pierde su propia serie de
medición cada pocas horas**. Los tres son defectos de *higiene*, no de
funcionamiento: nada está caído, y por eso ningún sensor existente se ha quejado.

Añadido de la misma auditoría, y más grave que los tres: la unidad systemd de esta
máquina es del **2026-08-21** y **no tiene `InaccessiblePaths`**. La plantilla que
el kit genera hoy sí lo tiene. Con `ProtectHome=read-only`, el proxy puede leer
todo el home, incluidos `~/.ssh`, `~/.aws`, `~/.gnupg` y `~/.config/gh`.

## 2. Estado medido (línea base, 2026-09-03)

| Hecho | Valor | Cómo se midió |
|---|---|---|
| Sesiones `claude` vivas | 3 (pid 3679767, 4158927, 4162418) | `ps -eo pid,lstart,args` |
| Enrutado | las 3 con socket `ESTAB` a `127.0.0.1:8787` | `ss -tnp` |
| Fuentes de `ANTHROPIC_BASE_URL` | 1 (`~/.claude/settings.json`) | `command grep -rl` |
| Modo | `cache` | `systemctl --user cat` |
| Peticiones del día | 1288 líneas `PERF` | `grep -c` |
| Ahorro de contenido | **1,198 %** de `tok_before` | suma `awk` de `tok_saved` |
| Ahorro con esquemas | **3,213 %** | suma de `tok_saved` + `tool_saved` |
| Inflación | **0** peticiones | suma de `tok_inflated` |
| Latencia añadida | **+208 ms** de media | media de `opt_ms` |
| RSS del proxy | **1,69 GB** | `ps -eo rss` |
| Errores del día | 0; 4 `WARNING` benignos (`No usage chunk in SSE`) | grep por campo de nivel |
| Petición mayor | **244 385** tokens, `opus-5`, con `context-1m` | máximo + cabecera |
| Vida (desde 31-ago 19:36) | 4876 peticiones, 612,8 M tokens, 3,84 M de contenido (**0,63 %**), 11,94 M de esquemas | `/stats` |
| Coste en dólares | `total_saved_usd = 0.0` (telemetría apagada) | `/stats` |
| `input_tokens` en el log | **0 apariciones** | `grep -c` |

Dos advertencias que el plan debe respetar y no maquillar. Los dólares del panel
son un contrafactual: con telemetría apagada valen 0. Y como `input_tokens` no
aparece nunca en el log, **los porcentajes de arriba están sobre el recuento propio
de Headroom, no sobre lo facturado**: sirven para comparar contra sí mismos a lo
largo del tiempo, no para prometer un ahorro en la factura.

## 3. Defectos que este trabajo cierra

### P1 — La unidad viva puede leer credenciales (deriva, no diseño)

- Unidad: `~/.config/systemd/user/headroom-proxy.service`, fechada `2026-08-21 14:36:51`.
- `command grep -E '^(InaccessiblePaths|ReadWritePaths|ProtectHome)=' ` sobre ella
  devuelve `ProtectSystem=strict`, `ProtectHome=read-only` y
  `ReadWritePaths=%h/.headroom %h/.cache/huggingface %h/.local/share/rtk`.
  **No hay línea `InaccessiblePaths`.**
- La plantilla del kit (`kit/install.sh:196-213`) sí la escribe:
  `InaccessiblePaths=-%h/.ssh -%h/.aws -%h/.gnupg -%h/.config/gh`, con el comentario
  que explica por qué `ProtectHome=read-only` obliga a taparlos a mano.
- **Causa raíz:** la unidad se escribió antes de que el kit añadiera esa línea, y
  nada re-aplica la plantilla. `kit/doctor.sh` inspecciona la unidad (`:275-283`)
  pero solo mira `ExecStart=`: comprueba `--mode cache` y la ausencia de
  `--budget`/`--log-messages`, y nunca el bloque de endurecimiento.
- **Severidad:** alta. No es una fuga demostrada, es una capacidad innecesaria
  concedida a un proceso que habla con la red.

### P2 — `proxy.log` escribe conversación en claro con `--log-messages` apagado

- Emisor: `headroom.cache.compression_store`, `event=headroom_retrieve`, a nivel
  `INFO`. 100 líneas hoy, ~4,7 KB por línea.
- `_RETRIEVAL_LOG_PREVIEW_CHARS = 4096` en
  `~/.venvs/tools/lib/python3.14/site-packages/headroom/cache/compression_store.py:54`.
- `_payload_preview_enabled()` (mismo fichero, `:115-118`) devuelve `True` **cuando
  la variable no está puesta**: el default es escribir.
- Redacta claves, bearers y `sk-*` con tres regexes (`:59-64`), pero el texto de la
  conversación va literal. El comentario del propio paquete lo admite: «makes
  proxy.log too sensitive for users to share in bug reports».
- **El sensor del kit mira el fichero equivocado.** `kit/doctor.sh:290-292` busca
  `"request_messages":[` dentro de `~/.headroom/logs/proxy.jsonl`. La fuga real está
  en `proxy.log` y su marca es `"payload_preview":"`. El sensor está verde mientras
  hay conversación en claro a un directorio de distancia.
- **Oráculo hoy:** `payload_preview_chars":1062` presente; `payload_preview":""` = 0.
- **Arreglo:** `HEADROOM_LOG_PAYLOAD_PREVIEW=0` (acepta `0`/`false`/`no`/`off`).

### P3 — El arreglo de P2 no se puede aplicar en caliente

- `HEADROOM_LOG_PAYLOAD_PREVIEW` **no** está en `_KNOBS_BY_ENV`: 0 aciertos en
  `headroom/proxy/runtime_env.py`.
- `set_overrides` (`runtime_env.py:110-124`) guarda en un dict interno y **nunca**
  escribe `os.environ` (0 aciertos de `os.environ[`), mientras el lector consulta
  `os.environ` directo.
- **Consecuencia:** el `POST /admin/runtime-env` que usa el shaper no sirve aquí.
  Hace falta `Environment=` en la unidad **y reiniciar el servicio**. El reinicio
  aborta las peticiones en vuelo de tres sesiones, así que el plan necesita una
  comprobación de reposo previa, no un reinicio a ciegas.

### P4 — Permisos laxos en los logs

- `~/.headroom` está en `700` (bien: bloquea el paso), pero `logs/` está en `775` y
  los siete ficheros en `664`.
- **Causa raíz de los ficheros:** el proceso corre con `Umask: 0002`, verificado en
  `/proc/385/status`. No es un `chmod` olvidado: es el umask heredado, así que
  cualquier rotación futura vuelve a nacer en `664`.
- `kit/install.sh:231` hace `chmod 700 "$HOME/.headroom"` pero nada toca `logs/`, y
  `kit/doctor.sh:295-298` solo mide `~/.headroom`, nunca el subdirectorio.
- **Arreglo:** `chmod` para lo que ya existe + `UMask=0077` en la unidad para lo
  futuro. Los dos, porque cada uno cubre lo que el otro no.

### P5 — La retención del log destruye la auditabilidad

- El 28,3 % de los bytes del log son `proxy_inbound_request` con **todas** las
  cabeceras de cada petición (`headroom/proxy/server.py:3291`, `logger.info`
  incondicional; las cabeceras van redactadas).
- No hay interruptor: `logging.basicConfig(level=logging.INFO)` está cableado en
  `headroom/proxy/server.py:470`, y `HEADROOM_LOG_LEVEL` solo gobierna a uvicorn
  (`server.py:5567-5584`, default `warning`).
- Rotación cableada en el paquete: `RotatingFileHandler(maxBytes=10*1024*1024,
  backupCount=5)` en `headroom/proxy/helpers.py:1506-1539`.
- **Efecto medido:** ~60 MB de techo total y `proxy.log.1` ya solo llega al
  `2026-09-02 13:34`. En un día cargado el histórico completo dura ~12 h.
- **Arreglo:** extraer las líneas `PERF` a un TSV mensual **antes** de que roten.
  Bajar el nivel de log no es opción: `PERF` también es `INFO`, así que silenciar el
  ruido silenciaría la única medición que tenemos.

## 4. Criterios de aceptación (verificables, no vagos)

| # | Criterio | Comando que lo demuestra | Esperado |
|---|---|---|---|
| A1 | La suite completa sigue verde | `make test; echo rc=$?` | `rc=0` y **0** líneas `NOT ok` |
| A2 | El recuento de suites no se mueve | `ls kit/test/*.sh \| wc -l` | `28` |
| A3 | Estilo limpio | `shellcheck -x` sobre los ficheros tocados | 0 hallazgos |
| A4 | Umask del proceso corregido | `grep ^Umask /proc/$(systemctl --user show -p MainPID --value headroom-proxy.service)/status` | `0077` |
| A5 | Credenciales tapadas | `systemctl --user show -p InaccessiblePaths --value headroom-proxy.service` | contiene `.ssh`, `.aws`, `.gnupg`, `.config/gh` |
| A6 | Sin conversación nueva en el log | `grep -c 'payload_preview_chars":[1-9]'` sobre las líneas posteriores al reinicio | `0` |
| A7 | La medición sobrevive al arreglo | `grep -c PERF` tras el reinicio | crece |
| A8 | Permisos apretados | `stat -c '%a %n' ~/.headroom/logs ~/.headroom/logs/*` | `700` y `600` |
| A9 | Unidad válida | `systemd-analyze --user verify headroom-proxy.service` | `rc=0`, sin salida |
| A10 | Nadie perdió el enrutado | `ss -tnp \| grep -c '127.0.0.1:8787'` | ≥ 3 sockets de `claude` |
| A11 | Serie histórica existente | `stat -c '%a' ~/.headroom/logs/perf-2026-09.tsv` y `wc -l` | `600`, > 1 línea |
| A12 | El archivador es idempotente | correrlo dos veces seguidas | la 2.ª añade **0** líneas |
| A13 | `doctor.sh` sigue aprobando | `bash kit/doctor.sh` | `OK (0 FAIL)` |
| A14 | El sensor nuevo sabe ponerse rojo | bloque de falsabilidad de la suite | detecta el caso fabricado |

## 5. No-objetivos (dichos, no escondidos)

- **No subir la agresividad de la compresión.** El margen es 1,2 % y el riesgo está
  demostrado: durante esta misma auditoría el compresor devolvió mi lectura de
  `compression_store.py` como «169 items compressed to 118» y convirtió una tabla
  de un informe en JSON, tirando la prosa. Hay vía de recuperación
  (`decision=inject_sticky_replay` inyecta el tool `headroom_retrieve` de 464 B y el
  proxy resuelve la llamada en el servidor), pero el resultado inmediato fue leer
  una versión mutilada del código que se estaba auditando.
- **No `--mode token`.** Tendría que comprimir el 85 % del contexto para empatar y
  comprime el 4,2 %.
- **No bajar el nivel de log** (mataría `PERF`) **ni parchear el paquete** de
  Headroom para hacer configurable la rotación.
- **No re-ejecutar `kit/install.sh` en esta máquina.** Es la vía "correcta" para
  regenerar la unidad, pero `cp -p` de la plantilla pública ya borró la statusline
  el 2-sep a las 11:34:24 y el arreglo jq-merge aún no está commiteado. La máquina
  se arregla con un drop-in; el kit se arregla en el repo para las instalaciones
  futuras.
- **No tocar `~/.claude/CLAUDE.md`** ni las reglas de permiso.
- **No investigar el tráfico directo al `:443`** (ver §7).

## 6. Restricciones globales (valores literales)

- `--mode cache` **siempre**; nunca `token`.
- Nunca `--budget` (al agotarse devuelve HTTP 200 con cuerpo vacío) ni
  `--log-messages`.
- Nunca `pkill`, nunca `nohup headroom proxy`, nunca `headroom install`.
  Reiniciar **solo** con `systemctl --user restart headroom-proxy.service`.
- Una sola fuente de `ANTHROPIC_BASE_URL`.
- Rama + PR; nunca directo a `main`. Sin `push` sin visto bueno explícito.
- Ningún guard se esquiva ampliando la allowlist: si un guard bloquea, se
  reformula el comando.
- Comentarios en castellano. `shellcheck -x` es el comando de la CI.
- Todo cambio en `knowledge/` va en commit aparte con prefijo `knowledge:`
  (`CLAUDE.md:58`).
- El recuento de suites se queda en **28**: los sensores nuevos van dentro de
  `kit/test/test_headroom_guardrails.sh`, que ya existe, para no mover una cifra que
  vive en seis documentos (`CLAUDE.md:7`, `:13`, `CONTRIBUTING.md:111`, `:213`,
  `README.md:29`, `kit/README.md:56`) y que `test_doc_claims.sh:97` vigila.
- Aviso heredado: `destructive-guard.sh` bloquea un `git commit` cuyo *mensaje*
  menciona un borrado recursivo de raíz. No usar esa frase en los mensajes.

## 7. Cabo abierto (declarado)

Las tres sesiones mantienen además una conexión directa a `160.79.104.10:443` —la
misma IP que Headroom usa de upstream— y a un balanceador de Google
(`165.66.149.34.bc.googleusercontent.com`). Es coherente con refresco de OAuth, el
poller de uso y statsig, y por el volumen de `PERF` no parece llevarse inferencia,
pero **no está demostrado**. Cerrarlo exige inspeccionar qué se envía ahí; queda
fuera de alcance salvo petición explícita.

## 8. Contención

- Todo el trabajo de repo va en la rama `harden/headroom-higiene-y-drift`, apilada
  sobre `ddff6fd` porque la rama de P0 todavía no está fusionada.
- El cambio de máquina es un **drop-in nuevo**, no una edición de la unidad: la
  unidad viva está comentada a mano y su endurecimiento no debe reescribirse por
  esto. Rollback = borrar un fichero y reiniciar.
- Copia de seguridad de la unidad antes de tocar nada, con fecha en el nombre.
- El reinicio se hace tras comprobar reposo, y se avisa a la sesión par que
  comparte el proxy.
- Sin `push` y sin PR hasta que la persona lo autorice.
