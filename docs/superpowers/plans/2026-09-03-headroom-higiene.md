# Higiene del log de Headroom y deriva de la unidad — Plan de implementación

> **Para trabajadores agénticos:** SUB-SKILL REQUERIDA: usa
> `superpowers:subagent-driven-development` (recomendada) o
> `superpowers:executing-plans` para implementar tarea a tarea. Los pasos usan
> sintaxis de casilla (`- [ ]`) para seguimiento.

**Goal:** dejar el proxy de Headroom sin conversación en claro en disco, sin
capacidad de leer credenciales, con permisos cerrados y con serie histórica de
ahorro auditable, sin perder ni una línea de medición ni tocar la calidad de las
respuestas.

**Architecture:** dos capas separadas a propósito. **En el repo** se arregla la
plantilla y el sensor, para que toda instalación futura nazca bien y `doctor.sh`
detecte los tres defectos (hoy está verde con conversación en claro a un
directorio de distancia). **En la máquina viva** no se reescribe la unidad —está
comentada a mano y ya endurecida—: se añade un **drop-in**, cuyo rollback es
borrar un fichero. El orden importa: la serie `PERF` se archiva *antes* de limpiar
los logs, para que la higiene no cueste la medición.

**Tech Stack:** bash, `jq`, systemd de usuario (unidades y drop-ins), `awk`,
`shellcheck -x`, las 28 suites de `kit/test/` ejecutadas por `make test`.

**Spec:** `docs/superpowers/2026-09-03-headroom-higiene-spec.md` — el plan
implementa el spec; los ejecutores leen los dos.

## Global Constraints

- `--mode cache` **siempre**; nunca `--mode token`.
- Nunca `--budget` ni `--log-messages` en la línea del proxy.
- Nunca `pkill`, nunca `nohup headroom proxy`, nunca `headroom install`.
- El servicio se maneja **solo** con `systemctl --user`.
- Una sola fuente de `ANTHROPIC_BASE_URL`: `~/.claude/settings.json`.
- **No re-ejecutar `kit/install.sh` en esta máquina** (pisa `settings.json`).
- El recuento de suites se queda en **28**: nada de ficheros nuevos en
  `kit/test/`; los sensores nuevos van dentro de `test_headroom_guardrails.sh`.
- Comentarios en castellano. `shellcheck -x` limpio.
- `knowledge/` va en commit aparte con prefijo `knowledge:` (`CLAUDE.md:58`).
- Rama + PR, nunca directo a `main`. **Sin `push`** sin autorización explícita.
- Si un guard bloquea un comando, se reformula el comando; **jamás** se amplía la
  allowlist.
- No usar frases sobre borrado recursivo de raíz en mensajes de commit
  (`destructive-guard.sh` bloquea el commit por el mensaje).

## File Structure

**Repo (rama `harden/headroom-higiene-y-drift`, apilada sobre `ddff6fd`):**

| Fichero | Responsabilidad | Acción |
|---|---|---|
| `docs/superpowers/2026-09-03-headroom-higiene-spec.md` | el spec | creado ya |
| `docs/superpowers/plans/2026-09-03-headroom-higiene.md` | este plan | creado ya |
| `kit/install.sh:189` | plantilla de la unidad: `UMask` + `Environment` nuevos | modificar |
| `kit/install.sh:231` | `chmod` también al subdirectorio `logs/` | modificar |
| `kit/doctor.sh:290-300` | sensores: conversación en `proxy.log`, permisos de `logs/`, endurecimiento de la unidad **incluyendo drop-ins** | modificar |
| `kit/test/test_headroom_guardrails.sh` | casos nuevos + falsabilidad | modificar |
| `CHANGELOG.md` | entrada de la entrega | modificar |
| `docs/superpowers/headroom-higiene-cambios.md` | informe vivo de cambios | crear |
| `knowledge/ORACLES.md` | fila de medición del oráculo | modificar (commit aparte) |

**Máquina (fuera del repo, paso explícitamente confirmado):**

| Fichero | Responsabilidad |
|---|---|
| `~/.config/systemd/user/headroom-proxy.service.d/10-higiene.conf` | drop-in: `UMask`, `Environment`, `InaccessiblePaths` |
| `~/.claude/scripts/headroom-perf-archive.sh` | extrae `PERF` a un TSV mensual |
| `~/.claude/scripts/headroom-quiesce-check.sh` | dice si es seguro reiniciar |
| `~/.config/systemd/user/headroom-perf-archive.service` | `Type=oneshot` que lo lanza |
| `~/.config/systemd/user/headroom-perf-archive.timer` | `OnCalendar=hourly` |

---

### Task 1: la plantilla de la unidad nace con higiene

**Files:**
- Modify: `kit/install.sh:189` (tras `Environment=HF_HUB_OFFLINE=0`)
- Modify: `kit/install.sh:231` (tras el `chmod 700` de `~/.headroom`)
- Test: `kit/test/test_with_headroom.sh`

**Interfaces:**
- Produces: la unidad generada contiene las líneas literales
  `Environment=HEADROOM_LOG_PAYLOAD_PREVIEW=0` y `UMask=0077`. Las tareas 2 y 3
  buscan exactamente esas dos cadenas.

- [ ] **Step 1: escribir el test que falla**

  La suite ya comprueba la unidad generada dentro de `if [ -f "$UNIT" ]; then`
  (líneas 60-69), donde `$UNIT` es
  `$ROOT_B/.config/systemd/user/headroom-proxy.service`. Los dos casos nuevos van
  **dentro de ese bloque**, junto al de `Restart=always`, y usan su `want`:

```bash
  # Higiene del log. El default de Headroom es ESCRIBIR hasta 4096 chars de
  # conversacion literal en proxy.log por cada event=headroom_retrieve
  # (_payload_preview_enabled devuelve True cuando la variable NO esta puesta), y el
  # proceso hereda Umask 0002, que hace nacer los logs en 664. Ninguna de las dos se
  # puede cambiar en caliente, asi que la unidad es el unico sitio donde ponerlas.
  want "la unidad debe fijar HEADROOM_LOG_PAYLOAD_PREVIEW=0 (el default escribe conversacion en proxy.log)" \
    grep -qx 'Environment=HEADROOM_LOG_PAYLOAD_PREVIEW=0' "$UNIT"
  want "la unidad debe fijar UMask=0077 (el proceso hereda 0002 y los logs nacen en 664)" \
    grep -qx 'UMask=0077' "$UNIT"
```

- [ ] **Step 2: correr y comprobar que falla**

  Ejecutar: `bash kit/test/test_with_headroom.sh; echo "rc=$?"`
  Esperado: `rc=1`, dos líneas `FAIL: ...` nombrando `HEADROOM_LOG_PAYLOAD_PREVIEW`
  y `UMask`, y `FAIL=2` en el resumen (`PASS=n FAIL=n` es el formato de esta suite;
  `ko()` imprime `FAIL: $1`).

- [ ] **Step 3: implementar en la plantilla**

  En `kit/install.sh`, justo después de `Environment=HF_HUB_OFFLINE=0` (línea 189):

```bash
# El default de Headroom es escribir en proxy.log hasta 4096 chars de conversacion
# literal por cada event=headroom_retrieve: _payload_preview_enabled() devuelve True
# cuando la variable NO esta puesta. Con 0 solo registra recuentos de bytes. No se
# puede cambiar en caliente: la clave no esta en _KNOBS_BY_ENV y el lector consulta
# os.environ directo, asi que /admin/runtime-env no la ve.
Environment=HEADROOM_LOG_PAYLOAD_PREVIEW=0
# El proceso hereda Umask 0002 y por eso proxy.log nace en 664. Esto solo gobierna
# los ficheros futuros, incluidas las rotaciones; lo ya escrito se arregla aparte.
UMask=0077
```

- [ ] **Step 4: implementar el `chmod` del subdirectorio**

  En `kit/install.sh`, tras `chmod 700 "$HOME/.headroom" 2>/dev/null || true`
  (línea 231):

```bash
    # logs/ aparte: se crea con el umask del proceso, no hereda el 700 de arriba.
    chmod 700 "$HOME/.headroom/logs" 2>/dev/null || true
```

- [ ] **Step 5: correr y comprobar que pasa**

  Ejecutar: `bash kit/test/test_with_headroom.sh; echo "rc=$?"`
  Esperado: `rc=0`, `FAIL=0`.

- [ ] **Step 6: shellcheck**

  Ejecutar: `shellcheck -x kit/install.sh kit/test/test_with_headroom.sh`
  Esperado: sin salida.

- [ ] **Step 7: commit**

```bash
git add kit/install.sh kit/test/test_with_headroom.sh
git commit -m "fix(headroom): que la unidad nazca sin volcar conversacion ni logs 664

El default de Headroom escribe hasta 4096 chars de conversacion literal en
proxy.log por cada event=headroom_retrieve, y el proceso hereda Umask 0002, que
hace nacer los logs con permisos de grupo. Ninguna de las dos cosas se puede
cambiar en caliente, asi que van en la unidad.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: el sensor mira donde esta la fuga

**Files:**
- Modify: `kit/test/test_headroom_guardrails.sh` (casos nuevos)
- Test: la propia suite

**Interfaces:**
- Consumes: las cadenas que produce la Task 1.
- Produces: los casos rojos que la Task 3 pone verdes, el ayudante
  `write_dropin <raiz-HOME> <cuerpo>` y un `mk_home` cuyo `logs/` ya nace en 700.
  La Task 4 reutiliza `install_clean`, `mk_home` y `run_doctor`.

- [ ] **Step 1: dejar sano el fixture base**

  `mk_home()` (línea 46) crea `.headroom/logs` y hace `chmod 700` solo al padre; el
  subdirectorio nace en **755**, así que el sensor de la Task 3 avisaría en todos
  los casos de la suite. El fixture base debe representar una máquina sana, y el
  caso malo pedir su permiso a mano. Añadir junto al `chmod 700 "$r/.headroom"`:

```bash
  # logs/ aparte: nace con el umask del proceso (755), no hereda el 700 del padre.
  chmod 700 "$r/.headroom/logs"
```

- [ ] **Step 2: añadir el ayudante de drop-in**

  Junto a `write_unit()` (línea 66), que solo sabe escribir la unidad:

```bash
write_dropin() { # $1 raiz-HOME, $2 cuerpo de [Service]
  mkdir -p "$1/.config/systemd/user/headroom-proxy.service.d"
  printf '[Service]\n%s\n' "$2" \
    > "$1/.config/systemd/user/headroom-proxy.service.d/10-higiene.conf"
}
```

- [ ] **Step 3: escribir los cinco casos**

  Añadir a `kit/test/test_headroom_guardrails.sh` antes de la línea del resumen
  (`echo "== $pass passed, $fail failed =="`), reusando los ayudantes de la suite:
  `run_doctor` es el único que monta el entorno hermético completo (`HOME`,
  `XDG_CONFIG_HOME`, y el `headroom` de pega en `PATH` sin el cual `doctor.sh`
  toma la rama `else` y los sensores **no llegan a correr**).

```bash
# --- 7) conversacion en claro en proxy.log -> FAIL --------------------------
# El sensor viejo solo miraba proxy.jsonl y su marca "request_messages". La fuga
# real vive en proxy.log, la escribe compression_store a nivel INFO con
# event=headroom_retrieve y --log-messages APAGADO, y su marca es "payload_preview".
# Un sensor que vigila el fichero equivocado se queda verde con conversacion en
# claro a un directorio de distancia: medido el 2026-09-03, 100 lineas en un dia.
CH7="$(install_clean)"; R7="$(mk_home)"
printf '%s\n' '2026-09-03 15:35:10,407 - headroom.cache.compression_store - INFO - event=headroom_retrieve {"hash":"abc","payload_preview":"texto literal de la conversacion","payload_preview_chars":1062}' \
  > "$R7/.headroom/logs/proxy.log"
out7="$(run_doctor "$CH7" "$R7")"
if echo "$out7" | grep -qE '^FAIL .*payload_preview'; then ok; else
  ko "un proxy.log con payload_preview con contenido no produce FAIL"
fi

# --- 8) el mismo log con el preview ya apagado -> silencio ------------------
printf '%s\n' '2026-09-03 15:35:10,407 - headroom.cache.compression_store - INFO - event=headroom_retrieve {"hash":"abc","payload_preview":"","payload_preview_chars":0}' \
  > "$R7/.headroom/logs/proxy.log"
out8="$(run_doctor "$CH7" "$R7")"
if echo "$out8" | grep -qE '^FAIL .*payload_preview'; then
  ko "un proxy.log con el preview apagado produce un FAIL falso"
else ok; fi

# --- 9) permisos de ~/.headroom/logs -> WARN -------------------------------
# El 700 del directorio padre no cubre al hijo, y ahi es donde vive el log.
chmod 755 "$R7/.headroom/logs"
out9="$(run_doctor "$CH7" "$R7")"
if echo "$out9" | grep -qE '^WARN .*headroom/logs tiene permisos 755'; then ok; else
  ko "un ~/.headroom/logs en 755 no produce WARN de permisos"
fi
chmod 700 "$R7/.headroom/logs"

# --- 10) unidad sin InaccessiblePaths -> WARN ------------------------------
# Con ProtectHome=read-only el proxy puede LEER ~/.ssh, ~/.aws, ~/.gnupg y
# ~/.config/gh. La plantilla del kit lo tapa, pero nada re-aplica la plantilla:
# la unidad viva de esta maquina es del 21-ago y no llego a tenerlo.
CH10="$(install_clean)"; R10="$(mk_home)"
write_unit "$R10" "proxy --port 8787 --mode cache --no-telemetry"
out10="$(run_doctor "$CH10" "$R10")"
if echo "$out10" | grep -qE '^WARN .*InaccessiblePaths'; then ok; else
  ko "una unidad que no declara InaccessiblePaths no produce WARN"
fi

# --- 11) el mismo endurecimiento, pero en un drop-in -> silencio -----------
# Un grep al fichero de la unidad no ve lo que vive en .service.d/: sin esto el
# sensor daria rojo falso a una maquina correctamente arreglada con drop-in.
write_dropin "$R10" 'InaccessiblePaths=-%h/.ssh -%h/.aws -%h/.gnupg -%h/.config/gh'
out11="$(run_doctor "$CH10" "$R10")"
if echo "$out11" | grep -qE '^WARN .*InaccessiblePaths'; then
  ko "el sensor no lee los drop-ins: da WARN con el endurecimiento ya puesto"
else ok; fi
```

- [ ] **Step 4: correr y comprobar que fallan los que deben**

  Ejecutar: `bash kit/test/test_headroom_guardrails.sh; echo "rc=$?"`
  Esperado: `rc=1` y exactamente **tres** líneas `NOT ok` — la de
  `payload_preview con contenido`, la de `logs en 755` y la de
  `InaccessiblePaths`. Los casos 8 y 11 pasan ya, porque asertan *ausencia* y el
  sensor todavía no existe: son los que la Task 3 tiene que mantener verdes
  mientras pone verdes los otros tres.

---

### Task 3: implementar los sensores en doctor.sh

**Files:**
- Modify: `kit/doctor.sh:290-300`
- Test: `kit/test/test_headroom_guardrails.sh` (los casos de la Task 2)

**Interfaces:**
- Consumes: `fail()` y `warn()`, ya definidas en `doctor.sh`.
- Produces: las cadenas `payload_preview`, `headroom/logs` e `InaccessiblePaths`
  en la salida, que son lo que asertan los tests.

- [ ] **Step 1: sensor de conversación en `proxy.log`**

  En `kit/doctor.sh`, justo después del bloque de `proxy.jsonl` (tras la línea
  292, el `fi` del `if [ -f "$hr_jsonl" ]`):

```bash
  # La otra mitad de la fuga, y la que estaba sin vigilar: compression_store
  # escribe en proxy.log, a nivel INFO y con --log-messages APAGADO, hasta 4096
  # chars de conversacion literal por cada event=headroom_retrieve. Su marca no es
  # request_messages sino payload_preview con contenido. Medido el 2026-09-03: 100
  # lineas en un dia. Se apaga con Environment=HEADROOM_LOG_PAYLOAD_PREVIEW=0 en la
  # unidad; no vale /admin/runtime-env, que no conoce esa clave.
  hr_log="$HOME/.headroom/logs/proxy.log"
  if [ -f "$hr_log" ] && grep -qm1 '"payload_preview":"[^"]' "$hr_log" 2>/dev/null; then
    fail "$hr_log guarda payload_preview con contenido: conversacion en claro en disco. Apagalo con Environment=HEADROOM_LOG_PAYLOAD_PREVIEW=0 en la unidad y reinicia el servicio"
  fi
```

- [ ] **Step 2: sensor de permisos del subdirectorio**

  Justo después del `case` de permisos de `~/.headroom` (tras la línea 300):

```bash
  # logs/ aparte: nace con el umask del proceso (medido: 0002 -> ficheros 664), asi
  # que el 700 del directorio padre no lo cubre. Solo lo protege que ~/.headroom
  # bloquee el paso, y eso es una sola linea de defensa.
  if [ -d "$HOME/.headroom/logs" ]; then
    hr_lperm="$(stat -c '%a' "$HOME/.headroom/logs" 2>/dev/null || echo '')"
    case "$hr_lperm" in
      700|'') : ;;
      *) warn "$HOME/.headroom/logs tiene permisos $hr_lperm: ahi vive el log del proxy. Corrigelo con chmod 700 y añade UMask=0077 a la unidad para las rotaciones futuras" ;;
    esac
  fi
```

- [ ] **Step 3: sensor de endurecimiento de la unidad, drop-ins incluidos**

  En el bloque de la unidad, tras la comprobación de `--budget|--log-messages`
  (línea 283):

```bash
    # El endurecimiento puede vivir en la unidad o en un drop-in, asi que se leen
    # los dos: un grep solo al fichero de la unidad daria verde falso en una maquina
    # arreglada con drop-in, y rojo falso en la que lo tiene en la unidad.
    hr_efectivo="$(cat "$hr_unit" "${hr_unit}.d"/*.conf 2>/dev/null || cat "$hr_unit")"
    case "$hr_efectivo" in
      *InaccessiblePaths*) : ;;
      *) warn "la unidad de headroom no declara InaccessiblePaths: con ProtectHome=read-only el proxy puede LEER ~/.ssh, ~/.aws, ~/.gnupg y ~/.config/gh. Añade: InaccessiblePaths=-%h/.ssh -%h/.aws -%h/.gnupg -%h/.config/gh" ;;
    esac
```

  `$hr_unit` es la variable que ya existe en ese bloque (`doctor.sh:275`,
  `${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/headroom-proxy.service`), y el
  código nuevo va **dentro** de su `if [ -f "$hr_unit" ]`. Los tres mensajes deben
  contener literalmente `payload_preview`, `headroom/logs tiene permisos` e
  `InaccessiblePaths`: son las cadenas que anclan los asertos de la Task 2.

- [ ] **Step 4: correr la suite y comprobar que pasa**

  Ejecutar: `bash kit/test/test_headroom_guardrails.sh; echo "rc=$?"`
  Esperado: `rc=0`, y `== N passed, 0 failed ==` con N = 5 casos más que antes.

- [ ] **Step 5: comprobar que no rompe al vecino**

  Ejecutar: `bash kit/test/test_doctor.sh; bash kit/test/test_doctor_base_url.sh`
  Esperado: los dos `rc=0`. `test_doctor.sh:11` ya aísla `proxy.jsonl`; si el
  sensor nuevo de `proxy.log` le afecta, aislarlo igual en esa suite.

- [ ] **Step 6: shellcheck**

  Ejecutar: `shellcheck -x kit/doctor.sh kit/test/test_headroom_guardrails.sh`
  Esperado: sin salida.

- [ ] **Step 7: commit**

```bash
git add kit/doctor.sh kit/test/test_headroom_guardrails.sh
git commit -m "fix(doctor): vigilar la fuga que estaba en proxy.log, no en proxy.jsonl

El sensor de conversacion en claro solo miraba proxy.jsonl y la marca
request_messages. La fuga real la escribe compression_store en proxy.log con
--log-messages apagado, y su marca es payload_preview: el sensor estaba verde con
100 lineas de conversacion literal de un solo dia al lado. Se añaden ademas los
permisos de logs/ -- que el 700 del padre no cubre porque nace con el umask del
proceso -- y el endurecimiento de la unidad leyendo tambien los drop-ins, porque
un grep al fichero de la unidad no ve lo que vive en .service.d/.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: falsabilidad de los sensores nuevos

**Files:**
- Modify: `kit/test/test_headroom_guardrails.sh` (bloque de falsabilidad)

**Interfaces:**
- Consumes: `falsified` (declarada en la línea 33 y ya usada por los casos de las
  líneas 109 y 137), `install_clean`, `mk_home` y `run_doctor`.
- Produces: un `run_doctor` con tercer argumento opcional (ruta de un doctor
  alternativo), retrocompatible con sus seis usos actuales.

- [ ] **Step 1: permitir que `run_doctor` apunte a otro doctor**

  `run_doctor` es el único sitio de la suite que monta el entorno hermético, y
  hace falta el mismo entorno para correr una copia mutada. Se le añade un tercer
  argumento con valor por defecto, así que los seis usos existentes no cambian:

```bash
run_doctor() { # $1 CLAUDE_HOME, $2 raiz-HOME, $3 doctor alternativo (opcional) -> salida completa
  env -u ANTHROPIC_BASE_URL HOME="$2" XDG_CONFIG_HOME="$2/.config" \
      PATH="$2/.local/bin:$PATH" CLAUDE_HOME="$1" bash "${3:-$KIT/doctor.sh}" 2>&1
}
```

- [ ] **Step 2: escribir el bloque de falsabilidad**

  Añadir antes de la línea del resumen:

```bash
# --- 12) falsabilidad del sensor nuevo -------------------------------------
# Un sensor que no se puede poner rojo no es un sensor. Se neutraliza la marca que
# busca, sobre una COPIA, y se exige que el caso malo pase de detectado a mudo. Sin
# esto el sensor podria estar comparando contra una cadena que nunca aparece --
# exactamente el defecto que esta entrega arregla -- y la suite seguiria verde.
CH12="$(install_clean)"; R12="$(mk_home)"
FALS="$(mktemp -d)"; cp "$KIT/doctor.sh" "$FALS/doctor.sh"
sed -i 's/payload_preview/zzz_marca_que_no_existe/g' "$FALS/doctor.sh"
printf '%s\n' '2026-09-03 15:35:10,407 - headroom.cache.compression_store - INFO - event=headroom_retrieve {"payload_preview":"texto literal","payload_preview_chars":13}' \
  > "$R12/.headroom/logs/proxy.log"
mudo="$(run_doctor "$CH12" "$R12" "$FALS/doctor.sh")"
if echo "$mudo" | grep -qE '^FAIL .*payload_preview'; then
  ko "el sensor de payload_preview no es falsable: neutralizado sigue detectando"
else
  ok; falsified=$((falsified + 1))
fi
```

- [ ] **Step 3: subir el recuento que ya existe**

  La suite ya lleva un único contador de falsabilidad al final (líneas 179-181) y
  exige `-ge 2`. Con el caso nuevo son tres, y dejarlo en 2 haría que su mensaje
  («detectados: N de 2») mintiera y que perder un caso pasara inadvertido:

```bash
if [ "$falsified" -ge 3 ]; then ok; else
  ko "los casos negativos no demuestran deteccion real (detectados: $falsified de 3)"
fi
```

- [ ] **Step 4: correr y verificar**

  Ejecutar: `bash kit/test/test_headroom_guardrails.sh; echo "rc=$?"`
  Esperado: `rc=0`, `0 failed`, y `falsified` llegando a 3 (si el resumen falla por
  el contador, el caso nuevo no incrementó y hay que revisar por qué el `if` tomó
  la rama `ko`).

- [ ] **Step 5: verificar que la mutación no toca el kit**

  Ejecutar: `command grep -c 'zzz_marca_que_no_existe' kit/doctor.sh`
  Esperado: `0` — la mutación vive solo en la copia temporal. Si diera `1`, el
  `sed -i` se aplicó al fichero real y hay que revertirlo antes de seguir.

- [ ] **Step 6: commit**

```bash
git add kit/test/test_headroom_guardrails.sh
git commit -m "test(headroom): exigir que el sensor nuevo sepa ponerse rojo

Neutraliza la marca que busca el sensor en una copia del doctor y exige que el
caso malo deje de detectarse. Sin esto, el sensor podria estar comparando contra
una cadena que nunca aparece y nadie se enteraria.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: la suite completa y el CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: correr la suite completa**

  Ejecutar: `make test 2>&1 | tail -5; echo "rc=$?"`
  Esperado: `rc=0`.

- [ ] **Step 2: el oráculo honesto, no la última línea**

  Ejecutar: `make test 2>&1 | grep -c '^NOT ok'`
  Esperado: `0`. La última línea de `make test` es el recuento de la *última*
  suite, no del total: solo `rc=0` **y** cero líneas `NOT ok` significan verde.

- [ ] **Step 3: comprobar que el recuento de suites no se movió**

  Ejecutar: `ls kit/test/*.sh | wc -l` y `bash kit/test/test_doc_claims.sh; echo "rc=$?"`
  Esperado: `28` y `rc=0`. Si `test_doc_claims.sh` falla, se ha añadido un
  fichero de suite por error: moverlo dentro de `test_headroom_guardrails.sh`.

- [ ] **Step 4: escribir la entrada del CHANGELOG**

  En la sección en curso de `CHANGELOG.md`, bajo `### Security` (o creándola):

```markdown
- **`doctor.sh` vigilaba el fichero equivocado.** El sensor de conversación en
  claro solo miraba `~/.headroom/logs/proxy.jsonl` y su marca `request_messages`.
  La fuga real la escribe `compression_store` en `proxy.log`, a nivel INFO y con
  `--log-messages` **apagado**, en forma de `payload_preview` de hasta 4096
  caracteres: 100 líneas medidas en un solo día. El sensor estaba verde.
- **La unidad generada no tapaba las credenciales en las máquinas viejas.** La
  plantilla declara `InaccessiblePaths` desde hace tiempo, pero nada re-aplica la
  plantilla y `doctor.sh` solo inspeccionaba `ExecStart=`. Ahora avisa, y lee
  también `headroom-proxy.service.d/*.conf` para no dar verde falso a una máquina
  arreglada con drop-in ni rojo falso a la que lo tiene en la unidad.
- **`UMask=0077` y `HEADROOM_LOG_PAYLOAD_PREVIEW=0` en la unidad.** El proceso
  heredaba `Umask 0002`, así que los logs nacían en 664 y cada rotación los
  volvía a crear así; `chmod` solo arregla el pasado. La variable no se puede
  cambiar en caliente: no está en `_KNOBS_BY_ENV` y el lector consulta
  `os.environ` directo, así que `/admin/runtime-env` no la ve.
- `chmod 700` también a `~/.headroom/logs`, que el `700` del directorio padre no
  cubría.
```

- [ ] **Step 5: commit**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): registrar la higiene del log y la deriva de la unidad

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: preparar la máquina — copia de seguridad y drop-in, sin aplicar

**Files:**
- Create: `~/.config/systemd/user/headroom-proxy.service.d/10-higiene.conf`
- Create: copia de seguridad de la unidad con fecha

**Interfaces:**
- Produces: el drop-in que la Task 8 activa con el reinicio.

- [ ] **Step 1: copia de seguridad de la unidad**

```bash
cp -p ~/.config/systemd/user/headroom-proxy.service \
      ~/.config/systemd/user/headroom-proxy.service.bak-$(date +%Y%m%d-%H%M%S)
ls -la ~/.config/systemd/user/ | grep headroom
```

  Esperado: el `.bak-<fecha>` junto a la unidad.

- [ ] **Step 2: escribir el drop-in**

```bash
mkdir -p ~/.config/systemd/user/headroom-proxy.service.d
cat > ~/.config/systemd/user/headroom-proxy.service.d/10-higiene.conf <<'EOF'
# Higiene del log y cierre de la deriva de seguridad de la unidad del 2026-08-21.
# Va en drop-in y no en la unidad porque la unidad esta comentada a mano y su
# endurecimiento no debe reescribirse por esto. Rollback: borrar este fichero y
# reiniciar el servicio.
[Service]
# El default de Headroom es escribir hasta 4096 chars de conversacion literal en
# proxy.log por cada event=headroom_retrieve. No se puede apagar en caliente: la
# clave no esta en _KNOBS_BY_ENV y el lector consulta os.environ directo.
Environment=HEADROOM_LOG_PAYLOAD_PREVIEW=0
# El proceso corria con Umask 0002 y por eso los logs nacian en 664. Gobierna solo
# los ficheros futuros, incluidas las rotaciones.
UMask=0077
# La unidad de esta maquina es del 21-ago y no llego a tener esta linea, que la
# plantilla del kit si escribe. Con ProtectHome=read-only el proxy puede LEER todo
# el home. El '-' tolera que alguno de los directorios no exista.
InaccessiblePaths=-%h/.ssh -%h/.aws -%h/.gnupg -%h/.config/gh
EOF
```

- [ ] **Step 3: validar sin aplicar**

```bash
systemctl --user daemon-reload
systemd-analyze --user verify headroom-proxy.service; echo "rc=$?"
systemctl --user show -p DropInPaths --value headroom-proxy.service
```

  Esperado: `rc=0` sin salida de `verify`, y `DropInPaths` nombrando el
  `10-higiene.conf`. **El proceso sigue con la config vieja**: `daemon-reload` no
  reinicia nada. Verificarlo:
  `grep ^Umask /proc/$(systemctl --user show -p MainPID --value headroom-proxy.service)/status`
  → todavía `0002`.

---

### Task 7: el archivador de PERF (antes de tocar ningún log)

**Files:**
- Create: `~/.claude/scripts/headroom-perf-archive.sh`
- Create: `~/.claude/scripts/headroom-quiesce-check.sh`
- Create: `~/.config/systemd/user/headroom-perf-archive.service`
- Create: `~/.config/systemd/user/headroom-perf-archive.timer`

**Interfaces:**
- Produces: `~/.headroom/metrics/perf-YYYY-MM.tsv` con 13 columnas y cabecera. La
  Task 9 lo lee para el informe.

- [ ] **Step 1: escribir el archivador**

```bash
cat > ~/.claude/scripts/headroom-perf-archive.sh <<'EOF'
#!/usr/bin/env bash
# Extrae las lineas PERF de proxy.log a TSVs mensuales antes de que la rotacion
# las borre. POR QUE: la rotacion es 10 MB x 5 backups y esta cableada en el
# paquete (headroom/proxy/helpers.py:1506-1539), y el 28 % de los bytes del log
# son las cabeceras de cada peticion. Sin esto no hay serie historica de ahorro
# que auditar, y bajar el nivel de log no es alternativa: PERF tambien es INFO y
# logging.basicConfig(level=INFO) esta cableado en headroom/proxy/server.py:470.
# Idempotente: deduplica por el id de peticion (hr_<epoch>_<contador>), asi que
# no le afecta que las rotaciones muevan los bytes.
set -euo pipefail
# POR QUE nullglob: sin el, un glob sin coincidencias deja el literal, y con `set -e` + `pipefail`
# el bucle de lectura del archivo aborta el script en silencio la PRIMERA vez que corre (o si el
# ultimo perf-*.tsv por orden alfabetico esta a cero bytes).
shopt -s nullglob
umask 077

# Un solo directorio temporal y el trap justo despues de crearlo: si TMP y
# VISTOS se crean en lineas separadas, un mktemp fallido a mitad deja el otro
# fichero huerfano porque el trap todavia no existe.
TD="$(mktemp -d)"
trap 'rm -f "$TD"/* 2>/dev/null; rmdir "$TD" 2>/dev/null' EXIT
TMP="$TD/tmp.tsv"
VISTOS="$TD/vistos.tsv"
NUEVAS="$TD/nuevas.tsv"

DIR="${HOME}/.headroom/logs"
# El archivo vive fuera de logs/: ese directorio es el que la tarea 8 vacia, y
# mientras el archivo sea la unica copia un borrado por glob se lo llevaria.
MET="${HOME}/.headroom/metrics"
mkdir -p "$MET"
chmod 700 "$MET"

# Cerrojo sobre todo el tramo de lectura-y-escritura: sin el, dos corridas
# solapadas (el timer horario disparando mientras algo mas lo llama a mano)
# fotografian VISTOS antes de que ninguna añada, y ambas añaden lo mismo.
exec 200>"$MET/.archive.lock"
flock 200

# Migracion unica del fichero que quedo en logs/ de una corrida anterior a
# este arreglo. mv, no cp: dos copias del mismo TSV en dos sitios es
# exactamente la ambiguedad que este cambio cierra.
[[ -f "$DIR/perf-2026-09.tsv" ]] && mv "$DIR/perf-2026-09.tsv" "$MET/perf-2026-09.tsv"

contar_filas_datos() {
  { cat /dev/null "$MET"/perf-*.tsv 2>/dev/null || true; } | grep -c '^[0-9]' || true
}

# El conjunto de vistos se construye de TODOS los meses ya archivados, no solo
# del mes en curso: si no, la primera corrida tras medianoche del dia 1
# re-archiva del orden de 6000 filas en el mes nuevo y cualquier agregado
# sobre perf-*.tsv las cuenta dos veces.
{ for a in "$MET"/perf-*.tsv; do
    [[ -s "$a" ]] && cut -f3 "$a" | tail -n +2
  done; true; } | sort -u > "$VISTOS"

# Cubre las SEIS ranuras de rotacion (proxy.log + 5 backups), no solo tres: la
# rotacion es 10 MB x 5 y quedarse en .log.2 pierde todo lo que ya rodo mas
# alla. Con nullglob activo, los backups que no existan desaparecen del bucle;
# el '[ -r "$f" ] || continue' cubre el otro caso, que proxy.log en si no exista
# o no se pueda leer. Barrer mas ancho es gratis porque el deduplicado por
# req_id ya existe.
for f in "$DIR"/proxy.log "$DIR"/proxy.log.[1-5]; do
  [ -r "$f" ] || continue
  # Anclado a la forma exacta del registro PERF, no a la subcadena ' PERF ':
  # esa subcadena tambien aparece dentro de previews de conversacion de
  # compression_store, que son texto arbitrario y pueden llevar un id entre
  # corchetes. Sin anclar, esa linea se coleria como fila vacia y registraria
  # el req_id como visto, suprimiendo para siempre el PERF autentico.
  command grep -hE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:,]+ - headroom\.proxy - INFO - \[hr_[0-9]+_[0-9]+\] PERF model=' "$f" 2>/dev/null || true
done | awk '
  {
    id = ""
    if (match($0, /\[hr_[0-9]+_[0-9]+\]/)) id = substr($0, RSTART + 1, RLENGTH - 2)
    if (id == "") next
    # Guarda de forma: sin esto, una fila cuya columna 1 no sea una fecha (arrastrada por un
    # ancla que no fuera de inicio de linea) crearia perf-<cualquiercosa>.tsv, que luego casa
    # con el glob perf-*.tsv e infla los recuentos.
    if ($1 !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) { descartadas++; next }
    split("", v)
    for (i = 1; i <= NF; i++) { n = index($i, "="); if (n > 1) v[substr($i, 1, n - 1)] = substr($i, n + 1) }
    split($2, hh, ",")
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", \
      $1, hh[1], id, v["model"], v["tok_before"], v["tok_after"], v["tok_saved"], \
      v["tok_inflated"], v["tool_saved"], v["cache_read"], v["cache_write"], \
      v["opt_ms"], v["total_ms"]
  }
  END { if (descartadas > 0) print "headroom-perf-archive: descartadas " descartadas " filas con fecha invalida" > "/dev/stderr" }
' | sort -u > "$TMP"

antes=$(contar_filas_datos)

# No se usa el idioma de dos ficheros 'NR==FNR': se rompe cuando VISTOS esta
# vacio (la primera corrida) porque NR nunca se adelanta a FNR y awk trata
# TODO TMP como si fuera el primer fichero, descartandolo entero. Con getline
# en BEGIN el filtrado no depende de que VISTOS tenga contenido.
awk -F'\t' -v vistos="$VISTOS" '
  BEGIN { while ((getline linea < vistos) > 0) visto[linea] = 1 }
  !($3 in visto)
' "$TMP" > "$NUEVAS"

# Cada fila va al mes de SU PROPIA fecha (columna 1), no al mes en que corre
# el script: si no, una corrida el dia 1 archivaria filas de finales del mes
# anterior en el TSV del mes nuevo.
cut -f1 "$NUEVAS" | cut -c1-7 | sort -u | while read -r mes; do
  d="$MET/perf-$mes.tsv"
  [[ -s "$d" ]] || printf 'fecha\thora\treq_id\tmodel\ttok_before\ttok_after\ttok_saved\ttok_inflated\ttool_saved\tcache_read\tcache_write\topt_ms\ttotal_ms\n' > "$d"
done
awk -F'\t' -v dir="$MET" '{ print >> (dir "/perf-" substr($1,1,7) ".tsv") }' "$NUEVAS"
chmod 600 "$MET"/perf-*.tsv 2>/dev/null || true

despues=$(contar_filas_datos)
esperado=$(wc -l < "$NUEVAS")
# Esto NO detecta una escritura truncada a mitad de fila: 'grep -c "^[0-9]"' cuenta una linea
# incompleta igual que una completa, asi que un truncado por disco lleno cuadraria igual. Ante
# eso la proteccion real es que 'awk' fallaria al escribir y 'set -e' cortaria el script antes
# de llegar aqui. Lo que esta comprobacion SI garantiza es mas modesto: que el total conto
# exactamente las filas que NUEVAS traia, para atrapar cualquier otra discrepancia (p.ej. un
# reparto a un mes equivocado) que de otro modo pasaria sin abortar.
if (( despues - antes != esperado )); then
  echo "headroom-perf-archive: ERROR - se esperaban +${esperado} filas y el total paso de ${antes} a ${despues}" >&2
  exit 1
fi

printf 'headroom-perf-archive: +%s filas -> %s (total %s)\n' \
  "$esperado" "$MET" "$despues"
EOF
chmod +x ~/.claude/scripts/headroom-perf-archive.sh
shellcheck ~/.claude/scripts/headroom-perf-archive.sh; echo "shellcheck rc=$?"
```

  Esperado: `shellcheck rc=0` sin hallazgos.

- [ ] **Step 2: primera corrida y verificación**

```bash
~/.claude/scripts/headroom-perf-archive.sh
stat -c '%a %n' ~/.headroom/metrics/perf-*.tsv
head -1 ~/.headroom/metrics/perf-*.tsv
wc -l ~/.headroom/metrics/perf-*.tsv
```

  Esperado: modo `600`, cabecera de 13 columnas en cada fichero, y un total del
  orden de **11 700 filas** repartidas entre `perf-2026-08.tsv` y
  `perf-2026-09.tsv` — el archivador cubre las seis ranuras de rotación
  (`proxy.log` + `.log.1` … `.log.5`), no solo las tres primeras (ver la
  precondición de la Task 8).

- [ ] **Step 3: probar la idempotencia (criterio A12)**

```bash
~/.claude/scripts/headroom-perf-archive.sh
```

  Esperado: `+0 filas`. Si añade filas, la deduplicación por `req_id` está mal y
  **no se sigue adelante**: el paso 4 de la Task 8 borra logs y solo es seguro si
  el archivado es fiable.

- [ ] **Step 4: escribir el comprobador de reposo**

```bash
cat > ~/.claude/scripts/headroom-quiesce-check.sh <<'EOF'
#!/usr/bin/env bash
# Dice si es seguro reiniciar el proxy: rc=0 si no hay trafico de inferencia
# reciente ni peticiones en vuelo; rc=1 si hay que esperar, o si no se pudo
# medir con confianza.
# POR QUE: el reinicio aborta las peticiones en curso de las sesiones de Claude
# Code enrutadas, y a media respuesta eso se ve como un error de API.
set -uo pipefail

LOG="${HOME}/.headroom/logs/proxy.log"
VENTANA="${1:-45}"
ahora=$(date +%s)

# POR QUE se filtra la lista: awk trata un fichero inexistente como error fatal, y tras el
# borrado de los rotados (tarea 8) este comprobador quedaria diciendo "no se pudo medir" para
# siempre si se le sigue pasando un .log.1 que ya no existe.
LOGS=()
for l in "$LOG" "${LOG}.1"; do [[ -f "$l" ]] && LOGS+=("$l"); done
if (( ${#LOGS[@]} == 0 )); then
  echo "ESPERAR: no hay ningun log que medir"
  exit 1
fi

medido=0
ultima=0
linea=$( { for l in "${LOGS[@]}"; do tac "$l" 2>/dev/null; done; } \
         | command grep -m1 -E 'event=proxy_inbound_(request|response).*path=/v1/messages' || true )
if [[ -n "$linea" ]]; then
  marca="${linea%%,*}"                       # "2026-09-03 16:55:46"
  if ultima=$(date -d "$marca" +%s 2>/dev/null); then medido=1; fi
fi

# POR QUE se sale por 1 sin medir: "no se pudo medir" no es "no hay trafico". Aprobar aqui
# abortaria la peticion en curso de una sesion viva.
if (( medido == 0 )); then
  echo "ESPERAR: no se pudo medir el silencio (log ilegible, vacio o marca no parseable)"
  exit 1
fi
silencio=$(( ahora - ultima ))

# POR QUE por emparejamiento de ids y no por bytes en cola: una peticion en vuelo tiene las dos
# colas del socket a 0 mientras el proxy espera al upstream, asi que contar bytes da siempre 0.
# Solo cuentan los desemparejados recientes: un request abortado hace horas nunca vera su
# response y bloquearia el gate de por vida.
en_vuelo=$(awk -v ahora="$ahora" -v margen=600 '
  function id_de(l) {
    return (match(l, /id=inbound-[0-9]+/)) ? substr(l, RSTART+3, RLENGTH-3) : ""
  }
  # POR QUE se corta la cadena en vez de dividir por 1e9: el id trae nanosegundos (19 digitos) y
  # eso no cabe exacto en el doble que usa awk. Quitando los 9 ultimos digitos quedan los
  # segundos, exactos y sin coma flotante.
  # POR QUE el segundo parametro "nsec": sin declararla ahi, esa variable es GLOBAL en awk y
  # pisa la "n" contadora del bloque END en cada llamada (comprobado: sin esto,
  # peticiones_en_vuelo salia como el numero de nanosegundos del ultimo id, no un conteo).
  function epoch_de(i,   nsec) { nsec = substr(i, 9); return substr(nsec, 1, length(nsec) - 9) + 0 }
  /event=proxy_inbound_request/  { i = id_de($0); if (i != "") req[i] = 1 }
  /event=proxy_inbound_response/ { i = id_de($0); if (i != "") res[i] = 1 }
  END {
    n = 0
    for (i in req) {
      if (i in res) continue
      if (ahora - epoch_de(i) <= margen) n++
    }
    print n
  }
' "${LOGS[@]}" 2>/dev/null) || en_vuelo=-1

if (( en_vuelo < 0 )); then
  echo "ESPERAR: no se pudo contar las peticiones en vuelo"
  exit 1
fi

printf 'silencio=%ss (exigido %ss)  peticiones_en_vuelo=%s\n' \
  "$silencio" "$VENTANA" "$en_vuelo"

if [ "$silencio" -ge "$VENTANA" ] && [ "$en_vuelo" -eq 0 ]; then
  echo "SEGURO: se puede reiniciar"; exit 0
fi
echo "ESPERAR: hay actividad"; exit 1
EOF
chmod +x ~/.claude/scripts/headroom-quiesce-check.sh
shellcheck ~/.claude/scripts/headroom-quiesce-check.sh; echo "shellcheck rc=$?"
~/.claude/scripts/headroom-quiesce-check.sh || true
```

  Esperado: `shellcheck rc=0`, y una línea con el silencio actual (probablemente
  `ESPERAR`, porque hay tres sesiones vivas).

- [ ] **Step 5: unidad y timer, siguiendo la convención de la máquina**

  La convención observada en esta máquina es `trending-weekly.{service,timer}`:
  `Type=oneshot` con script en `~/.claude/scripts/`, y `.timer` con `OnCalendar`,
  `Persistent=true`, `RandomizedDelaySec` y `WantedBy=timers.target`.

```bash
cat > ~/.config/systemd/user/headroom-perf-archive.service <<'EOF'
[Unit]
Description=Archiva las lineas PERF de headroom antes de que roten

[Service]
Type=oneshot
ExecStart=%h/.claude/scripts/headroom-perf-archive.sh
Nice=15
EOF

cat > ~/.config/systemd/user/headroom-perf-archive.timer <<'EOF'
[Unit]
Description=Dispara el archivado de las metricas de headroom

[Timer]
# HORARIO y no diario: medido el 2026-09-03, el log quema 10 MB cada ~2 h y guarda
# 5 backups, asi que el historico completo dura ~12 h en un dia cargado. Un timer
# diario perderia datos.
OnCalendar=hourly
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
EOF

systemctl --user daemon-reload
systemd-analyze --user verify headroom-perf-archive.service headroom-perf-archive.timer; echo "rc=$?"
```

  Esperado: `rc=0` sin salida.

- [ ] **Step 6: activar el timer y comprobarlo**

```bash
systemctl --user enable --now headroom-perf-archive.timer
systemctl --user list-timers headroom-perf-archive.timer --no-pager
systemctl --user status headroom-perf-archive.service --no-pager | tail -5
```

  Esperado: el timer aparece con su próximo disparo, y el `.service` en
  `inactive (dead)` con el último resultado `success`.

---

### Task 8: aplicar en la máquina (paso destructivo — requiere visto bueno)

**Files:**
- Modify: estado del servicio `headroom-proxy.service`
- Delete: los seis ficheros `proxy.log`, `proxy.log.1` … `proxy.log.5` de
  `~/.headroom/logs/`, **enumerados uno a uno y nunca como glob del directorio**
  (histórico con conversación en claro)

**Interfaces:**
- Consumes: el drop-in de la Task 6 y el archivo de la Task 7, que vive en
  `~/.headroom/metrics/`, **fuera** del directorio que este paso vacía.

> **Precondición añadida tras la revisión de las Tasks 6+7.** La versión inicial
> del archivador leía tres de las seis ranuras de rotación, y se midieron 5676
> registros PERF que existían **solo** en `proxy.log.3`, `.4` y `.5`. Borrar con
> ese archivador habría destruido el 48,6 % de la serie. Antes de borrar nada,
> el archivo debe contener la barrida ancha: del orden de 11 700 filas de datos
> repartidas entre `perf-2026-08.tsv` y `perf-2026-09.tsv`. Si el recuento no
> llega, **no se borra**.

> **Este es el único paso que no es reversible sin coste.** El reinicio corta las
> peticiones en vuelo de tres sesiones vivas, y el borrado de los logs es
> definitivo. No se ejecuta sin autorización explícita de la persona, y solo
> después de que la Task 7 haya demostrado que el archivado es idempotente.

> **Cómo se ejecuta, aprendido al ejecutarla (2026-09-04).** Dos hechos que el
> plan no preveía y que cambian el procedimiento, no el objetivo:
>
> 1. **La lanza la persona, no el agente.** El clasificador de auto-mode deniega
>    un script que hace `systemctl stop`/`start` y borra ficheros, y esa
>    denegación es correcta. Los pasos 2-5 van encapsulados en un único script
>    fail-closed (`t8.sh`) que la persona invoca con `!`. Encapsularlo no es
>    comodidad: entre el `stop` y el `start` no puede haber un turno del agente,
>    porque el proxy estaría caído justo cuando el agente necesita hablar por él.
> 2. **La puerta de reposo solo abre con la sesión parada.** Medido:
>    `silencio=0s` en pleno trabajo. Cada turno del agente es una petición
>    `/v1/messages` por el proxy, así que comprobar la puerta turno a turno la
>    deja en `ESPERAR` indefinidamente. El script espera **en bucle dentro de una
>    sola invocación** (hasta ~13 min), y durante esa espera la sesión calla y el
>    silencio se acumula.
>
> El script añade un pre-vuelo que el plan no tenía: aborta si `ExecStart` ha
> dejado de llevar `--mode cache`, o si lleva `--budget` o `--log-messages`. Un
> reinicio **aplica** lo que haya en `ExecStart`, así que este paso es el momento
> exacto en que una deriva ahí se volvería efectiva.

- [ ] **Step 1: avisar a la sesión par que comparte el proxy**

  Hay al menos otra sesión activa enrutada (`ss -tnp | grep 8787`). Avisarla antes
  del reinicio, para que no esté a mitad de turno.

- [ ] **Step 2: esperar reposo**

```bash
~/.claude/scripts/headroom-quiesce-check.sh 45
```

  Esperado: `SEGURO: se puede reiniciar` y `rc=0`. Si dice `ESPERAR`, esperar y
  repetir. **No forzar.**

- [ ] **Step 3: archivar por última vez lo que haya entrado desde la Task 7**

```bash
~/.claude/scripts/headroom-perf-archive.sh
wc -l ~/.headroom/metrics/perf-*.tsv
cut -f3 ~/.headroom/metrics/perf-*.tsv | sort | uniq -d | head
```

  Esperado: unas pocas filas nuevas, un total ≥ 11 700 filas de datos, y la
  comprobación de duplicados **vacía**. Anotar la cifra exacta: es la única copia
  que queda después del Step 4, y este recuento es lo que autoriza el borrado.

- [ ] **Step 4: parar, limpiar el histórico y arrancar**

```bash
systemctl --user stop headroom-proxy.service
rm -f ~/.headroom/logs/proxy.log ~/.headroom/logs/proxy.log.1 \
      ~/.headroom/logs/proxy.log.2 ~/.headroom/logs/proxy.log.3 \
      ~/.headroom/logs/proxy.log.4 ~/.headroom/logs/proxy.log.5
chmod 700 ~/.headroom/logs
systemctl --user start headroom-proxy.service
chmod 600 ~/.headroom/logs/*
```

  El `chmod` final no es decorativo: `proxy.stderr` **no se borra** (son 1860 bytes
  de banner de arranque, sin conversación: verificado con 0 coincidencias de
  `payload_preview`, `headroom_retrieve` y `PERF`) y está en `644`. `UMask=0077`
  solo gobierna los ficheros que nazcan después, no el modo de uno que sobrevive.
  `~/.headroom/metrics/` no se toca en ningún caso: es la única copia de la serie.

  Se para y se arranca en vez de `restart` porque el manejador de logs mantiene el
  descriptor abierto: borrar el fichero con el proceso vivo lo deja escribiendo a
  un inodo sin nombre. `Restart=always` no reactiva nada tras un `stop` explícito.
  Los ficheros se nombran uno a uno a propósito, para que el comando diga
  exactamente qué borra.

- [ ] **Step 5: verificar los siete oráculos**

```bash
P=$(systemctl --user show -p MainPID --value headroom-proxy.service)
echo "--- A4 umask (esperado 0077) ---";      grep ^Umask /proc/$P/status
echo "--- A5 credenciales tapadas ---";       systemctl --user show -p InaccessiblePaths --value headroom-proxy.service
echo "--- A9 unidad valida ---";              systemd-analyze --user verify headroom-proxy.service; echo "rc=$?"
echo "--- servicio sano ---";                 curl -s -m 5 localhost:8787/readyz | head -c 60; echo
echo "--- A8 permisos ---";                   stat -c '%a %n' ~/.headroom/logs ~/.headroom/logs/* ~/.headroom/metrics ~/.headroom/metrics/*
echo "--- A10 enrutado (esperado >=3) ---";   ss -tnp 2>/dev/null | grep -c '127.0.0.1:8787'
echo "--- A7 la medicion sigue viva ---";     grep -c PERF ~/.headroom/logs/proxy.log
```

  Esperado: `Umask: 0077`; `InaccessiblePaths` con los cuatro directorios;
  `verify` rc=0; `readyz` con `"ready":true`; `logs` en `700` y los ficheros
  nuevos en `600`; al menos 3 sockets; y `PERF` creciendo (si diera 0, esperar una
  petición y repetir).

- [ ] **Step 6: verificar que la fuga se cerró (criterio A6)**

```bash
grep -c 'payload_preview_chars":[1-9]' ~/.headroom/logs/proxy.log
grep -o 'payload_preview_chars":[0-9]*' ~/.headroom/logs/proxy.log | sort | uniq -c
```

  Esperado: `0` en el primero. El segundo, en cuanto haya habido algún
  `headroom_retrieve`, debe mostrar solo `payload_preview_chars":0`. Si aún no ha
  habido ninguno, repetir más tarde: es el criterio que cierra P2 y no vale darlo
  por bueno sin verlo.

- [ ] **Step 7: `doctor.sh` de punta a punta (criterio A13)**

```bash
bash kit/doctor.sh 2>&1 | tail -15
```

  Esperado: `OK (0 FAIL)`. Recordatorio del estado conocido: `doctor.sh` avisa de
  que 5 hooks desplegados difieren del kit; son los que arregla la rama de P0 y se
  realinean **después** de fusionarla, reinstalando.

- [ ] **Step 8: rollback si algo falla**

```bash
rm -f ~/.config/systemd/user/headroom-proxy.service.d/10-higiene.conf
systemctl --user daemon-reload
systemctl --user restart headroom-proxy.service
curl -s -m 5 localhost:8787/readyz | head -c 40; echo
```

  Eso revierte **el drop-in**, que es el único cambio de comportamiento del
  proxy. No revierte las otras dos cosas que esta entrega dejó en la máquina, y
  conviene saberlo antes de suponer que borrar un fichero la restaura:

  - el `chmod 700` de `~/.headroom/logs`, que era `775`. Se revierte con un
    `chmod`, pero nadie debería querer revertirlo.
  - el archivador horario, que son dos unidades más:
    `systemctl --user disable --now headroom-perf-archive.timer` y borrar
    `headroom-perf-archive.{service,timer}` y el script.

  Los logs borrados no se recuperan; su `PERF` está en `~/.headroom/metrics/`.
  La copia de seguridad de la unidad de la Task 6 sigue disponible.

---

### Task 9: informe vivo y registro del oráculo

**Files:**
- Create: `docs/superpowers/headroom-higiene-cambios.md`
- Modify: `knowledge/ORACLES.md`

- [ ] **Step 1: escribir el informe de cambios**

  Un apartado por edición, con el mismo formato que
  `docs/superpowers/headroom-decoupling-cambios.md`: qué se cambió, por qué, y
  **cómo se verificó** (con la cifra medida, no "se comprobó"). Debe incluir el
  apartado «Contención» con el rollback y un apartado «Fuera de alcance» que
  repita el cabo abierto del `:443` y los no-objetivos del spec.

- [ ] **Step 2: medir la corrida real del oráculo**

```bash
time make test 2>&1 | tail -3
make test 2>&1 | grep -c '^NOT ok'
```

  Anotar los segundos reales y exigir `0`.

- [ ] **Step 3: actualizar la fila de `knowledge/ORACLES.md`**

  Poner la fecha de hoy y los segundos medidos en el paso 2. La fila es un
  **registro de medición**: subir el número sin subir la fecha convierte la fila
  en una medición que nunca ocurrió ese día.

- [ ] **Step 4: dos commits, no uno**

```bash
git add docs/superpowers/headroom-higiene-cambios.md
git commit -m "docs(informe): registrar la entrega de higiene con su verificacion

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"

git add knowledge/ORACLES.md
git commit -m "knowledge: fechar la corrida del oraculo tras la higiene del log

Va en commit aparte con prefijo propio porque lo manda CLAUDE.md:58: knowledge/
es la memoria del harness y su historia se lee sola.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 5: estado final, sin `push`**

```bash
git log --oneline ddff6fd..HEAD
git status --porcelain
```

  Esperado: 6 commits, árbol limpio. **No hacer `push` ni abrir PR**: eso lo
  autoriza la persona, y la rama de P0 va delante en la cola.

---

## Self-Review

**Cobertura del spec:** P1 → Tasks 3 (sensor), 6 (drop-in), 8 (aplicación). P2 →
Tasks 1, 2, 3, 8 (criterio A6). P3 → Task 6 step 3 y Task 8 (el reinicio es la
consecuencia de que no haya vía caliente). P4 → Tasks 1 step 4, 3 step 2, 8 step 4.
P5 → Task 7 completa. Criterios A1-A3 → Task 5. A4-A10 → Task 8 step 5. A11-A12 →
Task 7 steps 2-3. A13 → Task 8 step 7. A14 → Task 4.

**Sin marcadores de posición:** los cinco ficheros de máquina llevan su contenido
completo; los tres cambios de repo llevan el código literal y su punto de
inserción con número de línea. No queda ningún "comprobar el nombre real de":
`$UNIT` (`test_with_headroom.sh:58`), `$hr_unit` (`doctor.sh:275`), `falsified`
(`:33`) y los ayudantes `install_clean` / `mk_home` / `write_unit` / `run_doctor`
están verificados contra los ficheros, no supuestos.

**Consistencia:** `payload_preview` es la marca en las Tasks 2, 3, 4 y 8;
`10-higiene.conf` es el mismo nombre en las Tasks 2 (fixture), 6 y 8;
`headroom-perf-archive.sh` es el mismo en las Tasks 7 y 8. `falsified` es la
variable que ya existe en la suite. El resumen de `test_headroom_guardrails.sh` es
`== N passed, N failed ==` (comprobado en el fichero, no supuesto: su `ko()` emite
`NOT ok - ...`).

**Riesgo declarado:** la Task 8 es la única con coste irreversible, va detrás de
una autorización explícita y de una prueba de idempotencia, y tiene rollback
escrito.
