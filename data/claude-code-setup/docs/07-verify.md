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
cd data/claude-code-setup
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
cd data/claude-code-setup
for t in test/*.sh; do echo "-- $t --"; bash "$t" || exit 1; done
```

Esperado: cada script imprime `N passed, 0 failed` y termina con código 0.

## Tabla de comprobaciones

| Qué se verifica | Fuente de la evidencia | Comando | Resultado esperado |
|---|---|---|---|
| Cero secretos/PII en el kit | patrones de valor (`sk-`, `pplx-`, `AKIA`...), rutas absolutas de la cuenta root, emails reales | `bash scan-secrets.sh .` | `PASS`, exit 0 |
| `settings.json` válido | `jq empty` sobre el fichero instalado | `jq empty "$CLAUDE_HOME/settings.json"` | sin error |
| Hooks referenciados existen y son ejecutables | `jq` sobre `.hooks` de `settings.json` + `test -e`/`-x` | (lo hace `doctor.sh` internamente) | `PASS · hooks referenciados presentes y ejecutables` |
| Agentes instalados | conteo de ficheros | `ls "$CLAUDE_HOME"/agents/*.md \| wc -l` | 8 |
| Venv de tools (opcional) | presencia del binario | `test -x "$HOME/.venvs/tools/bin/python3"` | `PASS` si está, `WARN` si no |
| Headroom (opcional) | presencia del CLI | `command -v rtk` | `PASS` si está, `WARN` si no |
| Capa de IOCs de Sentinel (opcional; ver `docs/05-security.md`) | presencia de `iocs.json` | `test -f "$CLAUDE_HOME/hooks/iocs.json"` | `PASS` si está, `WARN` si no (los guards de Bash siguen activos) |
| Instalación completa sin `FAIL` | agregado de todo lo anterior | `CLAUDE_HOME=... bash doctor.sh` | exit 0, 0 `FAIL` |
| Idempotencia del instalador | backup timestamped tras reinstalar | `bash install.sh` (segunda vez) | sin error, backup creado, original no pisado |
| Regresión de cada script | arnés TDD en bash puro | `bash test/test_scan_secrets.sh` / `test_install.sh` / `test_doctor.sh` | `N passed, 0 failed` |

Si cualquiera de estos comandos no da el resultado esperado en tu máquina, es una `FAIL` real: corrígelo antes de dar la instalación por buena. Ese es el bucle completo del kit: instalar, diagnosticar, corregir, reinstalar.
