# 07 · Verificación

La regla que gobierna todo este kit: **nada se da por bueno sin su comando y su salida esperada.** Cada afirmación de este documento (y de los seis anteriores) se puede reproducir. Si algo aquí no lo puedes comprobar tú mismo con un comando en tu máquina, sobra.

La secuencia "cifra → fuente → comando": por cada componente que se verifica, hay una cifra o estado concreto, de dónde sale esa cifra, y el comando exacto para reproducirla. `doctor.sh` sigue este mismo patrón internamente: cada línea que imprime dice qué comprueba y cómo lo comprobó.

## Los tres scripts

- **`scan-secrets.sh [DIR]`**: gate determinista de secretos/PII. Exit 0 = `PASS`. Exit 1 = `FAIL` con la lista de hallazgos.
- **`install.sh`**: instala la config saneada en `CLAUDE_HOME` (idempotente, con backup).
- **`doctor.sh`**: health-check de una instalación ya hecha, con evidencia por componente.

## Verificación paso a paso

**1. El kit no tiene secretos:**

```bash
cd kit
bash scan-secrets.sh .
```

Esperado: `PASS: sin secretos/PII en .`, exit 0.

**2. Una instalación limpia funciona en una máquina nueva** (usa un `CLAUDE_HOME` temporal para no tocar tu instalación real):

```bash
D=$(mktemp -d)
CLAUDE_HOME="$D/dot" bash install.sh
CLAUDE_HOME="$D/dot" bash doctor.sh
```

Esperado: `install.sh` sin error; `doctor.sh` con 0 `FAIL` (los `WARN` son aceptables cuando corresponden a terceros que no has instalado, como Headroom o el venv de tools).

**3. El instalador es idempotente**: reejecuta `install.sh` sobre el mismo `CLAUDE_HOME` (ideal: primero modifica un fichero instalado, para forzar la ruta de backup):

```bash
echo "MOD" >> "$D/dot/CLAUDE.md"
CLAUDE_HOME="$D/dot" bash install.sh
ls "$D/dot"/backups/*/CLAUDE.md
rm -rf "$D"
```

Esperado: la segunda ejecución no falla, y aparece un backup con timestamp del fichero modificado; el original no se pierde.

**4. La suite de tests, en verde:**

```bash
cd kit
for t in test/*.sh; do echo "-- $t --"; bash "$t" || exit 1; done
```

Esperado: cada script imprime `PASS=N FAIL=0` (o `N passed, 0 failed`, según el script) y termina con código 0. `test/test_secret_content_gitleaks.sh` (Capa 2 de secretos) hace `SKIP` con exit 0 si `gitleaks` no está instalado, en vez de fallar — instálalo (`docs/02-install.md`) para correrlo de verdad.

**5. La suite de guards es falsable, no una tautología:**

```bash
bash test/test_guards_falsifiability.sh
```

Esperado: con el guard real, `PASS=27 FAIL=0`; con `secret-guard.sh` sustituido por un stub `exit 0`, un número fijo de casos `BLOCK` cae (`FAIL>0`). Si neutralizar el guard no rompe ningún test, la suite no estaría midiendo nada — este script lo demuestra en cada corrida.

**6. El eval set NO forma parte de lo anterior — opt-in explícito, cuesta dinero real:**

`kit/evals/` no se ejecuta en el bucle del paso 4 (vive fuera de `test/`, y así se queda). Correrlo hace 6 llamadas reales a `claude -p`:

```bash
bash kit/evals/run.sh
```

Ver `kit/evals/README.md` para el criterio de admisión de tareas y por qué usa `--permission-mode auto`. Los transcritos que genera (`kit/evals/transcripts/`) y los resultados (`kit/evals/resultados-*.json`) están en `.gitignore`: no se comitean.

## Tabla de comprobaciones

| Qué se verifica | Fuente de la evidencia | Comando | Resultado esperado |
|---|---|---|---|
| Cero secretos/PII en el kit | patrones de valor (`sk-`, `pplx-`, `AKIA`...), rutas absolutas de la cuenta root, emails reales | `bash scan-secrets.sh .` | `PASS`, exit 0 |
| `settings.json` válido | `jq empty` sobre el fichero instalado | `jq empty "$CLAUDE_HOME/settings.json"` | sin error |
| Hooks referenciados existen y son ejecutables | `jq` sobre `.hooks` de `settings.json` + `test -e`/`-x` | (lo hace `doctor.sh` internamente) | `PASS · hooks referenciados presentes y ejecutables` |
| Agentes instalados | conteo de ficheros | `ls "$CLAUDE_HOME"/agents/*.md \| wc -l` | 8 |
| Venv de tools (opcional) | presencia del binario | `test -x "$HOME/.venvs/tools/bin/python3"` | `PASS` si está, `WARN` si no |
| Intérprete para los hooks Python (opcional) | venv o `python3` del sistema | `command -v python3` | `PASS` si hay alguno; `WARN` si no (quedan en no-op, los guards de bash siguen) |
| **Enrutado de la API** | si algo enruta a un proxy, ese proxy debe contestar | `jq -r '.env.ANTHROPIC_BASE_URL' settings.json` + `GET /readyz` | `PASS` sin proxy o con proxy vivo; **`FAIL` si está enrutado y no contesta** |
| Headroom, el proxy (opcional) | presencia del CLI | `command -v headroom` | `PASS` si está, `WARN` si no |
| `rtk`, el filtro de salida de CLI (opcional) | presencia del CLI | `command -v rtk` | `PASS` si está, `WARN` si no |
| Headroom enrutado de verdad (opcional) | informe de la propia herramienta | `headroom doctor` | 0 `failure`; ojo si dice `savings: no tokens saved yet` (proxy vivo, cliente sin enrutar) |
| Capa de IOCs de Sentinel (opcional; ver `docs/05-security.md`) | presencia de `iocs.json` | `test -f "$CLAUDE_HOME/hooks/iocs.json"` | `PASS` si está, `WARN` si no (los guards de Bash siguen activos) |
| `gitleaks` instalado (opcional; requerido para la Capa 2 de secretos), con versión | `command -v gitleaks` + `gitleaks version` | (lo hace `doctor.sh` internamente) | `PASS` si está (con versión), `WARN` si no (la Capa 1 sigue activa) |
| Checksum de `gitleaks` no coincidió en una instalación anterior | marca `$CLAUDE_HOME/.gitleaks-checksum-mismatch` | (lo hace `doctor.sh` internamente) | `FAIL` si la marca existe (posible ataque a la cadena de suministro); nada si no |
| Capa 2 (`core.hooksPath`) activa en el repo actual | `git config --get core.hooksPath` | (lo hace `doctor.sh` internamente) | `PASS` si está configurado, `WARN` si no |
| Instalación completa sin `FAIL` | agregado de todo lo anterior | `CLAUDE_HOME=... bash doctor.sh` | exit 0, 0 `FAIL` |
| Idempotencia del instalador | backup timestamped tras reinstalar | `bash install.sh` (segunda vez) | sin error, backup creado, original no pisado |
| Regresión de cada script | arnés TDD en bash puro | `bash test/test_scan_secrets.sh` / `test_install.sh` / `test_doctor.sh` | `N passed, 0 failed` |
| Regresión de los guards `PreToolUse` (Capa 1 + Sentinel) | arnés TDD en bash puro | `bash test/test_guards.sh` | `PASS=27 FAIL=0` |
| Regresión de la Capa 2 (`pre-commit` + `gitleaks`) | repos git temporales reales, `git commit` de verdad | `bash test/test_secret_content_gitleaks.sh` | `PASS=17 FAIL=0` (o `SKIP` si falta `gitleaks`) |
| La suite de guards es falsable (no una tautología) | guard real vs. guard neutralizado (`exit 0`) | `bash test/test_guards_falsifiability.sh` | exit 0; "neutralizar el guard rompe 10 caso(s) BLOCK que antes pasaban" |
| Puerta de plataforma de `install.sh` (solo Linux/WSL2) | simula `uname -s` no-Linux, comprueba abort limpio | `bash test/test_install_platform_gate.sh` | `4 passed, 0 failed` |
| Detección/degradación de `gitleaks` en `install.sh` | `gitleaks` ya presente vs. ausente sin red | `bash test/test_install_gitleaks.sh` | `6 passed, 0 failed` |
| Checksum de `gitleaks` fijado en el repo: un mismatch no rompe la instalación, deja marca persistente | tarball simulado con checksum incorrecto; `doctor.sh` sobre esa marca | `bash test/test_install_gitleaks_checksum.sh` | `9 passed, 0 failed` |
| `install.sh --enable-secrets-layer2` activa la Capa 2 solo en el repo nombrado | repos git temporales reales | `bash test/test_enable_secrets_layer2.sh` | `6 passed, 0 failed` |
| Sin CRLF en scripts/hooks versionados (`.gitattributes`) | `git ls-files` + detección de `\r`, auto-falseado con un CRLF fabricado | `bash test/test_gitattributes.sh` | `4 passed, 0 failed` |
| Eval set (opt-in, cuesta dinero real — no forma parte de lo anterior) | transcript de `claude -p`, gradeado por `grade.py` | `bash kit/evals/run.sh` | `pass`/`fail` por tarea, ver `kit/evals/README.md` |

Si cualquiera de estos comandos no da el resultado esperado en tu máquina, es una `FAIL` real: corrígelo antes de dar la instalación por buena. Ese es el bucle completo del kit: instalar, diagnosticar, corregir, reinstalar.
