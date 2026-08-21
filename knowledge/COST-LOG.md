# COST-LOG

Registro de los KPIs del harness. **Regla de oro: toda cifra lleva fecha y comando.**
Una métrica sin procedencia verificable es una predicción, no un dato.

Instrumento: `scripts/metrics.py` (absorbido de `~/ai-mastery/bucle/analyze.py`).
Filtro declarado para contar sesiones: se excluye toda ruta que contenga `/subagents/`.
Sin él el denominador se infla ~×5 (189 de 236 transcripts son de subagente).

---

## Baseline v0.1.0 — 2026-08-21T15:45:30Z

Comando: `/usr/bin/python3 scripts/metrics.py`  (ruta absoluta: ver MISTAKES.md · M-001)
Fuente: `$METRICS_OUT_DIR/latest.json` (def. `~/ai-mastery/bucle/data/`)
Informe legible con tendencia: `scripts/cost-report.sh`

| # | KPI | Valor | Dirección | Nota |
|---|---|---|---|---|
| 1a | Retrabajo **por turno** (`rework_turns`/`user_turns`) | **8,8 %** (12 / 136) | ↓ | Lo que medía el instrumento viejo. |
| 1b | **Retrabajo por sesión** (`rework_sessions_pct`) | **19,1 %** (9 / 47) | ↓ | **KPI principal.** Métrica nueva: es la pregunta que el encargo quería hacer. Sigue lejos del 68 % declarado. |
| 2 | Interrupciones | **0** (0,0 %) | ↓ | Cero en la ventana medida. |
| 3 | Coste equivalente-API | 1.934,41 $ · subagentes 31,8 % | ↓ a igual resultado | Equivalente API, no cuota real de suscripción. |
| 4 | Tool calls por sesión | total 3.424 · **mediana 2 · p90 254** | contexto | Métrica nueva. La mediana de 2 refleja el 66 % de sesiones one-shot. |
| 5 | **Sesiones con oráculo ejecutado** | **27,7 %** (13 / 47) | ↑ | **Corrección importante: no era 0.** Nunca se había medido, que no es lo mismo que valer cero. |
| 6 | Contexto fijo | **~2.240 tok** (8.961 chars) | dato único | CLAUDE.md 1.999 + RTK.md 241. Sobre 2,25 B de entrada: 0,0001 %. |

**Filtro declarado en la salida del instrumento** (`filter_applied`): sesiones = `*.jsonl`
bajo `CLAUDE_PROJECTS_DIR` **excluyendo toda ruta que contenga `/subagents/`**; los
transcripts de subagente se contabilizan aparte. Antes esa separación dependía de la
profundidad de dos globs, no de un filtro explícito: frágil y no auditable.

### Adopción (`adoption_pct`)

| Mecanismo | % de sesiones |
|---|---|
| Skills | 29,8 % |
| Subagentes | 25,5 % |
| **Plan mode** | **2,1 %** |

### Dónde va la delegación (150 llamadas a `Agent`)

| Destino | Llamadas | % |
|---|---:|---:|
| `general-purpose` | 105 | **70 %** |
| `deep-worker` | 17 | 11 % |
| `code-reviewer` | 15 | 10 % |
| `?` (sin identificar) | 9 | 6 % |
| `Explore` | 4 | 3 % |

**6 de los 8 agentes propios nunca se han invocado**: `orchestrator`, `strategist`,
`planner`, `quick-checker`, `security-reviewer`, `code-explorer`.

### Skills: 12 invocadas de 18 instaladas

Las cuatro más pesadas del disco suman **5,0 MB (94 % del total) y 2 invocaciones**:
`ui-ux-pro-max` 1,62 MB → 0 · `taste-skill` 87 KB → 0 · `graphify` 85 KB → 0 ·
`emil-design-eng` 27 KB → 0 · (`impeccable` 3,26 MB → 2).

### MCP: `serena` 4 · `firecrawl` 4 · `headroom` 0 · `linkedin` 0

### Slash commands: `/clear` 5 · `/model` 3 — ninguno de flujo de trabajo

### Latencia de la cadena de hooks (medida, 3 pasadas, mejor tiempo)

| Hook PreToolUse/Bash | ms |
|---|---:|
| `block-dangerous-commands.sh` | 58 |
| `sentinel_preflight.py` | 27 |
| `smart_approve.py` | 23 |
| `rtk hook claude` | 23 |
| `destructive-guard.sh` | 14 |
| `branch-guard.sh` | 9 |
| `secret-guard.sh` | 9 |
| **cadena completa, por comando Bash** | **160** |

Idéntica en ext4 y en `/mnt/c` (160 vs 163 ms): **los guards no ejecutan `git status`**,
así que no pagan la latencia del FS de Windows.
Acumulado en la ventana: 5.955 llamadas Bash × 160 ms ≈ **15,9 min**.
Otros: Stop/`impeccable` **108 ms** (timeout configurado 30 s) · `session-start.sh` 108 ms ·
`preflight.sh` 409 ms (timeout 15 s).

---

## Los KPIs heredados del encargo no son reproducibles

Se archivan como **históricos sin procedencia verificable** (contrato §0.2).

| KPI declarado en el encargo | Instrumento hoy | Diagnóstico |
|---|---|---|
| Correcciones **68 % de sesiones** (48 sesiones) | **19,1 % de sesiones** / 8,8 % de turnos (47 sesiones) | Ya medimos la métrica correcta, y aun así no da 68 %. El instrumento viejo solo emitía la de turnos, lo que explica de dónde salía la confusión, pero no de dónde salía el 68. |
| Interrupciones 14 % (17 en 6) | 0 | No reproducible. |
| Tool calls mediana 109 / p90 460 | **mediana 2 / p90 254** | Ya se calculan. No coinciden. |
| Encargos: mediana 520 ch / p90 19.363 | **142** / **798** | Un orden de magnitud de diferencia. |
| Contexto fijo ~2.200 tok sobre 2,09 B | ~2.240 tok sobre 2,25 B | ✅ el único que cuadra. |

**Consecuencia:** la línea base de mcharness es la de arriba, con su sello temporal.
Los objetivos se fijan contra ella, no contra las cifras heredadas.

---

## Formato de fila para las sesiones siguientes

```
fecha | sesión | modelo | turnos | correcciones | tool calls | oráculo ejecutado (sí/no + comando) | técnica aplicada
```

| fecha | sesión | modelo | turnos | corr. | tools | oráculo | técnica |
|---|---|---|---|---|---|---|---|
| 2026-08-21 | mcharness v0.1.0 | opus-5 | — | 1 (rechazo de ejecutar la suite ajena) | — | **sí** · `make test` → exit 0, 22 s | backup falsable, baseline sellada, canal de sensado caracterizado |
