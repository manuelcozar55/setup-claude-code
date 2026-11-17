# ADR 030 — El handoff automático guarda al cerrar el turno y deja el `/clear` para el próximo mensaje de la persona

**Fecha:** 2026-11-17 · **Estado:** aceptada · implementada en cockpit 0.11.0 (sin etiquetar) · **Enmienda a:** ADR 013

## Contexto

ADR 013 hace el handoff automático al cerrar un turno con el contexto por encima del umbral: guarda, hace `/clear` y
rellena el prompt. Diagnóstico del 2026-11-16 sobre cockpit 0.10.0 (Claude Code 2.1.311):

- El disparo es `turn.complete` con `reason: answer`: el `/clear` llega 300 ms después de la respuesta y **borra lo que
  la persona iba a leer**. Las guardas (turno en marcha, texto en el prompt, prompt nuevo) no cubren ese caso:
  justo al salir la respuesta ninguna se cumple.
- Con autonomía, el mod envía siempre «Continúa únicamente el trabajo ya autorizado…». En los transcripts, de 19
  continuaciones, 11 contestaron «no queda nada» o «falta tu OK», y solo 4 usaron 10 herramientas o más.
- La continuación citaba como objetivo el **primer** mensaje desde el último `/clear`, no el último. Una vez pasó
  una orden de un encargo anterior como si fuera la vigente.
- `COCKPIT_AUTONOMO=off` no lo evita: limpia igual. Solo `COCKPIT_AUTO_HANDOFF=off` lo evitaba, a costa de
  perder el handoff.

## Decisión

1. **Guardar sin limpiar.** El guardado sigue al cerrar el turno, que es cuando sale barato, y si se cierra la sesión
   no se pierde nada. La banda dice «Guardado en <ruta> · se limpiará al enviar tu próximo mensaje (× para no
   limpiar)».
2. **`/clear` con el próximo mensaje.** El hook `prompt.submit` retiene el mensaje (`{ drop }`) y lanza `/clear` desde
   `$.clock.after`. Después lo reenvía con `$.prompt.submit({ asUser: true })`. El ahorro es el mismo, porque una
   sesión parada no gasta. La respuesta anterior viaja como **fila oculta** (`$.session.append`, recortada a
   6 000 + 2 000 caracteres y entre `<respuesta-anterior>` como datos). No viaja como contexto del hook porque el
   hook `prompt.submit` de un mod no ve los envíos de ese mismo mod (comprobado con el arnés de tests). `nucleo.md`
   no se repite: ya lo inyecta `SessionStart`.
3. **Solo se retiene lo que se puede reenviar igual.** Se retiene lo que llega del compositor o del bridge, en reposo,
   sin adjuntos, `@fichero`, contexto ajeno ni `!`, sin agentes ni shells vivos, y con el contexto aún por encima del
   umbral. Lo demás pasa tal cual y desarma. Un comando pasa sin desarmar. Un turno que empieza, el fin de sesión o la
   × también desarman.
4. **Continuar solo con «AUTORIZADO: sí».** Con autonomía, el mismo fork que escribe el borrador empieza con
   «AUTORIZADO: sí|no»; esa línea no se guarda. Solo «sí» limpia en el acto y continúa. «No», una línea ausente o
   una dudosa cuentan como «no»: el automático pasa al punto 2, y `/handoff` limpia y rellena sin continuar. Todas
   las líneas «AUTORIZADO:» deben ser un «sí» limpio, y el veredicto va con el borrador que se guarda.
5. **La misión de la continuación** es el relleno («Siguiente acción») más la última orden literal de la persona,
   como datos entre `<ultima-orden>` y con un máximo de 500 caracteres. Nunca es el primer mensaje de la sesión. Sobrevive a `/clear`;
   `/nueva` y cualquier otro fin de sesión la borran.
6. **`/anterior`** muestra la última respuesta de la sesión anterior al `/clear`. Vive en memoria y se pierde al
   reiniciar `claude`.

**Invariante:** un mensaje retenido acaba enviado o devuelto, y nunca dos veces. El motor repone en la caja el texto de
un `{ drop }` (medido en sesión real): antes del reenvío el mod vacía la caja si contiene justo ese texto. Si `/clear` no cambia el id de sesión, va a esta
sesión. Si la sesión cambió antes del `/clear` (`/resume`) o otro hook rechaza el reenvío, vuelve al prompt, con lo que
hubiera en la caja debajo; si el prompt no admite el relleno, se muestra entero en la transcripción.

## Alternativas descartadas

- **Pegar la respuesta anterior en el texto reenviado:** la persona vería en su mensaje un texto que no escribió, y
  ese texto tendría la autoridad de una orden suya.
- **Adjuntarla como `context` desde el propio hook:** imposible. Ese hook no corre para el `$.prompt.submit` del mismo
  mod.
- **Repetir `nucleo.md` en la fila oculta:** lo duplica, porque `SessionStart` ya lo inyecta.
- **Reutilizar `clearAfter` para el reenvío:** sus guardas, pensadas para un prompt vacío y sin mensaje nuevo,
  abortan justo cuando hay un mensaje retenido.
- **Retener también mensajes con `@fichero` o imágenes:** el reenvío no los expande, así que cambiaría lo que la
  persona envió.
- **Pedir el veredicto en una segunda llamada:** costaría otra llamada al modelo. Una línea más en el fork que ya se
  hace no cuesta ninguna.

## Consecuencias

- El handoff automático sin autonomía ya no borra nada en pantalla, y el relleno del prompt solo aparece cuando hay
  `/clear` en el acto (`/handoff`, o el automático con «sí»).
- La precisión de «AUTORIZADO» no está medida. El fallo seguro es «no», que cuesta un Enter y no trabajo de más.
- Tests (arnés del mod, 2.1.311): 335 en verde. Contra 0.10.0, los tests nuevos y adaptados fallan. 17 mutaciones,
  una por guarda, dan rojo.
- Sesión interactiva real (2.1.311, `haiku`, umbral bajado con `CLAUDE_CODE_AUTO_COMPACT_WINDOW`). En la sesión
  nueva, el orden fue: `SessionStart` (nucleo), `/clear`, fila oculta y reenvío. El motor confirma que el hook
  propio no ve el reenvío («skipped: re-entry»). El modelo contestó por la respuesta anterior, y el fork escribió
  «AUTORIZADO: no», que no se guardó. Esa prueba destapó el doble envío de la caja, corregido con su test.
- Una revisión independiente encontró cuatro fallos más, todos corregidos y cubiertos por un test que da rojo sin
  su arreglo. (1) Grafías de la etiqueta que cerraban el bloque de datos: ahora se escapa su `<`. (2) Un Enter
  durante el reenvío llegaba a la conversación que se limpia: ahora se descarta. (3) Dos mensajes juzgados a la vez:
  ahora van de uno en uno. (4) «AUTORIZADO: sí, pero…» contaba como «sí»: ahora «sí» solo vale solo en su línea.
- Una segunda revisión (Codex) encontró cinco más, corregidos con su test. (1) Un `/resume` antes del reenvío lo
  mandaba a otra sesión: ahora se devuelve al prompt. (2) Un «sí» citado antes del «no» real ganaba: ahora todas las
  líneas deben decir «sí». (3) El «no» de un reintento por tamaño se ignoraba: el veredicto va con su borrador.
  (4) Un mensaje largo se perdía en la banda truncada: ahora vuelve al prompt o se muestra entero. (5) La última
  orden no escapaba su etiqueta: ahora va entre `<ultima-orden>` con el mismo escape.
- Una tercera revisión (17-nov, tarde) encontró dos fallos más, corregidos y cubiertos por un test que da rojo sin
  su arreglo. (1) Un turno que empezaba entre el drop y el `/clear`, por ejemplo un aviso de tarea, quedaba cortado:
  ahora el mensaje vuelve al prompt y el final de ese turno guarda y arma otra vez. (2) Una comprobación colgada
  bloqueaba todos los mensajes siguientes: ahora cada uno espera a la anterior 10 s como máximo. De paso,
  `resendAfterClear` tiene un solo camino de error, de modo que cualquier fallo antes del envío devuelve el mensaje.
- La revisión del cierre (17-nov, noche) bloqueó el arreglo (2). La espera acotada dejaba viva la comprobación
  anterior, y su respuesta tardía mandaba su mensaje después del reenvío del siguiente: dos veces si era el mismo
  texto, y tras el `/clear` si era otro. Ahora se acota la comprobación, no la espera. Si no responde en 10 s cuenta
  como fallida y su mensaje pasa tal cual, sin `/clear` y en orden. Su respuesta tardía no retiene, no limpia ni
  desarma nada. Se descartó dejar pasar al siguiente y anular el anterior: el mensaje anterior llegaría después del
  `/clear`, fuera de orden. Límite: dos Enter con el mismo texto durante una comprobación que vence salen dos veces,
  igual que cuando cualquier comprobación deja pasar el mensaje.
- Riesgo de inyección acotado, no eliminado. Con «sí», la continuación lleva una «Siguiente acción» escrita por el
  modelo, igual que el relleno que la persona aprueba con Enter. Un contenido hostil leído en la sesión podría
  colarla. Para acotarlo, la continuación pide contrastarla con la última orden literal de la persona y detenerse si
  esta no la cubre. Además, la autonomía solo se activa por `/autonomo` o por `COCKPIT_AUTONOMO`.
- Riesgo aceptado: si otro mod envuelve `prompt.submit` y repone la caja más tarde que el motor, el mensaje podría
  salir dos veces. No se ha visto; el mod vacía la caja solo si contiene justo ese texto.
- Coste: con el `/clear` pendiente, cada turno que no abre un mensaje retenido vuelve a guardar al cerrar por encima
  del umbral (1 fork).
