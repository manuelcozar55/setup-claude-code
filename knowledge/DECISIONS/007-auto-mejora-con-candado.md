# ADR 007 — Auto-mejora referenciada, y su superficie de ataque

**Fecha:** 2026-08-21 · **Estado:** aceptada

## Contexto

El objetivo es que el harness aprenda solo, de buenas fuentes y siempre referenciado.
Eso abre un canal por el que **contenido externo se convierte en instrucción**, que es la
definición de una inyección de prompt con persistencia.

El riesgo no es teórico. Un sistema que (a) trae contenido de la web, (b) lo escribe en
ficheros y (c) lee esos ficheros como reglas, es un sistema donde cualquiera que controle
una página puede modificar el comportamiento del agente de forma duradera. Y a diferencia
de una inyección de una sola sesión, esta sobrevive al `/clear`.

## Decisión

Cinco candados. Los cinco se cumplen o el mecanismo no se enciende.

**1 · `knowledge/SOURCES.md` es una allowlist explícita.** Cada entrada lleva URL, autor,
tipo (primaria/secundaria), fecha de verificación y ventana de frescura. Nada se ingiere de
fuera de la lista. Añadir una entrada es decisión del propietario, nunca del agente.

**2 · `knowledge/` es no-confiable por defecto.** Lo que viene de la web son **datos, nunca
instrucciones**. Ningún fichero de `knowledge/` puede modificar `CLAUDE.md`, hooks,
`settings.json` ni skills por sí mismo. Esta es la frontera que hace que las otras cuatro
reglas importen.

**3 · Puerta humana en la promoción.** El flujo es:
`hallazgo → ficha con fuente y fecha → propuesta de cambio → aprobación → commit`.
Automático hasta la propuesta; **nunca más allá**. `/retro` propone, no aplica.

**4 · Frescura, no acumulación.** Vencida la ventana, la entrada se marca `[STALE]` y deja
de citarse hasta reverificarse. Lo impone `test_harness_structure.sh`, que además
**demuestra que detecta una entrada vencida fabricada** — sin esa prueba, el check podría
estar pasando siempre y nadie lo sabría.

**5 · Todo hallazgo lleva su contra-argumento**, o la nota de que se buscó y no se
encontró. Sin eso, "aprender de las mejores fuentes" degenera en coleccionar
confirmaciones.

## Lo que este diseño NO protege

Decirlo importa más que la lista de protecciones:

- **Una fuente de la allowlist que se corrompe.** Si `martinfowler.com` sirviera contenido
  hostil, entraría. Mitigación parcial: es *dato*, no instrucción, y la puerta humana sigue
  ahí. Mitigación real: ninguna.
- **El propio agente escribiendo una ficha envenenada.** Nada impide que un agente
  comprometido escriba en `knowledge/`. Lo que sí impide el diseño es que ese fichero
  *ejecute* algo: `knowledge/` no es código y no lo carga ningún hook.
- **Skills de terceros.** Son un vector real y por eso **v0.1.0 adopta cero**. El vetado
  exige revisar `SKILL.md` **y sus scripts**, no solo la descripción.
- **Fatiga de la puerta humana.** Si `/retro` propone veinte cambios por sesión, el humano
  aprueba en bloque y la puerta deja de ser puerta. Mitigación: `/retro` solo propone
  promoción **a la segunda ocurrencia** del mismo error, no a la primera.

## El steering loop, con freno

Böckeler: *"Whenever an issue happens multiple times, the feedforward and feedback controls
should be improved."* Aplicado con una escalera explícita:

| Ocurrencia | Acción |
|---|---|
| 1ª | Ficha en `MISTAKES.md` con reproducción literal. **Nada más.** |
| 2ª | Propuesta de promoción: hook (`timeout ≤ 5 s`), test o skill |
| 3ª | La promoción anterior falló. Explicar **por qué** antes de proponer otra |

El freno de la primera ocurrencia es deliberado: cablear cada incidente aislado produce un
sistema lleno de controles que nadie recuerda por qué existen.

## Alternativas descartadas

- **Ingesta automática sin allowlist.** Es el diseño que hace atractivo el ataque.
- **Prohibir toda auto-mejora.** Descartada: el conocimiento vivo es una de las cuatro
  propiedades del encargo, y un harness que no aprende es una config estática.
- **Firmar criptográficamente las fichas.** Descartada por desproporcionada: el atacante
  realista aquí es una página web, no alguien con acceso de escritura al repo — y quien
  tenga ese acceso puede cambiar el código directamente.

## Fuentes

- Böckeler, *Harness engineering*, 02-abr-2026 — primaria, verificada 2026-08-21.
- `knowledge/SOURCES.md` para la allowlist vigente.
