---
description: Convierte un encargo en una especificación con criterios de aceptación verificables, antes de tocar código
disable-model-invocation: true
---

Vas a convertir este encargo en una **especificación ejecutable**. No escribas código todavía.

Encargo: $ARGUMENTS

## Por qué existe este comando

Los encargos de este usuario son bimodales: o una frase o un documento. Falta el término
medio — una especificación corta con criterios de aceptación escritos **antes** de empezar.
Ese hueco es la causa raíz de la mayor parte del retrabajo: no es que el agente falle, es
que nadie definió qué era "terminado".

El entregable de este comando **no es código**. Es un contrato verificable.

## Procedimiento

### 1. Entiende antes de proponer

Lee lo que haga falta del código real. No supongas la arquitectura: compruébala.
Si hay más de 3 sitios que mirar, delega la exploración a un subagente para no llenar
el contexto con ficheros que no vas a modificar.

### 2. Interroga solo lo que cambia el trabajo

Usa `AskUserQuestion` **una sola vez**, agrupando todo. El criterio para preguntar es
estrecho: pregunta solo si dos lecturas razonables producirían entregables distintos.
Si las dos producen lo mismo, elige, dilo, y sigue.

No preguntes lo que puedas medir. No preguntes lo que el código ya responde.

### 3. Escribe la especificación

Formato exacto. Sé breve: si pasa de una pantalla, has metido diseño donde va contrato.

```markdown
# Spec: <nombre>

## Problema
Qué está mal hoy, en una o dos frases. Con evidencia, no con adjetivos.

## Alcance
- DENTRO: …
- FUERA: …            <- esta lista es la que evita el scope creep

## Criterios de aceptación
Cada uno debe ser comprobable por un comando o una observación inequívoca.
1. [ ] …
2. [ ] …

## Oráculo
El comando exacto que dice si esto está bien:

    <comando por ruta absoluta, `rtk proxy …` o `make …`>

Resultado esperado: …
Resultado HOY (en frío): …          <- si ya pasa, el oráculo no mide lo que vas a cambiar

## Ficheros que se tocan
Rutas concretas. Si no puedes nombrarlas, no has explorado lo suficiente.

## Riesgos y qué haría falta para revertir
```

### 4. Verifica la spec contra sí misma

Antes de entregarla, responde:

- ¿Algún criterio de aceptación es una opinión? Reescríbelo o bórralo.
- ¿El oráculo se puede ejecutar **hoy**? Si no, la primera tarea es hacerlo ejecutable
  (declárala `bootstrap`), no fingir que existe.
- ¿El oráculo ya pasa antes de tocar nada? Entonces no mide tu cambio. Estréchalo.
- ¿Está la lista de FUERA vacía? Casi nunca es cierto. Piénsalo otra vez.

### 5. Entrega

Guarda la spec en `SPEC.md` en el directorio de trabajo y muéstrala.

Termina diciendo, en una línea, **qué comando ejecutará el usuario para saber que has
terminado**. Si no puedes escribir esa línea, la spec no está lista.

No implementes. La implementación es `/implement`, en sesión limpia.
