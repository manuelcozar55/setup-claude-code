# Componentes de terceros

Este fichero recoge el material de terceros del que deriva parte del software de
este repositorio, con sus avisos de copyright. Forma parte de las condiciones de
`LICENSE`.

Se distingue a propósito entre **código derivado** (material de otro proyecto que
este repositorio incorpora y redistribuye, con obligaciones de atribución) y
**dependencias externas** (programas que el usuario instala por su cuenta y que
este repositorio no redistribuye, sin obligación de atribución). Mezclar ambas
cosas es lo habitual y es incorrecto: infla la lista y desdibuja lo que de verdad
hay que cumplir.

---

## Código derivado

### yurukusa/claude-code-hooks — MIT

Ficheros de este repositorio que derivan de ese proyecto:

- `kit/claude/hooks/branch-guard.sh`
- `kit/claude/hooks/destructive-guard.sh`
- `kit/claude/hooks/secret-guard.sh`

Los tres lo declaran en su cabecera (`# Source: yurukusa/claude-code-hooks (MIT)`).
La licencia MIT exige que el aviso de copyright y el aviso de permiso se incluyan
en las copias o porciones sustanciales del software; se reproducen íntegros a
continuación, verificados contra el fichero `LICENSE` del repositorio de origen:

```
MIT License

Copyright (c) 2026 yurukusa

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### mattpocock/skills — MIT

Repositorio: <https://github.com/mattpocock/skills>, commit `49dd158`.

Directorios de este repositorio que derivan de ese proyecto, cada uno con su
`LICENSE` original (`Copyright (c) 2026 Matt Pocock`, texto MIT):

- `kit/claude/skills/retro/`

Adaptación: en `retro` se sustituyó la sección final de
adaptación local por una versión genérica (sin referencias a ninguna
organización concreta). El resto se copia sin cambios. La skill `deep-change`
de la misma carpeta es propia y no deriva de ese proyecto.

### obra/superpowers — MIT

Repositorio: <https://github.com/obra/superpowers>, versión 6.4.1.

El plugin `kit/plugins/esenciales/` deriva de ese proyecto: seis de sus skills
(`brainstorming`, `writing-plans`, `subagent-driven-development`,
`systematic-debugging`, `finishing-a-development-branch`,
`dispatching-parallel-agents`) con sus ficheros de apoyo (salvo el companion visual
de `brainstorming`, retirado), y el `LICENSE` original
íntegro (`Copyright (c) 2025 Jesse Vincent`, texto MIT) en
`kit/plugins/esenciales/LICENSE`.

Adaptación: namespace `esenciales:`, referencias a las skills no incluidas
sustituidas por su paso equivalente, y en `brainstorming`, `writing-plans` y
`subagent-driven-development` el flujo pasa por `.claude/estado/nucleo.md`. Cada
`SKILL.md` lo declara en su última línea; el detalle está en
`kit/plugins/esenciales/README.md`. No se incluye el hook `SessionStart` del original.

### randomdreft/claude-code-security-hook — declaración de dominio público

Fichero afectado: `kit/claude/hooks/block-dangerous-commands.sh`, cuya cabecera
dice `# Source: randomdreft/claude-code-security-hook (public domain), extended`.

La sección **License** del README original declara literalmente:

> Public domain — use freely.

Fuente verificada el 2026-11-04: [README en el commit
`a2254903020ebec4196946fce8fd0a559b5e8118`](https://github.com/randomdreft/claude-code-security-hook/blob/a2254903020ebec4196946fce8fd0a559b5e8118/README.md#license).
Se conserva aquí esa declaración y la atribución del fichero.

La anotación anterior se basaba en `license: null` de la API de GitHub y omitía
la declaración del README. La API no detecta una licencia separada; eso no
significa que el autor no haya publicado un permiso. No se atribuye al proyecto
una licencia SPDX que no declara.

---

## Dependencias externas (no redistribuidas)

Programas que el kit **usa** pero no incluye ni copia. Los instala el usuario, y
cada uno se rige por su propia licencia. No generan obligación de atribución para
este repositorio; se listan por transparencia.

| Componente | Licencia | Cómo entra |
|---|---|---|
| [gitleaks](https://github.com/gitleaks/gitleaks) | MIT | lo descarga el usuario o el CI, con versión y checksum fijados; ver `kit/docs/02-install.md` |
| [rtk](https://github.com/rtk-ai/rtk) | Apache-2.0 | opcional; el kit no lo cablea ni lo invoca — solo lo deja permitido en `permissions.allow` |
| [ponytail](https://github.com/DietrichGebert/ponytail) | MIT | plugin; lo instala `kit/install-plugins.sh --apply` desde su marketplace |
| [ui-ux-pro-max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) | MIT | plugin; lo instala `kit/install-plugins.sh --apply` desde su marketplace |
| [impeccable](https://github.com/pbakaus/impeccable) | Apache-2.0 | plugin opcional; `kit/install-plugins.sh --apply --with-optional` |
| [find-skills](https://github.com/vercel-labs/skills) | MIT | skill opcional; `kit/install-plugins.sh --apply --with-optional` vía `npx skills add` |

Las licencias de esta tabla se comprobaron contra la API de GitHub, no contra
la documentación de cada proyecto.

---

## Nota

Al actualizar material de terceros, conserva sus avisos y comprueba la declaración
de permiso en la versión concreta que se incorpora, además de los metadatos de
la plataforma.
