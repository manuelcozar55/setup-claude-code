# 06 · La rutina

Este setup solo rinde si además se opera bien: con qué modelo hacer cada cosa, cómo mantener la ventana limpia, y cómo aislar el trabajo en paralelo. Ninguno de estos hábitos lo instala `install.sh`; son disciplinas de uso diario.

## Tiering por categoría

La misma idea de `04-superpowers.md` aplicada a cómo eliges modelo tú mismo, no solo al delegar en agentes:

| Categoría | Modelo | Cuándo |
|---|---|---|
| Estrategia / arquitectura / research | `opus` | decisiones de diseño, planificación, análisis profundo |
| Implementación / refactor / features | `sonnet` | código, PRs, revisiones |
| Verificación / lint / tipos / tests | `haiku` | comprobaciones rápidas, validación barata |

El criterio es simple: no pagues el modelo de razonamiento caro para correr un linter. Reserva el tier caro para las decisiones que de verdad lo necesitan.

## Cuotas y coste medidos

Consulta `/usage` y los límites que muestre la barra de estado antes de una tarea larga.
Registra el modelo, el esfuerzo y el resultado de tus pruebas para comparar calidad y coste.
Una ventana de uso de la suscripción no equivale al coste de una llamada por API.

Los horarios de reinicio dependen del plan y del proveedor. Un ping a una hora fija
no garantiza más cuota y no forma parte del recorrido de instalación.

## `/compact` a mano frente al autocompact

Guarda el estado con `/handoff` al cerrar una fase si usas cockpit, o con
`handoff --desde borrador.md` desde la terminal. Si ejecutas `/compact`, indica qué
conservar. El kit fija `env.CLAUDE_CODE_AUTO_COMPACT_WINDOW` y conserva tu valor
si ya tenías uno. Consulta `/context` para ver la ventana efectiva de esa sesión;
la referencia del ajuste está en [`02-install.md`](02-install.md#modelo-ventana-y-esfuerzo-una-sola-fuente-medido).
Los hooks guardan un checkpoint y reinyectan el estado tras compactar: no recuperan
decisiones que nunca se escribieron.

## Modelo y ventana efectivos

La plantilla fija `"model": "opus"`, sin sufijo, y respeta tu modelo al actualizar.
Comprueba `/status` y `/context`: la disponibilidad y la ventana dependen de la
versión y de tu cuenta. Ajusta el modelo y el esfuerzo según la tarea y las pruebas,
no por una recomendación universal de contexto máximo.

## Git worktrees para aislar

Cuando hay dos o más frentes independientes en paralelo (varios agentes, varias tareas que no dependen entre sí), usa `git worktree` para que cada frente tenga su propio directorio de trabajo y su propia rama, sin pisarse:

```bash
git worktree add ../mi-repo-feature-x feature-x
```

Esto es lo que hace posible el principio de "Parallel-First": lanzar frentes independientes de verdad en paralelo, sin que compartir un único árbol de trabajo se convierta en el cuello de botella.

## Handoffs por fichero

Cuando delegas en un sub-agente, o cuando el contexto se va a compactar, pasa el estado por fichero (una spec, un plan, un paquete de revisión como diff) en vez de pegar el contenido completo en la ventana de conversación. Es la aplicación directa del modelo Karpathy de `01-overview.md`: la spec en disco es la fuente de verdad que sobrevive a la RAM que se vacía. Un diff pegado en el contexto consume RAM que no vas a recuperar; revisar desde el fichero mantiene la ventana limpia.
