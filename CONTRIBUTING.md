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
- `test_enable_secrets_layer2.sh` — `install.sh --enable-secrets-layer2`
  activa la Capa 2 solo en el repo desde el que se invoca explicitamente.

Corre todo con `make test` o cada script suelto con `bash kit/test/<script>.sh`.

**El eval set (`kit/evals/`) no forma parte de `make test` ni de CI.** Cuesta
dinero real (llamadas a la API de Anthropic). Es opt-in: `bash
kit/evals/run.sh` o `make evals-paid` (pide confirmación). Nunca lo invoques
desde un test, un hook o un job de CI.

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
