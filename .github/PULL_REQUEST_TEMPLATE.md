## Qué cambia y por qué

## Cómo se probó

- [ ] `make test` en local, en verde
- [ ] `bash kit/doctor.sh` en verde (si el cambio toca instalación/config)

## Checklist

- [ ] **Si este PR toca un guard** (`kit/claude/hooks/`, `kit/sentinel/`, o
      `kit/claude/hooks/git/pre-commit`), **añadí un test que lo cubre**.
      Un guard sin test no se puede distinguir de un guard roto.
- [ ] No añadí ni modifiqué nada bajo `kit/evals/` que haga que `make test`
      o CI invoquen el eval set (cuesta dinero real; debe seguir siendo
      opt-in).
- [ ] No hay secretos ni ejemplos con forma verosímil de credencial real en
      el diff (`gitleaks dir .` sigue en verde).
- [ ] Commits en Conventional Commits (`feat(kit): ...`, `fix(kit): ...`,
      `docs(kit): ...`).
