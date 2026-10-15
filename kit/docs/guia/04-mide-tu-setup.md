# Guía · Mide tu setup

Todo lo de esta guía se puede comprobar en tu máquina. Tres instrumentos, de más rápido a más profundo, y para cada uno qué mirar y qué cifra es razonable. Los objetivos son los que se fijaron tras medir un setup real en 2026; tómalos como punto de partida, no como ley.

## 1 · `/context`: lo fijo por turno (1 minuto)

En una sesión recién abierta, antes de escribir nada, teclea `/context`.

| Partida | Qué mirar | Referencia medida |
|---|---|---|
| Herramientas (esquemas) | la herramienta más grande; servidores MCP que no usas | 25k en un setup cargado |
| Skills | cuántas hay listadas y cuántas has usado este mes | 5,6k con 67 skills |
| Memoria | el índice `MEMORY.md` | 4,5k con 63 líneas largas |
| Instrucciones | `CLAUDE.md` y lo que importa | 3,2k |

**Cómo usarlo:** apunta el total, desactiva una cosa, abre sesión nueva y vuelve a medir. Si la cifra no baja, lo que quitaste no pesaba; si baja y no lo echas de menos en una semana, no vuelve. Ojo: los cambios de configuración se cargan al arrancar; medir en la misma sesión que los hizo no dice nada.

## 2 · Tus sesiones: correcciones, oráculo, compactaciones (5 minutos)

El kit trae [`scripts/cost-report.sh`](../../../scripts/cost-report.sh), que corre `scripts/metrics.py` sobre tus transcripciones (`~/.claude/projects`, o `CLAUDE_PROJECTS_DIR`) y pinta una tabla con tendencia frente a la medición anterior. Guarda cada medición en `METRICS_OUT_DIR`: fíjala a un directorio tuyo para conservar la serie.

```bash
METRICS_OUT_DIR="$HOME/.local/share/cc-metrics" bash scripts/cost-report.sh
```

Lo que más enseña:

| KPI | Por qué importa | Referencia medida |
|---|---|---|
| `% sesiones con retrabajo` | sesiones con alguna corrección; mide cuánto se aclara **antes** | 58 % |
| `% sesiones que corrieron el oraculo` | sin oráculo, «hecho» es una opinión | sube con el hábito |
| `compactaciones` | cada una tira ~88 % del contexto | baja con `/handoff` |
| `herramientas por sesion (mediana)` | cuánto trabajo autónomo hay por sesión | informativo |

## 3 · Compactaciones y estado: `compact-audit.py` y `nucleo_audit.py` (10 minutos)

Dos auditorías sobre las mismas transcripciones, que responden a las dos preguntas de [`01-por-que-contexto.md`](01-por-que-contexto.md): ¿compactas tú o compacta sola?, y cuando compacta, ¿el estado estaba al día?

```bash
python3 scripts/compact-audit.py --since 14   # últimas dos semanas
python3 scripts/nucleo_audit.py
```

| Métrica | Medido en 2026 | Objetivo |
|---|---|---|
| Compactaciones manuales (`/compact`, `/handoff`) | 0 % | ≥ 50 % |
| Compactaciones por sesión larga | hasta 66 en una sola sesión | ≤ 3 |
| Mensajes de la persona entre compactaciones | mediana de 4 | ningún hueco de ≤ 2 |
| Compactaciones con `nucleo.md` escrito en los 20 turnos previos | 25 % | ≥ 80 % |
| Contexto que destruye cada compactación | ~88 %, ~150 s | — (no se arregla: se evita) |

**Cómo leerlo:** si casi todas tus compactaciones son automáticas y llegan con el estado viejo, el problema no es la ventana, es el cierre de fase. Vuelve al [día 3](00-ruta-7-dias.md#día-3--handoff-y-clear-en-vez-de-esperar-a-la-compactación).

## 4 · Lo que cuesta cada hook

Cada llamada a `Bash` pasa por la cadena de guards de `PreToolUse` en serie, y cada guard arranca procesos. Mide un guard con una entrada sintética, en tu máquina:

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"git status"}}' > /tmp/entrada.json
time bash ~/.claude/hooks/block-dangerous-commands.sh < /tmp/entrada.json
```

Si añades un hook propio, mídelo igual antes de dejarlo: un hook en el camino caliente (todas las herramientas, todos los prompts) se paga cientos de veces por sesión. El kit lo dice de su propia cadena en [`05-security.md`](../05-security.md#los-guards-de-bash-y-git).

## Una ficha para repetir cada mes

```text
Fecha:
Fijo por turno (/context):              k
% sesiones con retrabajo:               %
% compactaciones manuales:              %
% compactaciones con estado fresco:     %
Qué cambié desde la última:
```

Si una cifra empeora dos meses seguidos, lo último que añadiste es el primer sospechoso.
