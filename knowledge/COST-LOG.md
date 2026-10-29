# COST-LOG

Registro de los KPIs del harness. **Regla de oro: toda cifra lleva fecha y comando.**
Una métrica sin procedencia verificable es una predicción, no un dato.

Instrumento: `scripts/metrics.py` (absorbido de `~/ai-mastery/bucle/analyze.py`).
Filtro declarado para contar sesiones: se excluye toda ruta que contenga `/subagents/`.
Sin él el denominador se infla ~×5 (192 de 239 transcripts son de subagente, según
`subagents.transcripts` del propio snapshot).

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

### Segunda medicion 2026-10

Fuente: `metrics-2026-10-20.json` (`generated_at` 2026-10-20T11:55Z; idéntico a `latest.json`) frente a `metrics-2026-08-21.json`. `scripts/cost-report.sh` ya imprime el delta entre snapshots.

| fecha | snapshot | sesiones | `sessions_with_oracle_pct` | `rework_sessions_pct` | nota |
|---|---|---|---|---|---|
| 2026-08-21 | metrics-2026-08-21.json | 47 | 27,7 % (13) | 19,1 % (9) | Línea base. |
| 2026-10-20 | metrics-2026-10-20.json | 141 | **40,4 %** (57) | 7,1 % (10) | +12,7 pp en `sessions_with_oracle_pct`. Definición por literal de comando (`make test`, `pytest`, `shellcheck`, `gitleaks`, CLI `oraculo`); no comparable con M2 (rc visto, no literal). |

---

## Contexto de arranque, línea base (ADR 018) — 2026-10-20

Comando: `bash scripts/contexto-base.sh` (inventario, sin red) y `bash scripts/contexto-base.sh --pagar` (primer turno real).
`claude` 2.1.304 · modelos `claude-haiku-5-5` (cuatro corridas) y `claude-opus-5-5` (una) · base `81dbdb6`.
Inventario: dos ejecuciones, `diff` vacío. Gasto de la medida: 0,11 USD con las corridas de diagnóstico.

### Por canal (peor caso razonable, `nucleo.md` de 8 KB)

| Canal | Caracteres | Bytes |
|---|---:|---:|
| Instrucciones globales (`CLAUDE.md` + `@AGENTS.md`) | 5.460 | 5.548 |
| SessionStart startup / clear (`session-start-clear.sh`) | 5.199 | 5.224 |
| SessionStart resume (con aviso de caché caducada) | 5.366 | 5.394 |
| SessionStart compact | 3.935 | 3.940 |
| SessionStart memoria (`session-start.sh`, sin memoria) | 76 | 76 |
| PostToolUse `nucleo-nudge` (airbag 85 %) | 348 | 351 |
| Stop `stop-context-gauge` (≥ 60 %) | 249 | 249 |
| UserPromptSubmit | 0 | 0 |
| Agentes: suma de las 8 `description` | 2.303 | 2.309 |
| Skills: suma de las `description` (retro y to-questionnaire no cuentan: `disable-model-invocation`) | 758 | 758 |

Los tres canales que más pesan: instrucciones globales (5.460), SessionStart con `nucleo.md` (5.199) y las
descripciones de agentes (2.303). startup, clear, resume y compact son eventos alternativos: no se suman.
Límites del inventario: el `nucleo.md` sintético (8.192 B, cuatro commits) no es el peor caso del test de
`nucleo.sh` (8.677 chars); `write-guard`, `stale-read-guard` y `narthex-post-mcp` solo avisan ante un evento
concreto y no se miden aquí.

### Primer turno real (`claude -p`, prompt «Responde solo: ok»)

Tokens de entrada = `input + cache_creation + cache_read`.

| Configuración | Modelo | Tokens de entrada | `total_cost_usd` |
|---|---|---:|---:|
| sin kit (`--safe-mode`) | haiku | 15.113 | 0,0008 |
| con kit (proyecto, `--setting-sources project`) | haiku | 20.634 | 0,0023 |
| con kit + `nucleo.md` lleno | haiku | 23.383 | 0,0030 |
| con kit | opus | 19.458 | 0,0830 |
| configuración viva de quien mide, sin aislar (no reproducible) | haiku | 29.631 | 0,0041 |

Deltas: el kit añade 5.521 tokens sobre «sin kit»; el `nucleo.md` lleno, 2.749 más. Con opus la misma
configuración da 19.458 frente a 20.634 en haiku (×0,94). El coste de haiku sale bajo porque ~9,7 k tokens
del prefijo vienen de caché; el de opus es una sola corrida con prefijo casi sin caché.

Aislamiento: `CLAUDE_CONFIG_DIR` vacío pide login (las credenciales no se copian), así que «con kit» carga el
kit instalado con `install.sh` en un `CLAUDE_HOME` de `mktemp` como **proyecto** y con `--setting-sources
project`; los hooks corren con `HOME` de `mktemp`. Comprobado: sin plugins ni MCP ni skills del usuario, y el
modelo solo cita la política gestionada y el `CLAUDE.md` del kit. **La política gestionada de
`/etc/claude-code/` (incluido su `CLAUDE.md`) está en todas las cifras**, también en «sin kit»; Debian sin ella
dará el número limpio. `--safe-mode` y `--setting-sources` son los modos de la 2.1.304.

### Presupuesto por canal, después (ADR 018, W4b) — 2026-10-20

Sin recortes: la medida no señala ninguno que se pueda hacer sin tocar reglas (no hay duplicados exactos entre
`CLAUDE.md` y `AGENTS.md`; seguridad y triggers de `description` no se tocan), así que no hay corrida de pago.
`test_presupuesto_contexto.sh` mide con `contexto-base.sh --peor`: `nucleo.md` de 24 KB (los topes de `nucleo.sh`
lo recortan), repo con ruta de ~200 chars, dueño ajeno, tareas sucias, checkpoint de compact y la entrada que
dispara cada guard. Tope = medida + 10 %, subido a la centena (SessionStart: 9.500, el de `nucleo_tope`).
`systemMessage` (aviso de caché caducada) no cuenta en SessionStart: lo ve la persona, no el modelo.

| Canal (caracteres) | W4a, 8 KB | Ahora, 8 KB | Peor caso | Tope |
|---|---:|---:|---:|---:|
| Instrucciones globales | 5.460 | 6.233 | 6.233 | 6.900 |
| SessionStart compact | 3.935 | 4.221 | 9.488 | 9.500 |
| SessionStart startup / clear / resume | 5.199 / 5.199 / 5.366 | 5.199 / 5.199 / 5.199 | 9.488 | 9.500 |
| SessionStart memoria | 76 | 76 | 76 | 100 |
| PostToolUse `nucleo-nudge` | 348 | 348 | 535 | 600 |
| Stop `context-gauge` | 249 | 316 | 316 | 400 |
| write-guard (fichero nuevo >150 líneas / secretos, deniega) | — | 206 / 289 | 393 / 476 | 500 / 600 |
| stale-read-guard | — | 502 | 689 | 800 |
| narthex (15 frases + invisibles) | — | 1.196 | 1.196 | 1.400 |
| Agentes: suma / mayor `description` | 2.303 / — | 2.303 / 392 | 2.303 / 392 | 2.600 / 500 |
| Skills: suma | 758 | 758 | 758 | 900 |
| Bloque de agentes (W3) | — | — | — | 800 (SKIP hasta fusionar W3) |

De W4a a hoy las instrucciones globales suben 773 chars: ~510 de la oleada 1 (reglas de estado, dónde se escribe
cada cosa) y 260 de la sección «Delegación». resume ya no suma el aviso de caché (antes 5.366). El tope de
SessionStart del peor caso (9.488) queda a 12 chars del de `nucleo_tope`: cualquier texto nuevo allí lo recorta la cola.
Propuesta (no aplicada): si hay que recortar, el candidato es el protocolo de arranque de `session-start-clear.sh`
(~1.100 chars), no las instrucciones globales.
