# TAREAS · plantilla

Cola de trabajo del proyecto. La lee `/harness`. **Este fichero es el estado del lazo**:
sobrevive a que se cierre la sesión, a un compact y a que te vayas a comer. Si el estado
solo vive en la conversación, no tienes un lazo, tienes una charla.

**Ninguna tarea de este fichero es ejecutable: todas son didácticas.** Copia el bloque del
final para escribir las tuyas.

Estados: `pendiente` · `en-curso` · `hecha` · `bloqueada`

Campos:

| Campo | Obligatorio | Para qué |
|---|---|---|
| `estado` | sí | El harness admite `pendiente` y `en-curso` (esta última se reanuda) |
| `oráculo` | sí | El comando que devuelve 0 cuando está hecho |
| `riesgo` | sí | `bajo` / `medio` / `alto`. `alto` nunca va sin confirmación |
| `timeout` | no | Presupuesto por ejecución del oráculo. Por defecto 5 min |
| `depende-de` | no | La tarea no entra en la pasada hasta que esa esté `hecha` |
| `idempotente` | no | `sí` solo si es correcto que el oráculo ya pase antes de empezar |
| `bootstrap` | no | `sí` cuando el objetivo de la tarea *es* dejar el oráculo invocable. Sin esto, la primera tarea de un proyecto sin entorno es inadmisible |

---

## EJEMPLO A · tarea bien especificada (didáctica, no ejecutar)

- estado: bloqueada
- oráculo: `pytest tests/test_extractor.py -q`
- riesgo: bajo
- timeout: 2min
- criterios:
  - [ ] `extraer_cif()` devuelve `None` en vez de lanzar cuando el texto no trae CIF
  - [ ] hay un test que **falla sin el arreglo** y pasa con él

Por qué está bien: el oráculo es **un comando ejecutable y estrecho**, los criterios son
**observables desde fuera**, y el segundo criterio obliga a que el test pueda dar rojo —
un oráculo que nunca ha fallado no mide nada.

---

## EJEMPLO B · tarea mal especificada (didáctica, no ejecutar)

- estado: bloqueada
- oráculo: —
- riesgo: —
- criterios:
  - [ ] mejorar el rendimiento
  - [ ] que quede más limpio

Por qué el harness la rechaza en la puerta de admisión: **«mejorar» y «más limpio» no
tienen función de parada.** No hay ningún comando que devuelva 0 cuando estén cumplidos,
así que el lazo no puede cerrarse: se detendría cuando tú te cansaras de mirar, que es
exactamente el trabajo que querías delegar.

Reparable así: *oráculo* `pytest -q && python bench.py --max-ms 800`, *criterio* «el bench
baja de 800 ms en la máquina de referencia».

---

## Cómo escribir el oráculo

Responde a: **¿qué comando ejecutaría yo para convencerme de que está hecho?**

| Tipo de tarea | Oráculo típico |
|---|---|
| Corregir un bug | Un test que falla ahora y pasa después |
| Añadir una función | `pytest tests/test_nuevo.py -q` |
| Refactor sin cambio de comportamiento | La suite entera: `pytest -q` |
| Script o CLI | `bash verificar.sh` con entradas de ejemplo y salida esperada |
| Datos / informe | Un comprobador que valide el artefacto producido |
| Infraestructura | Un `curl` al health-check, o `systemctl is-active` |

Alcance: **bucle de reparación con el oráculo estrecho** (segundos), **verificación de
cierre con el ancho** (la suite). Al revés, el lazo se ahoga esperando.

Si de verdad no hay comando posible (diseño visual, redacción), el oráculo es una
**revisión con criterios explícitos**: quién revisa, contra qué lista, y qué se considera
un fallo. Escríbelo igualmente. Un criterio escrito antes de empezar es un oráculo débil;
un criterio inventado al terminar es una excusa.

Y recuerda la regla que protege al sensor: **el oráculo es inmutable mientras se ejecuta
su tarea.** Si hay que cambiar el test, eso es otra tarea.

---

<!--
Copia desde aquí para una tarea nueva:

## T-00N · Título corto en imperativo

- estado: pendiente
- oráculo: `comando que devuelve 0 si está hecho`
- riesgo: bajo | medio | alto
- timeout: 5min
- depende-de: (opcional)
- criterios:
  - [ ] criterio observable desde fuera
  - [ ] otro criterio observable

Descripción libre: qué pasa hoy, qué debe pasar.
-->
