# Informe de cambios — desacoplar Headroom del kit

Rama: `harden/headroom-decoupling` (desde `v2-autonomous`).
Copia aislada: `~/work/cc-setup-b`. **Nada aplicado a `~/.claude` de esta máquina.**

Una entrada por modificación: qué / por qué / cómo se verificó.

## Punto de partida (hallazgos que motivan la rama)

Verificado antes de tocar nada, sobre `v2-autonomous` @ `44a1662`:

1. `kit/claude/settings.json:6` fijaba `ANTHROPIC_BASE_URL=http://127.0.0.1:8787` y
   `kit/install.sh:85` lo copiaba tal cual, pero `install.sh:195` declara Headroom como
   componente de terceros que el kit **no** instala. Una instalación limpia enrutaba todo el
   tráfico de la API a un puerto donde no escucha nadie.
2. `kit/doctor.sh:62` reportaba eso como `warn`, y `README.md:31` afirmaba que un `WARN` de
   Headroom es aceptable porque "el setup base funciona sin ellos". No era cierto: `doctor.sh`
   salía con código 0 en una máquina incapaz de hablar con la API.
3. `kit/claude/settings.json` invocaba `rtk hook claude` y
   `$HOME/.venvs/tools/bin/python3` (este último con `matcher: ""`, es decir en **toda** llamada
   a tool) sin que `install.sh` provea ninguno de los dos → exit 127 en cada llamada.
4. `kit/docs/03-headroom.md` presentaba Headroom y `rtk` como el mismo producto
   ("Instalar Headroom (`rtk`)"). Son dos herramientas distintas.

---
</content>
