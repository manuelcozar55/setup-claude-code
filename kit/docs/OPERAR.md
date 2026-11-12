# Operar SCC

Para quien ya tiene el kit instalado y necesita resolver algo concreto. Cada orden de esta página se probó con
`CLAUDE_HOME` apuntando a un directorio temporal. Qué hace cada hook y cada variable: [MAPA.md](MAPA.md).

Versión mínima de Claude Code probada: **2.1.311** (la fuente única es `MIN_CLAUDE_CODE` en
`kit/mods/cockpit/hooks/register.tsx`; `doctor.sh` y un test la leen de ahí).

## Se bloqueó una orden legítima

Un guard bloquea por lo que dice el texto de la orden, no por lo que haría. El mensaje que ves dice qué
guard fue y termina en «Que hacer: …».

1. **Mira qué guard fue.** Cada guard y lo que bloquea está en [MAPA.md](MAPA.md). Estos dejan rastro:
   - `destructive-guard.sh`: `~/.claude/audit-logs/blocked-commands.log` (una línea por bloqueo, con la orden).
   - Sentinel: `~/.claude/audit-logs/sentinel.jsonl`.
   - Los demás guards solo escriben su mensaje en la sesión.
2. **Déjala pasar una vez.** Ejecútala tú con `!` delante, en la sesión: `! git reset --hard HEAD~1`. No pasa por los
   hooks y la ves ejecutarse. Un `CC_ALLOW_DESTRUCTIVE=1` delante de la orden no vale: el guard lo lee del entorno.
3. **Apaga un guard para toda la sesión.** Solo `destructive-guard.sh` tiene interruptor:
   `CC_ALLOW_DESTRUCTIVE=1 scc` (o `claude`). Apaga el guard entero, así que úsalo en sesiones donde sepas lo que haces.
   Para ajustar sin apagar: `CC_PROTECT_BRANCHES=main:master` (ramas protegidas) y `CC_SAFE_DELETE_DIRS=node_modules:dist`
   (carpetas que se pueden borrar sin avisar).
4. **Quítalo del todo** con el procedimiento de la sección siguiente.

Si crees que el bloqueo es un fallo del guard, no lo ensanches tú: abre una incidencia con la orden y el mensaje
([SECURITY.md](../../SECURITY.md) explica qué cubre cada guard y qué no).

## Quiero quitar un hook

Quitar un hook es borrar su entrada de `~/.claude/settings.json` y anotar el script en `~/.claude/.kit-desactivados`
(una línea por script, solo el nombre). Sin la nota, `doctor.sh` da FAIL («settings.json no cablea hook(s) del kit»).
Con ella, `doctor.sh` lo cuenta como «desactivado por ti» y sale con 0.

```bash
S=~/.claude/settings.json
jq --arg s stale-read-guard.py '.hooks |= with_entries(.value |= map(select(.hooks | map(.command | contains("/" + $s + "\"")) | any | not)))' "$S" > "$S.new" && mv "$S.new" "$S"
echo stale-read-guard.py >> ~/.claude/.kit-desactivados
bash kit/doctor.sh      # desde el clon: INFO · desactivado por ti … ; == OK (0 FAIL) ==
```

Cambia `stale-read-guard.py` por el nombre que aparece en [MAPA.md](MAPA.md). Reinicia las sesiones abiertas.

Un agente o una skill se quitan igual: borra el fichero y anota su ruta tal como la ve el doctor.

```bash
rm ~/.claude/agents/code-reviewer.md
echo agents/code-reviewer.md >> ~/.claude/.kit-desactivados
```

`install.sh --apply` lee `.kit-desactivados` solo para no recrear lo que falta: un hook que ya está cableado o un fichero
que existe se tratan como siempre (la lista no quita nada), y `hooks/<nombre>` equivale a `<nombre>`. Apagar un guard de seguridad
(los hooks `PreToolUse`) deja un WARN en `doctor.sh`, no un INFO. Para encender algo de nuevo, borra su línea y reinstala.

## El aviso de contexto me molesta

El aviso lo emite un solo hook, `nucleo-nudge.sh` (`PostToolUse`): al modelo al 50, 70 y 85 % del contexto antes de
compactar, y a ti al 60 y al 85 %. Para apagarlo, quita ese hook con el procedimiento de arriba
(`nucleo-nudge.sh`). El guardado automático del estado (`autosave.sh`) sigue funcionando. Si usas el cockpit y solo
quieres que no haga el handoff solo al 70 %: `COCKPIT_AUTO_HANDOFF=off scc`.

## Lo que el kit hace solo, y cómo apagarlo

| Qué hace | Qué te cuesta | Cómo se apaga |
|---|---|---|
| **Handoff automático del cockpit** (solo con `scc`): al 70 % del contexto guarda el estado y después limpia la conversación (`/clear`), sin pedírtelo | Una llamada al modelo con todo el contexto; la conversación se limpia y retomas desde el estado guardado | `COCKPIT_AUTO_HANDOFF=off` (un número de 50 a 95 cambia el umbral) |
| **Autoinicio del estado**: el primer guardado con trabajo en cualquier repo git crea `<repo>/.claude/estado/nucleo.md` y añade `.claude/estado/` a `.git/info/exclude` | Un fichero local por repo; no entra en git. El desinstalador no lo borra: es tuyo | `NUCLEO_AUTOINICIO=0` |
| **Marcas del aviso de contexto**: `nucleo-nudge.sh` escribe `nudge-<sesión>` en `$HOME/.claude/session-logs`, aunque uses otro `CLAUDE_HOME` | Ficheros vacíos en tu carpeta personal | Quitar el hook (ver «Quiero quitar un hook») |
| Guardado con modelo (`/autosave`) | **Apagado por defecto**: encendido, una llamada por guardado | `/autosave on` o `COCKPIT_AUTOSAVE=on` lo encienden; `/autosave off` lo apaga |

Estas variables van en `env` de tu `settings.json` (ver la receta de la guía de adaptación) o en el entorno desde el que
lanzas `scc`.

## Cuánto cuesta

- **Contexto fijo en cada sesión.** Lo que el kit añade son sus ficheros de reglas, las descripciones de agentes y skills,
  y el estado del proyecto que inyecta al arrancar (como mucho `NUCLEO_TOPE`, 6500 bytes, y solo si el proyecto tiene
  `.claude/estado/nucleo.md`). Mídelo en tu máquina: `wc -c ~/.claude/CLAUDE.md ~/.claude/AGENTS.md` (unos 4 bytes por token).
- **Latencia.** Cada orden de Bash pasa por cinco guards y por Sentinel antes de ejecutarse; arrancan en paralelo.
  Mide uno: `time (echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | bash ~/.claude/hooks/destructive-guard.sh)`.
  Los hooks de estado corren una vez por turno (`autosave.sh` va asíncrono, no te espera).
- **Llamadas al modelo.** Sin cockpit, el kit no hace ninguna: todo son scripts locales. Con cockpit, el handoff
  automático al 70 % lanza una llamada al modelo con el contexto de la sesión; `/handoff` y `/nueva` lanzan otra cada vez
  que los usas; `/autosave` empieza apagado y, encendido, gasta tokens en cada guardado (su uso queda en
  `~/.claude/session-logs/autosave-cockpit.log`). `cupo` gasta un turno mínimo de `claude -p`.
- **Mide lo que pasa de verdad** con `efectividad` (cifras de tus sesiones, solo lectura).

## Actualizar a una versión nueva

Una sola receta, desde el clon:

```bash
git pull
bash kit/install.sh --plan     # qué cambiaría; no escribe nada
bash kit/install.sh --apply    # aplica, con copia de lo que sobrescribe en ~/.claude/backups/
bash kit/doctor.sh             # debe terminar en == OK (0 FAIL) ==
```

Reinicia las sesiones abiertas de Claude Code: no recargan los hooks ni el cockpit. Si quitaste algún hook, repite su
borrado (ver arriba). `~/.claude/.kit-version` dice qué versión tienes; `scc --version` imprime la del kit, la del
cockpit y la de Claude Code.

## Desinstalar

```bash
bash uninstall.sh --kit            # simulacro: lista lo que se borraría; no toca nada
bash uninstall.sh --kit --apply    # borra lo que el kit instaló, con copia previa en ~/.claude/backups/
```

Conserva y lista lo que modificaste, quita los enlaces de `~/.local/bin` solo si apuntan al kit y deshace en
`settings.json` solo lo que el kit añadió. Si actualizaste desde una versión anterior (sin copia previa de tu
`settings.json`), lo que queda igual a la plantilla del kit se enumera y se conserva; para quitarlo:
`bash uninstall.sh --kit --settings-plantilla --apply` (solo lo idéntico a la plantilla, con copia previa). Para restaurar un backup anterior a la instalación: `bash uninstall.sh --list` y después `--apply`.

## Diagnosticar

1. `bash kit/doctor.sh`: cada línea es `PASS`, `WARN`, `INFO` o `FAIL`, con su fuente entre paréntesis. Termina con
   `== OK (0 FAIL) ==` o con la lista de fallos. Un FAIL dice qué hacer.
2. Dónde mirar si algo se comporta raro:

| Qué | Dónde |
|---|---|
| Órdenes bloqueadas por `destructive-guard.sh` | `~/.claude/audit-logs/blocked-commands.log` |
| Sentinel y avisos de inyección en herramientas MCP | `~/.claude/audit-logs/sentinel.jsonl`, `narthex.jsonl` |
| Frescura del estado al compactar, compuerta de commit | `~/.claude/session-logs/` (`nucleo-freshness.log`, `gate-nucleo.log`) |
| Estado de cada proyecto | `<proyecto>/.claude/estado/nucleo.md` y su carpeta |
| Qué instaló el kit y con qué suma | `~/.claude/.kit-manifest`, `~/.claude/.kit-version` |

3. Un hook que falla por su cuenta no rompe la sesión salvo los guards, que cierran en falso (bloquean) a propósito.
   Si un hook que no es guard te estorba, quítalo; si es un guard, abre una incidencia con su mensaje.

## Si Claude Code se actualiza y algo se rompe

1. `scc --version` y `bash kit/doctor.sh`: el doctor avisa si tu Claude Code es anterior a la versión mínima probada
   (arriba). Una versión más nueva que la probada puede funcionar; no está garantizado.
2. Aísla el hook: quítalo con el procedimiento de arriba y comprueba si el problema desaparece.
3. Abre una incidencia con la salida de `scc --version`, la de `doctor.sh` y el mensaje del fallo.
4. Mientras tanto, `claude` a secas funciona sin el cockpit: `scc` solo añade los plugins del kit.

## Límite conocido: `CLAUDE_HOME` distinto de `~/.claude`

`CLAUDE_HOME=/otra/ruta bash kit/install.sh --apply` copia el kit a esa ruta, pero los comandos de hooks que escribe en
`settings.json` siguen apuntando a `"$HOME/.claude/hooks/…"` (lo comprobado: instalado con un `HOME` limpio y otro
`CLAUDE_HOME`, `settings.json` cita `$HOME/.claude/hooks/agentes.sh` y esa ruta no existe). Fuera de `~/.claude` los hooks no
se ejecutan: usa `CLAUDE_HOME` solo para ensayar (con `doctor.sh`) y para instalar de verdad deja el valor por defecto.

## Ver también

- [MAPA.md](MAPA.md): qué hace cada hook, orden y variable, y cómo se apaga.
- [SECURITY.md](../../SECURITY.md): qué cubren los guards y qué no.
