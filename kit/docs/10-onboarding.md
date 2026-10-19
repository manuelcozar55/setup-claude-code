# 10 · Onboarding: de cero a sesión verde

Esta es la ruta para alguien que llega nuevo. Un solo comando levanta lo obligatorio; lo
opcional se decide después.

Si eres Claude Code leyendo esto en una máquina nueva: los pasos 1 y 2 son el arranque y el
paso 3 es el diagnóstico cuando algo no cuadra.

---

## 0 · Qué vas a levantar

| Capa | Qué es | Obligatoria |
|---|---|---|
| `kit/` | La instalación endurecida en tu `~/.claude`: guards deterministas, Sentinel, 8 agentes, y la Capa 2 de secretos sobre cada commit | Sí |
| raíz (`.claude/`, `knowledge/`, `scripts/`) | El harness: comandos, skills, hooks de proyecto y el conocimiento versionado. Ya viaja en el repo | Sí, ya la tienes al clonar |
| `gitleaks`, venv de tools | Escáner de secretos por contenido (Capa 2) e intérprete de los hooks Python | No. Sin el venv esos hooks quedan en no-op **y los guards de bash siguen bloqueando**; sin `gitleaks` no puedes activar la Capa 2 |

Nada del kit da por supuesto lo opcional, y hay un test que lo demuestra en una máquina
pelada: `kit/test/test_clean_install_resilience.sh`.

## 1 · Instalar

Linux o WSL2, con `jq` (dependencia dura de cuatro guards). Desde un clon, `make bootstrap` crea tu
`config/profile.yaml`, instala el kit en `~/.claude` con backup (o enseña el diff, si es un repo
con remoto), corre el oráculo y `doctor.sh`. Requisitos, pasos a mano y desinstalación: [`02-install.md`](02-install.md).

## 2 · Verificar de verdad

```bash
make test          # 41 suites en bash puro, sin red, ~58 s. exit 0 o no está hecho.
bash kit/doctor.sh # estado de ESTA máquina
```

Cómo leer `doctor.sh`:

- **`FAIL`** → algo está roto o es inseguro. Sale con código distinto de 0. No lo ignores.
- **`WARN`** → un componente opcional que no instalaste. Es aceptable.
- Cada `PASS` dice de dónde sale el dato (`(fuente: …)`). Si un check no puede decir su
  fuente, no es un check.

Y no te creas que los guards funcionan porque lo diga el README: neutraliza uno y mira qué
pasa. `bash kit/test/test_guards_falsifiability.sh` desactiva un guard real y exige que eso
rompa exactamente 28 casos `BLOCK` conocidos. Si desactivarlo no rompiera nada, la suite no
estaría midiendo nada.

## 3 · Cuando algo va mal

| Síntoma | Causa medida |
|---|---|
| Un hook "no hace nada" | CRLF en el fichero, o sin bit de ejecución. `kit/test/test_gitattributes.sh` y `kit/test/test_exec_modes.sh` lo cubren en el repo. |
| Sentinel bloquea algo legítimo | Reformula el comando. **No amplíes la allowlist para esquivarlo**: los guards bloquean por el literal, así que nombrar un fichero de credenciales —aunque sea para excluirlo— dispara. |

## 4 · Antes de tu primer commit

```bash
bash kit/scan-secrets.sh   # secretos y PII en el árbol
shellcheck -x <tus .sh>
make test
```

Rama y PR, nunca directo a `main`. Y si tu cambio toca una cifra que la documentación
afirma, `kit/test/test_doc_claims.sh` te pondrá en rojo: eso no es un obstáculo, es el punto.
