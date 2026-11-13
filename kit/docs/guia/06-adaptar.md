# Guía · Adaptar el kit a tu caso

Cuatro cambios que casi todo el mundo acaba haciendo: añadir un hook propio, mover un umbral, quitar un agente y
sobrevivir a una actualización. Cada orden de esta página la ejecuta `kit/test/test_adaptar.sh` en un `HOME` aislado:
si una deja de funcionar, ese test se pone rojo. Regla para todo: mide con `/context` antes y después, en una sesión
nueva ([`01-por-que-contexto.md`](01-por-que-contexto.md)), porque lo que cargas y no usas lo pagas en cada turno.

Lo que **no** se quita en ningún caso: los guards de `PreToolUse` sobre `Bash` y el bloque `permissions.deny` que
protege la propia configuración. Son las barreras. Lo demás es preferencia. Qué hace cada pieza:
[`MAPA.md`](../MAPA.md).

## 1 · Añadir un hook tuyo

Tu hook vive en `~/.claude/hooks/` con un nombre que el kit no use y se cablea en `~/.claude/settings.json`.

```bash
cat > ~/.claude/hooks/mi-hook.sh <<'EOF'
#!/usr/bin/env bash
echo "mi-hook: $(jq -r .tool_input.command)" >&2
exit 0
EOF
chmod +x ~/.claude/hooks/mi-hook.sh
S=~/.claude/settings.json
jq '.hooks.PreToolUse += [{"matcher":"Bash","hooks":[{"type":"command","command":"\"$HOME/.claude/hooks/mi-hook.sh\"","timeout":5}]}]' "$S" > "$S.new" && mv "$S.new" "$S"
```

Comprobación: `echo '{"tool_input":{"command":"ls"}}' | ~/.claude/hooks/mi-hook.sh` imprime `mi-hook: ls`.
Reinicia las sesiones abiertas. `bash kit/doctor.sh` sigue en `== OK (0 FAIL) ==`: el doctor solo vigila los hooks del kit.
Un hook que bloquea sale con código 2 y escribe el motivo en la salida de error.

## 2 · Cambiar un umbral

Los valores que se ajustan son variables de entorno con un valor por defecto en el código; la lista completa y quién
las lee está en [`MAPA.md`](../MAPA.md). Se fijan en la clave `env` de `settings.json`, que Claude Code pasa a los hooks.
Ejemplo: proteger solo `production` en vez de `main:master:production`.

```bash
S=~/.claude/settings.json
jq '.env.CC_PROTECT_BRANCHES = "production"' "$S" > "$S.new" && mv "$S.new" "$S"
```

Comprobación: con esa variable, `branch-guard.sh` deja pasar `git push origin main` y sigue bloqueando
`git push origin production`. Otros umbrales: `NUCLEO_TOPE` (bytes de estado que se inyectan), `CC_SAFE_DELETE_DIRS`
(carpetas que se pueden borrar sin avisar), `COCKPIT_AUTO_HANDOFF` (a qué % de contexto el cockpit hace el handoff, o `off`).

## 3 · Quitar un agente

El kit instala siete agentes en `~/.claude/agents/`. Si no usas uno, bórralo y anótalo para que el doctor lo sepa:

```bash
rm ~/.claude/agents/code-reviewer.md
echo agents/code-reviewer.md >> ~/.claude/.kit-desactivados
bash kit/doctor.sh     # INFO · desactivado por ti … ; == OK (0 FAIL) ==
```

Sin la anotación el doctor da FAIL («componente obligatorio del kit ausente»). Las skills (`~/.claude/skills/<nombre>/`)
y los hooks se quitan igual; el procedimiento completo está en [`OPERAR.md`](../OPERAR.md#quiero-quitar-un-hook).

## 4 · Sobrevivir a una actualización

`bash kit/install.sh --apply` hace una copia de lo que sobrescribe y fusiona `settings.json` por dueño:

- **Se conserva:** tu hook propio (el cableado y el script), las claves de `env` que añadiste (`CC_PROTECT_BRANCHES`), y tu
  `CLAUDE.md` y `AGENTS.md` si son tuyos (el kit deja el suyo como `CLAUDE.kit.md`).
- **Sigue apagado:** lo que quitaste y anotaste en `.kit-desactivados` (un hook no se vuelve a cablear y un agente no se
  vuelve a copiar); la lista solo evita recrear lo que falta y no quita nada de lo que ya está cableado o instalado. El plan y
  el resumen de `install.sh` dicen qué se deja apagado, y apagar un guard de seguridad deja un WARN en `doctor.sh`. Para
  encenderlo, borra su línea y reinstala.

Receta completa de actualización: [`OPERAR.md`](../OPERAR.md#actualizar-a-una-versión-nueva).

## Al terminar

1. `bash kit/doctor.sh`: un `FAIL` es un hallazgo; un `INFO · desactivado por ti` es lo esperado.
2. `/context` en una sesión nueva, y apunta la cifra en la ficha de [`04-mide-tu-setup.md`](04-mide-tu-setup.md).
