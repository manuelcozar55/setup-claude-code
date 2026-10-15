# Guía · Antipatrones (todos vistos en un setup real)

Cada uno de estos pasó de verdad, en un setup real en 2026, y casi todos parecían una buena idea al configurarlos. El formato es siempre el mismo: qué se ve, por qué pasa, qué hacer.

## 1 · La sesión inmortal

**Se ve:** una sesión que «va bien» y no se cierra nunca; cada vez más lenta y más olvidadiza.
**Por qué:** una sesión permaneció abierta **42 días** y acumuló **66 compactaciones**. No era consumo desbocado: era no cerrar. Cada compactación tira ~88 % del contexto y tarda ~150 s, y la siguiente resume un resumen.
**Qué hacer:** una tarea, una sesión. Al cerrar una fase, `/handoff`; al cambiar de tarea, `/clear`. Lo que deba sobrevivir, en `nucleo.md` ([día 3](00-ruta-7-dias.md#día-3--handoff-y-clear-en-vez-de-esperar-a-la-compactación)).

## 2 · El diario en `nucleo.md`

**Se ve:** el fichero de estado crece cada sesión; aparecen varias «TAREA ACTUAL»; el modelo retoma algo que ya se terminó.
**Por qué:** un `nucleo.md` llegó a **78 KB**. Una salida de hook tiene un tope (10 000 caracteres según la documentación) y el inyector recorta por el centro: la tarea vigente desaparece. Lo ves con salidas reales en [`02-sesion-real.md`](02-sesion-real.md#2--el-mismo-hook-con-un-nucleomd-que-se-volvió-diario).
**Qué hacer:** forma fija, una sola tarea, lo terminado a otro fichero que nada inyecta.

## 3 · El proxy de compresión

**Se ve:** un proxy local delante de la API que promete comprimir el contexto y ahorrar tokens.
**Por qué:** medido sobre miles de peticiones, el proxy (Headroom) ahorró **entre 0,2 % y 0,6 %**. La caché de prompts ya absorbe casi todo lo repetido, y lo que sobra no se comprime sin perder información. A cambio, un proceso más que vigilar y una URL de API que, si el proxy cae, deja a Claude Code sin conexión. Se retiró.
**Qué hacer:** el ahorro real está en no cargar lo que no usas (`/context`) y en no traer volcados al hilo principal. Si alguien te enseña un porcentaje grande, pregunta de qué denominador sale.

## 4 · `effortLevel: "max"` en `settings.json`

**Se ve:** pones el máximo esfuerzo en la configuración y crees que lo tienes.
**Por qué:** medido: `"max"` en `settings.json` **cae a `high` en silencio**, sin error ni aviso. El máximo que se puede fijar por configuración es `"xhigh"`, que es lo que trae la plantilla del kit.
**Qué hacer:** `"effortLevel": "xhigh"`. Y en general: tras cambiar una clave, comprueba su efecto; que se acepte no significa que se aplique.

## 5 · `--1m` en el arranque

**Se ve:** arrancas con `--1m` para tener la ventana de un millón y algunas tareas fallan con `400 The long context beta is not yet available`.
**Por qué:** la bandera estampa el sufijo de ventana larga sobre **cualquier** modelo, incluido Haiku, que no lo admite. Los subagentes baratos (el verificador del kit va en Haiku) revientan.
**Qué hacer:** la ventana larga va en el id del modelo con el sufijo `[1m]` (como `opus[1m]` en la plantilla), y solo en el modelo que la admite.

## 6 · `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` para «compactar antes»

**Se ve:** una variable que parece mover el umbral de compactación.
**Por qué:** medido, se comporta como un gancho de pruebas: con 75 en una ventana normal adelantaba la compactación regalando ~32k de ~180k utilizables, y en la ruta de un millón fue **inerte** (la compactación real disparó por encima del millón). La documentación oficial la menciona; lo medido no coincide.
**Qué hacer:** si quieres mover cuándo compacta, `CLAUDE_CODE_AUTO_COMPACT_WINDOW` con un entero (`250000`, nunca `250k`: el valor se lee como entero). Y verifícalo con `/context`, no con la documentación.

## 7 · `/model` que no se queda

**Se ve:** cambias de modelo con `/model` y en la sesión siguiente vuelve el de antes. En 60 días se teclearon 28 `/model`.
**Por qué:** la variable de entorno `ANTHROPIC_MODEL` (en `settings.json` → `env`) se reaplica en cada arranque y pisa lo elegido en la sesión anterior. Con la clave `model` **y** la variable, tienes dos fuentes y gana la que no miras.
**Qué hacer:** una sola fuente. Si usas la variable, quita la clave `model` (o al revés), y cambia el modelo por defecto editando esa única fuente.

## 8 · `Bash(node *)` en la lista de permitidos

**Se ve:** para no aprobar cada `node script.js`, añades `Bash(node *)` a `permissions.allow`.
**Por qué:** `node -e '…'` ejecuta lo que sea, incluido descargar y lanzar código: es **ejecución arbitraria sin pregunta**. Lo mismo, con otra cara: `gh auth *` imprime el token en el contexto, y `git remote *` permite añadir un remoto y empujar ahí.
**Qué hacer:** permite el comando concreto (`Bash(node scripts/build.js)`), nunca el intérprete con comodín. Repasa `settings.local.json`, que es donde se acumulan estos «aprobar siempre».

## 9 · `Edit(/ruta)` creyendo que es absoluta

**Se ve:** una regla `Edit(/etc/**)` en `deny` que no protege `/etc`.
**Por qué:** una barra inicial **ancla al directorio del `settings.json`**, no a la raíz del sistema; la raíz necesita dos: `Edit(//etc/**)`. Y una regla `Write(...)` se acepta y se ignora: solo se consultan reglas `Edit`. Detalle en [`05-security.md`](../05-security.md#antes-de-todo-hook-las-reglas-permissionsdeny).
**Qué hacer:** `Edit(//ruta/absoluta/**)`, y comprueba el aviso que imprime `claude` al arrancar.

## 10 · Reglas en prosa que nadie comprueba

**Se ve:** `CLAUDE.md` crece con «acuérdate de…», y se incumple igual.
**Por qué:** «actualiza el estado antes de compactar» estaba escrito en cuatro sitios y el 75 % de las compactaciones llegaron sin estado fresco. Una regla que nadie verifica es un deseo.
**Qué hacer:** lo que tiene que cumplirse siempre, a un hook (la tabla de [`05-security.md`](../05-security.md#hook--incidente-que-evita) dice qué evita cada uno). En `CLAUDE.md`, solo lo que de verdad es criterio.

## 11 · Instalar «por si acaso»

**Se ve:** decenas de skills, varios servidores MCP, plugins que probaste una vez.
**Por qué:** todo lo cargado se paga en cada turno: 67 skills eran 5,6k tokens fijos, la mayoría sin un solo uso en 60 días; los esquemas de herramientas, 25k. Ver [`01-por-que-contexto.md`](01-por-que-contexto.md#1--pagas-45k-tokens-antes-de-escribir-nada).
**Qué hacer:** desactiva lo que no hayas usado en un mes y vuelve a mirar `/context`. [`06-adaptar.md`](06-adaptar.md) dice qué quitar de la plantilla según tu caso.
