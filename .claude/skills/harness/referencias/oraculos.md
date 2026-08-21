# Oráculos

Dos partes: **doctrina**, que no caduca, e **inventario**, que sí. Si la fecha del
inventario es vieja, vuelve a medirlo antes de fiarte — la puerta de admisión del harness
no debe decidir con datos rancios.

---

# Parte 1 · Doctrina

## Qué cuenta como oráculo

Un comando que devuelve **0 si la tarea está hecha** y **≠0 si no**. Tres propiedades
imprescindibles, y las tres se comprueban, no se suponen:

1. **Ejecutable aquí y ahora.** Un oráculo declarado que no se puede invocar —falta el
   entorno, faltan dependencias— no es un oráculo. No se descubre hasta que lo ejecutas en
   frío. Y cuando lo pruebes, **usa el intérprete que manda el proyecto o el `CLAUDE.md`**,
   no el primero del `PATH`: en esta máquina, probar con `python3` en vez de con
   `~/.venvs/tools/bin/python3` produjo un diagnóstico de "no hay ningún oráculo
   ejecutable" que era rotundamente falso.
2. **Capaz de dar rojo.** Si pasa antes de tocar nada, no mide lo que la tarea cambia.
   El harness lo marca `bloqueada: oráculo tautológico`.
3. **Inmutable durante su tarea.** Si el ejecutor puede modificar el sensor, el lazo se
   cierra siempre y no significa nada. Ver la regla 2 de `SKILL.md`.

## Alcance: estrecho para reparar, ancho para cerrar

| Alcance | Cuándo | Coste típico |
|---|---|---|
| El test que reproduce el fallo | Bucle de reparación | Segundos |
| El fichero de tests del módulo | Función nueva | Decenas de segundos |
| La suite entera | Refactor, o cierre de la cola | Minutos |

Un oráculo cuya ejecución supera el presupuesto de la tarea (5 min por defecto) no se
puede usar en un bucle: **tres reparaciones son cinco ejecuciones** (una en frío, una tras
el trabajo, y una tras cada reparación). El presupuesto real es `timeout × 5`.

## Cuando no hay comando posible

Para diseño visual, redacción o decisiones de producto no existe `exit 0`. El oráculo es
entonces **una revisión con criterios escritos antes de empezar**: quién revisa, contra
qué lista, y qué cuenta como fallo. Es un sensor débil, y hay que decirlo. Lo que **no**
vale es que el propio ejecutor declare terminado su trabajo leyendo lo que acaba de
escribir.

---

# Parte 2 · Inventario · medido 2026-08-21

**Metodología** (declararla importa: cambiarla cambia las cifras): `find` sobre el
proyecto excluyendo `.venv/`, `node_modules/` y `.claude/worktrees/`; «casos» cuenta
`def test_` en ficheros `test_*.py`.

| Proyecto | git | .py | ficheros test | casos | Oráculo |
|---|---|---|---|---|---|
| `circe-brain/circe-prospector` | sí | 325 | 207 | 975 | `pytest tests/ -q` — **funciona: 982 recogidos en 20 s** |
| `sistema-riego` | sí | 118 | 39 | 432 | `pytest -q` (`pytest.ini` + `pyproject.toml`) — sin comprobar |
| `ofertadora` | **NO** | 252 | 9 | 58 | `cd lab && pytest -q` (`lab/pytest.ini`) — sin comprobar |
| `tfm-agent-system` | sí | 24 | 6 | 48 | `pytest -q` — sin comprobar |

**Con qué intérprete:** `~/.venvs/tools/bin/pytest` (9.1.1), que es el que impone el
`CLAUDE.md` del usuario y trae ya las dependencias de circe-prospector. El `python3` del
sistema no tiene pytest, y confundir ambos lleva a un diagnóstico falso.

`circe-brain` (raíz) es un contenedor, no un proyecto: el código versionado es
`circe-prospector`.

## Lo que falta no es un oráculo, es reproducibilidad

**Ningún proyecto tiene entorno propio** (cero venvs en los cuatro), pero eso **no** deja
la máquina sin oráculos: el venv compartido de herramientas ejecuta la suite de
circe-prospector hoy mismo. Lo que se pierde es la reproducibilidad — el oráculo funciona
por coincidencia de dependencias, no por declaración, y cualquier cambio en ese venv puede
romperlo en silencio. Se puede empezar a automatizar ya; conviene fijar el entorno pronto.

```bash
# OJO: `uv venv` NO siembra pip (verificado con uv 0.12.1). Sin --seed, el
# segundo comando falla con "No such file or directory".
uv venv .venv --seed && .venv/bin/pip install -r requirements.txt
# alternativa sin pip en el venv:
uv venv .venv && uv pip install --python .venv/bin/python -r requirements.txt
```

Para `circe-prospector`, el propio `requirements.txt` documenta el resultado esperado:

> *"Dependencias con import a NIVEL DE MÓDULO: sin ellas no arranca ni la recolección de la
> suite (medido 2026-08-04: `pytest tests/ -q` con solo pytest+numpy → 104 errores de
> colección; con esto → 778 passed)."*

**Esa cifra es una predicción heredada, no una medición de esta máquina**: procede de un
comentario fechado el 2026-08-04 en otro equipo. Hoy se **recogen 982 tests** de los 975
`def test_` declarados (la diferencia son casos parametrizados). Usa el recuento real, no
el 778.

Nota de rendimiento: los cuatro proyectos viven en `/mnt/c` (sistema de ficheros de
Windows vía WSL2), donde las suites grandes van varias veces más lentas. Mide antes de
elegir el oráculo de una tarea.

## `ofertadora`: el riesgo es la ausencia de git, no la de tests

Tiene suite —9 ficheros, 58 casos, con `lab/pytest.ini` (`--strict-markers` y marcadores
`regresion`, `propiedad`, `llm`, `db`) y tests de caracterización y de regresión sobre
incidentes de producción—, así que **sí tiene función de parada**.

Lo que no tiene es **marcha atrás**: 252 ficheros Python sin control de versiones. Un lazo
que se equivoca ahí no se revierte, se pierde. Por eso el harness no ejecuta tareas
destructivas en este proyecto mientras no exista un repositorio.

```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/ofertadora
git init && git add -A && git commit -m "línea base antes de automatizar"
```
