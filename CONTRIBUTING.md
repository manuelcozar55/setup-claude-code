# Contribuir a setup-claude-code

Gracias por el interés. Esto es sobre todo un kit personal que se comparte en
abierto, pero las contribuciones (issues, PRs, correcciones) son bienvenidas.

## Montar el entorno

No hace falta nada exótico: `bash`, `git`, `python3`, `jq`. Para la Capa 2 de
secretos (`kit/claude/hooks/git/pre-commit`) hace falta además el binario
`gitleaks` (version fijada en CI: 8.30.1).

```bash
git clone https://github.com/manuelcozar55/setup-claude-code.git
cd setup-claude-code
make test     # corre todas las suites
make doctor   # verifica una instalacion existente (si ya instalaste el kit)
make help     # lista los targets disponibles
```

No necesitas privilegios de root para nada de esto: el kit está parametrizado
con `$HOME`/`CLAUDE_HOME` a propósito, y el smoke test de CI corre exactamente
así (contenedor limpio, usuario no root).

## Correr los tests

Todo vive bajo `kit/test/`:

- `test_guards.sh` — Capa 1 de secretos (por nombre de fichero) + guards de
  Bash/git.
- `test_guards_falsifiability.sh` — demuestra que `test_guards.sh` mide algo
  real: neutraliza `secret-guard.sh` y comprueba que eso rompe casos BLOCK
  conocidos. Si no rompiera ninguno, la suite sería una tautología.
- `test_secret_content_gitleaks.sh` — Capa 2 (contenido real vía
  `gitleaks` en `pre-commit`). Se salta sola (SKIP, no FAIL) si no encuentra
  el binario `gitleaks` en el sistema.
- `test_install.sh`, `test_doctor.sh`, `test_scan_secrets.sh`.
- `test_install_platform_gate.sh` — la puerta de plataforma de `install.sh`
  (solo Linux/WSL2) aborta en cualquier otra y no deja nada a medias.
- `test_install_gitleaks.sh` — deteccion de `gitleaks` y degradacion con
  aviso (no rotura) cuando no esta instalado.
- `test_install_gitleaks_checksum.sh` — un checksum de `gitleaks` que no
  coincide con el fijado en `install.sh` no rompe la instalacion, pero deja
  una marca persistente en `CLAUDE_HOME` que `doctor.sh` reporta despues.
- `test_enable_secrets_layer2.sh` — `install.sh --enable-secrets-layer2`
  activa la Capa 2 solo en el repo desde el que se invoca explicitamente.
- `test_gitattributes.sh` — ningun script/hook versionado tiene CRLF en el
  arbol de trabajo (ver ".gitattributes y CRLF" mas abajo).
- `test_exec_modes.sh` — los scripts versionados que se invocan como
  ejecutable (`./script.sh`) tienen el bit de ejecucion y un shebang correcto.
- `test_optional_hook.sh` — `optional-hook.sh` degrada con aviso (no rotura)
  cuando la dependencia que envuelve (`rtk`, venv) no esta instalada, y
  propaga el exit code si el guard subyacente si esta instalado y bloquea.
- `test_clean_install_resilience.sh` — el kit instalado en una maquina
  simulada sin ningun componente de terceros (sin proxy, sin `rtk`, sin venv,
  sin `gitleaks`) no rompe ningun hook y sigue bloqueando comandos
  destructivos: las dos mitades a la vez.
- `test_doctor_base_url.sh` — `doctor.sh` consulta `/readyz` (no `/health`) y
  marca `FAIL` si algo enruta la API a un endpoint que no contesta.
- `test_with_headroom.sh` — `install.sh --with-headroom` instala el proxy, lo
  arranca, comprueba `/readyz` y solo entonces escribe la variable de
  enrutado en `settings.json`.
- `test_headroom_guardrails.sh` — los guardarrailes del proxy: `--mode cache` y no
  `token`, nunca `--budget` ni `--log-messages`, una sola fuente de `ANTHROPIC_BASE_URL`,
  y que la unidad generada traiga las tres correcciones medidas (rtk, HF_HUB_OFFLINE,
  rutas inaccesibles). Hermetico: `HOME`, `XDG_CONFIG_HOME` y un `headroom` de pega
  propios, o en CI no se ejecutaria y daria verde falso.
- `test_install_diff_first.sh` — si `CLAUDE_HOME` es a su vez un repo git con
  remoto, `install.sh` nunca escribe encima: genera el arbol aparte y ensena
  el diff. `--apply` fuerza la escritura, `--plan` fuerza el diff.
- `test_uninstall.sh` — `uninstall.sh` restaura de verdad el backup mas
  reciente (backups incrementales de `install.sh` y ZIP de `scripts/backup.sh`),
  y falla si no puede verificar lo que restaura.
- `test_auto_spec.sh` — el hook `UserPromptSubmit` que mete el harness solo.
  No comprueba que "produzca texto": comprueba que DISCRIMINE entre un encargo
  y una pregunta. Un clasificador que responde lo mismo a todo no clasifica.
- `test_autonomy.sh` — `scripts/autonomy.sh` y el Stop hook `verify-gate.sh` en
  los cuatro estados que deciden si un run desatendido es seguro: oraculo rojo
  (bloquea), verde (libera), presupuesto agotado (libera y avisa) y cap de
  Claude Code (`stop_hook_active`: se aparta).
- `test_detect_oracle.sh` — `scripts/detect-oracle.sh` contra proyectos
  sinteticos, nunca contra proyectos reales del usuario.
- `test_metrics.sh` — `scripts/metrics.py` sobre transcripts sinteticos, con
  valores EXACTOS conocidos, y una comprobacion de falsabilidad: cambia el
  fixture y exige que las metricas cambien.
- `test_harness_structure.sh` — el presupuesto de complejidad de la capa nueva
  (`.claude/`, `config/`, `knowledge/`). La linea base de `kit/` queda fuera
  del computo a proposito (ADR 005).
- `test_doc_claims.sh` — las cifras que la documentacion afirma sobre el repo
  (suites, agentes, comandos, ADRs, documentos) contra el arbol real, y que
  ningun documento cite un script que ya no existe.
- `test_evals.sh` — el INSTRUMENTO del eval set, no el agente: que `run.sh`
  exporte las variables que usan los checks, que ninguna tarea verifique
  grepeando el transcript crudo (el prompt se copia dentro, asi que ese grep
  acierta solo por el eco) y que cada modo de `grade.py` sepa fallar. Offline,
  sin una sola llamada a la API.

**Un `shellcheck` verde en local no es prueba.** El de CI se instala con `apt` y puede ser
mas antiguo que el tuyo: sigue emitiendo checks de categoria `style` que las versiones
>= 0.11 retiraron (p. ej. `SC2002`, *useless cat*). Paso exactamente eso — local limpio con
0.11.0 y CI en rojo. **El oraculo es CI**, no tu maquina.

Corre todo con `make test` o cada script suelto con `bash kit/test/<script>.sh`
(las 26 suites listadas arriba).

**El eval set (`kit/evals/`) no forma parte de `make test` ni de CI.** Cuesta
dinero real (llamadas a la API de Anthropic). Es opt-in: `bash
kit/evals/run.sh` o `make evals-paid` (pide confirmación). Nunca lo invoques
desde un test, un hook o un job de CI.

## Actualizar gitleaks

`kit/install.sh` fija la version (`GITLEAKS_VERSION`) y el hash SHA-256
esperado por arquitectura (`GITLEAKS_SHA256_LINUX_X64`,
`GITLEAKS_SHA256_LINUX_ARM64`) como constantes al principio del propio
script — no se descarga ningun `checksums.txt` de la release para verificar
contra el. La razon: ese fichero lo publica el mismo host que el tarball, asi
que protege contra corrupcion en transito pero no contra una release
comprometida; fijar el hash aqui, versionado y revisable en un PR, es lo que
de verdad ancla la confianza fuera de lo que la red sirva ese dia.

Para subir de version:

1. En la [pagina de releases de gitleaks](https://github.com/gitleaks/gitleaks/releases),
   descarga `gitleaks_<version>_checksums.txt` de la release nueva.
2. Verifica ese fichero de checksums contra los tarballs `linux_x64` y
   `linux_arm64` que realmente vas a fijar (descargalos tu mismo y corre
   `sha256sum -c`, no confies solo en copiar el texto del fichero).
3. Actualiza `GITLEAKS_VERSION` y los dos `GITLEAKS_SHA256_LINUX_*` en
   `kit/install.sh` con los valores verificados.
4. Actualiza tambien `GITLEAKS_VERSION`/`GITLEAKS_SHA256_LINUX_X64` en
   `.github/workflows/ci.yml` (instalacion de gitleaks para la propia CI;
   es una ruta de instalacion distinta a la de `install.sh`, con su propio
   pin).
5. Corre `make test` completo (en especial `test_install_gitleaks.sh` y
   `test_install_gitleaks_checksum.sh`) antes de abrir el PR. Un hash
   equivocado rompe la instalacion de `gitleaks` para todo el mundo — con
   degradacion elegante (Capa 1 sigue activa), pero rompe igual la Capa 2.

Nunca inventes ni copies un hash de una fuente que no sea la release oficial
de gitleaks verificada por ti mismo.

## `.gitattributes` y CRLF

El repo fuerza LF (`eol=lf`) en todo lo que se ejecuta o parsea (`*.sh`,
`*.py`, `*.yml`/`*.yaml`, `*.toml`, `*.json`, `Makefile`, el hook sin
extension `kit/claude/hooks/git/pre-commit`, etc.) via `.gitattributes` en la
raiz. Publico objetivo incluye WSL2 clonando desde Windows, donde
`core.autocrlf=true` es el default de Git: sin esto, un clon normal convierte
LF a CRLF y rompe cada script con `bad interpreter: /usr/bin/env bash^M`.
`test_gitattributes.sh` comprueba que ningun fichero versionado de esa lista
tiene CRLF en el arbol de trabajo, y se auto-falsea fabricando un CRLF a
proposito para demostrar que la comprobacion si dispara.

## Qué se espera de un PR

- **Si tocas un guard (cualquier fichero bajo `kit/claude/hooks/`,
  `kit/sentinel/` o `kit/claude/hooks/git/pre-commit`), el PR necesita un
  test que lo cubra.** No es una sugerencia: es la norma más dura que dejó
  esta rama. Un guard sin test es un guard que nadie puede demostrar que
  funciona, y que se puede romper en silencio en el siguiente cambio. Ver
  `test_guards_falsifiability.sh` para el porqué: una suite que no puede
  fallar no está probando nada.
- Commits en estilo Conventional Commits (`feat(kit): ...`, `fix(kit): ...`,
  `docs(kit): ...`), como el resto del historial.
- Cambios quirúrgicos: toca solo lo que el PR necesita. No reformatees ni
  "mejores" código adyacente de paso.
- Si el cambio toca `kit/`, corre `make test` y `make doctor` en local antes
  de abrir el PR — es lo mismo que va a correr CI.
- Nada de secretos ni ejemplos con forma verosímil de credencial real en el
  repo (este es un repo público). `gitleaks dir .` debe seguir en verde.

## Reportar un fallo de seguridad

Ver [SECURITY.md](SECURITY.md) — no abras un issue público para
vulnerabilidades.

## Cortar una release

El versionado es [SemVer](https://semver.org/lang/es/). Como este repo es un kit
de configuración y no una librería, la regla práctica es:

- **MAJOR** — un cambio que rompe una instalación existente: `install.sh` deja de
  ser idempotente sobre la versión anterior, un guard cambia de contrato, o
  `settings.json` deja de ser compatible.
- **MINOR** — piezas nuevas que no rompen nada: un guard más, una suite de test,
  un documento, un flag de `install.sh`.
- **PATCH** — arreglos y documentación.

El orden importa: **verificar primero, etiquetar después.** Un tag es inmutable
en la práctica (alguien puede haberlo clonado), así que no se corta una versión
sobre algo sin comprobar.

El CHANGELOG se edita **en una rama, vía PR**, igual que cualquier otro cambio
de este repo — nunca directo sobre `main`. No es solo por consistencia con el
resto de este documento: `kit/claude/hooks/branch-guard.sh` **bloquea**
`git push origin main`, así que un `git push` directo a `main` con el
CHANGELOG movido ni siquiera llega al remoto. Etiquetar es distinto: la regex
de `branch-guard.sh` solo mira `main`, `master` y `production`, así que
`git push origin vX.Y.Z` sí pasa sin tocar esa protección.

```bash
# 1. main al dia y limpio
git checkout main && git pull --ff-only && git status --porcelain   # sin salida

# 2. las 26 suites y el escaner de secretos
make test                    # exit 0
bash kit/scan-secrets.sh .   # PASS en un arbol limpio (ver nota abajo)

# 3. la prueba que de verdad importa: instalacion limpia en un CLAUDE_HOME virgen
T=$(mktemp -d)
CLAUDE_HOME="$T/h" bash kit/install.sh
CLAUDE_HOME="$T/h" bash kit/doctor.sh   # exit 0, 0 FAIL
rm -r "$T"

# 4. rama para el CHANGELOG: mover [Unreleased] -> [X.Y.Z] - AAAA-MM-DD, dejar
#    [Unreleased] vacio, y añadir los dos enlaces de comparacion del final
V=X.Y.Z
git checkout -b "release/v$V"
# ... editar CHANGELOG.md ...
git status --porcelain   # solo CHANGELOG.md
git add CHANGELOG.md
git commit -m "docs: preparar CHANGELOG para v$V"
git push -u origin "release/v$V"
gh pr create --title "docs: preparar CHANGELOG para v$V" --body "Release v$V."

# 5. mergear el PR y esperar CI en verde sobre main antes de seguir
gh pr merge --squash --delete-branch
git checkout main && git pull --ff-only

# 6. etiquetar y publicar (ahora si sobre el commit que ya tiene el CHANGELOG)
git tag -a "v$V" -m "v$V"
git push origin "v$V"

# las notas salen de la seccion de esa version del CHANGELOG. El rango de sed
# seria inclusivo por los dos extremos y arrastraria la cabecera siguiente y las
# lineas de enlaces del final; awk corta antes de cualquiera de las dos.
awk -v v="## [$V]" 'index($0,v)==1{f=1;next} f && (/^## \[/ || /^\[[^]]+\]: http/){exit} f' \
    CHANGELOG.md > /tmp/notas-$V.md
gh release create "v$V" --title "v$V" --notes-file /tmp/notas-$V.md
```

Nota sobre el paso 2: `scan-secrets.sh` recorre también ficheros no
versionados y gitignorados **a propósito** — así un `.env` real que aún no
has commiteado no pasa inadvertido. Eso significa que un venv, unos logs o
cualquier scratch de proceso que tengas colgando en el árbol pueden dar
`FAIL` sin que haya una fuga real. Lo que de verdad bloquea una release es un
hallazgo en material **versionado**, y eso se comprueba sin ambigüedad en un
clon limpio (`git clone` a un directorio nuevo y `bash kit/scan-secrets.sh .`
ahí).

Nota sobre el paso 3: los dos `WARN` de `doctor.sh` en una instalación limpia
(IOCs de Sentinel y Capa 2 de secretos) son correctos — son capas opt-in, y
`doctor.sh` sale con 0 igualmente. Lo que bloquea una release es un `FAIL`.
