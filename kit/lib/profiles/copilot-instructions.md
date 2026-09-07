# copilot-instructions.md — perfil nativo de GitHub Copilot (proyectado por M)

Este fichero es la instruccion nativa de GitHub Copilot CLI. Lo PROYECTA y lo
POSEE M (mcharness) via su contrato de proyeccion; S nunca lo escribe ni puede
huerfanizarlo. Es el equivalente a `CLAUDE.md`/`AGENTS.md` para Copilot.

## Gobierno de la tarea

Este entorno esta gobernado por `mch` (mcharness). Antes de dar por terminado un
turno, el gate MANUAL de Copilot (`copilot_manual_gate.sh`) consulta al gate v2
de M y traduce su veredicto a una puerta explicita pre/post:

- VERDE (rc0) o proyecto no gobernado (rc3): la puerta permite.
- ROJO (rc1) o cualquier fallo del gate: la puerta bloquea; repara la causa, no
  el sensor, y cierra la tarea en `mch` cuando el oraculo pase.

Esta puerta es MANUAL y no se equipara a un hard-stop nativo.

## Ciclo de vida: enforcement ACOTADO por el tope de 8 bloqueos

Copilot SI expone un ciclo de vida nativo por `agentStop`/`subagentStop`: un hook
que devuelve `decision: "block"` fuerza otro turno. Pero es un enforcement
ACOTADO: tras 8 respuestas de bloqueo CONSECUTIVAS, Copilot FUERZA la parada pase
lo que pase. Por eso el ciclo de vida de este perfil es DEGRADADO (`block_cap` =
8), nunca `lifecycle-enforced`. El contador de bloqueos se RESETEA en cuanto un
turno cierra en verde. No se debe declarar el ciclo de vida como enforced sin un
runner externo aprobado por separado, que en esta rama no existe.

## Confianza (trust-gate) de hooks, extensiones y MCP

Los hooks de sesion, las extensiones y los servidores MCP solo se activan bajo el
trust-gate del propio Copilot (folder trust). Un hook de politica machine-wide
puede imponerse; los hooks de repositorio, usuario y plugin solo corren si la
carpeta esta confiada. No se copian credenciales de GitHub a ningun sitio, y no
se lee `~/.copilot`/`auth.json` ni variables con tokens.

## Provider

En esta maquina el transporte del modelo va en modo BYOK contra un proxy local
(`COPILOT_PROVIDER_TYPE`/`COPILOT_PROVIDER_BASE_URL`), NO contra el enrutado real
de GitHub Copilot. Certificar "Copilot" en esas condiciones seria certificar otro
proveedor con la etiqueta equivocada (identity drift): la certificacion real
(todo 25) debe sellar la identidad resuelta (binario realpath, version, endpoint)
antes de afirmar nada.
