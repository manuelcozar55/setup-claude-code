# Política de seguridad

## Reportar una vulnerabilidad

Si encuentras una vulnerabilidad de seguridad en este repositorio, repórtala
en privado, no abras un issue público:

- **GitHub Security Advisories** (preferido): pestaña "Security" →
  "Report a vulnerability" en
  https://github.com/manuelcozar55/setup-claude-code
- O por correo a **manuelcozar55@gmail.com**

Incluye pasos para reproducir, impacto esperado y, si puedes, una prueba de
concepto mínima. Se responde en un plazo razonable; no hay SLA formal (esto
es un proyecto personal en abierto).

## Qué protege este kit, y qué no

Los guards de `kit/claude/hooks/` y `kit/sentinel/` son **una red contra errores honestos, no una barrera contra un
adversario**. Frenan lo que un agente (o una persona con prisa) hace por equivocación: un `rm -rf` sobre el directorio
equivocado, un `git push` a `main`, un `git add` del fichero de entorno, una clave pegada en un fichero. No contienen a
quien controla el prompt o el entorno y busca esquivarlos a propósito: un comando se puede construir en el shell de mil
formas que un hook, que ve texto antes de la expansión, no puede resolver. Cuando no puede resolver algo que decide el
peligro (una variable en el destino de un borrado, una sustitución donde iría la rama), **pregunta** en vez de adivinar.
Y documentamos sus límites en vez de esconderlos: un proyecto de seguridad que declara dónde se rompe es más creíble.

Lo que cada capa protege y lo que no, de un vistazo:

| Capa | Protege | No protege |
|---|---|---|
| `permissions.deny` (Capa 0) | Borrados de la raíz y de `$HOME`, `git push --force`, la config del kit, antes de que corra ningún hook. | A `Bash` frente a lo que no reconoce como comando de fichero (un script que borra, `rsync --delete`). |
| Guards de Bash (Capa 1, 5 hooks) | Comandos destructivos, pipe-a-shell, push a ramas protegidas, `git add` de credenciales, secretos escritos desde Bash, **decididos sobre el comando parseado** (no sobre el texto crudo). | Lo que solo existe tras la expansión del shell y el código dentro de un intérprete (`python -c`, `perl -e`). |
| `gitleaks` en `pre-commit` (Capa 2) | Credenciales con firma textual que llegan al índice por cualquier vía. | Contenido binario sin firma; repos que no activaron `core.hooksPath`. |
| Sentinel | Rutas sensibles, comandos y redes sospechosas, escrituras sobre la config del kit, en cualquier herramienta. | Un comando que construye el nombre del fichero en el shell; el contenido de `python -c`/`node -e`. |

### Capa 0 — `permissions.deny` de `settings.json` (antes de que corra un hook)

Antes de los guards y de Sentinel hay una capa que no es un hook: las reglas
`permissions.deny` que el kit distribuye en `settings.json`. Las evalúa Claude
Code, así que deniegan la llamada a la herramienta **antes** de que ningún hook
la vea. Cubren tres familias: los borrados de la raíz y de `$HOME` y el `git
push --force` en sus distintas escrituras (reglas `Bash(...)`), los dos métodos
del MCP de LinkedIn que escriben a terceros, y la configuración del propio kit
—`Edit(/hooks/**)`, `Edit(/settings.json)`, `Edit(/settings.local.json)`,
`Edit(/sentinel-allowlist.json)` y `Edit(/sentinel/**)`— para que una sesión no
pueda desarmar sus propias barreras editándolas. Del lado de Sentinel, esas
mismas rutas están en `PROTECTED_CONFIG`: no las deniega él —bloquear la
escritura es trabajo de esta capa— pero garantiza que ningún allowlist las
exima de la detección y que toda decisión sobre ellas llegue al log de
auditoría, `allow` incluido.

Dos cosas de esta capa no son obvias, y las dos están medidas hoy sobre Claude
Code 2.1.259:

- **Las comprobaciones de permisos de fichero solo consultan reglas
  `Edit(ruta)`.** `Edit` ya cubre `Write`, `MultiEdit` y `NotebookEdit`, así que
  una regla `Write(ruta)` se acepta como sintácticamente válida y **se ignora**;
  el propio binario lo avisa por `stderr` en cada arranque. Escribir la regla
  duplicada (`Write(...)` **y** `Edit(...)`) no protege más que la segunda sola;
  escribirla solo como `Write(...)` no protege nada, y parece que sí.
- **Una barra inicial ancla la ruta al fichero de settings, no a la raíz del
  filesystem.** `Edit(/hooks/**)` significa "el `hooks/` que está junto a este
  `settings.json`" —es decir `~/.claude/hooks/**`, que es exactamente lo que se
  quiere aquí—, no `/hooks/**`. Para una ruta absoluta de verdad hacen falta
  **dos**: `Edit(//home/usuario/...)`.

Y lo que esta capa **no** cubre: una regla `Edit(...)` no frena a `Bash`. Un
`sed -i`, un `tee`, un `>` o un `cp` sobre el mismo fichero llegan por otra
herramienta y por otra ruta de decisión, y esa es la mitad que sostienen los
guards de la Capa 1, que normalizan los comandos compuestos antes de
comprobarlos, y `bash-write-guard.sh`, que mira lo que Bash escribe. Las dos mitades hacen falta: con una sola, el
fichero queda protegido por un lado y abierto por el otro. Detalle operativo en
[`kit/docs/05-security.md`](kit/docs/05-security.md).

### Capa 1 — guards de Bash (`block-dangerous-commands.sh`, `branch-guard.sh`, `destructive-guard.sh`, `secret-guard.sh`, `bash-write-guard.sh`)

Estos hooks `PreToolUse` inspeccionan el comando `Bash` antes de ejecutarlo. Los cuatro primeros comparten
`hooks/lib/cmdnorm.sh`, un analizador en awk POSIX (compatible con mawk) que parte el comando en **órdenes simples con su
separador y su origen** (`;`, `&&`, `|`, subshell, `$(…)`, heredoc) y reconoce los prefijos (`sudo`, `env`, `command`,
`timeout N`), la ruta del ejecutable y las opciones globales de git (`-C`, `-c`, `--git-dir`). Sobre eso:

- **La prosa no es una orden.** Un mensaje de commit (`git commit -m "no uses rm -rf"`), un patrón de `grep`, el
  argumento de `echo`/`printf`, un cuerpo de `gh pr create --body` o un heredoc que solo guarda texto
  (`cat > notas.md <<'EOF'`) ya no se leen como el comando que nombran. Si algún segmento lee su programa de la entrada
  (un shell sin `-c`, `ssh`, `xargs`, `. /dev/stdin`) o el heredoc se guarda y se ejecuta en la misma orden
  (`cat > a.sh <<EOF … EOF && bash a.sh`), el texto vuelve a contar como código.
- **El borrado recursivo se decide por operandos**, no por la palabra: `rm -rf node_modules` o `rm -rf build` pasan,
  `rm -rf ~/Documentos` o `rm -rf /` se deniegan, y `rm -rf .`, `*`, `./*` o `.git` también (vacían el repo). La exención es de
  una ruta relativa de build **dentro del proyecto** o de una subruta concreta (`/tmp/prueba-123`), nunca del directorio entero
  (`/tmp`, `/tmp/*`), de la raíz de otro usuario (`~root`, `~+`) ni de un sitio del sistema (`/opt/tmp`, `/mnt/c/…/dist`).
  Un `rm -r` que llega como **argumento** de otra orden (`xargs rm -rf`, `flock l rm -rf …`, `find -exec rm`, `at`,
  `awk 'BEGIN{system(…)}'`) se juzga como si fuera la orden: con un operando sensible a la vista se deniega, y si no se ve
  la ruta se pregunta. `git clean -n` pasa.
- **Monotonía.** Lo que la versión anterior (bc68243) bloqueaba solo pasa si el analizador demuestra que el literal peligroso
  es **dato** en un contexto conocido (argumento de `echo`/`printf`, patrón de `grep`/`rg`, valor de `-m`, cuerpo de `gh`,
  heredoc a un fichero, comentario) o es el borrado de una ruta relativa de build. En cualquier otro caso en que el análisis
  no encuentre la orden, el veredicto es `ask` (o bloqueo), nunca un permiso en silencio. `test_guards_r1.sh` lo comprueba con
  631 órdenes y la columna «base» de lo que daba bc68243: ninguna puede bajar de bloqueo a permiso sin una exención escrita
  y justificada en la propia fila.
- **Lo que no se puede resolver, se pregunta (`ask`)**: una variable o una sustitución en la orden que recibe un pipe
  (`curl … | $X`), en la propia orden (`$X -rf ~`, `$(echo rm) -rf ~`, `{rm,-rf,~}`), en el subcomando de git (`git $X`), en
  un refspec o en el operando de `rm`, `reset` o `clean`
  (`rm -rf $D`, `git push origin $B`, `git reset $H`), `git config alias.*` (los guards no ven lo que hace un alias) y un
  fichero que el propio comando escribe y ejecuta (`echo … > x.sh; bash x.sh`). Preguntar de más es el lado seguro.
- **Lo que es peligroso de verdad, se deniega.** El corpus de 25 comandos peligrosos de la auditoría se bloquea entero y
  `test_guards_veredictos.sh` lo comprueba en cada `make test`, junto a 34 legítimos que pasan, 12 bypasses y los casos
  que parecen prosa y no lo son.

**Lo que sigue sin ver ningún guard** (límites declarados, fijados en `test/fixtures/guards-bypass.jsonl`): el código de
un intérprete (`python3 -c "import shutil; shutil.rmtree('/home/u')"`, `perl -e "unlink glob q(/home/*/*)"`: el hook ve
texto, no lo que ejecutará Python o Perl), `eval "$X"` y `bash -c "$X"` con el valor construido antes, un nombre armado
con comillas (`cur''l`, `b""ash`), `rsync --delete` y cualquier cosa que borre sin nombrar una ruta. También pasan, y ya
pasaban en la versión anterior, estos que la revisión R1 midió (están fijados como `limite` en `test/fixtures/guards-r1.jsonl`):
`git checkout -- .`, `git checkout .` y `git restore .` (descartan cambios sin pasar por el reflog), `git branch -D` de una
rama que no es `main`/`master`, `git stash clear`, `git filter-branch`, `git reflog expire`, `git gc --prune=now`,
`git reset --merge|--keep`, `git checkout -f`, `git switch -f`, `mv ~ …`, `truncate` de un dotfile, `kill -9 -1`, `pkill -9 -u`,
`printenv`, `cat /proc/self/environ`, `cat` de ficheros de credenciales que no están en la lista cerrada
(`~/.git-credentials`, la config de gcloud), un nombre armado con `printf` o con `${X:-…}` (`cat $(printf .en%s v)`), el
nombre por glob (`cat .en*`), `rm${IFS}-rf${IFS}~/x`, la expansión de llaves `{rm,-rf,~/x}` y `$'\x72m' -rf ~`
(esta última sí pregunta: lleva un `$` en la orden). La barrera real es la capa de permisos de Claude Code y, para lo
catastrófico, que el agente no corra con permisos que no necesita.

`git push --force-with-lease` y `--force-if-includes` a una rama de trabajo **pasan** (solo pisan la rama si nadie la ha tocado);
a `main`/`master`, con `--force` junto a ellos o con un `+refspec`, se deniegan igual. El texto de `gh pr create|issue comment
--body|--title` es prosa. `python3 -c "print('rm -rf ~')"` sigue bloqueado: el código de un intérprete es un límite declarado.

`secret-guard.sh` y `bash-write-guard.sh` miran cosas distintas: el primero el nombre de lo que se añade al índice
(`git add .env`, `*.pem`), el segundo el contenido que un comando escribe. El chequeo de `git add -A` trabaja sobre el
árbol de trabajo declarado, no sobre el índice final; por eso existe la Capa 2.

### Capa 2 — `gitleaks` en `pre-commit` (contenido real)

Por eso existe una segunda capa (`kit/claude/hooks/git/pre-commit` +
`kit/claude/.gitleaks.toml`): en vez de adivinar el comando, escanea el
**contenido real que queda staged** justo antes del commit. Esto cierra el
hueco de la Capa 1 para credenciales con firma textual reconocible (claves de
API con prefijo conocido, alta entropía, patrones tipo `PASSWORD=` en
ficheros de config) sin importar cómo llegaron al índice.

**Lo que la Capa 2 no cubre:** contenido binario sin firma textual —
keystores binarios (`.jks`, `.p12`/`.pfx` con contenido opaco), blobs
cifrados, o cualquier secreto que no deje un patrón reconocible en texto
plano. `gitleaks` escanea contenido legible; un keystore binario sin cadenas
de texto detectables puede pasar. La Capa 1 sí bloquea estos por
**extensión/nombre de fichero** (`.pem`, `.key`, `.pfx`, `.jks`,
`credentials.json`, etc.), así que la protección real contra keystores viene
de ahí, con los límites de "por nombre" ya descritos arriba — no de la Capa
2.

### Sentinel (`sentinel/sentinel_preflight.py`)

Corre antes de **cualquier** herramienta, no solo `Bash`. Un error interno **falla cerrado** (`exit 2`); si falta su
`iocs.json` (`kit/sentinel/iocs.json`, que el kit **sí** distribuye, así que en una instalación normal está), `decide()` resuelve «allow»; si falta
`python3`, `optional-hook.sh` no bloquea pero **avisa una vez por sesión** de que Sentinel no está activo; y un hook que
agota su `timeout` deja ejecutar la herramienta (Sentinel no lleva `onFailure`), por eso se da un presupuesto de 1,5 s y
pregunta (`ask`) si no le cabe. La tabla completa, más abajo.

**Qué mira en un comando de `Bash`**: las rutas sensibles y los patrones de comando peligroso se juzgan sobre el comando
**sin su prosa** (mensaje de commit, patrón de `grep`, palabras de `echo`/`printf` sin pipe, cuerpos de heredoc que solo
van a un fichero), así que `git commit -m "ya no lee ~/.ssh/id_rsa"`, `echo ".env" >> .gitignore` o
`git rm --cached .env` pasan. Lo que **no** es prosa sigue bloqueado: la misma ruta como argumento de `grep`, `echo` con
la ruta por un pipe (`echo ~/.ssh/id_rsa | xargs cat`), cualquier sustitución (`git commit -m "$(cat ~/.ssh/id_rsa)"`) y
un heredoc que va a un shell. Límite nuevo y aceptado: un nombre guardado como texto en un fichero y leído después por
otro comando no se sigue.

**La allowlist no levanta un bloqueo sobre un comando.** Una entrada de `paths` exime un campo que es una ruta (`Read`,
`Edit`…), nunca un comando de `Bash`; antes el mensaje de bloqueo ofrecía la allowlist para un comando, y era mentira.
Ahora cada bloqueo de Sentinel acaba con `Que hacer:` y la salida que de verdad funciona.

**El allowlist solo se lee de tu `$HOME`.** `load_user_allowlist()` abre
`$HOME/.claude/sentinel-allowlist.json` y nada más: el
`./.security/sentinel-allowlist.json` del directorio de trabajo ya no se
consulta. Antes se probaba primero, y un repo clonado podía traerlo y anular tu
allowlist por el solo hecho de que abrieras la sesión dentro de él (con
`{"paths":["/srv/app/.env"]}` convertía en `allow` el deny de ese fichero) o
tumbar todas las herramientas con un JSON malformado (con `[]` o
`{"paths":null}` el hook reventaba y salía con 2 en toda herramienta, `Read`
incluido). Hoy un fichero que no sea un objeto JSON válido se ignora y cada
lista ausente o `null` cuenta como vacía. Lo que ningún allowlist puede levantar
es el suelo en código (`ALWAYS_DENY_PATHS`: el fichero de credenciales de Claude
Code, la clave privada de SSH y las credenciales de AWS), que se consulta antes.

## Cómo falla cada pieza

Un guard puede no poder decidir. Qué hace entonces está decidido, probado y es lo que sigue (la misma tabla está en
[`kit/docs/05-security.md`](kit/docs/05-security.md)):

| Fallo | Los 5 guards de Bash | Sentinel (`sentinel_preflight.py`) | `write-guard.py` |
|---|---|---|---|
| Falta `jq` | **Bloquean** (`exit 2` o `deny`): sin `jq` no pueden leer el comando. | No usa `jq`: funciona. | No usa `jq`: funciona. |
| Falta `python3` | No lo usan: funcionan. | **No bloquea y lo dice**: `optional-hook.sh` avisa una vez por sesión (`additionalContext`) de que Sentinel no está activo. | Igual: no bloquea y avisa una vez por sesión. |
| Falta su script o su librería | **Bloquean** (`exit 2`) si falta `lib/cmdnorm.sh`; `bash-write-guard.sh` deniega si falta `lib/secret-patterns`. | `exit 2` (con `python3` presente). | `exit 2`, como Sentinel. |
| JSON roto o ilegible | **Bloquean**. `bash-write-guard.sh` solo si el texto trae `>`, `<<`, `tee` o `sed` (su prefiltro lee texto, no JSON). | `exit 2`. | `exit 2`. |
| Entrada vacía | Permiten: no hay nada que juzgar. | Permite. | `exit 2`. |
| Caída interna (excepción) | Un fallo inesperado de shell sale con un código que no es 0 ni 2: lo bloquea `"onFailure": "block"` (Claude Code ≥ 2.1.295; `doctor.sh` avisa si es anterior). | `exit 2` (`try/except` de `__main__`). | `exit 2`. |
| Timeout del hook | `"onFailure": "block"` bloquea. Antes de llegar ahí, el tope de 128 KB y el de 16 cadenas anidadas preguntan o bloquean. | **Fail-open**: Sentinel no lleva `onFailure`. Lo acota con su presupuesto de 1,5 s (`ask`) y el tope de 128 KB (`ask`). | Sin `onFailure`: un timeout deja escribir. |

Cada fila está fijada por `kit/test/test_guards_degradacion.sh`: si esta tabla y esa suite discrepan, manda la suite y la tabla está mal.

Un bloqueo no es una pared: **cada mensaje de bloqueo de cada guard acaba con `Que hacer:`** y la salida que funciona
(reformular, usar una ruta concreta, `git stash`, o ejecutarlo la persona con `!`). `test/test_guards_mensajes.sh` lo
exige para los cinco guards, Sentinel y `write-guard.py`.

## Guard, interruptor y consecuencia

Qué variable cambia qué guard, y qué se pierde al usarla (las variables son las que lee el código, no las que sugiere
este texto):

| Guard | Interruptor (variable real) | Efecto de usarlo | Quién y dónde |
|---|---|---|---|
| `destructive-guard.sh` | `CC_ALLOW_DESTRUCTIVE=1` | Apaga el guard entero: pasan `rm` sobre rutas sensibles, `git reset --hard`, `git clean -fd` y `find … -delete`. Se atiende antes del fail-closed, así que no hace falta `jq`. `block-dangerous-commands.sh` y Sentinel siguen activos y **pueden seguir bloqueando** lo mismo. | La persona, en el entorno de la sesión (`env` de `settings.json` o `export`), nunca el agente. |
| `destructive-guard.sh` y `block-dangerous-commands.sh` | `CC_SAFE_DELETE_DIRS=node_modules:dist:…` | Lista (separada por `:`) de directorios de build que `rm -rf` puede borrar aunque cuelguen de una ruta sensible. Por defecto `node_modules:dist:build:.cache:__pycache__:coverage:.next:.nuxt:tmp`. Ampliarla amplía lo que se borra sin preguntar. | La persona, en el entorno. La lee `lib/cmdnorm.sh`. |
| `destructive-guard.sh` | `CC_BLOCK_LOG=ruta` | Dónde se registran sus bloqueos (por defecto `~/.claude/audit-logs/blocked-commands.log`). No cambia ninguna decisión. | Quien depura; los tests lo apuntan a un temporal. |
| `branch-guard.sh` | `CC_PROTECT_BRANCHES=main:master:production` | Ramas cuyo `git push` se bloquea (separadas por `:`). Vaciarla o quitar `main` deja empujar ahí. | La persona, en el entorno. |
| `block-dangerous-commands.sh` | ninguno | Sus reglas están en el script. Se cambia el script (`DENY_RULES`, `ASK_RULES`) o se quita el hook de `settings.json`. | La persona. |
| `secret-guard.sh` | ninguno (`SECRET_GUARD_BIN` solo lo usan los tests) | Se cambia el script o se quita el hook. | La persona. |
| `bash-write-guard.sh` y `write-guard.py` | ninguno | Los patrones están en `hooks/lib/secret-patterns` (una fila por patrón; solo cuentan las filas `block`). Quitar una fila deja de detectarla. | La persona. |
| Sentinel | `~/.claude/sentinel-allowlist.json` (`paths`, `commands`, `domains`, `env_vars`) | `paths` exime un campo que es **una ruta** (`Read`, `Edit`, `Write`…) y **nunca** un comando de `Bash`; `commands` exime un comando entero de los patrones de comando peligroso, por igualdad exacta. Lo que hay en `ALWAYS_DENY_PATHS` y `PROTECTED_CONFIG` no lo levanta ninguna entrada. | La persona; el kit protege el fichero de ediciones de la sesión. |
| `optional-hook.sh` | `PYTHON_HOOK_BIN=ruta` (intérprete) y `CC_WARN_DIR=dir` (dónde guarda el aviso de «una vez por sesión») | Fija el `python3` que usan Sentinel y `write-guard.py`; con una ruta que no existe se comporta como sin `python3`. | Tests y quien depura. |
| `nucleo-gate.sh` | `CC_NUCLEO_GATE=1` | Activa su aviso (opt-in); no es un guard de seguridad. | La persona. |

Un interruptor es una decisión de la persona sobre su máquina: un agente que lo propone para «salir del paso» está pidiendo desarmar la barrera, y la respuesta es reformular el comando (cada bloqueo acaba con `Que hacer:` por eso).

## Cuánto cuesta

Una llamada a `Bash` pasa por los cinco guards y Sentinel **en paralelo** (los hooks de un mismo evento corren a la vez):
el coste medido es de **62 a 67 ms** de reloj, el del más lento, no la suma (≈ 270 ms si se encadenaran). Es una
medida de esta máquina: la tuya variará, pero el orden de magnitud sirve para decidir si merece la pena añadir un hook más.

## Lo que este documento no promete

Que ningún comando peligroso pase. Un adversario con control del prompt puede construir el nombre de un fichero o el
código de un intérprete de forma que ningún guard lo vea (límites arriba); un hook que se pasa de su `timeout` (Sentinel,
`write-guard.py`) deja ejecutar; un guard apagado con `CC_ALLOW_DESTRUCTIVE=1` está apagado. La política es que la
configuración del kit la cambia la persona, que los guards frenan lo evidente y los errores honestos, y que cuando dudan
preguntan.

## En resumen

Ninguna de estas capas sustituye a revisar lo que el agente va a hacer antes
de que lo haga, ni a no versionar secretos reales para empezar. Son barreras
deterministas que reducen la probabilidad y el radio de un accidente, no un
sandbox de seguridad ni un perímetro frente a un atacante decidido.
