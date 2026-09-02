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

## El ping de las 6:00

Un hábito operativo: mandar un mensaje mínimo a las 6:00 de la mañana para anclar la ventana rodante de 5 horas justo al empezar el día, de forma que cuando llega el trabajo real (a media mañana) la cuota ya está corriendo sobre una ventana entera, no a mitad consumida.

**Aviso honesto, y esto es importante**: esto es mecánica de suscripción de Claude (planes Pro/Max), no una garantía contractual ni un comportamiento de la API. Los topes semanales van aparte y no se ven afectados por este hábito. Es un modelo mental de cómo se comporta habitualmente el reseteo de la ventana rodante, no una cifra que el proveedor prometa por escrito, y puede cambiar sin previsión con actualizaciones del plan. Verifícalo contra los términos vigentes de tu plan antes de asumir que se comporta igual en tu caso.

Este ping **no se automatiza como parte de este kit**. Si quieres programarlo tú mismo, hay una plantilla opcional y comentada más abajo.

## `/compact` a mano frente al autocompact

Prefiere compactar a mano con `/compact`, indicando explícitamente qué conservar, en los puntos naturales de una tarea (tras cerrar una fase, antes de delegar a un sub-agente). El autocompact automático es el airbag, no el plan A: está para cuando te olvidas o la sesión se alarga más de lo previsto, no para sustituir la decisión consciente de qué es prescindible. Este kit **no** toca su umbral: el `settings.json` que instala no lleva ninguna clave para moverlo.

## `opus[1m]` solo cuando no cabe

La config de este kit fija `"model": "opus[1m]"` como modelo por defecto (opus con ventana de contexto de un millón de tokens). Úsalo así, como variante de contexto amplio, solo cuando el conjunto de trabajo genuinamente no cabe en una ventana normal (un refactor multi-fichero grande, revisar un diff enorme). No lo trates como el modelo de trabajo rutinario: es sensiblemente más caro que la alternativa estándar, y para el día a día el tiering de la tabla de arriba ya cubre la mayoría de tareas.

## Git worktrees para aislar

Cuando hay dos o más frentes independientes en paralelo (varios agentes, varias tareas que no dependen entre sí), usa `git worktree` para que cada frente tenga su propio directorio de trabajo y su propia rama, sin pisarse:

```bash
git worktree add ../mi-repo-feature-x feature-x
```

Esto es lo que hace posible el principio de "Parallel-First": lanzar frentes independientes de verdad en paralelo, sin que compartir un único árbol de trabajo se convierta en el cuello de botella.

## Handoffs por fichero

Cuando delegas en un sub-agente, o cuando el contexto se va a compactar, pasa el estado por fichero (una spec, un plan, un paquete de revisión como diff) en vez de pegar el contenido completo en la ventana de conversación. Es la aplicación directa del modelo Karpathy de `01-overview.md`: la spec en disco es la fuente de verdad que sobrevive a la RAM que se vacía. Un diff pegado en el contexto consume RAM que no vas a recuperar; revisar desde el fichero mantiene la ventana limpia.

## Plantilla OPCIONAL: automatizar el ping (NO se ejecuta sola)

Lo siguiente es una plantilla de referencia, completamente comentada. No forma parte de la instalación de `install.sh`, no se activa por tenerla en este documento, y solo debes darla de alta tú mismo, a mano, si decides que quieres automatizar el ping.

**Opción cron** (`crontab -e`, añade la línea sin la almohadilla si decides usarla):

```bash
# OPCIONAL, no se instala solo. Da de alta con: crontab -e
# 0 6 * * 1-5  claude -p "ping" >/dev/null 2>&1
```

**Opción systemd (usuario)** (`~/.config/systemd/user/claude-ping.timer` + `.service`, ambos comentados a modo de referencia):

```ini
# OPCIONAL, no se instala solo. Guarda como ~/.config/systemd/user/claude-ping.service
# [Unit]
# Description=Ping matutino para anclar la ventana rodante de Claude
#
# [Service]
# Type=oneshot
# ExecStart=%h/.local/bin/claude -p "ping"
```

```ini
# OPCIONAL, no se instala solo. Guarda como ~/.config/systemd/user/claude-ping.timer
# [Unit]
# Description=Dispara claude-ping.service a las 6:00 en días laborables
#
# [Timer]
# OnCalendar=Mon..Fri 06:00
# Persistent=true
#
# [Install]
# WantedBy=timers.target
```

Si activas el timer: `systemctl --user enable --now claude-ping.timer`. Ajusta la ruta al binario `claude` y el mensaje a lo que de verdad quieras usar, y recuerda el aviso honesto de más arriba: esto ancla una ventana rodante, no te garantiza una cuota.
