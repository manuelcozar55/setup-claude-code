# ORACLES

Un **oráculo** es un comando que devuelve `0` si el trabajo está bien hecho y `≠0` si no.
No es una opinión, no es "revisar que funcione", no es el juicio del agente al terminar.
**Sin oráculo no hay lazo de verificación: hay un prompt largo con pasos.**

## Reglas de este registro

1. **Comando por ruta absoluta o `make …`.** Nunca un binario por nombre suelto: un hook
   `PreToolUse/Bash` puede sustituir el ejecutable en posición de comando — el de `rtk` lo
   hacía, y se retiró en la 1.1.0 justo por eso (ver [MISTAKES.md](MISTAKES.md) · M-001).
   La regla no depende de que ese hook exista: el canal sigue siendo reescribible por
   cualquier hook futuro. `test_oracle_registry` lo verifica.
2. **Resultado con fecha.** Un resultado sin fecha es una predicción.
3. **Un rojo honesto es un oráculo válido.** La línea base es lo que hay, no lo que
   queremos que haya. No se arregla el proyecto para que el oráculo pase.
4. **El oráculo es inmutable durante la tarea que verifica.** Si aparece la tentación de
   relajar un `assert`, añadir un `-k`, marcar `xfail` o tocar el `conftest`, la tarea se
   marca bloqueada. Aflojar el sensor no cierra el lazo: lo rompe dejando apariencia de éxito.

---

## Registro

| Proyecto | Comando | Resultado | Fecha | Duración | Fiabilidad |
|---|---|---|---|---|---|
| **mcharness** (este repo) | `make test` | ✅ **exit 0** · 32 suites, 0 failed | 2026-09-03 | 118-179 s | **Alta.** Determinista, sin red, sin LLM. Es el oráculo de referencia del harness. |
| **mcharness** (lint) | `/usr/bin/shellcheck -x scripts/*.sh kit/**/*.sh` | ✅ limpio | 2026-08-21 | <2 s | Alta. Computacional. |
| **mcharness** (secretos) | `/home/…/.local/bin/gitleaks dir --no-banner .` | ✅ `no leaks found` | 2026-08-21 | 124 ms | Alta. |
| `sistema-riego` | `/home/…/.venvs/riego/bin/pytest tests/unit -q` | ⏸️ **NO EJECUTADO** | 2026-08-21 | — | **Desconocida.** Ejecución no autorizada por el propietario. Ver nota. |

### Nota sobre `sistema-riego`

Entorno **listo pero no verificado**: `~/.venvs/riego` (Python 3.12.13, pytest 9.1.1),
39 ficheros de test / 432 casos, de los cuales **152 en `tests/unit`**. `pytest.ini` con
`testpaths=tests`; `tests/conftest.py` aísla el entorno (`DEV_MODE=true`,
`DATA_DIR=tests/fixtures/data`, tmp local).

**No se ejecutó**: el propietario declinó la ejecución sobre su proyecto de trabajo. Queda
como candidato para v0.2.0. Riesgos ya identificados que deberá absorber quien lo active:

- El venv tiene `pandas 3.0.5` / `numpy 2.5.2` frente a `pandas==2.2.1` / `numpy==1.26.4`
  pineados en `requirements.txt`. **Puede dar rojo por deriva de dependencias, no por el código.**
- Coexisten `pytest.ini` y `[tool.pytest.ini_options]` en `pyproject.toml`; pytest da
  precedencia al `.ini`, así que el bloque de `pyproject` queda inerte.
- `bin/gee/test_gee.py` cae fuera de `testpaths=tests` y no se recoge.
- `tests/integration` (5 ficheros) declara el marker *"tests that require external state"*.

### Estado del resto de proyectos (para v0.2.0)

| Proyecto | git | Casos declarados | Entorno ejecutable | Bloqueante |
|---|---|---|---|---|
| `circe-brain/circe-prospector` | ✅ | 1.443 | ❌ | Sin venv; 270 MB en `/mnt/c` |
| `ofertadora/lab` | ❌ | 58 | ❌ | **Sin control de versiones**: cualquier cambio es irreversible |
| `ofertadora/2025_v1` + `2025_webscraper_v1` | ✅ | 0 | ❌ | 20+ ficheros `TEST_*.py` que **no son tests** sino scripts que tocan la BD de producción |
| `legal-assistant` | ✅ | 104 | ❌ | Sin venv |
| `tfm-agent-system` | ✅ | 48 | ❌ | Sin fichero de dependencias |

**Ninguno de los 40 proyectos candidatos tiene un `.venv` local.** Ese, y no la falta de
tests, es el cuello de botella de *harnessability*: hay ~2.300 casos declarados y un solo
intérprete capaz de correr alguno.
