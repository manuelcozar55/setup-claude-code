# AGENTS.md — perfil nativo de Codex (proyectado por M)

Este fichero es la instruccion nativa de Codex (formato AGENTS.md oficial). Lo
PROYECTA y lo POSEE M (mcharness) via su contrato de proyeccion; S nunca lo
escribe ni puede huerfanizarlo. Es el equivalente a `CLAUDE.md` para Codex.

## Gobierno de la tarea

Este entorno esta gobernado por `mch` (mcharness). Antes de dar por terminado un
turno, el gate MANUAL de Codex (`codex_manual_gate.sh`) consulta al gate v2 de M
y traduce su veredicto a una puerta explicita pre/post:

- VERDE (rc0) o proyecto no gobernado (rc3): la puerta permite.
- ROJO (rc1) o cualquier fallo del gate: la puerta bloquea; repara la causa, no
  el sensor, y cierra la tarea en `mch` cuando el oraculo pase.

Esta puerta es MANUAL y NO es un hard-stop nativo. Codex no expone un Stop nativo
probado en esta rama, asi que su ciclo de vida es DEGRADADO: la puerta manual
nunca se equipara a enforcement de ciclo de vida.

## Sandbox

Ejecuta en sandbox `read-only` por defecto para las sondas y la exploracion. Solo
`mch oracle --run` y `mch task run` ejecutan proyecto, con argv JSON y sin shell.
No hagas llamadas de red en discovery/doctor/gate.

## Provider

El transporte al modelo puede ir por el provider Responses (OpenAI) directo o,
opcionalmente y solo si la matriz de Wave 0 lo declara y certifica, por Headroom.
El fragmento `codex-config.fragment.toml` describe ese provider; se aplica por
DIFF, nunca se pisa tu `config.toml`.
