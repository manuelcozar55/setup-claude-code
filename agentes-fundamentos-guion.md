# Guion - "Ingeniería de agentes: el mapa antes de mi setup"

**Duración objetivo:** 17-20 minutos (calentamiento; el deck de setup dura 20) · **Registro:** técnico, directo, de tú a tú · **Público:** tu jefe, un manager técnico
**Compañero visual:** `agentes-fundamentos.html` (una sección por bloque)
**Regla que repites al cerrar:** esto es el mapa; ahora te enseño el territorio, con las cifras reales de mi máquina.

> **Cómo usar este guion.** Cada bloque tiene un objetivo, el texto real que dices en voz alta (léelo casi tal cual, no es un esquema), la frase-gancho que quieres que se lleve tu jefe, y lo que señalas en pantalla. Los tiempos entre corchetes son tu presupuesto: si te pasas en un bloque, recórtalo en el siguiente, nunca en el cierre. Esta charla no tiene demos ni comandos: es el mapa conceptual. Las cifras vienen después, en el segundo deck.

---

## Bloque 0 · El cambio de mentalidad - Hero + Sección 01 [0:00–2:00]

**Objetivo:** que tu jefe entienda en dos minutos la tesis: hemos dejado de escribir prompts y hemos pasado a diseñar la máquina que rodea al modelo, y que el valor está en las capas de abajo, no en el prompt.

**Guion hablado:**
> Antes de enseñarte cómo tengo montado mi entorno, quiero darte el mapa de cómo se construye hoy un agente de IA de producción. Y lo primero que te quiero quitar de la cabeza es que esto va de encontrar el prompt perfecto. Ya no. El prompt sigue estando, pero es una pieza pequeña dentro de un sistema mucho mayor. El trabajo de verdad es diseñar el programa que rodea al modelo.
>
> El modelo mental es de Karpathy y te va a sonar porque es de arquitectura de computadores: el LLM es la CPU, potente pero inerte sin un programa que la dirija; el contexto es la RAM, finito, se llena, y hay que gestionarlo con cuidado; y el agente es el programa, el harness que orquesta a los dos y decide qué entra, qué sale y qué se hace. Sobre esa idea, el trabajo sube por una escalera de cuatro peldaños: prompt, contexto, harness y loop. Y cuanto más arriba subes, más determina el resultado.
>
> Por eso el principio de la disciplina es "design the loop, not the prompt": diseña el bucle, no el prompt. Y aquí está lo que a ti te importa: si el equipo solo optimiza prompts, toca techo enseguida. El valor real, y la ventaja difícil de copiar, está en las capas de ingeniería de abajo. En esta charla te enseño esas capas, son diez, y al final te enseño cuáles tengo montadas yo.
>
> Y que no te suene a teoría mía: este mismo mapa lo usan las plataformas serias de agentes. LangChain, por ejemplo, describe al modelo con la misma imagen de Karpathy, CPU y RAM, y llama a lo que hay debajo del prompt "ingeniería de contexto", que definen como la habilidad más importante que puede desarrollar un ingeniero de IA. Cuando dos sitios que no se copian llegan al mismo dibujo, es que el dibujo describe algo real.

**Frase-gancho:** "Si solo tocas prompts, tocas techo. El valor está debajo."

**Lo que señalas en pantalla:** el hero con la tesis "El prompt ya no es el trabajo" y la frase "Design the loop, not the prompt"; luego el diagrama de la sección 01, la CPU/RAM (LLM = CPU, contexto = RAM, dentro del marco del harness) y la escalera de cuatro peldaños con el último, loop engineering, resaltado.

---

## Bloque 1 · El motor - Sección 02, pilares 1-3 [2:00–5:30]

**Objetivo:** que entienda que, antes de darle capacidades al agente, hay que construir la máquina que lo ejecuta de forma fiable, y que esas tres primeras capas compran fiabilidad, coste acotado y calidad.

**Guion hablado:**
> El primer bloque es el motor: la máquina que ejecuta al modelo de forma previsible. Son tres capas por debajo del prompt. La primera es el harness, el entorno. Es todo el andamiaje que rodea al modelo para que corra sin caerse: reintentos cuando una llamada falla, aislamiento en sandbox, límites de coste y degradación elegante cuando una herramienta se rompe. No cambia lo que el modelo dice; cambia si el sistema aguanta en producción. Y eso a ti te importa porque es fiabilidad y facturas bajo control: el sistema no se cae cuando una pieza falla.
>
> La segunda capa es el loop, el bucle. Un agente no es una respuesta, es un ciclo que razona, actúa y observa hasta cumplir el objetivo, y vuelve a empezar. La ingeniería aquí está en las condiciones de parada y, sobre todo, en el presupuesto máximo de iteraciones, para que no se dispare. Aquí lo que compras es previsibilidad y coste acotado: sin bucles infinitos que queman dinero, y sabiendo cuándo termina.
>
> Y la tercera es el contexto. La ventana del modelo es finita, esa RAM de la que hablábamos, y todo lo que metes compite por el mismo espacio. La decisión es qué entra en la ventana y qué se recupera bajo demanda, cómo se comprime el historial, y cómo evitas el "context rot", que es la degradación de los contextos demasiado largos. Esto es calidad de las respuestas y coste por llamada, y que el agente no se atonte en las tareas largas.
>
> Y esto no me lo invento: LangChain, que construye agentes de producción, publica un artículo entero sobre "loop engineering", ingeniería del bucle, con la misma tesis que te acabo de dar: el potencial de un agente está en los bucles que construyes a su alrededor, no en el modelo. Van más lejos incluso: describen cuatro bucles apilados, el del agente, el de verificación, el que disparan los eventos y el de mejora, y lo resumen así, los tres primeros automatizan el trabajo y el cuarto automatiza la mejora. Sobre el contexto, la misma gente lo define como llenar la ventana con la información justa en cada paso, con cuatro jugadas: escribir fuera de la ventana, seleccionar, comprimir y aislar.

**Frase-gancho:** "El motor no cambia lo que el modelo dice; cambia si aguanta en producción."

**Lo que señalas en pantalla:** el pilar 01 (el marco "entorno / harness" envolviendo al modelo, con reintento, sandbox, límites y degradación), el pilar 02 (el bucle razonar-actuar-observar con la guarda "¿seguir?" y el presupuesto de iteraciones) y el pilar 03 (las cuatro fuentes confluyendo en la ventana finita).

---

## Bloque 2 · Las capacidades - Sección 03, pilares 4-6 [5:30–9:00]

**Objetivo:** que entienda que, con la máquina en pie, se le dan capacidades, y que la clave no es tener muchas piezas sino pocas y buenas, con memoria útil y complejidad solo cuando compensa.

**Guion hablado:**
> Con el motor montado, le das capacidades al agente. La primera son las herramientas, las funciones que el modelo puede llamar. Y aquí la lección es contraintuitiva: pocas y buenas, mejor que muchas que se solapan. Una buena herramienta se explica sola, tiene un esquema de entrada estricto y, cuando falla, devuelve un mensaje que ayuda al agente a autocorregirse en vez de atascarse. Eso a ti te importa porque son menos fallos y menos mantenimiento: el agente se arregla solo la mayoría de las veces.
>
> La segunda capacidad es la memoria. Hay que distinguir el corto plazo, lo que el agente recuerda dentro de la sesión y vive en el contexto, del largo plazo, lo que guarda entre sesiones y se almacena fuera. La decisión de ingeniería es qué persistir y qué no, y cómo recuperarlo. Y esto es continuidad y personalización, y no re-pagar el mismo contexto una y otra vez en cada sesión.
>
> Y la tercera es la orquestación: un solo agente o varios coordinados. Puedes tener un orquestador que hace triage y reparte el trabajo entre especialistas, en paralelo o en secuencia. Pero más piezas no es siempre mejor: a veces un buen agente basta y montar un sistema multi-agente solo añade complejidad. Lo que te llevas es velocidad cuando hay frentes independientes, y el criterio de saber cuándo esa complejidad compensa y cuándo mantenerlo simple.
>
> Y aquí LangChain te da la regla en una frase: un solo agente con las herramientas y el prompt adecuados consigue casi todo lo que la gente cree que necesita del multi-agente. El fallo típico que documentan es justo ese, un agente con demasiadas herramientas que elige mal cuál usar. Por eso, pocas y buenas no es estética, es lo que hace que acierte. Y cuando de verdad montas varios agentes, dicen que en el centro del diseño está la ingeniería de contexto: decidir qué ve cada uno. Sobre la memoria, su técnica es la misma que te conté: lo que no cabe en la ventana se guarda en un fichero y el agente lo consulta bajo demanda.

**Frase-gancho:** "Pocas herramientas buenas, y multi-agente solo cuando de verdad compensa."

**Lo que señalas en pantalla:** el pilar 04 (la ficha de una herramienta bien diseñada, y el contraste "pocas y buenas" frente a "muchas solapadas"), el pilar 05 (corto plazo en el contexto frente a largo plazo almacenado: episódica, semántica, procedimental) y el pilar 06 (el orquestador repartiendo trabajo a tres especialistas, con la nota "a veces un solo agente basta").

---

## Bloque 3 · La confianza - Sección 04, pilares 7-10 [9:00–12:30]

**Objetivo:** que entienda que estas cuatro capas son las que deciden si puedes fiarte del agente en producción, y que son las que evitan las sorpresas caras.

**Guion hablado:**
> Ya tienes motor y capacidades. Queda la pregunta que lo decide todo para un responsable: ¿te puedes fiar de esto en producción? Cuatro capas construyen esa confianza. La primera son los guardrails, las barreras y permisos: una capa determinista entre el agente y el mundo que decide qué puede tocar y qué no. Ojo, no es el modelo autolimitándose, son reglas fijas que se cumplen siempre, y su trabajo es acotar el radio de impacto, el blast radius: cuánto puede dañar un fallo. Esto es seguridad y contención: un error del agente no se convierte en un desastre.
>
> La segunda es la evaluación, los evals. Medir que el agente hace bien el trabajo, no solo que responde algo. Y evaluar un agente no es puntuar una respuesta: es juzgar toda la trayectoria hasta el resultado. Construyes casos "golden" a partir de fallos reales y pasas pruebas de regresión cada vez que cambias algo. Esto es saber que funciona y cazar regresiones antes de que lleguen al cliente: calidad que no se degrada con cada cambio.
>
> La tercera es el humano en el bucle. La cuestión no es si hay humano, es dónde: dentro del bucle aprobando cada paso, encima supervisando, o fuera dejándolo autónomo. La clave es poner puertas de aprobación en lo irreversible sin ahogar la autonomía del agente. Es control del riesgo donde de verdad duele. Y la cuarta es la observabilidad: ver qué hace el agente por dentro, cada paso, cada coste, cada latencia. Sin trazas, un agente es una caja negra que no puedes ni depurar ni mejorar; con trazas, los fallos de producción vuelven a los evals y cierras un ciclo de mejora. Esto es depurar rápido y ver el coste real.
>
> Estas cuatro capas también son las que LangChain trata como infraestructura de producción, no como extras. De los guardrails dicen algo que a ti te va a gustar: son middleware, y los hacen de dos formas, con reglas fijas rápidas y baratas, o con un clasificador LLM que caza lo sutil pero cuesta más. Y cuentan un fallo real, un guardrail suyo se quedó obsoleto tras un lanzamiento y bloqueó preguntas legítimas hasta que las trazas lo destaparon. De los evals y la observabilidad tienen la mejor frase de todo esto: con los agentes, la lógica de tu aplicación está en las trazas, no en el código. Por eso evaluar es un bucle, las trazas de producción se vuelven casos de prueba, y los casos deciden si despliegas. Y el humano en el bucle se apoya en algo técnico, la ejecución durable, poder parar, reanudar y reintentar sin perder el hilo.

**Frase-gancho:** "Estas cuatro capas son las que te dejan soltar el agente sin sustos."

**Lo que señalas en pantalla:** el pilar 07 (el agente que solo llega al mundo a través de la capa de políticas, con MCP y APIs permitidos y canales bloqueado), el pilar 08 (single-turn puntúa la respuesta frente al agente que puntúa la trayectoria), el pilar 09 (los tres modos: dentro, encima, fuera del bucle) y el pilar 10 (los pasos generan trazas, el panel realimenta los evals y cierra el ciclo).

---

## Bloque 4 · El puente + cierre - Sección 05 [12:30–15:00]

**Objetivo:** cerrar dejando claro que estos diez pilares no son teoría, que los tengo implementados, y entregar limpiamente al segundo deck.

**Guion hablado:**
> Y ahora la parte que te interesa de verdad: estos diez pilares no son teoría de folleto, los tengo montados en mi máquina. El reparto es limpio. superpowers pone el método: el bucle operativo, la orquestación de agentes y las puertas de humano, o sea los pilares dos, seis y nueve. Sentinel pone las barreras: un motor de políticas determinista en cada acción, que es el pilar siete. Headroom cuida el contexto, comprimiéndolo para proteger la ventana en sesiones largas, que es el pilar tres. Y la medición honesta, con verificación y logs reales, cubre los evals y la observabilidad, los pilares ocho y diez.
>
> Lo demás son los cimientos: el entorno con venv y sandbox, los servidores MCP y los handoffs por fichero, que cubren el harness, las herramientas y la memoria, los pilares uno, cuatro y cinco. Así que cuando en el siguiente deck te enseñe superpowers, Sentinel y Headroom, ya vas a saber qué hueco tapa cada uno en este mapa.
>
> Y con eso te dejo la idea con la que quiero que te quedes: esto que acabas de ver es el mapa. Ahora te enseño el territorio, una máquina de verdad, con sus cifras reales, en el segundo deck. Cada número de ahí sale de un log o de un comando.

**Frase-gancho:** "Esto es el mapa; ahora te enseño el territorio, con las cifras reales."

**Lo que señalas en pantalla:** la sección 05 (el puente), las cinco tarjetas que mapean cada pieza a sus pilares (superpowers, Sentinel, Headroom, verificación + logs, y el entorno) y la frase de cierre "El segundo deck lo enseña con las cifras reales de esta máquina".

---

# Anexo A · "Si te preguntan" (Q&A honesto)

**¿No basta con un buen prompt y un buen modelo?**
> No. El prompt es el primer peldaño de la escalera, el más útil de aprender pero el que menos margen deja. El valor y la ventaja difícil de copiar están en las capas de abajo: el contexto, el harness y el bucle que rodean al modelo. Un buen modelo con un mal harness se cae en producción; un buen harness aguanta aunque cambie el modelo.

**¿Esto no es sobre-ingeniería para lo que hacemos nosotros?**
> La ceremonia se ajusta al riesgo. No todo agente necesita las diez capas, y montarlas todas para una tontería sería un peaje absurdo. Pero saber que existen es justo lo que evita las sorpresas en producción: eliges cuáles te hacen falta a conciencia, en vez de descubrir que te faltaba una cuando ya ha reventado algo.

**¿Cuánto cuesta montar y mantener todo esto?**
> La mayoría no es infraestructura cara, son decisiones de diseño: poner un límite de iteraciones, definir qué persiste en memoria, escribir buenos mensajes de error. El coste de verdad es no tenerlas: bucles desbocados que queman factura, fallos sin trazas que no puedes depurar, y un agente sin límites tocando lo que no debe.

---

# Anexo B · Chuleta de una línea por pilar (para tener a mano)

- **Pilar 01 · Harness (entorno):** el andamiaje que rodea al modelo para que corra fiable: reintentos, sandbox y límites.
- **Pilar 02 · Loop (bucle):** el agente es un ciclo razonar-actuar-observar con presupuesto de iteraciones para no dispararse.
- **Pilar 03 · Context (contexto):** decidir qué entra en la ventana finita y qué se recupera, evitando el "context rot".
- **Pilar 04 · Tools (herramientas):** pocas y buenas, con errores que ayudan al agente a autocorregirse.
- **Pilar 05 · Memory (memoria):** corto plazo en el contexto, largo plazo almacenado; decidir qué persistir.
- **Pilar 06 · Orchestration (orquestación):** un agente o varios coordinados; complejidad solo cuando compensa.
- **Pilar 07 · Guardrails (barreras):** una capa determinista que acota el radio de impacto de un fallo.
- **Pilar 08 · Evals (evaluación):** medir que hace bien el trabajo, no solo que responde; cazar regresiones.
- **Pilar 09 · Human-in-the-loop (humano):** puertas de aprobación en lo irreversible, sin ahogar la autonomía.
- **Pilar 10 · Observability (observabilidad):** ver cada paso, coste y latencia; realimentar los fallos en los evals.

---

# Anexo C · Fuentes y lecturas (si te las piden)

Todo el mapa es verificable en la fuente. Las de más calidad:

- **Andrej Karpathy**: el modelo mental "LLM = CPU, contexto = RAM".
- **LangChain, The Art of Loop Engineering**: los cuatro bucles apilados; "el potencial está en los bucles que construyes alrededor". `langchain.com/blog/the-art-of-loop-engineering`
- **LangChain, Context Engineering**: llenar la ventana con lo justo; escribir, seleccionar, comprimir, aislar. `blog.langchain.com/context-engineering-for-agents`
- **LangChain, How and when to build multi-agent systems**: herramientas y orquestación; multi-agente solo cuando compensa. `langchain.com/blog/how-and-when-to-build-multi-agent-systems`
- **LangChain, The Runtime Behind Production Deep Agents**: harness frente a runtime; el humano en el bucle sobre ejecución durable. `langchain.com/blog/runtime-behind-production-deep-agents`
- **LangChain, AI Agent Observability & Evals**: "la lógica está en las trazas, no en el código"; el eval como bucle. `langchain.com/resources/agent-observability`
- **SwirlAI**: el framework de los 10 pilares aquí adaptado.
