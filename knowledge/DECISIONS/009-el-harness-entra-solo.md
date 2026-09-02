# ADR 009 — El harness entra solo: `UserPromptSubmit` en vez de comandos que hay que recordar

**Fecha:** 2026-08-21 · **Estado:** aceptada, verificada · **Sustituye parcialmente a:** ADR 004

## Contexto

v0.1.0 entregó cinco comandos de flujo bien escritos: `/spec`, `/implement`, `/verify`,
`/review`, `/retro`. Todos exigen lo mismo del usuario: **acordarse de teclearlos**.

El propio pre-mortem de este repo puso esa dependencia como **causa de abandono número 1**,
y la evidencia local la respalda sin margen de duda:

| Regla advisoria existente | Adherencia medida |
|---|---|
| `IntentGate` — 227 tok, la sección más larga de `CLAUDE.md` | **plan mode: 2,1 %** |
| `Parallel-First` — apunta a una skill concreta | **0 invocaciones** |
| `Agent Delegation` — tabla de 8 especialistas | **70 % va al agente genérico** |
| "verifica tu trabajo" | **27,7 % de sesiones con oráculo** |

Cuatro reglas, cuatro incumplimientos. El patrón no es "el usuario es indisciplinado": es
que **pedir disciplina no la produce**. Es exactamente lo que dice la documentación oficial
—*"if Claude keeps doing something you don't want despite having a rule against it, the file
is probably too long and the rule is getting lost"*— y su remedio: *"delete it or convert it
to a hook"*.

Y el gap concreto que hay que cerrar está medido: la mediana de encargo es de **142
caracteres** y casi nunca incluye cómo se sabrá que está bien hecho.

## Decisión

**Un hook `UserPromptSubmit` que actúa en el momento en que se pide algo**, sin que nadie
teclee nada: `.claude/hooks/auto-spec.sh`.

Qué hace, en orden:

1. **Clasifica el prompt**: ¿encargo de trabajo o pregunta?
2. **Si ya trae criterio de verificación**, se calla. Esta rama importa tanto como la otra:
   es la que **premia** escribir el criterio uno mismo con menos interrupción.
3. **Si es un encargo sin criterio**, inyecta: la petición de declarar qué será cierto al
   terminar y **qué comando lo demuestra**, el oráculo del proyecto **detectado
   automáticamente** (`scripts/detect-oracle.sh`), y el recordatorio de ejecutarlo en frío.
4. **Gotchas solo si aplican**: el aviso de M-001 aparece únicamente si el prompt menciona
   `pytest`, `rg`, `npm test`… No en cualquier prompt.
5. **Brief de errores una vez por sesión**, y solo en el primer *encargo*.
6. **Avisa si la medición envejece** (>7 días sin snapshot), que es la causa nº2 del pre-mortem.

## Contrato técnico, verificado contra la doc

> *"The exceptions are `UserPromptSubmit`, `UserPromptExpansion`, and `SessionStart`, where
> Claude Code adds **plain-text stdout as context that Claude can see and act on**."*
> — code.claude.com/docs/en/hooks, verificado 2026-08-21

**Se usa stdout plano, no JSON.** Un subagente propuso el esquema
`hookSpecificOutput.additionalContext`; al verificarlo contra la fuente resultó que **la doc
no especifica ese esquema para este evento**. Se eligió lo que está documentado literalmente.

> *"`UserPromptSubmit` … exit 2: **Blocks prompt processing and erases the prompt**"*

**Por eso el hook nunca emite `exit 2`** — borraría lo que el usuario acaba de escribir.
Hay un test que verifica que la cadena no aparece en el código (filtrando comentarios, ya
que el propio hook documenta por qué no la usa).

## Relación con el ADR 004

El ADR 004 decía que nada bloquea. **Sigue siendo cierto y este hook no lo contradice**:
inyecta contexto, no impone una decisión. El modelo puede ignorarlo, el usuario puede
ignorarlo, y `exit 0` es incondicional.

Lo que cambia es *cuándo* aparece la guía: antes había que ir a buscarla; ahora llega sola
en el instante en que es útil. Es la diferencia entre un manual y un copiloto.

## Consecuencia: se elimina `session-brief.sh`

Su función (poner delante el oráculo y los errores) la hace ahora `auto-spec.sh` en mejor
momento: el primer encargo, no el arranque —donde se diluye y no sobrevive a un `/clear`.

**El presupuesto se mantiene en 3 hooks**: se sustituye, no se suma. Es la única forma de
crecer en capacidad sin crecer en piezas, y el precedente importa porque el pre-mortem
señala el crecimiento como causa nº5.

## Verificación

`kit/test/test_auto_spec.sh` — **16 checks, 0 fallos**. Lo que se prueba no es que produzca
texto, sino que **discrimine**:

| Entrada | Comportamiento verificado |
|---|---|
| `"arregla el bug del login"` | pide criterio + inyecta `make test` + exige ejecución en frío |
| `"como funciona el sistema de hooks?"` | **silencio total** |
| `"añade paginación y verifica que make test siga en verde"` | **no** repite la petición de criterio |
| `"escribe un test con pytest"` | avisa de M-001; un prompt sin comandos susceptibles, no |
| entrada no-JSON / vacía / sin prompt | `exit 0`, nunca rompe la sesión |

Más un check de **falsabilidad**: un encargo y una pregunta deben producir salidas distintas
—una llena y otra vacía—. Sin él, todo lo anterior podría estar pasando con un hook que
imprime siempre lo mismo.

Latencia medida: **23 ms** (techo declarado 5 s). Corre en cada prompt, así que tenía que
ser imperceptible.

## Alternativas descartadas

- **Insistir con reglas en `CLAUDE.md`.** Ya se probó: cuatro reglas, cuatro incumplimientos.
- **`exit 2` para forzar reescribir el prompt.** Descartada: la doc dice que borra el prompt.
  Inaceptable a cualquier tasa de falsos positivos.
- **Una skill auto-invocable por `description`.** Descartada: el modelo decide si la carga,
  así que la garantía es probabilística. Un hook es determinista, y aquí lo que falla es
  precisamente lo probabilístico.
- **`/goal` fijado automáticamente.** Descartada: no está documentado que se pueda fijar
  desde un hook, y construir sobre lo no documentado es cómo se rompe una versión más tarde.

## Límites declarados

- **El clasificador es léxico**, por raíces de verbos en español e inglés. Tendrá falsos
  positivos (un prompt que dice "cambia" hablando de otra cosa) y falsos negativos (un
  encargo con fraseo raro). El coste de un falso positivo es una línea de más; el de un
  falso negativo, el estado actual. La asimetría justifica errar por exceso.
- **Solo actúa sobre el prompt**, no sobre lo que el modelo hace después. Que el contexto
  inyectado se siga es cosa del modelo; el hook garantiza que **esté**, no que se obedezca.
- Requiere `jq`. Sin él el hook sale en silencio: mejor callar que adivinar el parseo.
