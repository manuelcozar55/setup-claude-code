# Informe de cambios — desacoplar Headroom del kit

Rama: `harden/headroom-decoupling`, rebasada sobre `origin/main`.
Copia aislada: `~/work/cc-setup-b`. **Nada aplicado a `~/.claude` de esta máquina.**

Una entrada por modificación: qué / por qué / cómo se verificó.

## Nota de rebase (antes del PR)

La rama se creó sobre `v2-autonomous` @ `44a1662`, pero esa rama **ya se había
mergeado y borrado en el remoto**: el ref local era obsoleto. `main` estaba en
`7696e49`, cuatro commits por delante, y **dos de ellos pisaban este trabajo**:

- `cd1b87d docs: separar headroom de rtk, y WSL2 al principio del README`
- `a6360f6 docs: correcciones de la autorrevisión antes del merge`

Cómo se resolvió, y por qué así:

1. **La separación `headroom`/`rtk` de `main` gana; la mía se descarta.** La de
   `main` es mejor: enlaza los dos repos, distingue el proxy HTTP del filtro de
   salida de CLI, y explica que el check anterior daba un `PASS` falso en ambos
   sentidos. Igual en `doctor.sh`: se conserva su bloque y solo se le añaden
   encima mis dos checks nuevos (intérprete y enrutado).
2. **`main` corrigió un error real de mi `install.sh`.** Documenta que el extra
   necesario es `headroom-ai[proxy]`, no el paquete pelado: sin él el proxy no
   arranca y falla con `No module named 'httpx'`. Mi `--with-headroom` instalaba
   `headroom-ai` a secas, así que **nunca habría llegado a arrancar** — habría
   fallado de forma segura (sin cablear nada, gracias al readiness check) pero
   inservible. Corregido, con el porqué de no usar `[all]` (~900 MB frente a
   7,2 GB; ONNX ya viene en `[proxy]`).
3. **Un commit mío se volvió redundante** (`0de6b83`: nombre del test y
   numeración duplicada): ambos arreglos se aplicaron al resolver el conflicto de
   `doctor.sh`, así que `rebase --skip`.
4. **`03-headroom.md` de `main` decía que el kit instala `ANTHROPIC_BASE_URL`**,
   que es justo lo que este PR deja de hacer. Actualizado conservando su
   argumento —bueno y medido— de que la variable debe ir en `settings.json` y no
   en el shell, porque un export condicional deja la sesión sin proxy en
   silencio. Mi cambio es compatible: `--with-headroom` la escribe **en
   `settings.json`**; lo único que cambia es *cuándo*.

Resultado: 5 commits limpios sobre `main`, 16 suites en verde tras el rebase.

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

## 1. `optional-hook.sh` — degradar sin desarmar

**Qué:** nuevo `kit/claude/hooks/optional-hook.sh`. Ejecuta un hook solo si su
dependencia existe: no-op silencioso (exit 0) si falta, y `exec` con propagación
literal del código de salida si está. Modo `--python` que resuelve el intérprete
(venv de tools → `python3` del sistema).

**Por qué:** era la única forma de arreglar el exit 127 sin caer en el arreglo
perezoso. Envolver los hooks en `|| true` habría silenciado también el código 2,
que es como Claude Code señala "bloquea esto": los guards habrían pasado a
permitir lo que deben denegar. El wrapper falla-abierto **solo** cuando el guard
no está instalado, nunca cuando está instalado y dice no.

Como efecto secundario deseable, `--python` mejora la cobertura: en una máquina
con `python3` del sistema pero sin el venv, `smart_approve.py` y el preflight de
Sentinel ahora **sí** corren, cuando antes daban 127.

**Verificado:** `kit/test/test_optional_hook.sh`, 9 asserts, incluido el caso que
importa (un guard que sale 2 sigue saliendo 2 a través del wrapper) y que el
stdin del payload JSON llega intacto. Rojo antes de escribir el wrapper, verde
después.

## 2. `settings.json` — dejar de enrutar a un proxy ajeno

**Qué:** fuera `ANTHROPIC_BASE_URL`. Los tres hooks con dependencia de tercero
(`rtk`, `sentinel_preflight.py`, `smart_approve.py`) pasan por `optional-hook.sh`.
Intactos: los 8 deny, los 8 allow, los 13 hooks y sus `timeout: 10`.

**Por qué:** el kit prometía en su README que "el setup base funciona sin ellos" y
con esta variable no era verdad. Distribuir un enrutado a un puerto que el propio
instalador no levanta convierte la instalación en un brick con síntomas de fallo
de Claude Code.

**Verificado:** `kit/test/test_clean_install_resilience.sh`, 12 asserts. Antes del
cambio fallaba en 4, uno de ellos funcional (un hook salía 127 en la máquina
simulada). Después, 12/12. La mitad "y sigue protegiendo" se comprueba con un
comando destructivo real: sale 2 incluso con el venv y `rtk` ausentes — es decir,
la protección no dependía de Python, y sigue sin depender.

## 3. `doctor.sh` — que deje de aprobar lo inservible

**Qué:** check nuevo de enrutado (si hay `ANTHROPIC_BASE_URL`, el endpoint debe
contestar, o `FAIL`); Headroom y `rtk` separados en dos checks; check nuevo del
intérprete de los hooks Python (`WARN`, no `FAIL`, porque el wrapper degrada).

**Por qué:** salía `OK (0 FAIL)` en una máquina cuyo Claude Code no podía hablar
con la API. Un doctor que aprueba una instalación rota es peor que no tener
doctor: retira la sospecha justo donde hacía falta. Se consulta `/readyz` y no
`/health` porque `/health` es agregado y se pone en rojo por subcomprobaciones que
es legítimo no tener (el backend semántico de `kompress`).

**Verificado:** `kit/test/test_doctor_base_url.sh`, 6 asserts, los tres casos
(muerto → `FAIL` y rc≠0; sin enrutar → `PASS` de API directa; vivo → `PASS`), con
un servidor HTTP real en un puerto libre para el caso positivo. El test se hizo
**hermético** (`env -u ANTHROPIC_BASE_URL`) tras detectar que en la máquina del
autor el caso "sin enrutar" pasaba por el motivo equivocado: heredaba el proxy
vivo del entorno.

## 4. `install.sh --with-headroom` — el orden es el arreglo

**Qué:** subcomando nuevo. Instala `headroom-ai` en el venv, escribe la unidad de
usuario, arranca, espera `/readyz` hasta 30 s, y **solo entonces** escribe
`ANTHROPIC_BASE_URL` con `jq`. Si el proxy no responde, sale ≠ 0 y deja la config
intacta. Genera también el helper del output-shaper.

**Por qué:** es la inversión del fallo original. Antes se distribuía la variable y
se esperaba que el proxy apareciera; ahora la variable es la *consecuencia* de
haber comprobado que el proxy está vivo.

La unidad lleva tres decisiones que vienen de fallos medidos, no de preferencias:
`--mode cache` explícito (el modo `token` reescribe turnos e invalida el prefijo
cacheado, que es de donde sale ~99 % del ahorro); `StartLimitIntervalSec=0` en
`[Unit]` y no en `[Service]`, donde systemd lo ignora en silencio; y el shaper por
`ExecStartPost` con `-` para que no pueda tumbar el arranque.

**Verificado:** `kit/test/test_with_headroom.sh`, 13 asserts, sin red ni systemd
(`HEADROOM_DRY_RUN=1`). Cubre el caso negativo (proxy muerto → config intacta),
el positivo, la idempotencia y las tres decisiones de la unidad, incluida la
sección correcta de `StartLimitIntervalSec` vía `awk`.

## 5. Documentación — corregir un error de fondo

**Qué:** `kit/docs/03-headroom.md` reescrito. Tabla que separa Headroom de `rtk`;
la economía del modo `cache` con cifras y su comando de reproducción; las tres
trampas verificadas; el output-shaper como única palanca sin contrapartida.
Corregido lo mismo en `07-verify.md` (usaba `command -v rtk` como prueba de que
Headroom estaba instalado), `08-plugins-mcp-y-skills.md` (dos sitios),
`05-security.md` (la cadena de 7 hooks) y los tres párrafos de `README.md`,
`kit/README.md` y `02-install.md` que afirmaban que un `WARN` de Headroom era
aceptable sin matizar el caso del proxy muerto.

**Por qué:** el repo se vende con "cada afirmación citada y verificada", y tratar
dos herramientas de dos proyectos como una sola es el tipo de error que invalida
esa promesa. Además hacía imposible diagnosticar: `rtk --version` salía bien y el
proxy no estaba ni instalado.

**Verificado:** las afirmaciones nuevas se comprobaron contra la instalación real
antes de escribirlas — `pip show headroom-ai` → 0.33.0; `headroom proxy --help` →
`--mode [token|cache]` con default `cache` y la definición literal de cada modo;
`/stats-history` → 90,53 $ de caché frente a 0,10 $ de compresión. Lo que **no**
se pudo verificar desde el CLI (el mapeo perfil→modo) se atribuye explícitamente
como medido por el autor, en vez de presentarse como documentado.

## 6. CI y modos de fichero

**Qué:** las 4 suites nuevas añadidas a `.github/workflows/ci.yml` (la lista de
steps es explícita, no un glob: sin esto no se habrían ejecutado nunca).
`optional-hook.sh` pasado a `100755` en el índice de git y añadido a
`REQUIRED_EXEC` de `test_exec_modes.sh`.

**Por qué:** un test que no corre en CI no demuestra nada, y el repo ya tenía un
commit dedicado a que los hooks se commitearan como `100755` — el hook nuevo se
había quedado en `100644` y el test no lo cubría porque su lista está a mano.

**Verificado:** `shellcheck -x` con el comando exacto de la CI → 0 hallazgos (los
16 SC2015 que introduje están corregidos con un helper `want()`).
`test_exec_modes.sh` pasa de 23 a 25 asserts. `assert-install.sh` de la CI → OK.

---

## Estado final

| Comprobación | Resultado |
|---|---|
| 16 suites de `kit/test/` | **todas rc=0** |
| Asserts nuevos | 40 (9 + 12 + 6 + 13) |
| `test_guards_falsifiability.sh` | sigue demostrando que neutralizar un guard rompe 10 casos `BLOCK` |
| `shellcheck -x` (comando de la CI) | 0 hallazgos |
| `scan-secrets.sh` sobre el kit | sin secretos ni PII |
| Instalación real + `doctor.sh` | `OK (0 FAIL)` |
| `assert-install.sh` (CI) | post-condiciones verificadas |

## Contención

- Todo el trabajo está en `~/work/cc-setup-b`, rama `harden/headroom-decoupling`.
- **`~/.claude` de esta máquina: sin tocar.** El proxy sigue corriendo con su
  unidad de siempre.
- **Sin `push`.** `origin` sigue en `44a1662`.
- Rollback: borrar la copia aislada. El repo original en
  `Downloads/CC-Setup` está intacto en `v2-autonomous`.

## Fuera de alcance (dicho, no escondido)

- **Traducción a inglés**: no se hizo. Se propuso y quedó sin respuesta; es la
  palanca más grande para estrellas internacionales, pero también un entregable
  grande y separable.
- **`model: opus[1m]` y `effortLevel: xhigh`** se dejan intactos: son la identidad
  opinada del kit y no pude verificar cómo fallan en una cuenta sin acceso a Opus.
  Es el siguiente candidato a "rompe a un recién llegado" y merece comprobarse.
- **Falso positivo detectado de paso:** `destructive-guard.sh` bloquea un `git
  commit` cuyo *mensaje* menciona un borrado recursivo de raíz. Me pasó al
  commitear esta misma rama. No lo toqué (cambiar un guard merece su propia
  decisión), pero está documentado aquí como hallazgo.
