# ADR 015 — Handoff por defecto: híbrido determinista

**Fecha:** 2026-10-20 · **Estado:** aceptada · Matiza el ADR 013

## Contexto

El ADR 013 hizo del cockpit el que lanza el handoff solo, entre turnos. Pero `install.sh` no
instala el mod, así que un compañero recién instalado no lo tiene, y el coste del fork al 70 % y
el `/clear` interactivo siguen sin medirse. Sin el mod, lo que hay es el checkpoint de
PreCompact y la reinyección de SessionStart, y el estado puede llevar horas viejo cuando llega
la compactación: en esta máquina hubo 511 automáticas, el 96 % dentro de turnos autónomos.

## Decisión

- **Defecto, para todos:** checkpoint mecánico en PreCompact, reinyección en SessionStart
  (startup, clear, compact y resume) y avisos al 50/70/85 %. Además, **aviso de edad** tras
  compactar: si `nucleo.md` tiene más de 10 min y la sesión es la dueña, una línea pide
  refrescarlo con `handoff --desde`, con ruta absoluta si `handoff` no está en el PATH.
- **Cierre de fase:** `/handoff` manual.
- **Cockpit automático (70 % + `/clear`):** opción activable. Pasa a ser el defecto cuando
  la aceptación mida su coste y el `/clear`.
- Ningún hook llama a un modelo.

## Alternativas descartadas

- Fusión con modelo dentro de PreCompact: tope de 10 s, no puede inyectar contexto ni mostrar
  nada, ve el transcript a medio cortar, se llama a sí mismo en `claude -p`, compite con el
  cockpit y cuesta una llamada por compactación.
- Fusión en Stop: una llamada a modelo por turno.
- Bloquear la autocompactación hasta tener el estado fresco: si la compactación era de
  recuperación tras un error de límite, la petición falla.
- Todo manual, sin PreCompact: se pierde el único seguro gratis y la compactación sigue llegando.

## Consecuencias

- Coste 0, falla en abierto y no escribe en `nucleo.md`, así que no crea carreras.
- El compañero no necesita saber qué es `/handoff` para no perder el encargo.
- Riesgo por vigilar: que el aviso de edad se repita en bucle tras una compactación de
  recuperación (el test lo cubre).
