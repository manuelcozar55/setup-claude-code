---
name: Bug report
about: Algo del kit no funciona como se documenta
title: "[bug] "
labels: bug
---

## Qué esperabas

## Qué pasó en su lugar

## Cómo reproducirlo

```bash
# comandos exactos, incluyendo CLAUDE_HOME si lo tocaste
```

## Entorno

- SO: (solo Linux/WSL2 está soportado y probado en CI; si es otro, dilo igual)
- Salida de `bash kit/doctor.sh`:

```
pega aquí la salida completa
```

## Notas adicionales

¿Sospechas que el fallo está en un guard (`kit/claude/hooks/`,
`kit/sentinel/`)? Dilo explícitamente — esos cambios necesitan un test
acompañante (ver `CONTRIBUTING.md`).
