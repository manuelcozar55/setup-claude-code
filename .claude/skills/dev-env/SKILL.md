---
name: dev-env
description: Gotchas verificados de este entorno WSL2 — reescritura de comandos por hooks, venvs de Python, pnpm, rendimiento de /mnt/c y el proxy Headroom. Úsala antes de instalar herramientas, crear entornos, ejecutar suites de test o diagnosticar un comando que se comporta raro. No la uses para lógica de negocio.
---

# Entorno de desarrollo

Todo lo de aquí está **medido**, con fecha. Si algo contradice tu expectativa, gana la
medición; y si sospechas que ha caducado, vuelve a medirlo antes de fiarte.

Última verificación: **2026-08-21**.

---

## 1 · Los comandos no se ejecutan tal como los escribes

El hook `PreToolUse/Bash` sustituye el **ejecutable en posición de comando**:

```
rg --version                 ->  grep (GNU grep) 3.12          (se ejecutó grep)
python3 -m pytest --version  ->  No module named rtk           (se ejecutó python3 -m rtk)
echo pytest                  ->  pytest                        (los argumentos NO se tocan)
```

**Tres vías lo evitan, las tres verificadas:**

| Vía | Ejemplo | Resultado |
|---|---|---|
| Ruta absoluta | `/home/…/.venvs/riego/bin/pytest --version` | `pytest 9.1.1` ✅ |
| Bypass documentado | `rtk proxy rg --version` | `ripgrep 15.1.0` ✅ |
| Encapsular en script | el hook actúa sobre la invocación del agente, no sobre lo que el script ejecute después | ✅ |

**Consecuencia dura:** ningún oráculo se invoca por nombre suelto. Ver
`knowledge/MISTAKES.md` · M-001.

## 2 · Python

| | |
|---|---|
| Sistema | `/usr/bin/python3` → **3.14.4**, **sin pytest** |
| Herramientas | `~/.venvs/tools/bin/` → pytest 9.1.1, uv 0.12.1 |
| `uv` | 0.12.1 · pythons gestionados: 3.13.14, 3.12.13 |

**Nunca** `pip install --break-system-packages` ni `pip3 install` global. Receta:

```bash
~/.venvs/tools/bin/<tool> --version 2>/dev/null || (
  ~/.venvs/tools/bin/pip install <pkg> -q &&
  ln -sf ~/.venvs/tools/bin/<tool> ~/.local/bin/<tool>
)
```

Para un venv de proyecto: **`uv venv .venv --seed`**. Sin `--seed` no siembra `pip`, y
después no se puede gestionar con nada que no sea `uv`.

## 3 · Node

`node` v24.19.0 y `npm` 12.0.2 vía nvm. **`pnpm` NO está en `$PATH`**: existe solo como
shim de corepack (`~/.nvm/versions/node/v24.19.0/bin/pnpm`, versión 11.18.0). El directorio
`~/.local/share/pnpm/bin` está en `$PATH` pero vacío. Invócalo por ruta o vía `corepack`.

## 4 · Sistemas de ficheros

| | ext4 (`~`) | `/mnt/c` (9p/drvfs) |
|---|---|---|
| `find -type f` | 0,11 ms/fichero | **0,41 ms/fichero** (3,7×) |
| `git status` | rápido | **0,82 s** |
| `du -sh` de 1.000 ficheros | — | **4,4 s** |
| `stat` individual | — | **6,3 ms** |

El cuello no es el ancho de banda: es la **latencia por syscall de metadatos**, y la caché
apenas ayuda (una segunda pasada no mejora). Patrones patológicos: `du`, `stat` en bucle y
recolección de pytest con imports pesados.

Los proyectos del usuario viven en `/mnt/c/Users/…/Downloads/`. Un venv en ext4 apuntando a
código en `/mnt/c` es la combinación buena, y ya existe: `~/.venvs/riego`.

## 5 · Los guards bloquean por literal, no por acción

Sentinel y los guards de `kit/claude/hooks/` inspeccionan la **cadena del comando**. Escribir
el nombre de un fichero de credenciales dispara `[CRITICAL] sensitive path pattern` aunque
sea para excluirlo; `rm -rf` sobre un temporal propio también se bloquea.

**Ante un bloqueo: reformula.** Ampliar la allowlist convierte un sensor en decoración, y
solo se hace con justificación escrita en `knowledge/DECISIONS/`.

Coste medido de la cadena completa de 7 hooks: **160 ms por comando Bash**, idéntico en
ext4 y en `/mnt/c` (los guards no ejecutan `git status`). El más lento es
`block-dangerous-commands.sh` con 58 ms.

## 6 · Proxy Headroom — no tocar

`:8787` es una **unidad systemd con `Restart=always`**.

- Ruta correcta: `bash kit/install.sh --with-headroom`, que instala, arranca, espera a que
  `/readyz` responda hasta 30 s y **solo entonces** enruta. `headroom wrap claude` (alias
  `cc`) tambien funciona, pero escribe `ANTHROPIC_BASE_URL` en el `settings.local.json` del
  proyecto y lo repone con un hook `SessionStart`: medido, dejo la variable en 5 ficheros
  no declarados y el enrutado paso a depender del cwd de la sesion.
- `ANTHROPIC_BASE_URL` en `settings.json` **no** desactiva la ventana de 1M ni el tool
  search. Medido el 2026-09-01 dentro de una sesion enrutada por el `env` de settings:
  ventana de 1M activa (va por el sufijo del id de modelo, `claude-opus-5[1m]`, no por la
  cabecera beta) y herramientas diferidas funcionando (`ENABLE_TOOL_SEARCH`). Lo que **si**
  se pierde es `/remote-control`, y eso lo confirma `headroom doctor`. El fallo no es
  declararlo en `settings.json`: es declararlo en **dos** sitios, porque entonces no se
  puede apagar. `kit/doctor.sh` falla si encuentra mas de una fuente.
- **Nunca** `pkill -f "headroom proxy"` ni `nohup headroom proxy`: systemd relanza el suyo y
  quedan dos instancias peleando por el puerto → respuestas HTTP 200 vacías. Reiniciar solo
  con `systemctl --user restart <unidad>`.
- **Nunca** `--budget`: al agotarse bloquea peticiones.
- Si aparece *"empty or malformed response (HTTP 200)"*: `curl -s localhost:8787/readyz` y
  `grep PERF ~/.headroom/logs/proxy.log | tail -3`. No abrir más de 2 sesiones en paralelo
  contra el proxy.

## 7 · Herramientas presentes y ausentes

**Hay**: `gh` 2.46.0 · `gitleaks` 8.30.1 · `jq` 1.8.1 · `shellcheck` 0.11.0 ·
`rg` 15.1.0 · `git` 2.53.0 · `zip`/`unzip` · `uv` · `pre-commit`.

**No hay**: `bats`, `ruff`, `black`, `docker`.
→ Los tests de este repo son **bash puro**, no introduzcas un framework nuevo.

`sha256sum` es **uutils coreutils 0.8.0**, no GNU. En macOS no existe: usa
`shasum -a 256`. Todo script que valide checksums debe resolver ambos.
