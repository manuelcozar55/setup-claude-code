# SCC · setup-claude-code

**v2.3.0, estable** · cockpit: 0.11.1 · necesita Claude Code 2.1.311 o posterior, bash ≥ 5, jq, git y python3 · Linux o WSL2.

SCC frena en tu Claude Code los errores caros (borrados destructivos, un push a `main`, secretos en un commit) y guarda
el estado de cada tarea para que un `/clear` o una compactación no te la haga perder.
Es para quien ya usa Claude Code a diario y quiere esos controles comprobados por tests, no supuestos.
No es un tutorial de Claude Code ni funciona en Windows nativo ni en macOS (en Windows, abre antes WSL2).

> **Aviso: no abras Claude Code dentro de este clon para usar el kit.** La raíz del repo contiene el andamiaje de
> desarrollo de su autor (`.claude/`, con un hook `Stop` que avisa si tocaste código sin verificar y, en modo autónomo, te retiene hasta que
> `make test` pase: unos minutos). Se instala
> desde aquí, se usa desde tus proyectos, y solo se abre Claude Code aquí para contribuir al propio kit.

## Un ejemplo

```text
$ git push origin main
BLOCKED: Attempted push to protected branch 'main'.
Command: git push origin main
Que hacer: empuja a una rama de feature y abre un PR; si de verdad quieres empujar ahi, ejecutalo tu con ! en la sesion.

> /clear        (la sesión nueva recibe:)
Hay trabajo en curso en ~/proyecto (estado en ~/proyecto/.claude/estado/nucleo.md). Protocolo de arranque, antes de nada más: …
```

Las cuatro primeras líneas son la salida real del guard. La última es el principio de lo que el kit entrega a la sesión
nueva, seguido del objetivo, las invariantes y el siguiente paso que había en `nucleo.md`.

## Instalar

Clona el repo dentro de WSL2 o Linux (no en `/mnt/c/`) y, desde el clon:

```bash
bash kit/install.sh
```

Instala solo lo esencial en `~/.claude`, con copia de lo que sobrescribe, y acaba con el veredicto de `doctor.sh`
(`==> doctor: OK, N WARN`). Sale con código 1 si el doctor da algún FAIL. Para ver antes qué haría: `bash kit/install.sh --plan`.
Después reinicia las sesiones abiertas de Claude Code. Si dice que `~/.local/bin` no está en tu `PATH`, añade
`export PATH="$HOME/.local/bin:$PATH"` a tu `~/.bashrc`.

Para usarlo, abre `claude` como siempre.

## Tres ideas

- **Guards.** Scripts que se ejecutan antes de cada orden de Bash y la bloquean si es peligrosa, sin depender del modelo.
  Qué cubren y qué no: [`SECURITY.md`](SECURITY.md).
- **Estado automático.** Tras cada turno se guarda `.claude/estado/nucleo.md` (objetivo, plan, siguiente paso). Se crea solo
  en el primer guardado con trabajo en un repo git. Tras `/clear` o una compactación, la sesión nueva lo recibe sola (hasta 6500 bytes, `NUCLEO_TOPE`).
  Cómo funciona: [`12-metodologia.md`](kit/docs/12-metodologia.md).
- **`/deep-change`.** Para un cambio grande, ambiguo o de riesgo: diseño aprobado antes de ejecutar, commits con su porqué
  y verificación con el código de salida real. Lo pequeño se hace directo.

## Piezas opcionales

No se instalan por defecto. Se piden con `bash kit/install.sh --con <pieza>[,<pieza>…]`:
`sentinel` (un guard más, sobre cualquier herramienta), `cockpit` (lanzador `scc` con `/handoff` y Dock de agentes),
`esenciales` (plugin de skills), `revisores` (los agentes `silent-failure-hunter` y `pr-test-analyzer`), `skills-extra` (`retro` y
`verification-before-completion`) y `nudge` (avisos de contexto). Cada una se explica en [`OPERAR.md`](kit/docs/OPERAR.md) (sección «Piezas opcionales»).
Una actualización no quita lo que ya tenías instalado y te dice cómo quitarlo.

## Requisitos

Los que comprueba `install.sh` antes de escribir nada: `bash` ≥ 5, `git`, `jq` y `python3` (sin él quedan apagados
`write-guard` y `stale-read-guard`, y el instalador lo dice y pide `--sin-python`). Además `flock` (util-linux)
y, para las copias de seguridad, `zip` y `unzip`. Claude Code instalado y con sesión iniciada: `claude --version`.
En Debian/Ubuntu: `sudo apt install git jq python3 zip unzip` (lo lanzas tú; el kit no instala paquetes del sistema).

## Desinstalar

```bash
bash uninstall.sh --kit            # simulacro: lista lo que borraría
bash uninstall.sh --kit --apply    # borra lo que instaló, con copia previa
```

Conserva lo que modificaste y deshace en `settings.json` solo lo que el kit añadió.

## Para seguir

- [`kit/docs/10-onboarding.md`](kit/docs/10-onboarding.md): primer día, paso a paso.
- [`kit/docs/OPERAR.md`](kit/docs/OPERAR.md): qué hacer cuando una orden legítima se bloquea, qué hace el kit solo, costes, actualizar.
- [`kit/docs/MAPA.md`](kit/docs/MAPA.md): qué hace cada hook, agente, skill y variable, y cómo se apaga.
- [`SECURITY.md`](SECURITY.md): qué protegen los guards y qué no.

Si recibiste el paquete por transferencia, [`ENTREGA.md`](ENTREGA.md) explica cómo verificar su integridad.
Para contribuir: [`CONTRIBUTING.md`](CONTRIBUTING.md) (`make test`, `kit/` tiene 67 suites).
