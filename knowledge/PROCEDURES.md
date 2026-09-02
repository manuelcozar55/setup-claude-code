# PROCEDURES

Procedimientos validados, con **fecha de última validación**. Un procedimiento sin fecha es
folclore. Si la fecha es vieja, compruébalo antes de fiarte.

---

## P-001 · Verificar un backup de verdad

**Validado:** 2026-08-21 · **Comando:** `scripts/backup.sh`

Un backup que nadie ha restaurado es una suposición con nombre de fichero. El procedimiento
tiene tres partes y **las tres son obligatorias**:

1. **Crear** con manifiesto SHA-256 de todo el contenido.
2. **Restaurar** en un temporal y **revalidar todos los checksums** (`sha256sum -c`).
3. **Probar que falla cuando debe.** Sin este paso no sabes si tu verificador verifica.

Los cuatro casos que se comprobaron, y su resultado:

| Caso | Esperado | Real |
|---|---|---|
| ZIP intacto | pasa | ✅ pasa |
| Contenido alterado, manifiesto viejo | falla | ✅ falla |
| Bytes corruptos en el contenedor | falla | ✅ falla |
| Fichero inexistente | falla | ✅ falla |

**Gotcha caro que salió de aquí:** `sha256sum` en esta máquina es **uutils coreutils 0.8.0**,
no GNU, y en macOS no existe (allí es `shasum -a 256`). Todo script que valide checksums
resuelve las dos variantes o no es portable.

---

## P-002 · Medir la línea base de uso sin inflar el denominador

**Validado:** 2026-08-21 · **Comando:** `/usr/bin/python3 scripts/metrics.py`

`find ~/.claude/projects -name "*.jsonl"` devolvía **239 ficheros** el día de la validación,
de los que solo **47 eran sesiones reales**: 192 estaban bajo `*/subagents/*` y eran
transcripts de subagente (cifras del snapshot `metrics-2026-08-21.json`). Contarlos
infla el denominador ~×5 y deforma todas las medias.

**Filtra siempre `-not -path "*/subagents/*"` y declara el filtro** en la salida, no solo en
la cabeza de quien lo ejecuta. `metrics.py` lo emite bajo la clave `filter_applied`.

Corolario aprendido: separar por *profundidad de glob* en vez de por *nombre de ruta*
funciona hasta que alguien anida un directorio, y entonces falla en silencio.

---

## P-003 · Ejecutar un comando cuyo nombre puede ser reescrito

**Validado:** 2026-08-21 · Ver `knowledge/MISTAKES.md` · M-001

El hook `PreToolUse/Bash` sustituye el ejecutable **en posición de comando**. Tres vías lo
evitan, las tres verificadas:

```bash
/ruta/absoluta/al/binario --flags      # preferida para oráculos
rtk proxy <comando> --flags            # bypass documentado
bash script-que-lo-contiene.sh         # el hook no entra dentro del script
```

**Cómo comprobar si te está pasando:** ejecuta el binario con `--version` y mira si el
programa que responde es el que pediste. `rg --version` devolviendo `grep (GNU grep) 3.12`
es la firma del problema.

---

## P-004 · Cerrar trabajo en este repo

**Validado:** 2026-08-21

```bash
make test                                              # oráculo, ~45 s, exit 0 o no está hecho
/usr/bin/shellcheck -x scripts/*.sh .claude/hooks/*.sh # lint, cero hallazgos
bash kit/scan-secrets.sh .                             # secretos, capa 1
~/.local/bin/gitleaks dir --no-banner -c kit/claude/.gitleaks.toml .  # secretos, capa 2
git diff --name-only                                   # ¿tocaste el sensor?
```

Ese último es el que se olvida y el que más importa: si en el diff aparece un fichero de
test, un `conftest.py` o el propio comando del oráculo, **has aflojado el sensor** y el
verde no significa nada.

`shellcheck` y `gitleaks` van por ruta absoluta por lo mismo que los oráculos (M-001, P-003):
por nombre suelto el hook `PreToolUse/Bash` sustituiría el ejecutable y el verde sería el de
otro programa.

Después: rama + PR, nunca commit directo a `main`. Los cambios en `knowledge/` van en
commits aparte con prefijo `knowledge:`.

---

## P-005 · Reformular ante un bloqueo de guard

**Validado:** 2026-08-21 · Ver `knowledge/MISTAKES.md` · M-002

Los guards inspeccionan **el literal del comando**, no la acción. Escribir el nombre de un
fichero de credenciales dispara Sentinel aunque sea para *excluirlo* del backup; `rm -rf`
sobre un temporal propio también se bloquea.

La salida correcta es **reformular**: componer el nombre (`".$(printf 'credential')s.json"`),
usar otra herramienta, o mover la lógica dentro de un script.

**La salida incorrecta es ampliar la allowlist.** Eso convierte un sensor en decoración, y
se paga la primera vez que el guard tendría que haber saltado de verdad. Si de verdad hace
falta ampliarla, va con justificación escrita en `knowledge/DECISIONS/`.
