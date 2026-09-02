# Política de seguridad

## Reportar una vulnerabilidad

Si encuentras una vulnerabilidad de seguridad en este repositorio, repórtala
en privado, no abras un issue público:

- **GitHub Security Advisories** (preferido): pestaña "Security" →
  "Report a vulnerability" en
  https://github.com/manuelcozar55/setup-claude-code
- O por correo a **manuelcozar55@gmail.com**

Incluye pasos para reproducir, impacto esperado y, si puedes, una prueba de
concepto mínima. Se responde en un plazo razonable; no hay SLA formal (esto
es un proyecto personal en abierto).

## Qué protege este kit, y qué no

Los guards de `kit/claude/hooks/` y `kit/sentinel/` son **defensa en
profundidad, no un límite de seguridad duro**. Están pensados para acotar el
radio de impacto de un fallo o un comando destructivo generado por el agente,
no para contener a un adversario activo que controle el prompt o el entorno.
Documentamos sus límites conocidos en vez de esconderlos: un proyecto de
seguridad que declara dónde se rompe es más creíble, no menos.

### Capa 1 — guards por nombre de fichero/comando (`secret-guard.sh` y afines)

Estos hooks `PreToolUse` inspeccionan el **texto del comando `Bash`** antes de
ejecutarlo. No son un tokenizador de shell ni un intérprete de `git`: miran
patrones de texto, no el efecto real del comando. Formas conocidas de
esquivarlos:

- `git -C otra/ruta add secreto.env` — el flag `-C` cambia el directorio de
  trabajo antes del patrón que el guard busca.
- `xargs git add secreto.env` — el nombre del fichero llega por `xargs`, no
  aparece literal en el comando que ve el hook.
- Prefijos de entorno: `FOO=bar git add secreto.env`.
- `command git add secreto.env` — el builtin `command` es semánticamente
  idéntico a `git add` pero no matchea el patrón literal.
- Alias, funciones de shell, subshells y expansión de pathspecs en general:
  adivinar con certeza el efecto de una cadena de shell arbitraria exigiría,
  en el límite, un tokenizador de shell completo y un resolvedor de
  pathspecs de git corriendo dentro del presupuesto de tiempo de un hook; y
  aun logrado, seguiría mirando el árbol de trabajo declarado en el comando,
  no lo que de verdad queda en el índice al hacer commit.

Un hook `PreToolUse` no es eso, y esta capa no pretende serlo.

### Capa 2 — `gitleaks` en `pre-commit` (contenido real)

Por eso existe una segunda capa (`kit/claude/hooks/git/pre-commit` +
`kit/claude/.gitleaks.toml`): en vez de adivinar el comando, escanea el
**contenido real que queda staged** justo antes del commit. Esto cierra el
hueco de la Capa 1 para credenciales con firma textual reconocible (claves de
API con prefijo conocido, alta entropía, patrones tipo `PASSWORD=` en
ficheros de config) sin importar cómo llegaron al índice.

**Lo que la Capa 2 no cubre:** contenido binario sin firma textual —
keystores binarios (`.jks`, `.p12`/`.pfx` con contenido opaco), blobs
cifrados, o cualquier secreto que no deje un patrón reconocible en texto
plano. `gitleaks` escanea contenido legible; un keystore binario sin cadenas
de texto detectables puede pasar. La Capa 1 sí bloquea estos por
**extensión/nombre de fichero** (`.pem`, `.key`, `.pfx`, `.jks`,
`credentials.json`, etc.), así que la protección real contra keystores viene
de ahí, con los límites de "por nombre" ya descritos arriba — no de la Capa
2.

### Sentinel (`sentinel/sentinel_preflight.py`)

Es **fail-open** por diseño: si el hook crashea o no encuentra su fichero de
IOCs (`kit/sentinel/iocs.json`, que el kit **sí** distribuye, así que en una
instalación normal está), `decide()` resuelve "allow" en vez de bloquear.
Esto es una decisión consciente de disponibilidad sobre seguridad — ver
`kit/docs/05-security.md` para el razonamiento completo — y significa que
Sentinel es opcional y aditivo, no la barrera principal.

## En resumen

Ninguna de estas capas sustituye a revisar lo que el agente va a hacer antes
de que lo haga, ni a no versionar secretos reales para empezar. Son barreras
deterministas que reducen la probabilidad y el radio de un accidente, no un
sandbox de seguridad ni un perímetro frente a un atacante decidido.
