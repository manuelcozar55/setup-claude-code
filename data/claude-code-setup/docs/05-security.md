# 05 · Seguridad: Sentinel, guards y secretos

La filosofía de esta capa en una frase: **barreras deterministas que acotan el radio de impacto (blast radius) de un fallo.** No es el modelo autolimitándose; son reglas fijas que se ejecutan siempre, antes de que la acción llegue a tocar el mundo.

## Sentinel: la puerta

Sentinel (`sentinel/sentinel_preflight.py`) es un hook `PreToolUse` con `matcher` **vacío**, lo que significa que se ejecuta antes de cada llamada a **cualquier** tool, no solo `Bash`. Recibe por `stdin` el JSON de la tool call y decide.

En el código, la decisión resultante es siempre una de tres: **allow** (silencioso, exit 0), **warn** (deja pasar la acción pero añade contexto visible: `additionalContext` con el motivo) o **deny** (bloquea con `permissionDecision: "deny"` y una razón). Uno de los guards de Bash de esta misma capa (`block-dangerous-commands.sh`, más abajo) añade una cuarta posibilidad sobre el mismo protocolo de Claude Code: **ask**, para pedir confirmación humana en vez de bloquear o dejar pasar en silencio.

Los checks que corre Sentinel, por orden de severidad si hay más de uno:

- **Rutas sensibles** (`critical`): `.ssh`, credenciales, claves privadas, y similares, salvo que estén en el allowlist.
- **Red sospechosa** (`critical`/`high`/`medium`): dominios conocidos como maliciosos, IP en crudo dentro de una URL, servicios de exfiltración tipo pastebin, TLD sospechosos.
- **Comandos peligrosos** (`critical`): patrones de comando que coinciden con la librería de IOCs.
- **Variables de entorno sensibles** (`medium`): nombres de variable que huelen a secreto (`*_API_KEY`, etc.) mencionados en un comando.
- **Prompt injection** (`high` en campos de instrucción, `medium`/warn si aparece solo en contenido que se está escribiendo, como un fichero de test que cita la frase a modo de ejemplo).

`critical`/`high` → **deny**. `medium` → **warn**. Ausencia de hallazgos → **allow**.

### Fail-open: el trade-off consciente

Sentinel está envuelto en un `try/except` que, ante cualquier excepción o crash del propio hook, hace `sys.exit(0)`: deja pasar la acción. Esto es una decisión deliberada, no un descuido: prioriza no romper el flujo de una ejecución autónoma por encima del bloqueo estricto. Es una red calibrada a hábitos de trabajo reales, no un cortafuegos infalible. Lo de verdad catastrófico (rutas sensibles, comandos destructivos, exfiltración de la API key, `.ssh`) está cubierto por reglas explícitas que sí bloquean; el fail-open cubre el caso de que el propio hook falle, no el caso de que el hook detecte algo grave.

Cada decisión de deny/warn queda registrada en `$HOME/.claude/audit-logs/sentinel.jsonl`, con marca de tiempo, tool, decisión y motivo. Los falsos positivos se resuelven añadiendo la ruta/dominio/comando a `$HOME/.claude/sentinel-allowlist.json`, no desactivando el hook.

## Los guards de Bash y git

Por debajo de Sentinel, un segundo nivel de hooks `PreToolUse` sobre `Bash` (y, para dos de ellos, específicamente sobre `git`) endurece patrones concretos:

- **`block-dangerous-commands.sh`**: blocklist de comandos que se ejecutan con `Bash`. Bloquea en duro (`deny`) cosas como `rm -rf`, `shred`, `dd` sobre un dispositivo de bloque, `mkfs`/`fdisk`/`wipefs`, `reboot`/`shutdown`/`halt`, `curl`/`wget` seguido de pipe a shell, shells inversas (`/dev/tcp`, `nc -l`), escritura sobre `.ssh`, `git push --force`, exfiltración de variables de entorno o de `.env` a la red, y ejecución de paquetes directamente desde una URL (`npx`, `pnpm dlx`, `deno run`, `bun x`). Para operaciones arriesgadas pero legítimas (`systemctl stop`, `chmod 777`, `ssh-keygen`, `DROP DATABASE`, `docker system prune`, `npm publish`, `pip install` desde URL) responde con **ask**: pide confirmación humana en vez de bloquear.
- **`branch-guard.sh`**: bloquea `git push` a ramas protegidas (por defecto `main`, `master`, `production`; configurable con `CC_PROTECT_BRANCHES`).
- **`destructive-guard.sh`**: bloquea `rm -rf` sobre rutas sensibles (`/`, `/home`, `/etc`, `/root`, `~`, `..`), salvo que el objetivo sea un directorio de build conocido como seguro (`node_modules`, `dist`, `.cache`, etc.) y no toque a la vez una ruta sensible; también bloquea `git reset --hard`, `git clean -fd` y `find -delete` sobre rutas amplias. Incluye una nota específica para WSL2: `rm -rf` puede seguir *junctions* de NTFS y borrar mucho más allá del directorio objetivo.
- **`secret-guard.sh`**: bloquea `git add` de ficheros `.env` (salvo variantes de plantilla como `.env.example`), de ficheros con pinta de credencial (`.pem`, `.key`, `.p12`, `credentials`, `secret`), y bloquea `git add -A`/`git add .` si hay un `.env` sin ignorar en el directorio.
- **`smart_approve.py`**: descompone comandos compuestos (`&&`, `||`, `;`, `|`, `$()`, backticks, saltos de línea) y comprueba cada fragmento por separado contra `permissions.deny` de `settings.json`, para que una regla denegada no se cuele escondida dentro de un comando encadenado.

Todos siguen el mismo patrón de diseño que Sentinel: reglas deterministas, protocolo JSON o `exit 2` para bloquear, y en el caso de `smart_approve.py`, fail-open explícito ante un crash propio.

## Manejo de secretos

Los secretos reales (`ANTHROPIC_API_KEY`, `PERPLEXITY_API_KEY`, `LANGSMITH_API_KEY`) viven únicamente en `$HOME/.claude/.env`, que **nunca** se sube al repo. Lo que sí se versiona es `.env.example`, con los nombres de variable y valores placeholder, nunca un valor real. `secret-guard.sh` es la barrera en el momento de `git add`; si algo se cuela más allá de eso, el siguiente punto lo atrapa.

## El gate: `scan-secrets.sh`

`scan-secrets.sh [DIR]` es el guardarraíl determinista final del propio kit: escanea un directorio en busca de patrones de valor (`sk-...`, `pplx-...`, tokens `gh[oprsu]_...`, `AKIA...`, cabeceras de clave privada PEM), rutas absolutas de la cuenta root filtradas por error, y direcciones de email reales (todo lo que no sea `@example.com`, `noreply@` o la identidad pública del autor). Exit 0 = `PASS`, sin hallazgos. Exit 1 = `FAIL`, con la lista de qué se encontró y en qué fichero. Es el mismo script que usa `doctor.sh` para comprobar que la instalación no arrastra nada sensible, y el que se corre como último paso antes de cualquier commit de este kit.

## La filosofía en resumen

Ninguna de estas capas confía en que el modelo se autorregule. Cada una es una regla fija, barata, que se ejecuta siempre y que decide antes de que la acción tenga efecto. Donde falla (fail-open de Sentinel), falla hacia no romper el flujo, no hacia dejar pasar lo catastrófico: eso sigue cubierto por reglas explícitas. Y donde importa la confianza del propio kit, no hay fail-open posible: `scan-secrets.sh` bloquea el commit si encuentra algo.
