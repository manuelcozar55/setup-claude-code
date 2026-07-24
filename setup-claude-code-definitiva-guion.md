# Guion — "Cómo trabajo con Claude Code: el método, no el modelo"

**Duración objetivo:** 20 minutos · **Registro:** técnico, directo, de tú a tú · **Público:** devs
**Compañero visual:** `setup-claude-code-definitiva.html` (una sección por bloque)
**Regla de oro que repites al final:** si algo aquí no lo puedes reproducir con un comando en esta máquina, sobra.

> **Cómo usar este guion.** Cada bloque tiene un objetivo, el texto real que dices en voz alta (no un esquema: léelo casi tal cual), la frase-gancho que quieres que se lleven, la cifra que señalas en pantalla y, donde toca, el comando exacto de la demo. Los tiempos entre corchetes son tu presupuesto: si te pasas en uno, recórtalo en el siguiente, no al final.

---

## Bloque 0 · Gancho + tesis — Hero [0:00–2:00]

**Objetivo:** que entiendan en 2 minutos la tesis entera: el modelo importa menos que el método, y las tres piezas que lo sostienen.

**Guion hablado:**
> Voy a enseñaros cómo trabajo yo con Claude Code en esta máquina. Y lo primero que os quiero quitar de la cabeza es la idea de que esto va de tener el modelo más listo. No va de eso. No es el modelo, es el método. El modelo es intercambiable; el método es lo que hace que un agente autónomo no te reviente el sistema ni te queme la factura mientras tú miras para otro lado.
>
> Os doy el modelo mental con el que pienso todo esto, porque es de ingeniería y os va a sonar: el LLM es la CPU, el contexto es la RAM, y la spec es la fuente de verdad. La CPU es potente pero tonta sin instrucciones; la RAM es finita y se llena; y la spec es lo único que sobrevive cuando la RAM se te vacía. Sobre eso monto tres piezas: superpowers, que es el método; Sentinel, que es la puerta; y Headroom, que es la factura. El método dice qué hacer, la puerta dice qué se permite, la factura dice cuánto cuesta. Durante los próximos veinte minutos os enseño las tres con datos reales de esta máquina, no con cifras de folleto.

**Frase-gancho:** "No es el modelo. Es el método."

**Cifra que enseñas:** los cuatro números del hero — **14** skills, **204** DENY reales, **57,3 M** tokens comprimidos, **4** fases del loop.

**Demo/comando:** ninguno todavía — solo señalas la portada. Anuncia que "cada número de esta página sale de un log o de un comando; y al final os enseño cómo verificarlo vosotros mismos".

---

## Bloque 1 · El método + el loop — Sección 01 [2:00–7:00]

**Objetivo:** que entiendan que el método es un bucle con puertas de calidad, y que la ceremonia se ajusta al riesgo — no es burocracia porque sí.

**Guion hablado:**
> El corazón del método es un bucle operativo que llamo deep-change. Compone las catorce skills de superpowers en cuatro fases: brainstorm, plan, execute, verify. Y lo importante no son las fases, son las puertas entre fases. En brainstorm no se escribe una línea de código hasta acordar el diseño. En plan sale una spec con pasos verificables. En execute, el test va antes que la implementación, TDD de verdad. Y en verify no digo "hecho" hasta enseñar el comando y su salida. Esa última es innegociable: evidencia, no afirmaciones.
>
> De las catorce skills, cuatro son leyes de hierro, invariantes que el bucle nunca se salta: skills-first, el gate de brainstorming, TDD, y verificar antes de completar. Las otras diez son herramientas que invoco cuando la tarea las pide. Y cuando delego, delego con tiering: el modelo más caro y potente para pensar —opus en el orchestrator, en el strategist, en el planner—, el intermedio para ejecutar y revisar —sonnet en el deep-worker y en los reviewers—, y el barato para verificar —haiku en el quick-checker, que solo dice PASS o FAIL. No pago un opus para correr un linter.
>
> Y todo esto lo gobiernan tres reglas. IntentGate antes de arrancar: intención real, alcance, criterios de éxito. Never-Stop una vez dentro: aprobado el diseño, ejecuto hasta el final sin preguntarte "¿sigo?" cada dos pasos. Y Parallel-First: si hay dos frentes independientes, van en paralelo por defecto. El gate y el never-stop no se pelean: uno es antes de ejecutar, el otro es durante. Y lo más honesto de todo: esto no se aplica a rajatabla siempre. La ceremonia se ajusta al riesgo. Una tontería de una línea la hago directo. Algo sustancial o irreversible se lleva el bucle completo.

**Frase-gancho:** "La ceremonia se ajusta al riesgo: trivial, directo; sustancial, bucle completo."

**Cifra que enseñas:** **4** fases · **14** skills (4 leyes de hierro) · **8** subagentes con tiering opus/sonnet/haiku.

**Demo/comando:** opcional, si quieres enseñar que las skills existen de verdad:
```
ls ~/.claude/skills/
```
Espera una lista de directorios de skills. Si vas justo de tiempo, sáltalo y quédate en la pantalla.

---

## Bloque 2 · SDD + Karpathy — Sección 02 [7:00–11:00]

**Objetivo:** que entiendan por qué la spec y el plan son artefactos durables que sobreviven a la compactación, con evidencia real en disco.

**Guion hablado:**
> Aquí conecto con una idea que Karpathy explica muy bien. Dije que el contexto es RAM y que se llena. Cuando se llena, hay que tirar historial. ¿Qué es lo que no puedes permitirte perder? Lo acordado. Por eso el par spec-más-plan es la unidad de trabajo durable: vive en disco, no en la ventana. Cuando el contexto se compacta, la spec y el plan reconstruyen el estado sin volver a discutir lo que ya estaba decidido. Eso es lo que evita que el agente "se olvide" a mitad de una tarea larga.
>
> Y no os lo cuento en abstracto, os enseño el fichero. Esto es progress.md real de esta máquina, de un plan SDD. Cuatro tareas, cada una con su commit nombrado. Task 1, review limpio tras un fix. Task 2, aprobada. Task 3, aprobada pero completada parcial por diseño: la retirada de hooks se abortó sola porque saltó la regla de más de diez huérfanos, y quedó una decisión de usuario pendiente. Task 4, aprobada pero con un checkpoint humano R1 todavía pendiente. Fijaos en el detalle: los tres review packages se entregaron como fichero en disco, como diffs, no pegados en el contexto. ¿Por qué? Porque un diff pegado en la ventana te come RAM que no vas a recuperar. Revisas desde el fichero y la ventana sigue limpia.
>
> Y el mapeo con Karpathy es uno a uno. Contexto es RAM: handoffs por fichero y autocompact al setenta y cinco por ciento. LLM es CPU: treinta y dos mil tokens de pensamiento, effort en xhigh, tiering por agente. Spec primero: el par spec-plan. Correa corta: tareas de dos a cinco minutos con TDD. Verificar, no confiar: gates de revisión. Y autonomía acotada: IntentGate antes, y contención de riesgo trabajando en copia aislada y aplicando a producción solo como paso confirmado.

**Frase-gancho:** "La spec y el plan viven en disco, no en la ventana: por eso sobreviven a la compactación."

**Cifra que enseñas:** **4** tareas con commits nombrados · Task 3 parcial y checkpoint **R1** pendiente · **3** review packages como fichero.

**Demo/comando:** si el proyector se ve bien, abre el fichero real de evidencia:
```
cat ~/.claude/.superpowers/sdd/progress.md
```
Espera las cuatro tareas con sus commits. Si no, la sección de la web ya lo muestra — señálala.

---

## Bloque 3 · Las dos capas, CON DEMO EN VIVO — Sección 03 [11:00–16:00]

**Objetivo:** que entiendan que Sentinel y Headroom son lo que me deja soltar el control — y que los dos están medidos con honestidad, incluidos sus límites. Aquí es donde la charla se gana la credibilidad con comandos en vivo.

### 3a · Sentinel — la puerta [11:00–13:30]

**Guion hablado:**
> Si el método me dice que ejecute hasta el final sin parar, ¿qué me deja hacer eso sin miedo? Sentinel. Es un hook PreToolUse de coste cero que se aplica a todas las tools, matcher vacío. Se mete entre cada acción y su ejecución, y decide: DENY, ASK, WARN o ALLOW. Y es fail-open por diseño: si el hook peta, deja pasar la acción. Prioriza no romperme el flujo por encima del bloqueo estricto. Ahora mismo os chirría; volveré a ello.
>
> Los números del audit, congelados en el snapshot de la web: doscientos dieciséis eventos, doscientos cuatro DENY, doce warn, doscientos siete comandos bloqueados. Y los motivos top son mis propios hábitos: rutas sensibles, comandos peligrosos, IP en crudo, `~/.ssh`, la variable de la API key, algún dominio malicioso, prompt injection. Ese es justo el sesgo honesto del log: solo registra lo que se bloqueó, o sea que retrata mis manías, no una amenaza externa. Es una red calibrada para no estorbar, no un cortafuegos infalible.

**[DEMO EN VIVO — este es el momento fuerte de la charla. No lo escondas, lúcelo.]**

Comando exacto, en la terminal, a la vista:
```
grep -c '"deny"' ~/.claude/audit-logs/sentinel.jsonl
```

> **Guion de la demo (dilo mientras sale el número):**
> Fijaos. En la web pone doscientos cuatro. Aquí, hoy, sale más —doscientos seis, doscientos siete, el que toque ese día—. ¿Es un error? No. Es exactamente el punto. El log está vivo, crece con el uso, y esa deriva al alza es la medición honesta: no os enseño un número maquillado, os enseño uno que sube mientras trabajo. De hecho —y esto ha pasado de verdad preparando esto— fui a comprobar el proxy con un curl a una IP en crudo, y Sentinel me lo bloqueó a mí y registró un DENY nuevo. El número subió por culpa de la propia demo. Eso es la puerta funcionando delante de vosotros.

Si quieres el segundo golpe de efecto (opcional, muy potente), provoca un DENY en directo:
```
grep -c '"deny"' ~/.claude/audit-logs/sentinel.jsonl
cat ~/.ssh/id_rsa
```
Espera el bloqueo de Sentinel (no lee la clave), y vuelve a correr el `grep -c` para ver el contador subir uno. **Nunca** enseñes contenido de `~/.ssh` — el objetivo es el bloqueo, no el fichero.

**Frase-gancho:** "El número ya subió; el log crece con el uso, y esa deriva al alza es justo la medición honesta."

**Cifra que enseñas:** **216** eventos / **204** DENY / **12** warn / **207** bloqueados (web) → en vivo saldrá **≥204** (hoy 207).

### 3b · Headroom — la factura [13:30–16:00]

**Guion hablado:**
> La segunda capa es Headroom, y es la que me deja sostener sesiones largas sin que la ventana se llene a mitad de tarea. Ojo con lo que es y lo que no es: no resume con otro LLM. Es un router de contenido, un proxy local que comprime cada resultado de herramienta antes de que llegue al modelo. Claude Code habla con el proxy en local, y el proxy con la API de Anthropic.
>
> Los números, versión cero-treinta y dos-uno: cincuenta y siete coma tres millones de tokens comprimidos. Doscientos treinta y uno con setenta y uno de dólares de ahorro propio, el de la compresión. Mil ochocientos cincuenta y dos con ochenta y siete de ahorro por la caché nativa. Y dos mil novecientos setenta y tres con trece de coste de input total pagado. La cascada lo cuenta claro: partíamos de un potencial de cinco mil cincuenta y siete con setenta y uno; le quitas la caché nativa, le quitas la compresión de Headroom, y pagas dos mil novecientos setenta y tres.
>
> Y aquí viene la parte honesta, que es la que quiero que os llevéis. El grueso del ahorro no lo pone Headroom, lo pone la caché nativa de Anthropic: mil ochocientos contra doscientos treinta y uno. El mérito propio de Headroom es pequeño, un once por ciento del ahorro. Pero es real, y su valor de verdad no es tanto el ahorro directo como no pisar esa caché mientras comprime. Un proxy en medio podría romperte el prompt-caching y salirte carísimo; el mérito es comprimir sin cargártelo.

**[DEMO EN VIVO]** Comando exacto:
```
headroom_stats
```
Alternativa si prefieres el endpoint de salud (¡cuidado! `curl` a `127.0.0.1` lo bloquea Sentinel por IP en crudo — es otro punto a favor, pero tenlo previsto; si lo quieres correr, hazlo desde una allowlist o enséñalo desde la tabla de la web):
```
curl -s 127.0.0.1:8787/readyz
```
> **Guion de la demo:** igual que con Sentinel — los dólares de hoy serán algo mayores que los congelados en la web. Dilo en alto: "otra vez, sube; el proxy sigue vivo y facturando; el snapshot es una foto, no la verdad congelada".

**Frase-gancho:** "El grueso lo pone la caché de Anthropic; el mérito de Headroom es pequeño pero real — y su trabajo es proteger esa caché, no pisarla."

**Cifra que enseñas:** **57,3 M** tokens · **$231,71** propio · **$1.852,87** caché · **$2.973,13** total · potencial **$5.057,71**.

---

## Bloque 4 · La rutina de una sesión fresca — Sección 04 [16:00–18:00]

**Objetivo:** que entiendan que el método solo rinde con la RAM limpia, y las tres disciplinas que lo mantienen — con los caveats dichos sin trampa.

**Guion hablado:**
> Todo esto rinde con una condición: la ventana tiene que estar limpia. Os cuento tres hábitos. El primero, el ping de las seis de la mañana. Mando un mensaje a las seis y eso ancla la ventana rodante de cinco horas justo cuando empieza el día, así el cupo se resetea con la ventana entera cuando de verdad voy a trabajar. Aviso honesto: esto es mecánica de suscripción, no de la API; los topes semanales van aparte; y es un modelo mental de cómo se comporta, no un número que el proveedor me garantice.
>
> El segundo hábito: compacto a mano con `/compact` y le digo qué conservar, en vez de esperar al autocompact del setenta y cinco por ciento. El autocompact es el airbag, no el plan A. Y el tercero: opus con ventana de un millón solo cuando el contexto no cabe, nunca para el trabajo rutinario; y paralelizar solo frentes independientes, con los subagentes devolviéndome rutas y conclusiones, no volcándome su contexto entero de vuelta.

**Frase-gancho:** "El autocompact al 75 % es el airbag, no el plan A."

**Cifra que enseñas:** ventana rodante de **5 h** (6:00 → 11:00) · autocompact al **75 %** · **opus[1m]** solo si no cabe.

**Demo/comando:** ninguno — usa la línea de tiempo de la web. Si quieres, menciona que el ping se automatiza, sin abrir nada.

---

## Bloque 5 · Mejoras honestas + cierre — Secciones 05 y 06 [18:00–20:00]

**Objetivo:** cerrar con la filosofía única y con humildad — enseñar el backlog abierto y rematar con la regla de oro reproducible.

**Guion hablado:**
> Y si os fijáis, las tres piezas no son tres herramientas sueltas: son una misma idea desde tres ángulos. El método dice qué hacer, Sentinel qué se permite, Headroom cuánto cuesta. Y la idea que las une es esta: fail-open donde importa el flujo, medición honesta donde importa la confianza. Sentinel deja pasar si falla, para no romperme el flujo. Headroom mide su propio mérito sin inflarlo, para no romperme la confianza. Y el método verifica con evidencia, no con afirmaciones.
>
> No os quiero vender que esto está perfecto, así que os enseño el backlog abierto. Falta un backup remoto de `~/.claude` — es mi único riesgo catastrófico de verdad: máquina de un solo disco, hoy sin copia off-site. Falta medir con números si Headroom rompe el caching, para justificar tener ese proxy en el camino o quitarlo. Falta adelgazar el CLAUDE.md, que ha engordado. Faltan cerrar los planes SDD abiertos, el de Task 3 y el checkpoint R1 de Task 4. Formalizar los git worktrees, higiene de la config de agentes, y rotar la key de Perplexity, que sigue pendiente.
>
> Y cierro con la regla que ordena todo esto y con la que os quedáis: si algo aquí no lo podéis reproducir con un comando en esta máquina, sobra. Cada número que os he enseñado sale de un log o de un `jq`. Ahí tenéis la tabla del "verifícalo tú mismo": la cifra, la fuente y el comando exacto. Copiadlo y comprobadlo. Gracias.

**Frase-gancho:** "Si algo aquí no lo puedes reproducir con un comando en esta máquina, sobra."

**Cifra que enseñas:** el backlog de **7** mejoras honestas + la tabla "Cifra → fuente → comando".

**Demo/comando:** cierra en la sección 06 con la tabla visible. Comandos byte-exactos que aparecen ahí (coinciden con la web):
```
wc -l ~/.claude/audit-logs/sentinel.jsonl
grep -c '"deny"' ~/.claude/audit-logs/sentinel.jsonl
wc -l ~/.claude/audit-logs/blocked-commands.log
jq .lifetime.tokens_saved ~/.headroom/proxy_savings.json
jq .lifetime ~/.headroom/proxy_savings.json
curl -s 127.0.0.1:8787/readyz
```

---

# Anexo A · "Si te preguntan" (Q&A honesto)

**¿Fail-open no es inseguro?**
> Sí, y es un trade-off consciente, no un descuido. Prioriza no romperme el flujo de trabajo autónomo por encima del bloqueo estricto. Es una red de seguridad calibrada a mis hábitos, no un cortafuegos infalible — y lo de verdad catastrófico (rutas sensibles, comandos destructivos, la API key, `~/.ssh`) está cubierto por reglas explícitas que sí bloquean.

**¿Headroom vale la pena si el grueso del ahorro es la caché de Anthropic?**
> Su mérito propio es pequeño —doscientos treinta y uno con setenta y uno, un once por ciento del ahorro— pero real. Y lo más importante: no me rompe la caché nativa mientras comprime. Dicho esto, verificar con números que no la rompe es una mejora que aún tengo pendiente; hasta cerrarla, lo trato como una hipótesis medida, no como una certeza.

**¿No es demasiada ceremonia?**
> La ceremonia se ajusta al riesgo. Una tontería trivial la hago directo, sin bucle. Algo sustancial o irreversible se lleva el loop completo. El gate está antes de empezar; una vez dentro, Never-Stop: ejecuto hasta el final sin pararme a preguntar "¿sigo?". La ceremonia es proporcional, no un peaje fijo.

---

# Anexo B · Checklist pre-charla

- [ ] **Proxy vivo:** confirma que Headroom responde. `curl -s 127.0.0.1:8787/readyz` (ojo: Sentinel puede bloquear la IP en crudo — tenlo allowlisteado o usa `headroom_stats`). Debe estar arriba antes de empezar.
- [ ] **Terminal lista con el log a mano:** el `grep -c '"deny"'` cargado en el historial para lanzarlo de un tecleo; fuente grande y legible en el proyector.
- [ ] **Tema elegido y probado:** claro u oscuro decidido y verificado en el proyector real (el contraste cambia mucho); no lo descubras en directo.
- [ ] **Navegador con la web abierta:** `setup-claude-code-definitiva.html` cargada, en la sección del hero, lista para hacer scroll sección a sección al ritmo del guion.
- [ ] **Ensayo de la deriva:** ejecuta el `grep -c` una vez antes para saber qué número saldrá hoy y no dudar en vivo — sea 206, 207 o el que sea, tú lo lees y dices "es ≥ 204, y sube".
- [ ] **Regla mental de tiempo:** si un bloque se alarga, recórtalo del siguiente, nunca del cierre.
