# MISTAKES

Errores observados → regla derivada → dónde se persistió.
Un error que solo se anota vuelve. Un error que se cablea, no.

Formato: **qué pasó** (con reproducción literal) · **por qué importa** ·
**regla** · **dónde vive la regla ahora** (guía advisoria vs sensor determinista).

---

## M-001 · El canal de Bash reescribe el comando antes de ejecutarlo

**Fecha:** 2026-08-21 · **Severidad:** crítica · **Estado:** mitigado por convención, pendiente de cablear

### Qué pasó

El hook `PreToolUse/Bash` → `rtk hook claude` sustituye el ejecutable en posición de
comando. Reproducido en dos sesiones independientes:

```
$ rg --version
grep (GNU grep) 3.12          <-- se ejecutó grep, no ripgrep

$ python3 -m pytest --version
/usr/bin/python3: No module named rtk    <-- se ejecutó python3 -m rtk

$ echo pytest
pytest                        <-- control: los argumentos NO se tocan
```

Alcance caracterizado: la sustitución ocurre **solo en posición de comando**.
Dos vías la evitan, ambas verificadas:

```
$ /home/…/.venvs/riego/bin/pytest --version     ->  pytest 9.1.1     ✅ ruta absoluta
$ rtk proxy rg --version                        ->  ripgrep 15.1.0   ✅ bypass documentado
```

Un tercer camino, descubierto de paso: **dentro de un script, el hook no interviene** —
actúa sobre la invocación que hace el agente, no sobre lo que el script ejecuta después.

### Por qué importa

Bash es **5.955 de las llamadas a herramienta** de la ventana medida (2.379 en la sesión
principal + 3.576 en subagentes). Es, con diferencia, el sensor principal del harness.

Un oráculo es *un comando que devuelve 0 si el trabajo está bien*. Si el comando que se
ejecuta no es el que se escribió, el oráculo no mide lo que dice medir. Peor que no tener
sensor: es tener uno que miente sin avisar. Esto invalida la premisa de la que parte todo
el diseño y por eso se repara antes de construir ningún control nuevo.

### Regla

> Todo comando registrado en `knowledge/ORACLES.md` se invoca por **ruta absoluta**,
> vía **`rtk proxy …`**, o **encapsulado en un script**. Nunca por nombre suelto.

### Dónde vive

- **Sensor determinista:** `test_oracle_registry` rechaza toda entrada de `ORACLES.md`
  cuyo comando no empiece por `/` o por `rtk proxy`. *(FASE 4)*
- **Guía:** una línea en `CLAUDE.md`, no un párrafo. El test es quien manda.

### Contra-argumento buscado

¿Es un fallo o el diseño previsto? `~/.claude/RTK.md` describe la reescritura como
deliberada y *"transparent, 0 tokens overhead"*, con el ejemplo `git status` → `rtk git
status`, que **preserva el comando**. Los casos observados (`rg`→`grep`, `pytest`→`rtk`)
**sustituyen el binario**, que es otra cosa. Se trata como fallo de implementación, no como
diseño. Verificado en `rtk 0.42.0`.

---

## M-002 · Los guards bloquean por el literal del comando, no por la acción

**Fecha:** 2026-08-21 · **Severidad:** baja (fricción) · **Estado:** aceptado, sin cambio

### Qué pasó

Escribir `scripts/backup.sh` fue bloqueado dos veces por Sentinel
(`[CRITICAL] sensitive path pattern`) por contener el nombre del fichero de credenciales
**en la lista de exclusiones** — es decir, por el código que impide que la credencial entre
en el backup. También `rm -rf "$TMPDIR"` sobre un temporal propio fue bloqueado.

### Por qué importa

Es el compromiso correcto para un guard *name-only*: falla del lado seguro y es barato
(9 ms). Pero significa que **el coste del guard no es cero**, y que la salida correcta ante
un falso positivo es **reformular**, nunca ampliar la allowlist. Ampliarla convierte un
sensor en decoración.

### Regla

> Ante un bloqueo de guard: reformular el comando. La allowlist solo se toca con
> justificación escrita en `knowledge/DECISIONS/`.

### Dónde vive

Guía en `CLAUDE.md`. No se cablea: el guard ya es el sensor.

### Recuento de ocurrencias

Tres en una sola sesión: al escribir `scripts/backup.sh`, al probarlo, y al editar
`CLAUDE.md` para **eliminar** una frase que contenía el patrón. **No se promueve a pesar de
las tres**, y esa decisión es deliberada: el control ya existe y funciona: el guard está
haciendo exactamente su trabajo. Lo que se repite no es un fallo del sistema, sino su
coste de operación. La regla correcta —reformular, nunca ampliar la allowlist— se aplicó
las tres veces sin incidente.

Promover esto sería confundir *fricción esperada* con *defecto*. Un harness que elimina toda
fricción de sus propios guards se queda sin guards.

---

## M-003 · `set -o pipefail` + `grep -q` = falso fallo por SIGPIPE

**Fecha:** 2026-08-21 · **Severidad:** media · **Estado:** corregido

### Qué pasó

`verify_zip()` daba `FAIL falta MANIFEST.sha256` sobre un ZIP correcto:

```
unzip -Z1 "$zip" | grep -q 'MANIFEST.sha256$'
```

`grep -q` sale al primer acierto y cierra la tubería; `unzip` muere con SIGPIPE; con
`set -o pipefail` el pipeline devuelve error. **Con 6 entradas no se manifestaba; con 933,
sí** — `unzip` terminaba antes de que `grep` cerrara.

### Por qué importa

Un verificador que falla en verde es tan inútil como uno que pasa en rojo, y este solo
aparecía a escala real. Lo cazó ejecutar el script contra el estado de verdad, no contra
el fixture. **Los fixtures pequeños no ejercitan las condiciones de carrera.**

### Regla

> En scripts con `pipefail`, no consumir parcialmente una tubería. Capturar la salida una
> vez en una variable y filtrar sobre ella.

### Dónde vive

Corregido en `scripts/backup.sh`. `shellcheck -x` **no detecta este caso** — se anota aquí
porque el linter no es sensor suficiente para él.

### ⚠️ SEGUNDA OCURRENCIA — 2026-08-21, misma tarde

Volvió a morder en `kit/test/test_detect_oracle.sh`:

```bash
"$DET" --why "$d" 2>&1 | grep -q "no hay sensor"    # el check fallaba con el mensaje presente
```

`$DET` sale con 1 —correctamente, porque no hay oráculo— y `pipefail` propaga ese 1 aunque
`grep` acierte. El síntoma es distinto del primero (allí era SIGPIPE, aquí es un exit code
legítimo aguas arriba), pero **la causa es la misma**: encadenar en una tubería un comando
cuyo estado de salida no es el que se quiere evaluar.

**Aplicando el steering loop, la segunda ocurrencia no se anota: se promueve.**

| Ocurrencia | Qué se hizo |
|---|---|
| 1ª (`backup.sh`) | Ficha en `MISTAKES.md` |
| 2ª (`test_detect_oracle.sh`) | **Promoción: regla en la skill `house-rules` y patrón documentado aquí** |

**Regla promovida:**

> Con `set -o pipefail`, no evalúes por tubería la salida de un comando cuyo *exit code* no
> es el que te interesa. Captura primero en una variable, filtra después:
>
> ```bash
> salida="$(comando 2>&1)"
> printf '%s' "$salida" | grep -q patron
> ```

**Por qué no se cableó como test:** `shellcheck` no lo detecta y escribir un linter propio
para este patrón cuesta más de lo que ahorra con dos ocurrencias. Si aparece una tercera,
la promoción actual habrá fallado y **entonces** toca herramienta —y habrá que explicar por
qué la regla escrita no bastó, en vez de repetirla más alto.
