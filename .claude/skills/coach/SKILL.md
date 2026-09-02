---
name: coach
description: Explica el porqué de las decisiones técnicas relevantes sin bloquear la ejecución. Úsala cuando el perfil tenga explain en brief o full y se acabe de tomar una decisión con alternativa descartada. No la uses para narrar pasos obvios ni para justificar cada edición.
---

# Coach

El objetivo del harness no es solo producir trabajo correcto: es que quien lo dirige
**suba de nivel**. Un agente que acierta sin explicar deja al humano dependiente.

Consumir tokens en explicar es aceptable. Consumirlos en explicar lo obvio, no.

## Niveles

Se leen de `config/profile.yaml` → `explain`.

| Nivel | Comportamiento |
|---|---|
| `off` | No explicar. Solo el informe final. |
| `brief` | Dos o tres líneas tras cada **decisión relevante**. El valor por defecto. |
| `full` | Explicación completa: mecanismo, alternativa descartada, coste y cómo se comprobaría. |

## Qué es una "decisión relevante"

Solo estas cuatro. Todo lo demás se hace y se calla:

1. **Había alternativa real** y elegiste una. (Elegir entre dos formas idénticas no cuenta.)
2. **El resultado sorprende**: contradice lo que el usuario esperaba o dijo.
3. **Hay un compromiso con coste**: velocidad contra claridad, cobertura contra tiempo.
4. **Descubriste algo del entorno** que no estaba documentado.

Que un cambio sea grande no lo hace relevante. Que sea sutil, sí.

## Forma

Nunca antes de actuar. **El coach explica después o en paralelo, jamás bloquea.**
Si la explicación retrasa el trabajo, sobra.

En `brief`:

```
· Decidido: <qué>
· Porque: <la razón que de verdad pesó, no la lista de razones>
· Descartado: <la alternativa> — <por qué no>
```

En `full`, además: el mecanismo subyacente, el coste (tiempo, complejidad, mantenimiento),
y **qué observaría el usuario si la decisión fuera errónea**. Esto último es lo más útil:
convierte una explicación en una hipótesis falsable.

## Cómo detectar que el coach es ruido

Esta sección es la que evita que esta skill se convierta en relleno.

> **Señal de fallo:** una explicación que no cambia ninguna decisión del usuario es ruido,
> por bien escrita que esté.

Comprobación, en `/retro`: de las explicaciones de la sesión, ¿cuántas provocaron una
pregunta, una corrección o un cambio de rumbo? Si la respuesta es cero durante dos
sesiones seguidas:

1. Anótalo en `knowledge/MISTAKES.md`.
2. Baja un nivel (`full` → `brief` → `off`).
3. Estrecha el criterio de "decisión relevante".

**Métrica de éxito del coach**, la única que importa: el número de veces que el usuario
escribe un criterio de verificación en su encargo inicial **sin que el harness se lo pida**.
Base medida 2026-08-21: cerca de cero. Si esa cifra no sube, el coach no está enseñando —
está decorando.

## Qué no hacer

- No expliques lo que se infiere del código a simple vista.
- No conviertas la explicación en disculpa ni en autocrítica.
- No repitas en la explicación lo que ya dice el informe final.
- No expliques cada edición: explica cada **decisión**. Suelen ser muchas menos.
