# ADR 031 — Con trabajo de fondo vivo, el handoff automático guarda una vez, avisa de qué bloquea y limpia cuando termina

**Fecha:** 2026-11-20 · **Estado:** aceptada · **Enmienda a:** ADR 030

## Contexto

Medido el 20-nov (sesión ee5ddf47, cockpit 0.10.0): con un subagente, un shell de fondo o un Monitor vivos, el
handoff automático se omitía sin guardar (correcto, limpiar perdería su resultado) y sin más: la sesión llegaba al
airbag y autocompactaba (10:14 y 11:12). Además:

- El aviso del Stop solo contaba `type == "subagent"`: a las 08:55Z dijo «Fase cerrada: /handoff» con un shell vivo.
- El toast salía una vez por sesión y el motivo solo iba al log de depuración.
- Un Monitor o una espera eterna bloqueaban el automático para siempre.

## Qué hace `/clear` con lo vivo

**No es concluyente, así que se decide lo conservador: todo lo vivo bloquea el `/clear`.** Fuentes: los tipos del
motor (2.1.311 en esta máquina; F1 pasó tsc con los de 2.1.317) describen `background_tasks` del hook Stop (tipos
`shell`, `subagent`, `monitor`, `workflow`) y `SessionEnd reason: clear` («el proceso sigue bajo otro id de sesión»),
pero no dicen si el `/clear` mata, conserva o pierde esas tareas; `$.agent.list()` no lista shells ni workflows. La
documentación oficial (`interactive-mode`, `commands`) tampoco lo dice. Sin prueba contraria, limpiar puede perder su
resultado.

## Decisión

1. **Una sola verdad.** La foto de agentes (la que escribe el Stop de `agentes.sh` desde `background_tasks`) guarda
   la descripción (40 caracteres, sin control) de cada tarea. `handoff --estado` devuelve `bloquea` («monitor (espera
   eterna); shell de fondo (oráculo)») con `nucleo_agentes_texto`, único sitio que lo redacta. El aviso del Stop cuenta
   todos los tipos y lo cita; el cockpit lo cita en el toast y la banda.
2. **Guardar ya, sin limpiar.** Al cruzar el umbral con trabajo vivo el automático guarda una vez (no arma el
   `/clear`: el mensaje de la persona nunca se retiene con algo vivo) y no repite el guardado mientras siga vivo.
3. **Limpiar al terminar.** Cuando un fin de turno ya no ve nada vivo (el aviso de tarea terminada abre ese turno),
   el automático sigue el camino de ADR 030: guarda de nuevo, arma el `/clear` para el siguiente mensaje o, con
   «AUTORIZADO: sí», limpia. Mismas guardas; el `/clear` nunca corre dentro de un hook que el turno espera.
4. **Aviso por cruce.** Toast con lo que bloquea y cómo desbloquearlo (esperar, o parar ese trabajo con `/tasks`), en
   cada cruce del umbral y cada vez que cambia el conjunto; no se repite si no cambia.

## Alternativas descartadas

- **Limpiar con lo vivo:** puede perder resultados; no hay prueba de lo contrario.
- **Armar el `/clear` también con lo vivo:** `holdForClear` ya deja pasar el mensaje con lo vivo y desarma, y cada
  turno volvería a guardar (1 fork por turno).
- **Un evento de «terminó lo último»:** la API del mod no lo ofrece; se usa el fin de turno que abre la notificación.
- **Matar el Monitor o la espera:** decide la persona.

## Consecuencias y riesgos

- Un Monitor que no termina nunca deja el estado guardado una vez y el `/clear` sin llegar; el toast lo dice.
- La foto se escribe en el Stop: si el cockpit la lee antes que el hook, puede ver aún lo ya terminado y esperar un
  turno más. `PostToolUse` ve la foto del último Stop, no los shells lanzados en el turno actual. A medir en F4.
- El texto de `bloquea` viene de descripciones de tareas: se muestra como dato, acotado, sin obedecerlo.
