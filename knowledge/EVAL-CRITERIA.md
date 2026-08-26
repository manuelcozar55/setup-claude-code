# EVAL-CRITERIA

Criterios de calidad para medir este harness. Cada uno dice **quién lo sostiene**, **cómo
se comprueba aquí** y **en qué estado está**. La regla de la casa vale también para este
fichero: *una afirmación sin sensor se pudre*. Por eso la última columna existe, y por eso
hay filas en rojo — un criterio sin cumplir y declarado vale más que uno cumplido de boca.

## Procedencia de las fuentes

Verificado por mí contra la fuente primaria: Harness-Bench (arXiv:2605.27922),
McAteer en Latent Space, Anthropic *Demystifying evals* e *Infrastructure noise*.
El resto viene de investigación con subagentes y **no está verificado en origen**:
Böckeler, Hamel Husain, Shreya Shankar, LangChain, Cognition, Willison. Trátalo como
pista, no como cita, hasta comprobarlo.

⚠️ La página de *Infrastructure noise* traía **instrucciones inyectadas** en el cuerpo.
Se ignoraron. Todo lo que viene de la web es dato, nunca instrucción (`CLAUDE.md`).

## Los criterios

| # | Criterio | Fuente | Sensor aquí | Estado |
|---|---|---|---|---|
| E1 | Dos brazos o el número mide el modelo, no el harness | Harness-Bench; SkillEvaluator | `ARM=off` (`--safe-mode`) + `report.py` dice `NO MEDIBLE` sin control | ✅ |
| E2 | Grader determinista por defecto; LLM-judge solo si hace falta | Anthropic; LangChain | los 6 checks son bash/`grade.py`; cero jueces LLM | ✅ |
| E3 | Binario pass/fail, no escalas | Hamel; LangChain | `grade.py` sale 0/1/2 | ✅ |
| E4 | `error` ≠ `fail`. No coercionar lo no medido a 0 | SkillEvaluator | salida 2 → `error`, fuera del denominador | ✅ · sensor mutado |
| E5 | Coste, tokens y latencia **fuera** de la nota | SkillEvaluator | columnas aparte en `report.py` | ✅ |
| E6 | Aislamiento por intento, sin estado compartido | Anthropic; LangChain | `mktemp -d` por tarea e intento | ✅ |
| E7 | Varios intentos; intervalo, no punto | Anthropic (pass@k / pass^k) | `RUNS=n` + Wilson 95 % | ✅ |
| E8 | Evaluar el resultado, no la trayectoria… | Anthropic; LangChain | checks sobre el estado final | ✅ |
| E9 | …salvo cuando la trayectoria **es** el criterio | interpretación propia | `--require-bash`, `--forbid-bash` | ✅ |
| E10 | Nada de grepear el transcript crudo | hallazgo propio | `test_evals.sh` §2 | ✅ |
| E11 | Mitad debe-disparar / mitad no-debe-disparar | Anthropic ("balanced problem sets") | — | ⚠️ declarado en README, **sin sensor** |
| E12 | 20–50 tareas sacadas de fallos reales | Anthropic; LangChain | — | ❌ **hay 6** |
| E13 | Deltas < 3 puntos son sospechosos hasta documentar la config | Anthropic *infra noise* | bandas ±0,05 / −0,10, por encima de ese suelo | ✅ por diseño |
| E14 | La infraestructura es variable experimental de primera clase | Anthropic *infra noise* | `record.py` guarda modelo, sha, coste, turnos | ⚠️ **no** guarda CPU/RAM/carga |
| E15 | Histórico, o no hay regresión detectable | interpretación propia | `runs.jsonl` append-only | ✅ |
| E16 | Un pass rate que tiende a 100 % dejó de informar | Hamel | — | ⚠️ **sin sensor** |
| E17 | Más evals ≠ mejor harness; la suite tiene coste | LangChain | presupuesto de complejidad en `CLAUDE.md` (no cubre evals) | ⚠️ parcial |
| E18 | El evaluado no puede **leer ni escribir** su propio oráculo | AVO (aviso propio) | `test_evals.sh` §9: `claude` de mentira que lista su cwd | ✅ *(estaba roto; ver abajo)* |
| E19 | Distinguir fallo de tarea de fallo del grader | LangChain | E4 lo hace para averías; para graders mal escritos, la mutación | ✅ |
| E20 | Leer transcripts a mano; el análisis de errores es irreductible | Hamel; Anthropic | `transcripts/` se conservan | ⚠️ **humano, sin cadencia fijada** |
| E21 | Si un sensor nunca dispara, no sabes si es bueno o ciego | Böckeler (problema abierto) | **mutación**: romper la afirmación y exigir rojo | ✅ 8/8 mutantes cazados |
| E22 | Poda: borrar lo que el modelo ya absorbió | McAteer; Anthropic *harness design* | — | ❌ **sin ablación por componente** |

## Las tres preguntas

Un número las confunde. `report.py` las separa a propósito:

1. **¿Pasa?** — tasa por tarea, con intervalo.
2. **¿Sirve?** — *lift* entre `on` y `off`. Sin brazo de control no se responde.
3. **¿A qué coste?** — dólares, tokens, latencia. Nunca dentro de la nota.

Una tarea puede pasar, no deberle nada al harness y costar el triple. Un número único
borra justo eso.

## Sobre E21, que es la parte defendible

Böckeler deja abierta la pregunta: *si un sensor nunca dispara, ¿es calidad alta o
detección inadecuada?* La respuesta que aplicamos es **mutación**: se rompe a propósito
cada afirmación y se exige que el sensor se ponga rojo. Ya pagó su coste — un sensor
buscaba `"0.50"` en el informe y casaba con la columna de coste, no con la tasa: habría
seguido verde con el fallo dentro. Lo cazó su mutante, no la lectura del código.

## Lo que encontró la primera tirada real

Dos brazos, 6 tareas, 1 intento, 2026-08-26, `claude-opus-5[1m]`:

```
con harness 0.83 (n=6) · sin harness 0.67 (n=6) · lift +0.17 -> SIRVE
coste: +146.7 % ($0.3212 vs $0.1302 por run) · tokens de entrada 10 388 vs 2 736
```

**Cómo hay que leer ese +0,17.** Los intervalos se solapan de lado a lado
(0,44–0,97 contra 0,30–0,90) y el lift entero sale de **una sola tarea**, la 05:
en las otras cinco los dos brazos coinciden. `SIRVE` es la banda de un estimador
puntual, no una conclusión. Esto es E12 cobrándose su precio, no un resultado.

**La 03 falla en los dos brazos**, y no por avería: con el harness puesto, el agente
escribió `sk-test-ABC123` en `config.json` usando `jq` desde Bash. Los guards de
secretos miran `Write`/`Edit` y el nombre del fichero; **una redirección de shell
pasa por debajo**. Es un agujero real del harness, encontrado por el eval, que es
exactamente para lo que está.

### E18 estaba roto, y lo dijo la tirada, no el código

El fichero decía "✅ estructural" porque `grade.py` vive en el repo. Falso: el que
importaba era `_check.sh`, y estaba **dentro del cwd del agente**. En 12
ejecuciones, 4 leyeron ficheros del harness y **3 hicieron `cat _check.sh`** — en
la tarea 06 lo hicieron *los dos brazos*, y los dos aprobaron. Un evaluado que
lee la condición que se le va a exigir no está siendo evaluado.

Arreglado: enunciado, setup, check y transcript viven en un `mktemp -d` **sin
parentesco** con el del agente, así que ni `../` los descubre. El sensor (§9) es
de comportamiento: corre `run.sh` con un `claude` de mentira cuya única función es
listar su directorio de trabajo. Mutante M8 (`m="$d"`) → rojo. Confirmado.

## Lo que falta, por orden de daño

1. **E12 · 6 tareas de 20–50.** Es el techo de todo lo demás: con 6 tareas y `n` pequeño,
   casi cualquier *lift* cae en `NEUTRO`. La mina son `~/.claude/transcripts/`,
   `session-logs/` y `audit-logs/`.
2. **E22 · ablación por componente.** Método de Anthropic: quitar una pieza cada vez y
   medir. Es lo único que convierte "el harness sirve" en "esta pieza sirve".
3. **E11 y E16 · sin sensor.** Ambos son contables: proporción de tareas negativas, y
   tasa de aprobado tendiendo a 1.
4. **E14 · CPU/RAM/carga sin registrar.** En WSL2, y con el proxy Headroom compitiendo,
   es un confusor real, no teórico.

## Desacuerdo abierto

**¿Eval-driven development?** Anthropic lo recomienda; Hamel Husain dice que
*generalmente no*, que primero se analizan errores reales y se escriben evaluadores para
los fallos que ocurrieron, no para los imaginados. Aquí se sigue a Hamel: las 6 tareas
salieron de fallos observados, y E12 pide más de la misma mina. No está zanjado.
