# SCC · setup-claude-code

**v1.10.1, estable** · cockpit: 0.9.0 · necesita Claude Code 2.1.311 o posterior, bash ≥ 5, jq, git y python3 · Linux o WSL2.

SCC configura tu Claude Code con controles que actúan antes de cada herramienta (bloquean borrados destructivos,
pushes a ramas protegidas y secretos escritos en ficheros), guarda el estado de cada tarea para retomarla tras un
`/clear` o una compactación, y trae un conjunto de agentes y skills de trabajo.
Es para quien ya usa Claude Code a diario y quiere esos controles comprobados por tests, no supuestos.
No es un tutorial de Claude Code ni funciona en Windows nativo ni en macOS (en Windows, abre antes WSL2).

> **Aviso: no abras Claude Code dentro de este clon para usar el kit.** La raíz del repo contiene el andamiaje de
> desarrollo de su autor (`.claude/`, con un hook `Stop` que avisa si tocaste código sin verificar y, en modo autónomo, te retiene hasta que
> `make test` pase: unos minutos). Se instala
> desde aquí, se usa desde tus proyectos, y solo se abre Claude Code aquí para contribuir al propio kit.

## Qué cambia en tu Claude Code

- **Escribe en `~/.claude`**: hooks, agentes, skills, `CLAUDE.md`/`AGENTS.md`, comandos `handoff`, `oraculo`, `cupo`, `efectividad`
  y `scc`. Fusiona tu `settings.json` sin pisar lo tuyo, hace copia de lo que sobrescribe y no toca un `CLAUDE.md` tuyo.
- **Latencia**: cada orden de Bash pasa por cinco guards y por Sentinel antes de ejecutarse. Son scripts locales; cómo medirlo
  en tu máquina está en [`OPERAR.md`](kit/docs/OPERAR.md).
- **Contexto fijo**: el kit añade sus reglas, las descripciones de agentes y skills y, si el proyecto tiene estado,
  hasta 6500 bytes de `nucleo.md` al arrancar. Cuánto es en tu instalación: también en `OPERAR.md`.
- **Llamadas al modelo**: sin el cockpit, ninguna; todo son scripts. Con el cockpit (`scc`), el handoff automático al 70 %
  del contexto hace una; `/autosave` está apagado y, si lo enciendes, gasta tokens en cada guardado.
- Puede bloquear una orden legítima. Cómo ver qué guard fue, dejarla pasar o quitarlo: `OPERAR.md`.

## Requisitos

Los que comprueba `install.sh` antes de escribir nada: `bash` ≥ 5, `git`, `jq` y `python3` (sin él quedan apagados
Sentinel, `write-guard` y `stale-read-guard`, y el instalador lo dice y pide `--sin-python`). Además `flock` (util-linux)
y, para las copias de seguridad, `zip` y `unzip`. Claude Code instalado y con sesión iniciada: `claude --version`.
En Debian/Ubuntu: `sudo apt install git jq python3 zip unzip` (lo lanzas tú; el kit no instala paquetes del sistema).

## Instalar

Clona el repo dentro de WSL2 o Linux (no en `/mnt/c/`) y, desde el clon:

```bash
bash kit/install.sh --plan     # qué haría; no escribe nada
bash kit/install.sh --apply    # instala en ~/.claude, con copia de lo que sobrescribe
bash kit/doctor.sh             # comprueba la instalación
```

`--apply` termina diciendo «Reinicia las sesiones abiertas de Claude Code»; `doctor.sh` termina en `== OK (0 FAIL) ==`.
Si dice que `~/.local/bin` no está en tu `PATH`, añade `export PATH="$HOME/.local/bin:$PATH"` a tu `~/.bashrc`.

## Usar

- Con cockpit (recomendado): `scc` lanza Claude Code con el cockpit y los plugins del kit. `scc --version` imprime la versión
  del kit, la del cockpit y la de Claude Code.
- Sin cockpit: `claude` a secas. Los guards, los hooks y el estado automático funcionan igual; faltan `/handoff`, `/nueva`,
  `/autonomo`, `/dock`, `/simple` y `/autosave`. Con `install.sh --apply --sin-cockpit` ni siquiera se copia.

## Desinstalar

```bash
bash uninstall.sh --kit            # simulacro: lista lo que borraría
bash uninstall.sh --kit --apply    # borra lo que instaló, con copia previa
```

Conserva lo que modificaste y deshace en `settings.json` solo lo que el kit añadió.

## Tres sitios para seguir

- [`kit/docs/OPERAR.md`](kit/docs/OPERAR.md): qué hacer cuando algo te estorba o falla, actualizar, desinstalar, costes.
- [`kit/docs/MAPA.md`](kit/docs/MAPA.md): qué hace cada hook, agente, skill y variable, y cómo se apaga.
- [`SECURITY.md`](SECURITY.md): qué protegen los guards y qué no.

Si recibiste el paquete por transferencia, [`ENTREGA.md`](ENTREGA.md) explica cómo verificar su integridad.
Para contribuir: [`CONTRIBUTING.md`](CONTRIBUTING.md) (`make test`, `kit/` tiene 61 suites).
