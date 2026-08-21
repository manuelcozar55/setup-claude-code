---
name: house-rules
description: Estándares de código de la casa — simplicidad, cambios quirúrgicos, alcance y verificación. Úsala al escribir o modificar código, al revisar un diff, o cuando haya que decidir cuánto código escribir. No la uses para preguntas de hecho ni para exploración.
---

# Reglas de la casa

Cuatro principios contra los modos de fallo predecibles de un LLM escribiendo código:
suposición silenciosa, sobrecomplejidad, deriva de alcance y ejecución vaga.

> **Atribución.** Se citan a menudo como "los principios de Karpathy". **No hay fuente
> primaria.** Son una formulación de la comunidad derivada de sus observaciones
> (`multica-ai/andrej-karpathy-skills`, literal: *"derived from Andrej Karpathy's
> observations on LLM coding pitfalls"*). Aquí son **principios de la casa**, y valen por
> lo que hacen, no por quién los firma. Verificado 2026-08-21.

---

## 1 · Pensar antes de escribir

No supongas. No escondas la confusión. Saca los compromisos a la luz.

Ante ambigüedad, el fallo típico no es elegir mal: es **elegir en silencio**. Si dos
lecturas producen entregables distintos, preséntalas. Si producen lo mismo, elige, dilo, y
sigue — preguntar lo irrelevante también es un fallo.

Empuja cuando haga falta. Un "de acuerdo" que sabes que es malo es peor que una objeción.

## 2 · Simplicidad primero

El mínimo código que resuelve el problema. Nada especulativo.

El defecto es escribir 1.000 líneas donde bastan 100. Concretamente:

- Ninguna funcionalidad más allá de lo pedido.
- Ninguna abstracción para un solo uso.
- Ninguna "flexibilidad" o "configurabilidad" que nadie pidió.
- Ningún manejo de errores para escenarios imposibles.
- Sin comentarios salvo que el *porqué* no sea obvio. El *qué* ya lo dice el código.

**Prueba del ingeniero senior:** si 200 líneas podrían ser 50, reescríbelas antes de
entregar.

## 3 · Cambios quirúrgicos

Toca solo lo que debas. Limpia solo tu propio desorden.

- No "mejores" código, comentarios ni formato adyacentes.
- No refactorices lo que no está roto. Imita el estilo existente aunque tú lo harías de otra
  forma: un fichero coherente y mediocre es mejor que uno inconsistente y brillante a medias.
- **Regla del huérfano**: elimina los imports, variables y funciones que *tus* cambios
  dejaron sin usar. **No** elimines código muerto preexistente — menciónalo y sigue.
- Prefiere editar un fichero existente a crear uno nuevo.

## 4 · Ejecución dirigida a un objetivo

Define el criterio de éxito. Itera hasta verificarlo.

Un objetivo verificable es un comando. "Que funcione" no es un criterio; `make test`
devolviendo 0 sí lo es. Si no puedes nombrar el comando, no has definido el objetivo — y
eso se arregla con `/spec`, no escribiendo código y esperando.

Verificar no es opinar: es ejecutar y enseñar la salida.

---

## Cómo se aplican en revisión

Ante un diff, en este orden:

1. ¿Hace lo que se pidió? ¿Y **solo** lo que se pidió?
2. ¿Sobra código? ¿Alguna abstracción tiene un solo llamante?
3. ¿Toca ficheros que la tarea no requería?
4. ¿Dejó huérfanos? ¿Borró código muerto que no le tocaba?
5. ¿Hay un comando que demuestre que funciona, y se ejecutó?

## Señales de que estás incumpliendo

| Estás a punto de… | Significa | Haz esto |
|---|---|---|
| Añadir un parámetro "por si acaso" | Especulación | Bórralo. Se añade cuando haga falta |
| Crear una clase base con un hijo | Abstracción prematura | Código directo |
| Arreglar un typo en una función que no tocabas | Deriva de alcance | Menciónalo, no lo toques |
| Escribir `try/except` sin saber qué falla | Defensa ritual | Deja que falle ruidosamente |
| Decir "debería funcionar" | No has verificado | Ejecuta el oráculo |
| Reescribir un fichero para "dejarlo limpio" | Refactor no pedido | Edición incremental |
