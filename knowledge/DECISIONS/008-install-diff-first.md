# ADR 008 — `install.sh` no escribe en un `~/.claude` que sea repo git ajeno

**Fecha:** 2026-08-21 · **Estado:** aceptada, verificada end-to-end

## Contexto

`kit/install.sh` instala en `$CLAUDE_HOME` (default `$HOME/.claude`), es idempotente y hace
backup antes de tocar nada. Está probado por 4 suites y por el job `smoke-install-nonroot`
de CI, que verifica la idempotencia comparando huellas `sha256sum` entre dos pasadas.

Pero el `~/.claude` de este usuario **es un repositorio git de otro proyecto privado**
(`claude-config-private`), y en el momento de la medición tenía **138 ficheros modificados
sin commitear**. Instalar encima habría pisado trabajo suyo. El backup interno lo hace
recuperable, pero recuperable no es lo mismo que no roto: nadie revisa un backup que no
sabe que necesita.

## La tensión

El encargo pedía, literalmente, que `install.sh` **no escribiera** en `~/.claude`.
Aplicado al pie de la letra, eso:

- rompe 4 suites y el job de CI que prueban la escritura,
- y deja el kit sin instalación de un tirón, rompiendo el quick start del README y las dos
  charlas HTML que lo enseñan.

Es decir: cumplir la letra del requisito habría destruido la función principal del producto
para resolver el problema de un solo usuario.

## Decisión

**Diff-first por detección, no por flag.**

```
si $CLAUDE_HOME es repo git CON remoto  →  no escribe; genera, diffea, explica; exit 0
--apply                                 →  fuerza la escritura
--plan                                  →  fuerza el modo diff aunque no sea repo git
en cualquier otro caso                  →  comportamiento de siempre, sin cambios
```

En modo diff genera el árbol completo en `${MCHARNESS_OUT:-$PWD/.mcharness-out}`, clasifica
en **nuevos / idénticos / modificados**, imprime el `diff -u` solo de los modificados, y
dice qué copiar y qué commitear en el repo privado.

**Por qué la detección y no un flag:** un flag protege a quien ya sabe que lo necesita.
La detección protege a quien no lo sabe, que es justo el caso en el que se pierde trabajo.
Y el criterio *"repo git con remoto"* es preciso: un `~/.claude` normal no lo es, así que el
usuario corriente no nota ningún cambio.

**Por qué esto no rompe los tests:** en el HOME temporal que usan las suites, `.claude` no
es un repo git → toman la rama de siempre. **Cero cambios en las 4 suites y en CI.**
El requisito se cumple sin sacrificar cobertura, que era la tensión real.

## Verificación end-to-end

Ejecutado contra el `~/.claude` **real** el 2026-08-21, con huella SHA-256 antes y después:

```
raiz          antes 1e5f387d206d9277…   despues 1e5f387d206d9277…
agents+hooks  antes e0361af3a0b0a7a0…   despues e0361af3a0b0a7a0…

VEREDICTO: ~/.claude INTACTO. No escribio nada.
```

Y la salida fue útil, no solo inocua: detectó 3 ficheros nuevos, 12 idénticos y varios
modificados con su diff.

Además, `uninstall.sh` (nuevo) aplica el mismo principio invertido: **`--dry-run` es el
comportamiento por defecto**, restaurar exige `--apply`, y antes de restaurar hace un backup
del estado actual. Nunca se destruye sin red.

## Alternativas descartadas

- **Prohibir la escritura siempre.** Rompe 4 suites, el job de CI, el quick start y las dos
  charlas. Coste desproporcionado.
- **Dejarlo como estaba.** Es el estado que pone en riesgo 138 ficheros sin commitear.
- **Preguntar interactivamente.** Descartada: `install.sh` corre en CI y en contenedores,
  donde no hay nadie para responder, y un prompt interactivo lo colgaría.

## Consecuencias y límites declarados

- Los subcomandos `--enable-secrets-layer2` y `--with-headroom` **no pasan por el gate**:
  siguen escribiendo directo aunque `$CLAUDE_HOME` sea repo git. Son opt-in explícitos, y
  quien los teclea sabe lo que hace. **Es una excepción consciente**, no un olvido; si
  resulta molesta, se extiende el gate.
- La detección requiere `git` en el PATH. Sin él se cae a la rama de siempre — se prefiere
  fallar hacia el comportamiento conocido.
