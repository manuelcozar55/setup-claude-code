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

Corre todo con `make test` o cada script suelto con `bash kit/test/<script>.sh`.

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
