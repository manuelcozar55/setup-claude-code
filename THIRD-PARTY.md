# Componentes de terceros

Este fichero recoge el material de terceros del que deriva parte del software de
este repositorio, con sus avisos de copyright. Forma parte de las condiciones de
`LICENSE-CODE`.

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

### randomdreft/claude-code-security-hook — situación de licencia SIN RESOLVER

Fichero afectado: `kit/claude/hooks/block-dangerous-commands.sh`, cuya cabecera
dice `# Source: randomdreft/claude-code-security-hook (public domain), extended`.

**Ese "public domain" no está respaldado por el repositorio de origen.**
Comprobado contra la API de GitHub: el repositorio existe, no está archivado y
**no contiene ningún fichero de licencia** (`license: null`). Sin una declaración
explícita del autor, el derecho de autor por defecto reserva todos los derechos, y
"dominio público" no se presume.

No se corrige la cabecera inventando otra afirmación: se documenta el hecho
verificable y queda como asunto abierto para el propietario de este repositorio.
Las vías para cerrarlo, en orden de menor a mayor coste:

1. Pedir al autor original que añada una licencia explícita (o una renuncia tipo
   CC0/Unlicense) y citarla aquí.
2. Comprobar si lo que queda en el fichero tras haberlo extendido es material
   propio: si las partes derivadas ya no están, la atribución sobra y la cabecera
   debe reflejarlo.
3. Reescribir el fichero desde cero a partir de su especificación de
   comportamiento, que ya está fijada por `kit/test/test_guards.sh` y por la suite
   de falsabilidad.

Mientras no se cierre, esta entrada es la constancia honesta del estado real.

---

## Dependencias externas (no redistribuidas)

Programas que el kit **usa** pero no incluye ni copia. Los instala el usuario, y
cada uno se rige por su propia licencia. No generan obligación de atribución para
este repositorio; se listan por transparencia.

| Componente | Licencia | Cómo entra |
|---|---|---|
| [gitleaks](https://github.com/gitleaks/gitleaks) | MIT | lo descarga el usuario o el CI, con versión y checksum fijados; ver `kit/docs/02-install.md` |
| [Headroom](https://github.com/headroomlabs-ai/headroom) | Apache-2.0 | componente de terceros opcional; el kit no lo instala, ver `kit/docs/03-headroom.md` |
| [rtk](https://github.com/rtk-ai/rtk) | Apache-2.0 | opcional; el kit no lo cablea ni lo invoca — solo lo deja permitido en `permissions.allow` |

Las tres licencias de esta tabla se comprobaron contra la API de GitHub, no contra
la documentación de cada proyecto.

---

## Nota

Esto es un registro de atribución, no asesoramiento legal. Si el repositorio va a
usarse en un contexto donde la procedencia importe formalmente, conviene una
revisión por alguien cualificado — en particular el punto sin resolver de arriba.
