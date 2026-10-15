# 13 · Memoria: un hecho por fichero, recordado bajo demanda

Claude Code guarda memoria por proyecto en `~/.claude/projects/<proyecto>/memory/`. El índice
`MEMORY.md` se inyecta en **cada** arranque; las memorias enteras no. Por eso el índice se
mantiene corto y las memorias se consultan con `recuerda`, que devuelve solo los párrafos que
interesan en vez de cargar ficheros enteros en el contexto. La plantilla
[`kit/claude/AGENTS.md`](../claude/AGENTS.md) enseña al modelo a hacerlo así.

## Formato de una memoria

Un hecho por fichero, `<slug>.md`, con frontmatter:

```markdown
---
name: pnpm global bin PATH
description: pnpm movió su bin global a $PNPM_HOME/bin; qué se rompió y cómo se arregló
metadata:
  type: project        # user | feedback | project | reference
---

Qué pasó, con la cifra o el comando que lo prueba.

Por qué importa y qué hacer la próxima vez.
```

- `description` es lo que ve `recuerda -l`: una línea que permita decidir si abrirla.
- Párrafos cortos y separados por una línea en blanco: `recuerda` devuelve párrafos, no líneas.
- Antes de crear una, búscala (`recuerda <términos>`): se actualiza la que existe, no se duplica.

## El índice `MEMORY.md`

Una línea corta por memoria, enlazada a su fichero; **60 líneas como máximo**, porque se paga
en cada sesión:

```markdown
- [pnpm global bin PATH](pnpm-global-bin-path.md) — el bin global se movió a $PNPM_HOME/bin
```

El detalle va en la memoria, nunca en el índice. Si una línea crece, el sobrante se mueve al
fichero; si el índice pasa de 60 líneas, se fusionan o se retiran memorias obsoletas.

## `recuerda`

[`scripts/recuerda`](../../scripts/recuerda) es un atajo de
[`scripts/recall.py`](../../scripts/recall.py). Enlázalo en tu `PATH` una vez:

```bash
ln -sf "$PWD/scripts/recuerda" ~/.local/bin/recuerda
```

| Comando | Devuelve |
|---|---|
| `recuerda <términos>` | los párrafos que contienen algún término, de las 3 memorias con más coincidencias; sin acentos ni mayúsculas (`compactacion` encuentra «compactación») |
| `recuerda -l` | el índice: `name` y `description` de cada memoria |
| `recuerda -f <slug>` | una memoria completa |

Sale 0 con resultados, 1 si ningún término coincide y 2 ante un uso inválido. Lee
`$CLAUDE_MEMORY_DIR`; por defecto, el `memory/` del proyecto de tu `$HOME`
(`~/.claude/projects/-home-<usuario>/memory`). Como es un comando y no un fichero, Codex y
opencode lo usan igual que Claude Code: los tres comparten el mismo almacén.

## Privacidad

Las memorias describen tu máquina, tus repos y tu trabajo: **las memorias nunca salen a un
servicio externo**. Ni se pegan en un prompt a otro proveedor ni se sincronizan con una nube
de terceros; si quieres copia, un repo git privado tuyo.
