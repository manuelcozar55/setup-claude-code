---
description: Explica el trabajo una vez y el sistema lo lleva hasta el final — entrevista, especifica, ejecuta, verifica y revisa sin que tengas que volver a entrar
disable-model-invocation: true
---

Encargo: $ARGUMENTS

Vas a llevar esto de principio a fin. **El usuario entra una sola vez** —en el paso 3— y
después se aparta. Todo lo que le preguntes va agrupado ahí; a partir de ese punto, cada
pregunta que hagas es un fallo del diseño, no una cortesía.

## El contrato

> El usuario explica el trabajo. **El sistema se encarga de la interacción.**

Eso significa que **tú** eres quien decide cómo trabajar con Claude Code: qué explorar, a
qué especialista delegar, cuándo verificar, cuándo reintentar y cuándo parar. No le
devuelvas esas decisiones al usuario: son precisamente las que él quiere dejar de tomar.

Lo que sí es suyo: **qué** hay que construir, los compromisos de negocio, y aprobar lo
irreversible.

---

## 1 · Entiende antes de preguntar

Explora el código de verdad. Si hay más de tres sitios que mirar, **delega a un subagente**
para no llenar tu contexto con ficheros que no vas a modificar.

Averigua tú lo que se puede averiguar. **No preguntes nada que el código responda.**

Detecta el oráculo del proyecto:

```bash
scripts/detect-oracle.sh --why .
```

Si no hay ninguno, la primera tarea del trabajo es dejar uno ejecutable. Anótalo; no es
motivo para parar.

## 2 · Prepara UNA sola tanda de preguntas

El criterio para preguntar es estrecho, y conviene aplicarlo con dureza:

> Pregunta **solo** si dos lecturas razonables del encargo producirían entregables
> distintos, o si la decisión es del negocio y no técnica.

Si las dos lecturas producen lo mismo: **elige, decláralo como supuesto, y sigue.**
Si es una decisión técnica con una opción claramente mejor: **tómala tú.**

Preguntas legítimas, y no hay más categorías: alcance ambiguo que cambia el entregable ·
un compromiso que solo el usuario puede arbitrar · algo irreversible (borrar, publicar,
migrar datos, tocar producción) · falta un oráculo y no es derivable.

## 3 · El único momento en que el usuario entra

Una sola llamada a `AskUserQuestion` con **todo** lo que necesites, y en la misma pasada
enséñale la especificación para que la apruebe:

```markdown
## Voy a hacer esto
<qué, en dos frases>

## Fuera de alcance
<lo que NO voy a tocar — esta lista es la que evita el scope creep>

## Cuando esté hecho, será cierto que:
1. …
2. …

## Y lo demuestra este comando:
<oráculo, por ruta absoluta / rtk proxy / make>
Estado HOY en frío: <verde|rojo>

## Supuestos que he tomado sin preguntar
· …
```

Si no tienes ninguna pregunta, **no inventes una**: enseña la spec y pide solo el visto bueno.

## 4 · Entra en el lazo con `mch`

Con la aprobación dada:

```bash
mch task start <id>
```

Quien impide terminar el turno no es un script del kit: es `mch`, leyendo
`.agents/journal.jsonl` — un registro append-only que el agente no puede reescribir
ni decrementar. El Stop hook (`verify-gate.sh`) le pregunta a `mch task gate` en cada
intento de cerrar el turno y obedece su código de salida: **mientras la tarea siga
abierta sin una ejecución VERDE del oráculo registrada tras el `start`, bloquea.** Es
lo que permite que el usuario se vaya.

Como alternativa nativa, `/goal <condición>` hace algo parecido evaluado por un modelo.
Úsalo cuando el criterio no sea un comando sino un estado observable en la conversación
(*"todos los criterios del diseño se cumplen"*). Los dos se pueden combinar.

**En un repo sin `mch`** (o donde no gobierna) no hay nada que consultar: el hook
avisa por stderr si hay cambios sin verificar, pero no bloquea. Ahí `/work` no ofrece
una red — solo el aviso.

## 5 · Ejecuta sin volver a preguntar

1. **Aísla.** Rama dedicada, nunca la rama por defecto. Sin git: copia de cada fichero
   antes de tocarlo, y dilo en el informe.
2. **Oráculo en frío.** Si ya pasa, o el trabajo está hecho o el oráculo no mide lo que vas
   a cambiar. Averigua cuál de las dos.
3. **Análisis de impacto antes de tocar nada compartido**: `find_referencing_symbols` de
   serena responde qué se rompe, y cuesta una fracción de leer los ficheros enteros.
4. **Implementa** siguiendo `.claude/skills/house-rules/`: el mínimo que resuelve el
   problema, sin refactors de paso, limpiando solo tus propios huérfanos.
5. **Verifica.** Ejecuta el oráculo y guarda la salida literal.
6. **Repara, máximo 3 veces.** Si aparece la tentación de relajar un `assert`, añadir un
   `-k`, marcar `xfail` o tocar el `conftest`: **eso es aflojar el sensor y está prohibido.**
   Comprueba con `git diff --name-only` que el sensor no está en tu diff. Si de verdad el
   test está mal, para y dilo — se decide fuera de este lazo.
7. **Revisión adversaria**: delega el diff a `code-reviewer` (o `security-reviewer` si toca
   autenticación, entrada de usuario, secretos o permisos). **Verifica cada hallazgo antes
   de aceptarlo**: un revisor al que pides huecos los encuentra aunque no los haya, y
   perseguirlos todos lleva a sobreingeniería. Arregla los confirmados y reverifica.

Si algo te bloquea de verdad —no ambiguo, **bloqueado**— para y explícalo. Es la única
salida válida antes del final.

## 6 · Cierra

Con el oráculo en VERDE, cierra la tarea en la cola:

```bash
mch task run <id>    # registra la ejecución del oráculo
mch task done <id>   # cierra la tarea si esa ejecución fue VERDE
```

Informe único, no narración durante el trabajo:

```
HECHO        : …
ORÁCULO      : <comando> → <salida literal> → exit <n>
SENSOR       : intacto | ALTERADO (lista)
REVISIÓN     : n confirmados (arreglados) · n descartados (con motivo)
SUPUESTOS    : los que tomaste sin preguntar
FUERA        : lo que NO hiciste y por qué
ABIERTO      : …
```

Y una línea final honesta: **qué no cubre este oráculo**. Todo sensor tiene puntos ciegos;
el que dice no tenerlos es el peligroso.

## Cuando NO usar este comando

Para un cambio de una línea, una pregunta o una exploración. La ceremonia debe ser
proporcional al riesgo: montar un run autónomo para arreglar un typo es la clase de
sobreingeniería que hace que la gente deje de usar la herramienta.
