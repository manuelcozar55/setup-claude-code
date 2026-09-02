---
name: harness
description: Ejecuta una cola de tareas de forma autónoma y verificada. Úsalo cuando el usuario escriba /harness, diga "procesa las tareas", "ejecuta la cola", "coge la siguiente tarea", o cuando exista un TAREAS.md con tareas pendientes. Lee la especificación, exige un oráculo por tarea, ejecuta aislado, verifica con evidencia y solo pregunta en los puntos de decisión declarados.
---

# Harness: ejecutar una cola de tareas, no responder a un prompt

Un prompt produce una respuesta. Un **lazo** produce un resultado verificado y deja
constancia. Esta skill convierte `TAREAS.md` en trabajo terminado sin supervisión turno a
turno, y **falla ruidosamente** en vez de entregar algo que parezca hecho.

## Las dos reglas que lo gobiernan todo

> **1. Ninguna tarea entra en ejecución sin un oráculo.**

Un oráculo es un **comando** que devuelve 0 si la tarea está bien hecha y ≠0 si no.
No es una opinión, no es "revisar que funcione", no es tu propio juicio al terminar.
Sin oráculo no hay lazo: hay un prompt largo con pasos, que es justo lo que esto sustituye.

Si una tarea no trae oráculo, tienes dos salidas, en este orden:
1. **Derivarlo** si es evidente (hay tests, hay linter, hay un script de arranque) y
   escribirlo en la tarea para que quede.
2. **Preguntar** —una sola vez, agrupado con las demás preguntas— cuál sería la señal
   objetiva de "esto está terminado".

Nunca inventes un oráculo que no puedes ejecutar, y nunca sustituyas el oráculo por tu
propia lectura del código.

> **2. El oráculo es inmutable durante la ejecución de su tarea.**

Esta es la regla que impide el fallo característico de los lazos autónomos: **aflojar el
sensor para poder cerrar la tarea**. Al tercer intento la tentación es relajar un
`assert`, añadir un `-k` que esquive el test que falla, marcar `xfail`, tocar el
`conftest.py` o bajar un umbral. Eso no cierra el lazo: lo rompe, y encima deja el
proyecto peor que antes con apariencia de éxito.

Operativamente:
- **Los ficheros del oráculo no pueden aparecer en tu diff.** Antes de dar una tarea por
  `hecha`, comprueba que los ficheros de test, la configuración de test y el propio
  comando siguen como estaban (`git diff --name-only` no debe tocarlos).
- Si de verdad el test está mal, **eso es otra tarea**: márcala `bloqueada` explicando que
  el oráculo es incorrecto, y deja que se decida fuera del lazo.
- Cambiar el comando del oráculo a mitad de una tarea está prohibido sin excepciones.

## Fases

Ejecuta en este orden. Crea un todo por fase.

### Fase 0 · Cargar la cola y resolver el orden

1. Localiza la cola: `TAREAS.md` en el directorio de trabajo. Si no existe, este es el
   **único** caso en que preguntas fuera de la Fase 1: pide la ruta o propón crearla desde
   `PLANTILLA-TAREAS.md` (en esta misma skill), y termina ahí.
2. Parsea las tareas y admite las de estado **`pendiente` y `en-curso`**.
3. **Reanudación — trata `en-curso` antes que nada.** Una tarea en ese estado es una
   sesión que murió a mitad, y **es el caso normal**, no el excepcional. No la ignores
   nunca: una tarea `en-curso` que nadie recoge deja trabajo a medio aplicar sin que nadie
   lo mire, que es el peor desenlace posible. Para cada una, en este orden:
   - mira el árbol de trabajo (`git status`, `git diff`) para ver qué llegó a aplicarse;
   - ejecuta su oráculo en frío;
   - si pasa → la tarea se completó antes de morir: márcala `hecha` con esa evidencia;
   - si falla → continúa desde ahí, con el presupuesto de intentos **reiniciado**;
   - si el árbol tiene cambios que no sabes atribuir → `bloqueada`, describiendo el diff.
     No adivines sobre trabajo a medio aplicar.
4. **Dependencias.** Si una tarea declara `depende-de: T-00X`, no entra en la pasada
   mientras esa tarea no esté `hecha`. Sácala con `bloqueada: dependencia T-00X`. Sin esta
   regla el harness ejecuta la dependiente igual, gasta sus tres intentos y produce ruido.
5. **Solapes.** Si dos tareas admitidas tocan ficheros que se solapan, ejecútalas
   **estrictamente en secuencia** y corre el oráculo ancho entre ambas. Si no, un fallo de
   la segunda es inatribuible: puede venir de la primera.
6. **Anúnciate**: cuántas tareas hay pendientes, cuáles vas a intentar, cuáles quedan
   fuera y por qué.

### Fase 1 · Puerta de admisión (la única donde preguntas)

Revisa **todas** las tareas admitidas antes de ejecutar ninguna, y reúne en **una sola**
llamada a `AskUserQuestion` todo lo que necesites. Preguntar a mitad de la ejecución
rompe el lazo y devuelve al usuario a la silla de piloto: eso es lo que venimos a eliminar.

Motivos legítimos para preguntar, y no hay más:
- **Falta el oráculo** y no es derivable.
- **El oráculo no se puede ejecutar** (falta el entorno, faltan dependencias). Ojo: «no
  invocable» y «da rojo» son sucesos distintos con desenlaces opuestos. Que un comando no
  arranque **no** es una señal de que el trabajo esté pendiente: es que no hay sensor.
  - Por defecto: **bloquea** la tarea.
  - **Excepción, el caso de arranque:** si la tarea declara `bootstrap: sí`, su objetivo
    *es* dejar el oráculo invocable, así que no poder ejecutarlo al principio es lo
    esperado. Se admite, y el criterio de cierre es que el oráculo **pase a ser
    ejecutable y verde**. Sin este campo, la primera tarea de cualquier proyecto nuevo
    es inadmisible por definición, y la pasada inaugural sale vacía.
- **Ambigüedad que cambia el trabajo**: dos lecturas razonables producen entregables
  distintos. Si las dos producen lo mismo, elige y sigue.
- **Riesgo irreversible**: borrar, sobrescribir, publicar, migrar datos, tocar producción
  o mandar algo al exterior.
- **El proyecto no tiene control de versiones** y la tarea modifica ficheros.

Además, aquí se fija el **presupuesto de tiempo**: mide el oráculo en frío. Si una sola
ejecución ya supera el `timeout` de la tarea (por defecto **5 minutos**), no admitas la
tarea: pide un oráculo más estrecho. El presupuesto real es `timeout × 5`, porque tres
reparaciones son cinco ejecuciones — con un oráculo de 20 minutos, más de hora y media sin
señal. Ese lazo no se puede vigilar.

Todo lo demás lo decides tú y lo declaras en el informe como supuesto.

### Fase 2 · Aislamiento

- **Proyecto con git**: trabaja en una rama o worktree dedicada
  (`superpowers:using-git-worktrees` si aplica). Nunca en la rama por defecto.
- **Proyecto sin git**: si el usuario rechazó `git init` en la Fase 1, **esa decisión
  manda**: no ejecutes tareas destructivas, y para las aditivas haz copia de seguridad de
  cada fichero antes de tocarlo y dilo en el informe.
- **`TAREAS.md` y el aislamiento.** La cola es el estado del lazo, no el producto, y tiene
  que sobrevivir a que se descarte la rama. Dos opciones válidas, y hay que elegir una
  explícitamente al empezar:
  - **preferida**: `TAREAS.md` sin versionar (en `.gitignore`) y editado en su ruta real;
  - si está versionado —compruébalo con `git ls-files --error-unmatch TAREAS.md`—
    mantenlo **dentro** del aislamiento y haz commit en cada transición de estado, para no
    dejar sucio el árbol principal ni provocar conflictos al integrar.

### Fase 3 · Ejecutar una tarea

Por cada tarea:

1. Marca `estado: en-curso` en `TAREAS.md` **antes** de empezar, y persiste el cambio. Ese
   apunte es lo que hace reanudable el lazo (Fase 0.3).
2. **Ejecuta el oráculo en frío.** Para una tarea que entra **por primera vez**
   (`pendiente`): si ya pasa, **marca `bloqueada: oráculo tautológico`** y pasa a la
   siguiente — un oráculo que da verde antes de tocar nada no mide lo que la tarea cambia.
   Dos excepciones: que la tarea declare `idempotente: sí` (entonces `hecha`), o que
   declare `bootstrap: sí` (entonces el verde en frío es justo el objetivo).
   **Las tareas `en-curso` NO pasan por aquí**: ya se resolvieron en la Fase 0.3, donde un
   verde en frío significa que la sesión murió con el trabajo hecho.
3. Haz el trabajo. Explora con herramientas simbólicas antes que leyendo ficheros enteros
   (`mcp__serena__get_symbols_overview`, `find_symbol`); usa `find_referencing_symbols`
   **antes** de cambiar cualquier símbolo compartido, para saber qué se rompe.
4. **Ejecuta el oráculo.** Guarda la salida literal.
5. Si falla: repara y vuelve a 4. **Como máximo 3 reparaciones = 5 ejecuciones del
   oráculo** (1 en frío, 1 tras el trabajo, y 1 tras cada una de las 3 reparaciones).
   Ese 5 es el que hay que multiplicar por la duración al dimensionar el presupuesto de
   la Fase 1. Agotadas, para y marca `bloqueada` con la salida
   del oráculo y tu hipótesis. Insistir más allá no es perseverancia: es un lazo sin
   condición de salida, y es donde aparece la tentación de aflojar el sensor.
6. Si pasa: **comprueba que no has tocado el oráculo** (regla 2), marca los criterios
   cumplidos, pon `estado: hecha`, y anota el comando ejecutado y su resultado.

### Fase 4 · Cierre

1. **Informe único** al final, no narración durante. Por tarea: qué se hizo, qué oráculo la
   cerró y con qué salida, qué supuestos asumiste, y qué queda abierto.
2. Estado final de la cola: hechas / bloqueadas / pendientes.
3. **Nunca declares nada terminado sin la salida del comando delante.** Aplica
   `superpowers:verification-before-completion`.

## Cómo mantener el lazo honesto

| Síntoma | Qué significa | Qué hacer |
|---|---|---|
| Estás a punto de preguntar en Fase 3 | La puerta de admisión falló | Anota el supuesto, sigue, y súbelo a Fase 1 la próxima vez |
| Vas a tocar un test para que pase | Estás aflojando el sensor | Prohibido. `bloqueada`, y que se decida fuera |
| El oráculo pasa en frío en una tarea `pendiente` | No mide lo que la tarea cambia | `bloqueada: oráculo tautológico`, salvo `idempotente`/`bootstrap` |
| Llevas 3 reparaciones | El problema no es el que creías | `bloqueada` + hipótesis, no un cuarto intento |
| El oráculo tarda más que el presupuesto | No se puede vigilar el lazo | Oráculo más estrecho, o fuera de la pasada |
| No sabes cómo verificar | No es una tarea, es un deseo | Devuélvela a Fase 1 |
| Vas a leer entero un fichero que ya editaste | Relectura obsoleta | El contenido en contexto ya refleja tu edición |
| Encuentras una tarea `en-curso` | Una sesión murió a mitad | Fase 0.3, nunca ignorarla |

## Modo continuo

Una pasada: `/harness`.
Cola vigilada: `/loop /harness` — sin intervalo, el lazo se autorregula y decide cuándo
volver. Para tareas que esperan algo externo (un CI, un despliegue), el retardo debe
ajustarse a lo que tarda ese estado en cambiar, no a un sondeo corto.

## Ficheros de esta skill

- `PLANTILLA-TAREAS.md` — el formato de la cola, con ejemplos buenos y malos.
- `referencias/oraculos.md` — doctrina para construir un oráculo, y un inventario **con
  fecha** del estado de los proyectos. El inventario caduca: si la fecha es vieja,
  compruébalo antes de fiarte.
