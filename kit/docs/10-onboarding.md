# 10 · Onboarding: de cero a sesión verde

Esta es la ruta completa para alguien que llega nuevo. Un solo comando levanta lo
obligatorio; lo opcional se decide después, con las cifras delante.

Si eres Claude Code leyendo esto en una máquina nueva: los pasos 1 a 4 son el arranque, el
paso 6 es el diagnóstico cuando algo no cuadra, y **no ejecutes el paso 5 sin que la
persona lo pida** — cuesta latencia y no se recupera sola.

---

## 0 · Qué vas a levantar

| Capa | Qué es | Obligatoria |
|---|---|---|
| `kit/` | La instalación endurecida en tu `~/.claude`: guards deterministas, Sentinel, 8 agentes, y la Capa 2 de secretos sobre cada commit | Sí |
| raíz (`.claude/`, `knowledge/`, `scripts/`) | El harness: comandos, skills, hooks de proyecto y el conocimiento versionado. Ya viaja en el repo | Sí, ya la tienes al clonar |
| Headroom | Proxy local de compresión de contexto en `:8787` | **No.** Opt-in: `make bootstrap` no lo instala, y lee el paso 5 antes |
| `rtk`, `gitleaks` | Filtro de salida de CLI y escáner de secretos por contenido | No. Sin ellos el kit degrada a no-op **y sigue bloqueando** |

Nada del kit da por supuesto lo opcional, y hay un test que lo demuestra en una máquina
pelada: `kit/test/test_clean_install_resilience.sh`.

## 1 · Requisitos

- **Linux o WSL2.** `kit/install.sh` aborta en cualquier otra plataforma, a propósito y sin
  dejar nada a medias.
- **En WSL2, activa systemd** (`/etc/wsl.conf` con `[boot]\nsystemd=true`) antes de nada. Sin
  él no hay `systemctl --user`, y el paso 5 no puede funcionar.
- **`git config core.autocrlf`**: si lo tienes en `true` (típico si vienes de Windows), el
  repo trae `.gitattributes` que fuerza LF en scripts y hooks. No lo desactives: un hook con
  CRLF no se ejecuta y el fallo se lee como "el hook no hace nada".
- `bash`, `git`, `jq`, `curl`, `python3`. `jq` es dependencia dura de cinco guards.

## 2 · El camino corto

```bash
git clone https://github.com/manuelcozar55/setup-claude-code.git
cd setup-claude-code
make bootstrap
```

`make bootstrap` hace cuatro cosas y para si alguna falla: crea tu `config/profile.yaml`
desde el ejemplo, instala el kit en `~/.claude`, corre `kit/doctor.sh` y ejecuta el oráculo
del repo.

## 3 · Qué acaba de pasar

- Se ha copiado (no enlazado) la configuración a `~/.claude`: `settings.json`, `CLAUDE.md`,
  los hooks, los agentes y Sentinel.
- **Si un fichero ya existía y difería, se guardó una copia** en
  `~/.claude/backups/<fecha>-<pid>-<aleatorio>/` antes de sobrescribirlo. Reinstalar dos
  veces seguidas no crea un segundo backup: es idempotente.
- **Si tu `~/.claude` es un repo git con remoto**, el instalador toma el camino *diff-first*:
  te muestra el diff y **no escribe nada**. Para aplicarlo de verdad, `--apply`.
- `config/profile.yaml` es tuyo, está en `.gitignore` y no viaja. Ahí van tu nombre, tu nivel
  de coach y tu oráculo.

## 4 · Verificar de verdad

```bash
make test          # 29 suites en bash puro, sin red, ~58 s. exit 0 o no está hecho.
bash kit/doctor.sh # estado de ESTA máquina
```

Cómo leer `doctor.sh`:

- **`FAIL`** → algo está roto o es inseguro. Sale con código distinto de 0. No lo ignores.
- **`WARN`** → un componente opcional que no instalaste. Es aceptable.
- Cada `PASS` dice de dónde sale el dato (`(fuente: …)`). Si un check no puede decir su
  fuente, no es un check.

Y no te creas que los guards funcionan porque lo diga el README: neutraliza uno y mira qué
pasa. `bash kit/test/test_guards_falsifiability.sh` desactiva un guard real y exige que eso
rompa exactamente 10 casos `BLOCK` conocidos. Si desactivarlo no rompiera nada, la suite no
estaría midiendo nada.

## 5 · Headroom, con las cifras delante

Headroom es un proxy local que comprime el contexto antes de enviarlo. Está soportado, está
testado, y **la recomendación es no activarlo por defecto**. Lo medido en un perfil de uso
real de un día (687 peticiones):

| | |
|---|---|
| Input que son lecturas de caché | **95,4 %** |
| Ahorro efectivo de tokens | **0,8 %** (de por vida: 0,813 % sobre 26 353 peticiones, medido el 2026-09-02) |
| Latencia añadida | **512 ms** de media por petición, pico de 2 633 ms |
| RAM residente | ~1,3 GB permanentes |
| Ahorro en dinero según su propia contabilidad | **0,00 $** |

El motivo del 0,8 % no es que comprima mal: es que el 95,4 % del input son lecturas de caché
que el proxy **se niega a tocar deliberadamente**, y hace bien — cambiar un prefijo cacheado
convierte lecturas a 0,1× en escrituras a 1,25×.

**Nunca pongas `HEADROOM_MODE=token`**, aunque el panel del propio proxy te lo sugiera. Con
este perfil, el modo `token` tendría que comprimir el **85 %** del contexto solo para empatar
con el modo `cache`; comprime el 4,2 % de media. Detalle en [`03-headroom.md`](03-headroom.md).

Si aun así lo quieres:

```bash
bash kit/install.sh --with-headroom
```

Ese subcomando instala, escribe la unidad systemd, arranca, **espera a que `/readyz`
responda hasta 30 s y solo entonces enruta la API**. Si el proxy no contesta, sale con
error y no toca `settings.json` — cablear la API a un puerto muerto deja Claude Code sin
poder conectar, y parece un fallo de la herramienta.

Guardarraíles que el instalador y `doctor.sh` sostienen, cada uno por un fallo ya pagado:

- `--mode cache` explícito. La documentación de la herramienta se contradice sobre cuál es el
  default, y esa inconsistencia ya puso un proxy en `token` sin querer.
- Nunca `--budget`: al agotarse devuelve HTTP 200 con cuerpo vacío, que se lee como un fallo
  del cliente y no del presupuesto.
- Nunca `--log-messages`: escribe la conversación entera en texto plano. `doctor.sh` falla si
  encuentra `request_messages` en `~/.headroom/logs/proxy.jsonl`.
- Una sola fuente de `ANTHROPIC_BASE_URL`. Si aparece en `settings.json` **y** en
  `settings.local.json`, `doctor.sh` falla: no se puede apagar lo que está declarado en dos
  sitios.
- Nunca `headroom install`, ni `pkill -f "headroom proxy"`, ni `nohup headroom proxy`:
  systemd relanza el suyo y quedan dos instancias peleando por el puerto. Reiniciar solo con
  `systemctl --user restart headroom-proxy`.

Todo esto lo vigila `kit/test/test_headroom_guardrails.sh`.

Una advertencia práctica: el compresor reescribe con pérdida el contenido de los resultados
de herramienta. Para trabajo forense o de depuración —leer logs, comparar salidas byte a
byte— arranca la sesión sin proxy: `ANTHROPIC_BASE_URL= claude`.

## 6 · Cuando algo va mal

| Síntoma | Causa medida |
|---|---|
| "empty or malformed response (HTTP 200)" | El proxy está saturado o agotó un `--budget`. `curl -s localhost:8787/readyz` y `systemctl --user status headroom-proxy`. No abras más de 2 sesiones en paralelo contra él. |
| Un hook "no hace nada" | CRLF en el fichero, o sin bit de ejecución. `kit/test/test_gitattributes.sh` y `kit/test/test_exec_modes.sh` lo cubren en el repo. |
| Sentinel bloquea algo legítimo | Reformula el comando. **No amplíes la allowlist para esquivarlo**: los guards bloquean por el literal, así que nombrar un fichero de credenciales —aunque sea para excluirlo— dispara. |
| El proxy comprime 0 tokens y aun así `/readyz` dice healthy | Falta el modelo ONNX. La unidad fija `HF_HUB_OFFLINE=0` por esto; si lo heredas en 1, el motor queda `available:false` en silencio. |
| `unable to open database file (code 14)` cada 60 s | La unidad no da escritura a `~/.local/share/rtk`. La que genera el kit ya la da. |

## 7 · Desinstalar

```bash
bash uninstall.sh          # dry-run: dice qué haría y no toca nada
bash uninstall.sh --apply  # restaura el backup más reciente
bash uninstall.sh --list   # enumera los backups disponibles
```

## 8 · Antes de tu primer commit

```bash
bash kit/scan-secrets.sh   # secretos y PII en el árbol
shellcheck -x <tus .sh>
make test
```

Rama y PR, nunca directo a `main`. Y si tu cambio toca una cifra que la documentación
afirma, `kit/test/test_doc_claims.sh` te pondrá en rojo: eso no es un obstáculo, es el punto.
