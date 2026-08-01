# 05 · Seguridad: Sentinel, guards y secretos

La filosofía de esta capa en una frase: **barreras deterministas que acotan el radio de impacto (blast radius) de un fallo.** No es el modelo autolimitándose; son reglas fijas que se ejecutan siempre, antes de que la acción llegue a tocar el mundo.

## Sentinel: la capa de IOCs (opcional)

Sentinel (`sentinel/sentinel_preflight.py`) es un hook `PreToolUse` con `matcher` **vacío**, lo que significa que se ejecuta antes de cada llamada a **cualquier** tool, no solo `Bash`. Recibe por `stdin` el JSON de la tool call y decide.

### ⚠ Importante: Sentinel necesita `iocs.json`, y el kit no lo trae

Todos los checks de Sentinel (rutas sensibles, red sospechosa, comandos peligrosos, variables de entorno, prompt injection) leen sus patrones de un fichero `iocs.json` que `load_iocs()` busca en `sentinel/iocs.json`, `$HOME/.claude/hooks/iocs.json` o la ruta de la skill `mcp-sentinel`. **El kit no incluye ninguno de esos ficheros** (para no filtrar indicadores propios/personales en el repo), así que en una instalación recién hecha `load_iocs()` devuelve `{}` y **todos los checks de Sentinel son un no-op silencioso**: `decide()` siempre resuelve "allow".

Por defecto, nada más instalar el kit, la protección activa y funcional sin ningún fichero adicional son los **4 guards de Bash** de la siguiente sección (`block-dangerous-commands.sh`, `branch-guard.sh`, `destructive-guard.sh`, `secret-guard.sh`): esos sí llevan sus patrones embebidos en el propio script y funcionan solos.

Para activar la capa de IOCs de Sentinel:

```bash
cp $HOME/.claude/sentinel/iocs.example.json $HOME/.claude/hooks/iocs.json
```

y luego personaliza `iocs.json` con tus propios dominios/IPs/patrones (el fichero de ejemplo trae solo entradas genéricas tipo `evil.example.com`). Ver `docs/07-verify.md` para comprobar si esta capa está activa.

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

Junto a Sentinel, un segundo nivel de hooks `PreToolUse` sobre `Bash` (y, para dos de ellos, específicamente sobre `git`) endurece patrones concretos; a diferencia de Sentinel, estos guards llevan sus patrones embebidos y están activos desde el primer momento, sin fichero adicional:

- **`block-dangerous-commands.sh`**: blocklist de comandos que se ejecutan con `Bash`. Bloquea en duro (`deny`) cosas como `rm -rf`, `shred`, `dd` sobre un dispositivo de bloque, `mkfs`/`fdisk`/`wipefs`, `reboot`/`shutdown`/`halt`, `curl`/`wget` seguido de pipe a shell, shells inversas (`/dev/tcp`, `nc -l`), escritura sobre `.ssh`, `git push --force`, exfiltración de variables de entorno o de `.env` a la red, y ejecución de paquetes directamente desde una URL (`npx`, `pnpm dlx`, `deno run`, `bun x`). Para operaciones arriesgadas pero legítimas (`systemctl stop`, `chmod 777`, `ssh-keygen`, `DROP DATABASE`, `docker system prune`, `npm publish`, `pip install` desde URL) responde con **ask**: pide confirmación humana en vez de bloquear.
- **`branch-guard.sh`**: bloquea `git push` a ramas protegidas (por defecto `main`, `master`, `production`; configurable con `CC_PROTECT_BRANCHES`).
- **`destructive-guard.sh`**: bloquea `rm -rf` sobre rutas sensibles (`/`, `/home`, `/etc`, `/root`, `~`, `..`), salvo que el objetivo sea un directorio de build conocido como seguro (`node_modules`, `dist`, `.cache`, etc.) y no toque a la vez una ruta sensible; también bloquea `git reset --hard`, `git clean -fd` y `find -delete` sobre rutas amplias. Incluye una nota específica para WSL2: `rm -rf` puede seguir *junctions* de NTFS y borrar mucho más allá del directorio objetivo.
- **`secret-guard.sh`** (Capa 1 de secretos, por NOMBRE): bloquea `git add` de ficheros `.env` (salvo variantes de plantilla como `.env.example`), de ficheros con pinta de credencial por su nombre/extensión (`.pem`, `.key`, `.p12`, `.pfx`, `.jks`, `.keystore`, `credentials.json`), y bloquea `git add -A`/`git add .` si hay un `.env` sin ignorar en el directorio. Ver la sección "Dos capas de secretos" más abajo para la Capa 2, que escanea contenido en vez de nombre.
- **`smart_approve.py`**: descompone comandos compuestos (`&&`, `||`, `;`, `|`, `$()`, backticks, saltos de línea) y comprueba cada fragmento por separado contra `permissions.deny` de `settings.json`, para que una regla denegada no se cuele escondida dentro de un comando encadenado.

Todos siguen el mismo patrón de diseño que Sentinel: reglas deterministas, protocolo JSON o `exit 2` para bloquear, y en el caso de `smart_approve.py`, fail-open explícito ante un crash propio.

**Límite conocido de `secret-guard.sh`**: el chequeo de `git add -A`/`git add .` funciona sobre el texto del comando, no sobre el índice real de git. Adivinar con certeza el efecto de una cadena de shell arbitraria (alias, subshells, pathspecs) exigiría, en el límite, un tokenizador de shell y un resolvedor de pathspecs completos, ejecutándose bajo el presupuesto de tiempo de un hook; y aun con eso, solo vería el árbol de trabajo, no lo que realmente queda staged para el commit. Un hook `PreToolUse` no es eso, y este no pretende serlo. Por eso esta capa se complementa con una segunda, más abajo.

**Coste de la cadena, no solo su cobertura**: con la config que instala este kit, una llamada a `Bash` pasa por 7 hooks `PreToolUse` en serie (`rtk hook claude`, Sentinel, y los 4 guards, más `smart_approve.py`). No es gratis: en pruebas sobre esta misma cadena se midió un overhead perceptible por llamada (varios cientos de ms; cada invocación de `jq` dentro de un hook añade lo suyo), que variará con tu máquina pero da el orden de magnitud. Merece la pena pagarlo por las barreras que compra, pero tenlo en cuenta antes de añadir un hook más encima.

## Dos capas de secretos: por qué hacen falta las dos

`secret-guard.sh` (Capa 1) es rápido y no necesita nada instalado, pero decide mirando el **nombre** del fichero y el **texto** del comando `Bash` antes de que se ejecute. Eso dejaba, a propósito, un hueco: un fichero con nombre inocente (`config.yaml`) pero con una credencial real dentro pasa sin bloquear, porque la Capa 1 nunca abre el fichero. Cerrar ese hueco desde un hook `PreToolUse` sobre el comando exigiría reconstruir, en bash y con presupuesto de tiempo, lo que un tokenizador de shell + un resolvedor de pathspecs + un escáner de secretos hacen en conjunto — y aun logrado, seguiría mirando el árbol de trabajo, no el índice que de verdad se va a commitear. Es la misma lección que ya aparece arriba sobre el límite de `secret-guard.sh`, generalizada: **algunas garantías no se pueden dar adivinando el efecto de un comando; hace falta mirar el estado real después de que el comando se ejecutó.**

Por eso el kit añade una **Capa 2**, un hook `pre-commit` de git (`claude/hooks/git/pre-commit`) que corre [`gitleaks`](https://github.com/gitleaks/gitleaks) `--staged` sobre el índice real, justo antes de que el commit se cree:

- `--staged`: escanea exactamente lo que va a quedar commiteado, no el árbol de trabajo — cierra el hueco de contenido con nombre inocente, de ficheros ignorados añadidos con `-f`, y de cualquier ruta por la que el contenido haya llegado al índice.
- `--ignore-gitleaks-allow`: gitleaks por defecto respeta un comentario `# gitleaks:allow` en la misma línea para silenciar un hallazgo; se ignora deliberadamente esa convención, porque es una forma trivial de colar una credencial real con un comentario al lado.
- `env -u GITLEAKS_CONFIG`: sin este `unset`, una variable de entorno del propio shell podría apuntar gitleaks a una config distinta (más permisiva) a la que trae el kit; se fuerza siempre `-c claude/.gitleaks.toml`.
- **Falla cerrado**: si el binario `gitleaks` no está instalado, o la config no carga, o gitleaks devuelve un error inesperado, el hook bloquea el commit en vez de dejarlo pasar — lo opuesto al fail-open de Sentinel de la sección anterior, y a propósito: aquí lo que falla es la última barrera antes de un commit real, no una heurística sobre una llamada a herramienta.

`claude/.gitleaks.toml` extiende las reglas por defecto de gitleaks (`useDefault = true`, no las sustituye) y añade una regla propia acotada por ruta (`.yaml`/`.toml`/`.ini`/`.properties`/`.conf`/`.cfg`/`.json`) para contraseñas de tipo diccionario en ficheros de config — el tipo de credencial que las reglas por defecto (pensadas para tokens de alta entropía tipo `sk-`/`AKIA`) no cubren. El acotado por ruta es intencional: la misma regla sin acotar producía falsos positivos sobre prosa y código que solo menciona `PASSWORD=`/`TOKEN=` como ejemplo; acotada a ficheros de config, no.

**Activación**: a diferencia de la Capa 1 (activa desde el primer `install.sh`), la Capa 2 requiere que el repo donde vayas a commitear apunte su `core.hooksPath` al hook instalado. Dos formas equivalentes de hacerlo, ambas explícitas y por repositorio:

```bash
# opción A: subcommand del propio instalador, corrido DENTRO del repo a proteger
cd tu-repo
bash /ruta/al/kit/install.sh --enable-secrets-layer2

# opción B: el one-liner manual, mismo efecto
git config core.hooksPath "$HOME/.claude/hooks/git"
```

`install.sh` (sin flags) no automatiza este paso ni siquiera cuando corre dentro de un repo git, porque `core.hooksPath` es una config **por repositorio de trabajo**, no de `$HOME/.claude`: instalar el kit no implica saber a qué repos quieres aplicarle esta barrera, y activarla en silencio en un repo que el usuario no nombró explícitamente es exactamente el tipo de sorpresa que hace que se desinstale una herramienta. `--enable-secrets-layer2` existe para que la activación siga siendo un acto deliberado (tú decides el repo, corriéndolo desde dentro) sin tener que memorizar el one-liner de git; ambas rutas quedan documentadas porque ninguna sustituye a la otra — la segunda es la vía de escape si por lo que sea no tienes el kit a mano en ese momento.

Las dos suites de test que cubren esta parte: `test/test_guards.sh` (Capa 1 + Sentinel + `smart_approve.py`, con una demostración de falsabilidad en `test/test_guards_falsifiability.sh`: neutraliza `secret-guard.sh` y comprueba que casos `BLOCK` conocidos caen) y `test/test_secret_content_gitleaks.sh` (Capa 2: credencial con nombre inocente, fichero ignorado añadido con `-f`, señuelos `EXAMPLE` junto a una credencial real, la regla propia de contraseñas de diccionario y su allowlist). Detalle de cómo correrlas en `docs/07-verify.md`.

## Manejo de secretos

Los secretos reales (`ANTHROPIC_API_KEY`, `PERPLEXITY_API_KEY`, `LANGSMITH_API_KEY`) viven únicamente en `$HOME/.claude/.env`, que **nunca** se sube al repo. Lo que sí se versiona es `.env.example`, con los nombres de variable y valores placeholder, nunca un valor real. `secret-guard.sh` es la barrera en el momento de `git add`; el `pre-commit` con gitleaks (Capa 2, si está activado) es la barrera en el momento de `git commit`; si algo se cuela más allá de ambas, el siguiente punto lo atrapa.

## El gate: `scan-secrets.sh`

`scan-secrets.sh [DIR]` es el guardarraíl determinista final del propio kit: escanea un directorio en busca de patrones de valor (`sk-...`, `pplx-...`, tokens `gh[oprsu]_...`, `AKIA...`, cabeceras de clave privada PEM), rutas absolutas de la cuenta root filtradas por error, y direcciones de email reales (todo lo que no sea `@example.com`, `noreply@` o la identidad pública del autor). Exit 0 = `PASS`, sin hallazgos. Exit 1 = `FAIL`, con la lista de qué se encontró y en qué fichero. Es el mismo script que usa `doctor.sh` para comprobar que la instalación no arrastra nada sensible, y el que se corre como último paso antes de cualquier commit de este kit.

## La filosofía en resumen

Ninguna de estas capas confía en que el modelo se autorregule. Cada una es una regla fija, barata, que se ejecuta siempre y que decide antes de que la acción tenga efecto. Donde falla (fail-open de Sentinel), falla hacia no romper el flujo, no hacia dejar pasar lo catastrófico: eso sigue cubierto por reglas explícitas. Y donde importa la confianza real de que nada sensible quedó commiteado, no hay fail-open posible: `scan-secrets.sh` bloquea si encuentra algo en el propio kit, y el `pre-commit` de la Capa 2 bloquea el commit si `gitleaks` encuentra algo — o si `gitleaks` mismo no está disponible o falla.
