# ADR 004 — Ni el coach ni los sensores bloquean la ejecución

**Fecha:** 2026-08-21 · **Estado:** aceptada

## Contexto

Dos componentes podrían interrumpir el trabajo: el **coach** (explicaciones pedagógicas) y
el **verify-gate** (aviso de trabajo sin verificar). La documentación oficial señala el Stop
hook como *"a deterministic gate"* que *"blocks the turn from ending until it passes"* — y
es tentador usarlo, porque es la forma más fuerte de garantizar que algo ocurra.

Contra esa tentación hay dos hechos locales:

1. El usuario tiene un incidente documentado con un hook que le tumbó el flujo, y una regla
   explícita: ningún hook que lance procesos de fondo, mate procesos o imponga presupuestos.
2. Un Stop hook bloqueante con un **falso positivo** deja la sesión atrapada. Claude Code lo
   anula tras 8 bloqueos consecutivos, pero para entonces el daño a la confianza ya está.

## Decisión

**Ningún componente de mcharness bloquea.**

- **Coach**: explica *después* o en paralelo, nunca antes de actuar. Tres niveles
  (`off|brief|full`) leídos de `config/profile.yaml`. Si una explicación retrasa el trabajo,
  sobra.
- **`verify-gate.sh`** (Stop): detecta trabajo sin verificar y **escribe un aviso a stderr
  con `exit 0`**. No impide terminar el turno.
- **`oracle-log.sh`** (PostToolUse) y **`session-brief.sh`** (SessionStart): puros
  observadores, `exit 0` siempre.

Todos con `timeout: 5` declarado. Latencia medida: **19, 15 y 23 ms**.

## La asimetría que decide

El coste de un **falso positivo bloqueante** (sesión atascada, confianza perdida, hook
desactivado para siempre) es mucho mayor que el de un **aviso ignorado** (nada). Cuando los
costes de los dos errores son así de asimétricos, se elige el error barato.

## Cómo se endurece, si hace falta

Esto no es una renuncia permanente. Es una decisión con condición de revisión:

> Si `oracle-log.sh` muestra que el aviso de `verify-gate` se ignora sistemáticamente
> durante varias sesiones con código modificado, **entonces** se promociona a bloqueante,
> con datos delante. Esa decisión se toma en `/retro`, no de entrada.

Es el *steering loop* de Böckeler aplicado al propio harness: el control se endurece cuando
la evidencia dice que el blando no bastó, no por si acaso.

## Alternativas descartadas

- **Stop hook bloqueante desde el principio.** Descartada por la asimetría de costes y por
  el incidente previo del usuario.
- **Coach bloqueante que exige confirmación de lectura.** Descartada: convertiría cada
  explicación en una interrupción, y el objetivo del harness es sacar al humano del bucle,
  no meterlo más.
- **Sin verify-gate.** Descartada: era el estado anterior, y el KPI de sesiones con oráculo
  valía 0.

## Consecuencias

El harness **puede ser ignorado**. Es deliberado: un harness que no se puede ignorar acaba
desinstalado. La contrapartida es que su eficacia depende de que los avisos sean pocos y
pertinentes — por eso `verify-gate` solo habla si hay ficheros modificados en un repo git,
y calla en sesiones de lectura.
