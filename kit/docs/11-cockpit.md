# 11 · Cockpit: handoff y Agent Dock

`kit/mods/cockpit/` es un mod de Claude Code (plugin de *function hooks*, superficie de acceso temprano: puede cambiar entre versiones). Aporta dos cosas y es opt-in: `install.sh` no lo carga.

## Qué hace

- **`/handoff`**: pide al modelo el borrador de las secciones del estado y se lo entrega al CLI `~/.claude/bin/handoff`, que lo valida y lo fusiona en `.claude/estado/nucleo.md`; después limpia el contexto (`/clear`) y la sesión nueva lo recibe del hook `SessionStart`.
- **Handoff automático**: al cerrar un turno con el contexto al 70 % del límite de autocompactación, el mod guarda el estado con el mismo handoff, hace `/clear` y deja escrito en el prompt «adelante con la Siguiente acción…: <su primera línea>».
- **`/nueva <tarea>`**: cambia de tarea. Archiva el `nucleo.md` actual, limpia el contexto y deja la tarea nueva en el prompt.
- **Agent Dock**: un panel lateral con la misión en curso y los subagentes en cuatro secciones fijas (trabajando, en cola, parados, hechos). Muestra también el dueño del estado y el % del tope del `nucleo.md`. Lleva además el vigía de contexto con handoff sobre el prompt y `/simple` (modo de pasos con resumen corto).

## Cómo se carga

**Versión de Claude Code.** El mod se probó con Claude Code 2.1.292 (`claude --version`). No se ha comprobado una versión mínima: los mods son de acceso temprano y pueden cambiar entre versiones. Comprueba la tuya antes de instalar y, si algo no carga, `claude plugin validate kit/mods/cockpit` dice qué falla.

**Va con la versión del kit.** El marketplace no fija una versión: instala lo último de la rama `main`, no el tag con el que instalaste el kit. Por eso el kit y el cockpit se actualizan juntos: tras pasar el kit a otra versión (ver «Actualizar» en [`02-install.md`](02-install.md)), ejecuta también `claude plugin update cockpit@setup-claude-code`. Para fijar una versión, instala desde una copia del tag.

Este repo es un marketplace (`.claude-plugin/marketplace.json`). Para todas tus sesiones, en scope user, desde el prompt de una sesión de terminal:

```
/plugin install cockpit --marketplace manuelcozar55/setup-claude-code
```

o desde la shell: `claude plugin install cockpit --marketplace manuelcozar55/setup-claude-code` (también lo hace `kit/install-plugins.sh --apply`). Se actualiza con `claude plugin update cockpit@setup-claude-code` y se quita con `claude plugin uninstall cockpit@setup-claude-code`.

Para desarrollarlo desde una copia de trabajo, sin instalar:

```bash
claude --plugin-dir <ruta>/kit/mods/cockpit
```

## `/handoff`

```
/handoff [solo] [foco de la próxima sesión]
```

- Sin argumentos: guarda el documento y hace `/clear`. El mod no envía ningún prompt: el hook `kit/claude/hooks/session-start-clear.sh` (SessionStart `startup|clear|resume`) entrega `nucleo.md` a la sesión nueva como datos, con el protocolo de arranque (con proyecto llega además un bloque `<git-hechos>` con `git log --oneline -5` y `git status --short` que calcula el hook, así que el paso 1 ya no pide ejecutarlos; después, propuesta del oráculo rápido; si el estado contradice a git, manda git; ningún comando del nucleo, tampoco la «Siguiente acción», corre sin que confirmes). Desde `~` (o `~/.claude`) no se inyecta un nucleo sino un `<indice-tareas>` (también tras compactar; el aviso de contexto y la puerta de commit tampoco tratan el nucleo de `~` como propio), derivado del registro `~/.claude/estado/raices`, con las líneas `(persona)` de los pendientes de cada tarea. Pulsa Enter sobre el prompt que el mod deja relleno (si no pudo rellenarlo, te dice qué escribir). Así un mensaje tuyo enviado durante el `/clear` no compite con un prompt del mod.
- `solo`: guarda el documento y no limpia nada. No confundir con el CLI: `/handoff solo` es el argumento del mod (guarda sin `/clear`), mientras que `handoff --solo` es una opción del CLI y significa otra cosa: el borrador sustituye al `nucleo.md` entero en vez de fusionarse.
- El resto del texto es el **foco**: el documento se adapta a lo que hará la próxima sesión.
- En la banda sobre el prompt, el botón `handoff` (`h`) pide confirmación con tres acciones: `[guardar + /clear]`, `[solo guardar]` y `[no guardar + /clear]` (limpia el contexto sin escribir handoff), dibujadas sin cromo y sin tecla propia: un clic o Enter bajo el foco. Para cancelar, vuelve a pulsar `handoff`. Durante un turno en marcha solo queda `solo guardar`.

El documento es `.claude/estado/nucleo.md` de la raíz del proyecto, la convención de estado que ya leen CLAUDE.md, los hooks PreCompact y la re-inyección tras compactar. **La raíz es** la raíz git del cwd de la sesión, salvo que sea `$HOME` o cuelgue de `$HOME/.claude`; sin git tampoco hay proyecto. Sin proyecto el mod no hace fork ni escribe nada y lo dice.

**Reparto de trabajo.** El fork del modelo solo redacta un borrador con las secciones de la plantilla (`kit/claude/templates/nucleo.md`): Plan, Paso actual, Siguiente acción, Pendientes, Comandos de verificación y Ficheros tocados, y Objetivo e Invariantes cuando faltan o están vacíos. Pide además tres campos baratos: las correcciones literales de la persona (hasta 3 líneas, con fecha, en Invariantes), los ficheros calientes con rango (`ruta:L120-180 — qué`) y el resultado de cada comando de verificación (`→ rc=N`, que el CLI pliega desde `verificaciones.log`). El mod no fusiona nada: no queda en TypeScript ninguna función de fusión, rotación de copias ni exclusión de git; lo hace `handoff` (`test_mod_cockpit.sh` lo comprueba).

**Cómo se entrega.** Antes de escribir se redactan claves conocidas (`sk-`, `ghp_`, `AKIA`, `xox*`, JWT), asignaciones tipo `password=`/`token:`, `Bearer …`, bloques `PRIVATE KEY`, credenciales en URLs, `github_pat_`/`glpat-` y valores entrecomillados: una red de seguridad parcial, porque la redacción principal la hace el prompt. El borrador va a un fichero temporal propio (`mktemp`, permisos 600, borrado siempre al terminar, también si el CLI falla) y el mod ejecuta, con la ruta absoluta (no depende del PATH):

```
$HOME/.claude/bin/handoff --desde <borrador> --raiz <raíz> --sesion <id>
```

Si el binario no existe el mod avisa con la orden de instalación (`bash kit/install.sh`, que copia `handoff` y `oraculo` en `~/.claude/bin`) y no hay fusión de reserva en TypeScript.

| Exit | Significado | Qué dice la UI |
|---|---|---|
| 0 | Fusionado | «Guardado en …/nucleo.md» y, salvo `solo`, `/clear` |
| 2 | Borrador inválido | «borrador inválido: <cabecera que nombra el CLI>; repite /handoff» |
| 3 | Sin proyecto | «aquí no hay proyecto …: no hay estado que guardar» |
| 4 | `nucleo.md` cambió durante la fusión | Reintenta una vez con el mismo borrador; si vuelve a fallar, «cambió durante la fusión (dos intentos); repite /handoff» |

Si la respuesta del fork no trae ninguna sección `## ` no se escribe nada. Si `.claude/estado/`, `nucleo.md` o una copia `nucleo.prev-*` son enlaces simbólicos, el handoff se niega a leer y escribir. Copias, límite de tamaño, `diario.md`, exclusión de `.git/info/exclude` y dueño son del CLI.

Secciones fijas (las fija el CLI: se escriben una sola vez): Objetivo · Invariantes. Secciones que actualiza cada handoff: Plan (`[x]` con el comando que lo verificó, que el CLI mueve a `diario.md` / `[ ]`) · Paso actual · Siguiente acción · Pendientes (incluye riesgos; las líneas que solo puede hacer la persona empiezan por `(persona)` y el índice de `~` las reúne) · Comandos de verificación · Ficheros tocados (los de fuera de git con su copia de seguridad). No duplica specs, planes, issues ni commits: los referencia por ruta o URL.

```mermaid
flowchart LR
  A["/handoff [solo] [foco]"] --> B["Generación<br/>(fork del modelo)"]
  B --> C["Redacción de secretos<br/>+ borrador temporal 600"]
  C --> D["handoff --desde<br/>(el CLI valida y fusiona en nucleo.md)"]
  D --> E{"¿solo?"}
  E -->|"sí"| F["Fin: ruta en pantalla"]
  E -->|"no"| G["/clear"]
  G --> H["Hook SessionStart(clear):<br/>nucleo.md como datos"]
  G -.->|"falla"| I["Escribe /clear a mano"]
  T["Turno principal cerrado<br/>(contexto ≥ umbral)"] -->|"automático"| B
  G -->|"automático"| P["Rellena el prompt:<br/>«adelante con la Siguiente acción…: primera línea»"]
```

## Handoff automático

Se activa solo, sin comando.

**Disparo.** Al cerrar un turno del bucle principal (`reason` `answer`) con el contexto en o por encima del umbral, un porcentaje del límite de autocompactación. El mod:

1. Guarda el estado con el mismo handoff que `/handoff`.
2. Hace `/clear` desde `$.clock.after`: dentro del hook que el turno espera, el motor lo rechaza.
3. Deja «adelante con la Siguiente acción de .claude/estado/nucleo.md: <primera línea de «Siguiente acción»>» en el prompt, sin enviarlo: así aprobarás sabiendo qué sigue. La línea sale del documento ya fusionado, sin marcador de lista ni caracteres de control y cortada a 200 caracteres; el prefijo fijo impide que el relleno empiece por `/` o `!`. Sin esa línea, el relleno es «sigue con la Siguiente acción de .claude/estado/nucleo.md». La UI cuenta lo que pasó: «revisa el prompt y pulsa Enter», «escribe: <texto>» si el prompt no se pudo rellenar, o «/clear falló: escribe /clear y luego <texto>».

Rellena el prompt (`$.prompt.fill`) y no lo envía (`prompt.submit`) porque un prompt enviado tras `/clear` se perdía (14-oct). La sesión nueva recibe `nucleo.md` del hook `SessionStart`, como en `/handoff`; tú pulsas Enter.

**Configuración.** Variable `COCKPIT_AUTO_HANDOFF`:

| Valor | Efecto |
|---|---|
| `off` | Desactivado. |
| Entero de 50 a 95 | Umbral en % del límite de autocompactación. |
| Cualquier otra cosa, o vacío | 70. |

**Cuándo no actúa.**

- En un subagente: solo cuenta el bucle principal.
- Con subagentes o teammates sin terminar.
- Con un handoff en curso o en error.
- Sin proyecto (la raíz es `$HOME`, cuelga de `$HOME/.claude` o no hay git): no hay estado propio de la tarea.
- Si empieza otro turno entre el guardado y el `/clear`: no limpia, deja el documento guardado y avisa.

**Veto de compactación.** Si la autocompactación salta a mitad de turno (`session.compact` con `trigger` auto), el mod la pospone para que el handoff llegue al cerrar el turno, que entonces lo dispara aunque no se haya llegado al umbral. El techo es `min(1,5 × límite, 0,5 × ventana real del modelo)`. Pasado el techo, compacta como siempre. En ventanas de 200k el techo queda por debajo del límite y el veto no actúa. Cede también en subagentes, con `off`, sin proyecto, con el handoff en error y si la lectura del contexto falla.

## `/nueva`

```
/nueva <la tarea nueva>
```

Cambia de tarea sin arrastrar el contexto. Si hay `nucleo.md`, guarda primero el estado con el handoff, lo mueve a `.claude/estado/archivo/nucleo-<sello UTC>.md`, hace `/clear` y deja la tarea nueva escrita en el prompt. Sin argumento muestra el uso.

- Sin proyecto no hay estado por tarea: solo hace `/clear` y deja la tarea en el prompt, con el aviso.
- No corre con un turno o un handoff en marcha: repítelo cuando termine.
- Si el handoff falla o no puede archivar, no limpia.

## Agent Dock

Se abre solo al iniciar sesión (columna de 66 de ancho) y con `/dock`.

**Misión.** Plegada por defecto en una sola línea, cortada en `…` al ancho del pane, para que los agentes ocupen las filas; la cabecera lleva el porcentaje y el tiempo del turno (`10m42s`). Si no cabe en una línea, la cabecera lleva el botón `▸ más`: un clic o Enter con el foco la despliega entera y `▾ menos` la pliega. Una misión nueva nace plegada. El texto va fuera del botón a propósito: un `Button` no acota a su hijo, así que un `Text` con `wrap` dentro de él no envuelve nunca (por eso el clic de la versión anterior "no hacía nada": desplegaba una sola línea cortada por el borde). Debajo, la barra de progreso (pasos completados o, sin lista de pasos, agentes de la misión completados: un fallo no suma) y, durante el turno, la actividad del agente principal.

**Estado.** Bajo la misión, dos líneas: `nucleo N% del tope` (en el color del vigía) y `dueño: esta sesión | otra sesión (<id>) | ninguno` (con «vencido» si el dueño pasó su TTL). Salen de `handoff --estado --raiz <raíz>`, la única fuente: el mod no calcula el tope ni el dueño. La lectura nunca la espera el dibujo: se refresca al abrir la sesión, al cerrar un handoff y cada 20 s desde el sondeo de agentes, con un timeout de 2 s; sin proyecto, sin binario o con el CLI caído la fila no se dibuja.

**Agentes.** Una columna a cualquier ancho y cuatro secciones fijas con su cuenta, también a cero (atenuadas), en orden de urgencia: `Trabajando`, `En cola`, `Parados` (fallados `✗`, detenidos `■` y atascados `◌`: más de 2 min sin ninguna herramienta en marcha; una llamada larga, como un `make test` de 4 min, es actividad hasta que vuelve) y `Hechos`. Se dibujan todos los agentes de la sesión, sin tope ni `… y N más`: el pane hace scroll. Cada agente es una línea: glifo de estado, `T<n>` por orden de arranque, descripción truncada y tiempo fijo a la derecha. Solo la descripción cede ancho: el prefijo y el tiempo no se encogen nunca, así que el tiempo no se parte en dos líneas por estrecho que sea el pane. El tiempo lleva unidades (`45s`, `10m42s`, `1h05m`) porque un `10:42` a secas se leía como una hora del día. Los que trabajan añaden una segunda línea con su última herramienta (`Bash Ejecutar los tests`, `Read checkout/precio.ts`: de una ruta queda la cola, que es lo que se ve al truncar), y los parados, su motivo (`falló`, `2m10s sin actividad`). Un agente `waiting` (aprobación de un plan o tarea en segundo plano) o `idle` (un teammate entre turnos) sigue en `Trabajando` con ese motivo y no se atasca: no le toca llamar a ninguna herramienta. Si el pane es más bajo que la lista, el motor hace scroll (flechas con el pane enfocado); lo urgente queda arriba. Los botones de `Equipo` van bajo la cabecera, antes de la misión: es el mando que se toca antes de empezar. El tamaño de equipo viaja al modelo como contexto oculto del prompt. Los tests miden el texto dibujado a 24, 30, 44, 56 y 66 columnas, incluidos los estados fallado, detenido y atascado.

## Tests

```bash
cd kit/mods/cockpit
claude plugin validate .                          # Validation passed
claude plugin test .                              # 89 pass, 0 fail (tests/handoff.test.tsx lleva los del handoff)
pnpm dlx --package=typescript@5 tsc -p .          # rc=0
bash ../../test/test_mod_cockpit.sh                # estructura y saneado; sin red ni claude
```

`tsconfig.json` extiende `.claude-plugin/types/tsconfig.json`, que **no se versiona**: lo escribe Claude Code junto al mod cuando lo carga desde una carpeta propia (versión TypeScript 5.4 o superior) y su contenido es de Claude Code, no nuestro. Si falta, `tsc` falla con `Cannot find module 'claude-code/testing'`. Para regenerarlo, carga el mod una vez, por ejemplo `claude -p --plugin-dir "$PWD" "ok"`; si en tu versión no aparece, copia la carpeta `.claude-plugin/types/` de otro mod ya cargado. Está en `.gitignore`. `validate` y `test` no lo necesitan. Sin esos tipos `tsc` pierde el `noEmit` heredado y escribe `.js` junto a las fuentes: bórralos si pasa.

`claude plugin test` funciona desde cualquier carpeta, no solo desde dev-mods.

## Limitaciones conocidas

- **`/clear` lanzado desde el mod no está verificado en una sesión interactiva.** Se comprobó de punta a punta con el arnés de tests, no a mano. Si falla, el mod deja el documento guardado; escribe `/clear` y luego el texto que te indica el mod.
- **Sin verificar en una sesión interactiva** (solo con el arnés de tests): el `/clear` lanzado desde el temporizador tras un turno, el relleno del prompt después de él, el comportamiento del motor tras varios vetos de compactación seguidos y el coste del fork del handoff al 70 % de contexto.
- **El clic sobre el dock solo llega en pantalla completa**: es donde el terminal reporta clics (y donde existe el dock lateral). Con el pane encajado sobre el prompt, enfócalo (`ctrl+x tab`) y usa la tecla `m` o Tab + Enter.
- El redactor de secretos es un último recurso parcial; revisa el documento antes de compartirlo.
- **Permisos del borrador temporal**: la API `$.fs.write(path, text)` no admite modo; el borrador se crea con `mktemp` (600) y se vuelve a fijar con `chmod 600` antes de escribirlo. El permiso del `nucleo.md` final es cosa del CLI.
- El hook de arranque entrega `nucleo.md` envuelto como datos y exige confirmar lo irreversible, pero eso mitiga la inyección de instrucciones escritas en el fichero, no la elimina.
