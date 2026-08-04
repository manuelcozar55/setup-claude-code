# 09 · Clave SSH y GitLab privado (desde WSL2)

Guía completa para dejar tu WSL2 hablando con un **GitLab autoalojado** por SSH: clonar repos internos, hacer `push` sin escribir la contraseña cada vez, y usar un **marketplace de plugins privado** desde Claude Code.

Todo lo que hay aquí está probado en OpenSSH 10.2 sobre WSL2 (Ubuntu). Los mensajes de error que se citan son **literales**, capturados ejecutando los comandos; los que no se pudieron reproducir no aparecen.

## Antes de empezar

| Necesitas | Cómo lo compruebas |
|---|---|
| WSL2 (o Linux). No PowerShell ni `cmd` | `uname -a` responde `...microsoft-standard-WSL2` |
| Cliente OpenSSH | `ssh -V` → `OpenSSH_9.x` o superior |
| Red hasta el GitLab: normalmente **VPN corporativa levantada** | `getent hosts "$GITLAB_HOST"` devuelve una IP |
| Tu usuario en ese GitLab, con permiso para añadir claves | puedes entrar por web |

Guarda el nombre del host en una variable y reutilízala en toda la guía. Sustituye el valor por el de **tu** GitLab (pregunta a tu equipo de sistemas si no lo sabes; suele ser algo como `gitlab.tu-empresa.es` o `git.tu-empresa.es`):

```bash
GITLAB_HOST="gitlab.tu-empresa.es"
```

Si `getent hosts "$GITLAB_HOST"` no devuelve nada, **para aquí**: o la VPN está caída, o el nombre no es ese. Seguir adelante solo produce errores que parecen de clave y no lo son.

## ⚠️ Los guards de este kit bloquean estos comandos, y está bien que lo hagan

Si ya instalaste el kit, **Sentinel trata `~/.ssh/` como ruta sensible y bloqueará cualquier comando que la mencione**, incluido un `cat` inocente de la clave *pública*:

```
SENTINEL BLOCKED [Bash]: [CRITICAL] sensitive path: ~/.ssh/
```

No es un fallo: es exactamente la barrera que se instaló para que un agente no lea tus claves privadas. El guard no distingue `.pub` (pública, se puede publicar) de la privada, y esa imprecisión es deliberada — mejor un falso positivo que un falso negativo con claves.

**Qué hacer:** este alta es una tarea humana y de una sola vez. **Hazla en una terminal normal de WSL, no a través de Claude Code.** No añadas `~/.ssh/` al `sentinel-allowlist.json` para salir del paso: estarías abriendo el acceso a tus claves privadas de forma permanente para ahorrarte abrir una pestaña.

## Paso 1 · Generar la clave

```bash
ssh-keygen -t ed25519 -C "tu.usuario@example.com (WSL portatil)" \
  -f ~/.ssh/id_ed25519_miempresa -N ""
```

Salida real:

```
Generating public/private ed25519 key pair.
Your identification has been saved in /home/tu-usuario/.ssh/id_ed25519_miempresa
Your public key has been saved in /home/tu-usuario/.ssh/id_ed25519_miempresa.pub
The key fingerprint is:
SHA256:n2H6h4WvmJgLQTCgZKGfZmlZB+2doPiE9kW4821Q0DU tu.usuario@example.com (WSL portatil)
```

Cada flag, y por qué:

- **`-t ed25519`** — el tipo de clave. Ed25519 sobre RSA: claves cortas (68 caracteres de pública frente a cientos), verificación rápida, y sin el pie de tiro de RSA, donde una clave de 1024 o 2048 bits ya no es defendible y hay que acordarse de pedir 4096. No uses DSA (retirado) ni ECDSA (sin ventaja aquí).
- **`-C "..."`** — un comentario, **no** un identificador que el servidor use para nada. GitLab lo muestra en la lista de claves, así que su único trabajo es que dentro de seis meses sepas **de qué máquina es esta clave** al verla en la web. Poner solo el email no sirve: si tienes tres máquinas, verás tres entradas idénticas y no sabrás cuál revocar. Pon email **y** máquina.
- **`-f ~/.ssh/id_ed25519_miempresa`** — nombre de fichero dedicado, en vez del `id_ed25519` por defecto. Una clave por destino y por máquina: si mañana revocas esta, no rompes GitHub ni tus servidores. **Tiene una consecuencia que muerde y que casi nadie te cuenta: al no llamarse como los nombres por defecto, `ssh` no la va a usar** hasta que se lo digas explícitamente (paso 5).
- **`-N ""`** — sin passphrase. Es la parte con contrapartida real, así que decídelo tú:

| | Sin passphrase (`-N ""`) | Con passphrase |
|---|---|---|
| Comodidad | funciona siempre, sin agente | hay que desbloquearla, con `ssh-agent` una vez por sesión |
| Riesgo | **cualquiera que lea el fichero tiene tu identidad** | el fichero solo no vale de nada |
| Cuándo tiene sentido | máquina de un solo usuario, disco cifrado, automatismos | portátiles, equipos compartidos, claves con más permisos |

Sin passphrase, la seguridad de tu identidad en GitLab **es exactamente la seguridad del fichero**. Si el disco no está cifrado o el equipo es compartido, pon passphrase: quita el `-N ""` y `ssh-keygen` te la pedirá.

## Paso 2 · Comprobar los permisos

```bash
ls -l ~/.ssh/id_ed25519_miempresa*
```

Esperado: `600` (`-rw-------`) en la privada y `644` en la `.pub`. `ssh-keygen` ya los crea así; el problema aparece cuando se copian claves entre máquinas o desde un disco NTFS, que no tiene permisos POSIX.

Si hay que arreglarlo:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519_miempresa
chmod 644 ~/.ssh/id_ed25519_miempresa.pub
```

**No cuentes con que `ssh` te avise.** Se probó con la privada en `640`, `644`, `660`, `666` y `777`: **OpenSSH 10.2 no emitió ningún aviso de permisos** en ninguno de los casos. Versiones más antiguas sí se niegan a usar la clave con un `UNPROTECTED PRIVATE KEY FILE`, pero no puedes fiarte de eso como red de seguridad. Compruébalo tú.

## Paso 3 · Copiar la clave pública

```bash
cat ~/.ssh/id_ed25519_miempresa.pub
```

Sale **una sola línea**, de unos 110-120 bytes, con esta forma:

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... tu.usuario@example.com (WSL portatil)
```

Cópiala **entera y en una línea**, sin saltos ni espacios de más. Si tu terminal la parte visualmente no pasa nada; lo que importa es lo que va al portapapeles.

- **`.pub` es la pública**: se puede pegar en GitLab, en un chat o en un README. No es un secreto.
- **El fichero sin `.pub` es la privada**: no sale de la máquina. Nunca. Ni por email, ni a un repo, ni "un momento para probar".

Para verla sin volcarla, y de paso confirmar que es una ed25519 sana:

```bash
ssh-keygen -l -f ~/.ssh/id_ed25519_miempresa.pub
# 256 SHA256:n2H6h4Wv... tu.usuario@example.com (WSL portatil) (ED25519)
```

Guarda ese `SHA256:...`: es la huella que verás en GitLab, y sirve para comprobar que subiste la clave que creías.

## Paso 4 · Darla de alta en GitLab

En la web de tu GitLab:

1. Arriba a la derecha, tu avatar → **Edit profile**.
2. En el menú lateral, **SSH Keys** → botón **Add new key**.
   (La URL directa depende de la versión de GitLab: en las recientes es
   `/-/user_settings/ssh_keys` y en las anteriores `/-/profile/keys`. Navegar
   por el menú funciona en todas, así que es lo que se recomienda aquí.)
3. **Key** — pega la línea completa del paso 3. GitLab rellena el **Title** solo, a partir del comentario: por eso el `-C` importa.
4. **Usage type** — deja **Authentication & Signing** (o **Authentication** si solo la quieres para clonar y empujar).
5. **Expiration date** — GitLab lo rellena por defecto, normalmente a un año. **Déjalo puesto.** Una clave que caduca es una clave que alguien revisa; y anótate la fecha, porque el día que expire los `push` empezarán a fallar con el mismo `Permission denied` de siempre y no es evidente.
6. **Add key**.

Comprueba en la lista que la huella coincide con la del `ssh-keygen -l` del paso 3.

## Paso 5 · Decirle a `ssh` que use esa clave (el paso que todos se salta)

Aquí es donde falla la mayoría, así que va con la prueba delante. Sin configurar nada, `ssh` **solo** prueba los nombres por defecto. Esto es la salida real de `ssh -v` contra el GitLab, sin config:

```
debug1: Trying private key: /home/tu-usuario/.ssh/id_rsa
debug1: Trying private key: /home/tu-usuario/.ssh/id_ecdsa
debug1: Trying private key: /home/tu-usuario/.ssh/id_ecdsa_sk
debug1: Trying private key: /home/tu-usuario/.ssh/id_ed25519
debug1: Trying private key: /home/tu-usuario/.ssh/id_ed25519_sk
```

Tu `id_ed25519_miempresa` **no aparece**. Por eso `ssh -T` da `Permission denied (publickey)` aunque la clave esté perfectamente dada de alta en GitLab.

La solución durable es un bloque en `~/.ssh/config`:

```bash
cat >> ~/.ssh/config <<EOF

Host $GITLAB_HOST
    User git
    IdentityFile ~/.ssh/id_ed25519_miempresa
    IdentitiesOnly yes
    AddKeysToAgent yes
EOF
chmod 600 ~/.ssh/config
```

Qué hace cada línea:

- **`IdentityFile`** — la clave a usar con este host. Esto es lo que arregla el problema de arriba.
- **`IdentitiesOnly yes`** — usa **solo** esa clave y ninguna más. No es cosmético: sin él, `ssh` ofrece todas las claves que encuentre, una a una, y si tienes varias el servidor corta por `MaxAuthTries` antes de llegar a la buena. El síntoma es un `Too many authentication failures` que parece un problema del servidor y es tuyo.
- **`AddKeysToAgent yes`** — si la clave tiene passphrase, la mete en el agente al primer uso y no te la vuelve a pedir en esa sesión. Con `-N ""` es inofensivo.
- **`User git`** — así puedes escribir `ssh $GITLAB_HOST` sin el `git@`. GitLab siempre usa el usuario `git`, tu identidad va en la clave.

Con esto no hace falta `ssh-agent` para el caso sin passphrase.

## Paso 6 · `ssh-agent` (solo si pusiste passphrase)

El agente guarda la clave desbloqueada en memoria para no pedirte la passphrase en cada comando. **Si usaste `-N ""` puedes saltarte este paso.**

```bash
eval "$(ssh-agent -s)"          # arranca el agente y exporta SSH_AUTH_SOCK
ssh-add ~/.ssh/id_ed25519_miempresa
ssh-add -l                      # lista lo que tiene cargado
```

Si ves esto, es que no hay agente en esa shell:

```
Could not open a connection to your authentication agent.
```

**Y el aviso de WSL2:** `eval "$(ssh-agent -s)"` arranca un agente **por shell**. Abres otra pestaña y no está; y `ssh-add -l` vuelve a fallar. Para que persista, un agente único reutilizable en `~/.bashrc`:

```bash
# Agente SSH único y reutilizable entre shells
export SSH_AUTH_SOCK="$HOME/.ssh/agent/socket"
if ! ssh-add -l >/dev/null 2>&1; then
    mkdir -p "$HOME/.ssh/agent" && chmod 700 "$HOME/.ssh/agent"
    rm -f "$SSH_AUTH_SOCK"
    eval "$(ssh-agent -a "$SSH_AUTH_SOCK")" >/dev/null
    ssh-add ~/.ssh/id_ed25519_miempresa 2>/dev/null
fi
```

Ojo: en WSL2 el agente muere con la instancia de WSL (un `wsl --shutdown` se lo lleva), no sobrevive a un reinicio de Windows. Es normal: al abrir la siguiente terminal, el bloque de arriba lo levanta otra vez.

## Paso 7 · Probar la conexión

```bash
ssh -T git@$GITLAB_HOST
```

**La primera vez** te pedirá aceptar la huella del servidor:

```
The authenticity of host 'gitlab.tu-empresa.es (10.x.x.x)' can't be established.
ED25519 key fingerprint is SHA256:...
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

**No escribas `yes` sin mirar.** Esa huella es lo único que te protege de que alguien se ponga en medio. Compárala con la que publique tu equipo de sistemas (GitLab la muestra en su documentación interna, o te la pueden dar por un canal de confianza). Al aceptarla se guarda en `~/.ssh/known_hosts` y no se vuelve a preguntar.

Si todo está bien, GitLab te saluda por tu nombre de usuario:

```
Welcome GitLab, @tu-usuario!
```

Ese mensaje es la prueba de las tres cosas a la vez: hay red, la clave se ofreció, y GitLab la reconoce como tuya.

## Paso 8 · Usarlo

Clonar por SSH:

```bash
git clone git@$GITLAB_HOST:grupo/proyecto.git
```

Si ya tenías el repo clonado por HTTPS y te pide usuario y contraseña cada vez, cambia el remoto:

```bash
git remote -v                                                  # mira qué hay
git remote set-url origin git@$GITLAB_HOST:grupo/proyecto.git
git remote -v                                                  # confirma
```

**Un marketplace de plugins privado en Claude Code** (ver `08-plugins-mcp-y-skills.md`) se da de alta con la URL SSH, y por tanto necesita todo lo anterior funcionando:

```bash
claude plugin marketplace add git@$GITLAB_HOST:grupo/marketplace.git
```

Si la VPN está caída, ese marketplace fallará al refrescarse y **el resto de Claude Code sigue funcionando igual**: los marketplaces públicos, los guards y los agentes no dependen de esto.

## Diagnóstico: `ssh -v` y nada más

Casi todos los fallos dan **el mismo** mensaje, así que el mensaje no te dice qué pasa:

```
git@TU_GITLAB: Permission denied (publickey,password).
```

(El texto real trae el nombre de tu host donde aquí pone `TU_GITLAB`.)

Ese texto sale tanto si la clave no se ofreció como si se ofreció y GitLab la rechazó. Para distinguirlo, `ssh -v` y busca la línea `Offering public key`:

```bash
ssh -vT git@$GITLAB_HOST 2>&1 | grep -E 'Offering|Trying private key|Authentications'
```

- **No aparece `Offering public key` con tu fichero** → `ssh` nunca la ofreció: te falta el paso 5 (o la ruta del `IdentityFile` está mal escrita).
- **Sí aparece `Offering public key: ~/.ssh/id_ed25519_miempresa ... explicit`, y aun así deniega** → la clave se ofreció y **GitLab no la reconoce**: no está dada de alta, la subiste mal (cortada, o pegaste la privada), o ha **caducado**.

Con eso, el resto:

| Mensaje | Qué pasa | Arreglo |
|---|---|---|
| `Could not resolve hostname ...: Name or service not known` | no hay DNS para ese nombre | VPN caída, o el host no es ese. `getent hosts "$GITLAB_HOST"` |
| `Connection timed out` / `No route to host` | el nombre resuelve pero no llegas | VPN a medias, o firewall. Prueba el puerto 22 |
| `Permission denied (publickey)` **sin** `Offering` | clave no ofrecida | paso 5: `IdentityFile` en `~/.ssh/config` |
| `Permission denied (publickey)` **con** `Offering` | clave rechazada por el servidor | revisa el alta en GitLab y su fecha de expiración |
| `Too many authentication failures` | ofreció demasiadas claves y el servidor cortó | `IdentitiesOnly yes` (paso 5) |
| `Could not open a connection to your authentication agent.` | no hay `ssh-agent` en esa shell | paso 6, o prescinde del agente si no hay passphrase |
| `Host key verification failed` | la huella del servidor no coincide con `known_hosts` | **no lo ignores.** Puede ser un servidor reinstalado o alguien en medio: confirma la huella por un canal de confianza antes de borrar la entrada vieja con `ssh-keygen -R "$GITLAB_HOST"` |
| `git@...: Permission denied` solo al hacer `push` | la clave vale, faltan permisos en el proyecto | pide rol `Developer` o superior en GitLab |

## Seguridad

- **La privada no sale de la máquina.** Ni a un repo, ni por email, ni a un pendrive sin cifrar. Si necesitas acceso desde otro equipo, **genera otra clave allí** y dala de alta también: es igual de cómodo y te deja revocar una sin tocar la otra.
- **Una clave por máquina y por destino.** Es la razón del `-f` con nombre propio: revocar es entonces una operación de un minuto y sin daños colaterales.
- **Cuidado con los respaldos.** Una copia de tu `$HOME` (un `tar`, una imagen de WSL, un backup a disco externo) **incluye `~/.ssh` con las claves privadas** aunque el índice del respaldo no lo mencione. Si haces ese tipo de copia, cífrala. Un disco externo con tu `~/.ssh` dentro es tu identidad en un cajón.
- **Si crees que se ha filtrado:** borra la clave en GitLab (**Edit profile → SSH Keys → Delete**) *antes* de generar la nueva. Revocar primero, recrear después.
- **Rota cuando expire.** El proceso es esta misma guía otra vez, con un `-f` nuevo. No reutilices el fichero anterior.
- **No metas `~/.ssh/` en el allowlist de Sentinel** para que Claude Code pueda leer ahí. Ese guard existe precisamente para esto.

## Resumen, todo junto

Para copiar y pegar de una vez, cambiando las dos primeras líneas:

```bash
GITLAB_HOST="gitlab.tu-empresa.es"
KEY=~/.ssh/id_ed25519_miempresa

# 1. generar
ssh-keygen -t ed25519 -C "tu.usuario@example.com (WSL portatil)" -f "$KEY" -N ""

# 2. permisos
chmod 700 ~/.ssh && chmod 600 "$KEY" && chmod 644 "$KEY.pub"

# 3. copiar la publica -> pegar en GitLab (Edit profile > SSH Keys > Add new key)
cat "$KEY.pub"

# 4. decirle a ssh que la use con este host
cat >> ~/.ssh/config <<EOF

Host $GITLAB_HOST
    User git
    IdentityFile $KEY
    IdentitiesOnly yes
    AddKeysToAgent yes
EOF
chmod 600 ~/.ssh/config

# 5. (solo con passphrase) cargarla en el agente
eval "$(ssh-agent -s)" && ssh-add "$KEY"

# 6. probar -> debe responder "Welcome GitLab, @tu-usuario!"
ssh -T git@$GITLAB_HOST
```

Recuerda: el paso 3 hay que hacerlo en la web entre el 3 y el 4, y **todo esto en una terminal normal de WSL**, no a través de Claude Code, porque los guards del kit bloquean las rutas de `~/.ssh/`.
