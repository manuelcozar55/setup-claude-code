# Enriquecimiento LangChain de agentes-fundamentos + blindaje del repo — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enriquecer el deck conceptual `agentes-fundamentos` (HTML + guion) con material citado de las fuentes de máxima calidad de LangChain (sumando como máximo ~10 min de contenido hablado), y dejar la carpeta `CC-Setup` como un repositorio git profesional y seguro para compartir con compañeros.

**Architecture:** Dos frentes independientes. (A) **Contenido**: cada uno de los 10 pilares recibe un `aside.pillar-source` con una idea atribuida a LangChain que profundiza su "por qué"; la sección 01 gana un "beat de validación" (LangChain usa la MISMA analogía de Karpathy y acuñó "context engineering"); se añade una sección "Fuentes / para profundizar" y se amplía la atribución del footer; el guion se amplía en paralelo (+~10 min) con la misma profundidad y un anexo de fuentes. (B) **Repo**: `README.md`, `LICENSE` (CC BY 4.0), `.gitignore`, `git init` + commits atómicos, con un disclaimer honesto sobre las cifras reales del deck hermano y confirmación (por escaneo) de que no hay valores de secretos.

**Tech Stack:** HTML5 + CSS/JS inline (sin build, sin dependencias externas salvo Google Fonts), Markdown, git. Sin framework de test: la verificación es por render en navegador (ambos temas), `grep`/`wc` sobre los ficheros, y conteo/contraste manual.

## Global Constraints

Copiadas verbatim del encargo y del sistema de diseño ya establecido en los ficheros. Cada tarea las hereda implícitamente.

- **Presupuesto de tiempo**: el guion añade **como máximo ~10 min** de contenido hablado (hoy 12-15 min → objetivo 22-25 min). En palabras: sumar **≤ 1.400 palabras habladas** al total (base actual: 2.385 palabras de fichero). Si un bloque se pasa, recórtalo en otro, nunca en el cierre.
- **Acento bloqueado**: solo `--field` (ámbar/ocre). Light `--field: #8f5e00`, `--field-ink: #875600`, `--field-soft: #faf1dc`; dark `--field: #e6b45c`, `--field-ink: #eec277`, `--field-soft: #2e2612`. Los colores del setup (violeta/verde/azul, `--set-*`) SOLO en el puente `#puente`. Prohibido introducir hex nuevos en prosa o en los asides.
- **Sin em-dash (—)** en el cuerpo del HTML ni en la prosa del guion. En-dash solo en cabeceras de tiempo del guion (patrón ya existente). Usa comas, dos puntos o paréntesis.
- **Honestidad / cero cifras inventadas**: el deck es conceptual; NO se inventan números. Las citas de LangChain van atribuidas. Los números reales viven en el deck hermano (setup).
- **Hermano coherente**: no se toca `setup-claude-code-definitiva.html` ni su guion salvo lo explícitamente indicado en la Tarea 7 del README/hardening (que no edita su contenido, solo lo documenta).
- **Cambios quirúrgicos**: edición incremental, sin reescrituras. No "mejorar" código adyacente. Mantener el estilo existente aunque lo harías distinto.
- **Autocontenido**: nada de CDNs nuevos ni assets remotos. Todo inline.
- **Idioma y registro**: español, tú-a-tú, técnico y directo, idéntico al tono actual.

---

## File Structure

**Se modifican (contenido):**
- `agentes-fundamentos.html` (1584 líneas) — CSS de `.pillar-source` + `.sources`; beat de validación en `#cambio`; 10 asides de fuente (uno por pilar); sección "Fuentes"; footer ampliado.
- `agentes-fundamentos-guion.md` (2385 palabras) — cabecera de duración; profundidad citada por bloque; anexo C "Fuentes y lecturas".
- `agentes-fundamentos-cambios.md` — nueva entrada de change report documentando este enriquecimiento.

**Se crean (repo):**
- `README.md` — portada profesional del repo (qué es, cómo abrirlo, los dos decks, disclaimer de cifras, atribución, licencia).
- `LICENSE` — CC BY 4.0 (contenido divulgativo/charla). Alternativa MIT si se prefiere estilo software.
- `.gitignore` — excluye `data/` (capturas de WhatsApp, no profesionales), temporales de SO y de editor.

**No se tocan:** `setup-claude-code-definitiva.html`, `setup-claude-code-definitiva-guion.md` (contenido intacto; solo se referencian desde el README).

---

## Material de fuentes (LangChain) — banco de citas verificado

Estas son las afirmaciones ya investigadas y atribuidas que las tareas insertarán. **No inventar más; usar estas.**

- **Loop** — LangChain, *The Art of Loop Engineering* (Sydney Runkle; sobre "loopcraft" de Swyx): "el potencial de los agentes está en los bucles que construyes a su alrededor"; un agente es "un modelo que llama a herramientas en un bucle hasta completar la tarea"; cuatro bucles apilados (agente, verificación, por eventos, hill-climbing); "los tres primeros automatizan el trabajo; el cuarto automatiza la mejora". `https://www.langchain.com/blog/the-art-of-loop-engineering`
- **Context** — LangChain, *Context Engineering*: "el arte y la ciencia de llenar la ventana de contexto con la información justa en cada paso de la trayectoria del agente"; cuatro estrategias: write, select, compress, isolate; usa la MISMA analogía de Karpathy (LLM=CPU, contexto=RAM); en Deep Agents, un resultado de herramienta que supera 20.000 tokens se descarga al filesystem y se sustituye por una ruta + preview. `https://blog.langchain.com/context-engineering-for-agents/`
- **Rise of context engineering** — "context engineering es la habilidad más importante que un ingeniero de IA puede desarrollar"; "casi siempre que un agente falla es porque no se le comunicó el contexto, las instrucciones o las herramientas adecuadas". `https://blog.langchain.com/the-rise-of-context-engineering/`
- **Harness vs runtime** — LangChain, *The Runtime Behind Production Deep Agents*: "el harness es el sistema que construyes alrededor del modelo para que tenga éxito en su dominio (prompts, herramientas, skills); el runtime es todo lo de debajo: ejecución durable, memoria, multi-tenancy, observabilidad". `https://www.langchain.com/blog/runtime-behind-production-deep-agents`
- **Tools / Orchestration** — LangChain, *How and when to build multi-agent systems*: "un solo agente con las herramientas y el prompt adecuados consigue mucho de lo que la gente busca del multi-agente"; el multi-agente compensa cuando un agente tiene demasiadas herramientas y elige mal, cuando hace falta conocimiento especializado con mucho contexto, o cuando hay que imponer restricciones secuenciales; "en el centro del diseño multi-agente está la ingeniería de contexto: decidir qué ve cada agente". `https://www.langchain.com/blog/how-and-when-to-build-multi-agent-systems`
- **Memory** — LangChain, *How agents can use filesystems for context engineering*: escribir contexto = guardarlo fuera de la ventana (scratchpad/notas); Deep Agents usa un filesystem virtual para system prompts, skills y memoria de largo plazo. `https://blog.langchain.com/how-agents-can-use-filesystems-for-context-engineering/`
- **Guardrails** — LangChain, *Guardrails* (docs): se implementan como middleware con dos enfoques, reglas (regex/keywords: rápidas, baratas, se les escapan matices) o LLM/clasificadores (capturan lo sutil, más lentos y caros); moraleja real: en Chat LangChain un guardrail se quedó obsoleto tras un lanzamiento y bloqueó preguntas legítimas hasta que las trazas lo destaparon. `https://docs.langchain.com/oss/python/langchain/guardrails`
- **Evals + Observability** — LangChain, *AI Agent Observability*: "con los agentes, la lógica de tu app está documentada en las trazas, no en el código"; los agentes son no deterministas (la misma entrada dispara secuencias distintas); tres principios: instrumenta todo antes de optimizar nada, cierra el bucle de traza de producción a dataset de regresión, deja que las evaluaciones automáticas sustituyan a las decisiones por instinto; el eval solo funciona como bucle (ADLC): trazas → datasets → experimentos → decisiones de despliegue; las evaluaciones de producción también sirven de guardrail. `https://www.langchain.com/resources/agent-observability`
- **Human-in-the-loop** — LangChain: HITL se apoya en la ejecución durable (checkpointing que puede parar, reanudar y reintentar entre procesos); además los humanos calibran los jueces LLM revisando las muestras donde el juez discrepa. `https://www.langchain.com/blog/runtime-behind-production-deep-agents`

---

## Task 1: Repo profesional y seguro (scaffolding + git)

**Files:**
- Create: `README.md`
- Create: `LICENSE`
- Create: `.gitignore`
- (git) init + commit inicial en `/mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup`

**Interfaces:**
- Produces: un repo git limpio con `data/` ignorado y disclaimer de cifras; base sobre la que las tareas 2-8 harán commits atómicos.

- [ ] **Step 1: Confirmar (de nuevo, en el momento de ejecutar) que no hay valores de secretos**

Run:
```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup
grep -rnoE '(sk-[A-Za-z0-9]{20,}|pplx-[A-Za-z0-9]{20,}|-----BEGIN|AKIA[0-9A-Z]{16})' --include='*.html' --include='*.md' . || echo "SIN_SECRETOS"
```
Expected: `SIN_SECRETOS`. (Confirmado en el análisis previo: `~/.ssh`, `id_rsa`, `ANTHROPIC_API_KEY` y `127.0.0.1` aparecen solo como objetivos de demo / localhost, sin valores; los `$` son cifras del deck hermano, intencionales.)

- [ ] **Step 2: Crear `.gitignore`**

```gitignore
# Capturas de origen (WhatsApp): fondo negro, barras de estado; no profesionales para compartir.
# Se conservan en local pero fuera del repo. Ver README (sección "Origen de los diagramas").
data/

# Sistema operativo
.DS_Store
Thumbs.db
desktop.ini

# Editores
.vscode/
.idea/
*.swp
*~

# Temporales
*.log
*.tmp
```

- [ ] **Step 3: Crear `LICENSE` (CC BY 4.0)**

Contenido divulgativo de charla: CC BY 4.0 es la elección profesional (permite compartir/adaptar con atribución). Si el equipo prefiere licencia de software, sustituir por MIT.

Escribe la cabecera legible verbatim y, a continuación, pega el texto legal canónico de CC BY 4.0 obtenido con:
```bash
# Ejecutar durante la implementación para incrustar el texto legal completo:
# WebFetch https://creativecommons.org/licenses/by/4.0/legalcode.txt -> volcar íntegro en LICENSE bajo la cabecera.
```
Cabecera (verbatim) al inicio del fichero:
```
Creative Commons Attribution 4.0 International (CC BY 4.0)

Copyright (c) 2026 Manuel Cózar Baranguán

Esta obra (los decks "agentes-fundamentos" y "setup-claude-code-definitiva",
sus guiones y diagramas originales) se distribuye bajo licencia
Creative Commons Attribution 4.0 International.

Eres libre de compartir y adaptar el material, incluso con fines comerciales,
siempre que des el crédito adecuado. Texto legal completo a continuación.

--------------------------------------------------------------------------------
```

- [ ] **Step 4: Crear `README.md`**

```markdown
# CC-Setup — Cómo trabajo con Claude Code

Dos charlas hermanas sobre ingeniería de agentes de IA y un método de trabajo real con Claude Code.
Autocontenidas (HTML + CSS + JS inline, solo Google Fonts), tema claro/oscuro. Sin build ni dependencias.

## Los dos decks

| Deck | Fichero | Guion | Duración | Para quién |
|------|---------|-------|----------|------------|
| **1. Fundamentos** (el mapa) | [`agentes-fundamentos.html`](agentes-fundamentos.html) | [`agentes-fundamentos-guion.md`](agentes-fundamentos-guion.md) | ~22-25 min | Manager técnico |
| **2. Setup** (el territorio) | [`setup-claude-code-definitiva.html`](setup-claude-code-definitiva.html) | [`setup-claude-code-definitiva-guion.md`](setup-claude-code-definitiva-guion.md) | ~20 min | Devs |

El primero es el **mapa conceptual** (los 10 pilares de la ingeniería de agentes, el modelo mental de
Karpathy). El segundo es el **territorio**: mi setup real, con cifras de mi propia máquina.

## Cómo verlos

Abre cualquiera de los `.html` en el navegador (doble clic). No necesitan servidor.
Botón arriba a la derecha para alternar tema claro/oscuro.

## Sobre las cifras del deck de setup

El deck de setup muestra números reales de **mi** máquina en un momento dado (eventos de auditoría,
tokens comprimidos, ahorro en dólares). Son una **foto ilustrativa**, no una garantía ni un dato tuyo:
reprodúcelos con tus propios logs y comandos (el propio deck incluye la tabla "cifra -> fuente -> comando").
Las referencias a `~/.ssh`, `id_rsa` o `ANTHROPIC_API_KEY` aparecen solo como **objetivos de demostración**
(para enseñar que la puerta de seguridad los bloquea); el repo no contiene ninguna clave ni secreto real.

## Origen de los diagramas

Los diagramas son SVG/CSS originales, on-brand. Las capturas originales que sirvieron de referencia
(carpeta `data/`) quedan fuera del repo por `.gitignore` (son capturas de WhatsApp, no aptas para compartir).

## Fuentes y atribución

- Modelo mental "el LLM es la CPU, el contexto es la RAM": Andrej Karpathy.
- Framework de los 10 pilares: material divulgativo tipo SwirlAI, adaptado.
- Profundización por pilar: blog y documentación de LangChain (ver sección "Fuentes" dentro del deck de fundamentos).

## Licencia

[CC BY 4.0](LICENSE). Comparte y adapta con atribución.
```

- [ ] **Step 5: Inicializar git y primer commit**

Run:
```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup
git init
git add .gitignore README.md LICENSE agentes-fundamentos.html agentes-fundamentos-guion.md agentes-fundamentos-cambios.md setup-claude-code-definitiva.html setup-claude-code-definitiva-guion.md docs/
git status --short
```
Expected: `data/` NO aparece en el staging (ignorado); sí aparecen los `.html`, `.md`, `LICENSE`, `README.md`, `.gitignore`, `docs/`.

- [ ] **Step 6: Commit**

```bash
git commit -m "chore: scaffold shareable repo (README, CC BY 4.0, .gitignore) and init git

Prepara CC-Setup para compartir con compañeros: portada profesional, licencia
de contenido, exclusión de capturas de origen y disclaimer honesto de cifras.
Escaneo previo confirma que no hay valores de secretos, solo objetivos de demo.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```
Expected: commit creado. `git log --oneline -1` muestra el mensaje.

---

## Task 2: HTML — CSS de fuentes + beat de validación LangChain en sección 01

**Files:**
- Modify: `agentes-fundamentos.html` (bloque `<style>`: añadir reglas `.pillar-source` y `.sources`; sección `#cambio`: añadir párrafo de validación tras el modelo de Karpathy, ~línea 656-692)

**Interfaces:**
- Produces: clases `.pillar-source` (aside ámbar por pilar, usadas en tareas 3-5) y `.sources` (lista de la sección Fuentes, usada en tarea 6). No dependen de ninguna tarea previa salvo el token `--field` ya existente.

- [ ] **Step 1: Añadir CSS de `.pillar-source` y `.sources`**

Localiza el final del bloque de estilos de pilares (busca `.pillar-why`). Justo después de su regla, inserta:

```css
  /* ---------- fuente citada por pilar (BUILD 5 - enriquecimiento LangChain) ---------- */
  .pillar-source {
    margin-top: 1rem;
    padding: 0.85rem 1rem;
    border-left: 3px solid var(--field);
    background: color-mix(in srgb, var(--field-soft) 55%, var(--surface));
    border-radius: 0 6px 6px 0;
    font-size: 0.9rem;
    line-height: 1.55;
  }
  .pillar-source .src-label {
    display: block;
    font-family: var(--mono);
    font-size: 0.72rem;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: var(--field-ink);
    margin-bottom: 0.35rem;
  }
  .pillar-source cite { font-style: normal; color: var(--field-ink); font-weight: 600; }

  /* ---------- sección Fuentes / para profundizar ---------- */
  .sources { list-style: none; padding: 0; margin: 1.5rem 0 0; display: grid; gap: 0.9rem; }
  .sources li { padding-left: 1.1rem; border-left: 2px solid var(--border); }
  .sources .src-title { font-weight: 600; }
  .sources .src-note { color: var(--muted); font-size: 0.9rem; }
```

- [ ] **Step 2: Añadir el beat de validación en `#cambio`**

Tras el párrafo que explica el modelo de Karpathy (el que contiene "El <strong>LLM</strong> es la", ~línea 656), y antes de la subsección 1.2 (`<h3>...La escalera de la ingeniería</h3>`, ~línea 692), inserta un párrafo de prosa (clase `prose` como los vecinos; usa `<span class="field">` para el énfasis, no color hex):

```html
      <p class="prose">
        No es una imagen aislada. LangChain, una de las plataformas de referencia para construir agentes,
        usa <span class="field">exactamente la misma analogía</span>: el LLM como CPU y la ventana de
        contexto como RAM. Y ha puesto nombre a la disciplina que sale de ahí, la
        <span class="field">ingeniería de contexto</span>, que define como "la habilidad más importante
        que un ingeniero de IA puede desarrollar". Cuando dos fuentes independientes llegan al mismo mapa,
        no es moda: es que el mapa describe el terreno.
      </p>
```

- [ ] **Step 3: Verificar render y estilo**

Run:
```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup
grep -c 'pillar-source' agentes-fundamentos.html   # espera >=1 (la regla CSS)
grep -c 'ingeniería de contexto' agentes-fundamentos.html  # espera >=1
grep -n '—' agentes-fundamentos.html | grep -v 'kd-\|desc' | head  # espera vacío (sin em-dash nuevos)
```
Abre `agentes-fundamentos.html` en el navegador, tema claro y oscuro: sección "El cambio" muestra el párrafo nuevo sin romper el flujo; 0 errores en consola.
Expected: el `grep '—'` no devuelve líneas nuevas de prosa; render correcto en ambos temas.

- [ ] **Step 4: Commit**

```bash
git add agentes-fundamentos.html
git commit -m "feat(deck): add source-callout CSS and LangChain validation beat in section 01

LangChain converge con Karpathy (CPU/RAM) y acuña 'context engineering': refuerza
la tesis del deck con una fuente independiente de máxima calidad.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: HTML — asides de fuente en pilares 01-03 (El motor)

**Files:**
- Modify: `agentes-fundamentos.html` (dentro de cada `article.pillar` de los pilares 01, 02, 03: insertar un `<aside class="pillar-source">` justo tras el cierre de `<p class="pillar-why">...</p>` y antes de `</article>`)

**Interfaces:**
- Consumes: la clase `.pillar-source` definida en Task 2.
- Produces: 3 asides atribuidos. Patrón de inserción idéntico reutilizado por Tasks 4-5.

**Patrón de inserción (uniforme para los 10 pilares):** localizar el `article` por su `aria-labelledby="pN-term"`, encontrar su `<p class="pillar-why">`, e insertar el aside inmediatamente después de esa `</p>`.

- [ ] **Step 1: Pilar 01 (Harness) — insertar tras su `pillar-why`**

```html
        <aside class="pillar-source">
          <span class="src-label">LangChain · lo que dice la fuente</span>
          LangChain separa dos capas que aquí conviene distinguir: el <cite>harness</cite> es
          "el sistema que construyes alrededor del modelo para que tenga éxito en su dominio"
          (prompts, herramientas, skills), y el <cite>runtime</cite> es todo lo de debajo:
          ejecución durable, memoria, observabilidad. Este pilar es el harness; el runtime asoma
          en los pilares de confianza.
        </aside>
```

- [ ] **Step 2: Pilar 02 (Loop) — insertar tras su `pillar-why`**

```html
        <aside class="pillar-source">
          <span class="src-label">LangChain · The Art of Loop Engineering</span>
          Su tesis es la misma que la nuestra: "el potencial de los agentes está en los bucles
          que construyes a su alrededor". Y describen no uno sino cuatro bucles apilados: el del
          agente, el de verificación, el disparado por eventos y el de mejora ("hill climbing").
          Lo resumen bien: los tres primeros automatizan el trabajo; el cuarto automatiza la mejora.
        </aside>
```

- [ ] **Step 3: Pilar 03 (Context) — insertar tras su `pillar-why`**

```html
        <aside class="pillar-source">
          <span class="src-label">LangChain · Context Engineering</span>
          Lo definen como "el arte y la ciencia de llenar la ventana de contexto con la información
          justa en cada paso". Y lo aterrizan en cuatro estrategias concretas: escribir (guardar fuera
          de la ventana), seleccionar, comprimir y aislar. Dato de ingeniería real: en su harness Deep
          Agents, un resultado de herramienta que supera los 20.000 tokens se descarga a fichero y se
          sustituye por una ruta más un preview, en vez de envenenar la ventana.
        </aside>
```

- [ ] **Step 4: Verificar**

Run:
```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup
grep -c 'class="pillar-source"' agentes-fundamentos.html   # espera 3
grep -n '—' agentes-fundamentos.html | grep -iv 'kd-\|<desc' | head  # espera vacío
```
Navegador (ambos temas): los pilares 01-03 muestran su aside ámbar, borde izquierdo `--field`, legible; el borde no compite con los diagramas.
Expected: 3 asides; contraste AA del texto del aside sobre `--field-soft` (ya verificado en el sistema: ink 5.56:1 claro / 9.0:1 oscuro).

- [ ] **Step 5: Commit**

```bash
git add agentes-fundamentos.html
git commit -m "feat(deck): cite LangChain sources on engine pillars (harness, loop, context)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: HTML — asides de fuente en pilares 04-06 (Las capacidades)

**Files:**
- Modify: `agentes-fundamentos.html` (pilares 04, 05, 06; mismo patrón que Task 3)

**Interfaces:**
- Consumes: `.pillar-source` (Task 2), patrón de inserción (Task 3).

- [ ] **Step 1: Pilar 04 (Tools) — insertar tras su `pillar-why`**

```html
        <aside class="pillar-source">
          <span class="src-label">LangChain · multi-agente, cuándo y cómo</span>
          Confirman la lección contraintuitiva: "un solo agente con las herramientas y el prompt
          adecuados consigue mucho de lo que la gente busca del multi-agente". Y avisan del fallo
          típico: cuando un agente tiene demasiadas herramientas, elige mal cuál usar. Pocas y buenas
          no es una preferencia estética, es lo que hace que el agente acierte.
        </aside>
```

- [ ] **Step 2: Pilar 05 (Memory) — insertar tras su `pillar-why`**

```html
        <aside class="pillar-source">
          <span class="src-label">LangChain · filesystems para contexto</span>
          Su técnica de memoria coincide con la idea de "escribir contexto": guardar fuera de la
          ventana lo que no cabe. En Deep Agents, un filesystem virtual almacena los system prompts,
          las skills y la memoria de largo plazo, y el agente lo consulta bajo demanda con búsquedas,
          en vez de arrastrar todo el historial en cada paso.
        </aside>
```

- [ ] **Step 3: Pilar 06 (Orchestration) — insertar tras su `pillar-why`**

```html
        <aside class="pillar-source">
          <span class="src-label">LangChain · multi-agente, cuándo y cómo</span>
          Su regla es la misma que enseño: no recurras al multi-agente por defecto. Compensa en tres
          casos concretos: cuando un agente tiene demasiadas herramientas, cuando hace falta
          conocimiento especializado con mucho contexto, o cuando hay que imponer un orden
          (desbloquear pasos solo tras cumplir condiciones). Y rematan con lo importante: "en el centro
          del diseño multi-agente está la ingeniería de contexto, decidir qué ve cada agente".
        </aside>
```

- [ ] **Step 4: Verificar**

Run:
```bash
grep -c 'class="pillar-source"' agentes-fundamentos.html   # espera 6
```
Navegador: pilares 04-06 con su aside; sin desbordes ni em-dash nuevos.

- [ ] **Step 5: Commit**

```bash
git add agentes-fundamentos.html
git commit -m "feat(deck): cite LangChain sources on capability pillars (tools, memory, orchestration)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: HTML — asides de fuente en pilares 07-10 (La confianza)

**Files:**
- Modify: `agentes-fundamentos.html` (pilares 07, 08, 09, 10; mismo patrón)

**Interfaces:**
- Consumes: `.pillar-source` (Task 2), patrón (Task 3).

- [ ] **Step 1: Pilar 07 (Guardrails) — insertar tras su `pillar-why`**

```html
        <aside class="pillar-source">
          <span class="src-label">LangChain · Guardrails</span>
          Los implementan como middleware con dos sabores: reglas (regex, palabras clave: rápidas,
          baratas, se les escapan matices) y clasificadores LLM (cazan lo sutil, más lentos y caros).
          Y cuentan una moraleja real: en su asistente Chat LangChain, un guardrail se quedó obsoleto
          tras un lanzamiento y empezó a bloquear preguntas legítimas, hasta que las trazas lo
          destaparon. Las barreras también se mantienen.
        </aside>
```

- [ ] **Step 2: Pilar 08 (Evals) — insertar tras su `pillar-why`**

```html
        <aside class="pillar-source">
          <span class="src-label">LangChain · Agent Observability</span>
          Lo dicen mejor que nadie: "con los agentes, la lógica de tu app está documentada en las
          trazas, no en el código". Por eso el eval solo funciona como bucle: trazas de producción se
          vuelven datasets, los datasets se vuelven experimentos, y los experimentos se vuelven
          decisiones de despliegue. Evaluar en dos momentos: antes de desplegar (comparar versiones) y
          después (puntuar trazas reales y realimentar).
        </aside>
```

- [ ] **Step 3: Pilar 09 (Human-in-the-loop) — insertar tras su `pillar-why`**

```html
        <aside class="pillar-source">
          <span class="src-label">LangChain · runtime de producción</span>
          Un matiz de ingeniería que suele olvidarse: la puerta de aprobación humana se apoya en la
          ejecución durable, un checkpointing que permite parar, reanudar y reintentar entre procesos.
          Sin esa base, "pausar para que apruebe un humano" no es fiable. Y hay un segundo papel del
          humano: calibrar al juez, revisando las muestras donde el eval automático discrepa.
        </aside>
```

- [ ] **Step 4: Pilar 10 (Observability) — insertar tras su `pillar-why`**

```html
        <aside class="pillar-source">
          <span class="src-label">LangChain · Agent Observability</span>
          Su guía cabe en tres principios: instrumenta todo antes de optimizar nada; cierra el bucle
          de la traza de producción al dataset de regresión; y deja que las evaluaciones automáticas
          sustituyan a las decisiones por instinto. Detalle que cierra el círculo con el pilar 07: las
          evaluaciones de producción también hacen de guardrail, atrapando respuestas que violan una
          política antes de que lleguen al usuario.
        </aside>
```

- [ ] **Step 5: Verificar**

Run:
```bash
grep -c 'class="pillar-source"' agentes-fundamentos.html   # espera 10 (los 10 pilares)
```
Navegador (ambos temas): los 10 pilares tienen aside; ninguno rompe el grid; 0 errores en consola; `prefers-reduced-motion` y print siguen mostrando todo.
Expected: exactamente 10 asides.

- [ ] **Step 6: Commit**

```bash
git add agentes-fundamentos.html
git commit -m "feat(deck): cite LangChain sources on trust pillars (guardrails, evals, HITL, observability)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: HTML — sección "Fuentes / para profundizar" + footer

**Files:**
- Modify: `agentes-fundamentos.html` (añadir `<section id="fuentes">` tras el puente `#puente` y antes del `<footer>`, ~línea 1502; ampliar `.footer-attr`, líneas 1508-1510)

**Interfaces:**
- Consumes: `.sources` (Task 2).

- [ ] **Step 1: Insertar la sección Fuentes antes del footer**

Localiza `<footer class="site-footer">` (~línea 1502). Inmediatamente antes, inserta:

```html
  <section id="fuentes" class="wrap" aria-label="Fuentes y para profundizar">
    <header class="sec-head" data-reveal>
      <p class="sec-kicker">Para profundizar</p>
      <h2>De dónde sale este mapa</h2>
    </header>
    <p class="sec-lead" data-reveal>
      Nada de esto es opinión mía. El mapa combina un modelo mental y un cuerpo de ingeniería que
      puedes leer en la fuente. Estas son las de <span class="field">máxima calidad</span>.
    </p>
    <ul class="sources" data-reveal>
      <li>
        <span class="src-title">Andrej Karpathy — el modelo mental</span><br>
        <span class="src-note">El LLM como CPU y el contexto como RAM: el marco con el que arranca este deck.</span>
      </li>
      <li>
        <span class="src-title">LangChain — The Art of Loop Engineering</span><br>
        <span class="src-note">Los cuatro bucles apilados; "el potencial está en los bucles que construyes alrededor". langchain.com/blog/the-art-of-loop-engineering</span>
      </li>
      <li>
        <span class="src-title">LangChain — Context Engineering</span><br>
        <span class="src-note">Llenar la ventana con la información justa; escribir, seleccionar, comprimir, aislar. blog.langchain.com/context-engineering-for-agents</span>
      </li>
      <li>
        <span class="src-title">LangChain — How and when to build multi-agent systems</span><br>
        <span class="src-note">Herramientas y orquestación: pocas y buenas, y multi-agente solo cuando compensa. langchain.com/blog/how-and-when-to-build-multi-agent-systems</span>
      </li>
      <li>
        <span class="src-title">LangChain — The Runtime Behind Production Deep Agents</span><br>
        <span class="src-note">Harness frente a runtime, ejecución durable y el humano en el bucle. langchain.com/blog/runtime-behind-production-deep-agents</span>
      </li>
      <li>
        <span class="src-title">LangChain — AI Agent Observability & Evals</span><br>
        <span class="src-note">"La lógica de tu app está en las trazas, no en el código"; el eval como bucle. langchain.com/resources/agent-observability</span>
      </li>
      <li>
        <span class="src-title">SwirlAI — los 10 pilares</span><br>
        <span class="src-note">Material divulgativo que da la estructura de los diez pilares aquí adaptados.</span>
      </li>
    </ul>
  </section>
```

- [ ] **Step 2: Ampliar la atribución del footer**

Localiza `.footer-attr` (~líneas 1508-1510). Reemplaza su contenido para añadir LangChain a la atribución existente (mantén el patrón, sin em-dash):

Old (verbatim actual):
```html
        Framework de los 10 pilares de ingeniería de agentes, adaptado de material divulgativo (SwirlAI); modelo mental
        «el LLM es la CPU / el contexto es la RAM» de Andrej Karpathy.
```
New:
```html
        Framework de los 10 pilares de ingeniería de agentes, adaptado de material divulgativo (SwirlAI); modelo mental
        «el LLM es la CPU / el contexto es la RAM» de Andrej Karpathy; profundización por pilar citada del blog y la
        documentación de LangChain (ver «Para profundizar»).
```

- [ ] **Step 3: Verificar**

Run:
```bash
grep -c 'id="fuentes"' agentes-fundamentos.html      # espera 1
grep -c 'class="sources"' agentes-fundamentos.html    # espera 1
grep -c 'LangChain' agentes-fundamentos.html          # espera >=10 (asides + fuentes + footer)
```
Navegador: la sección "Para profundizar" aparece antes del footer, con la lista legible en ambos temas; el reveal-on-scroll la anima; el footer cita LangChain.

- [ ] **Step 4: Commit**

```bash
git add agentes-fundamentos.html
git commit -m "feat(deck): add 'Para profundizar' sources section and extend footer attribution

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Guion — ampliar +~10 min con profundidad citada + anexo de fuentes

**Files:**
- Modify: `agentes-fundamentos-guion.md` (cabecera de duración; añadir un párrafo hablado citado por bloque 0-4; nuevo Anexo C "Fuentes y lecturas")

**Interfaces:**
- Consumes: el banco de citas de este plan (sección "Material de fuentes").
- Produces: guion de ~22-25 min, mapeado a los asides del HTML.

**Restricción de tiempo:** el total sube de 2.385 a como mucho ~3.800 palabras de fichero. La prosa hablada nueva no debe superar ~1.400 palabras.

- [ ] **Step 1: Actualizar la cabecera de duración**

Old (línea 3):
```markdown
**Duración objetivo:** 12-15 minutos (calentamiento; el deck de setup dura 20) · **Registro:** técnico, directo, de tú a tú · **Público:** tu jefe, un manager técnico
```
New:
```markdown
**Duración objetivo:** 22-25 minutos (calentamiento; el deck de setup dura 20) · **Registro:** técnico, directo, de tú a tú · **Público:** tu jefe, un manager técnico
```

- [ ] **Step 2: Bloque 0 — añadir párrafo de validación (tras el guion hablado existente, antes de la frase-gancho)**

Inserta como tercer párrafo del guion hablado del Bloque 0:
```markdown
> Y que no te suene a teoría mía: este mismo mapa lo usan las plataformas serias de agentes. LangChain, por ejemplo, describe al modelo con la misma imagen de Karpathy, CPU y RAM, y llama a lo que hay debajo del prompt "ingeniería de contexto", que definen como la habilidad más importante que puede desarrollar un ingeniero de IA. Cuando dos sitios que no se copian llegan al mismo dibujo, es que el dibujo describe algo real.
```

- [ ] **Step 3: Bloque 1 (El motor) — añadir párrafo citado al final del guion hablado**

```markdown
> Y esto no me lo invento: LangChain, que construye agentes de producción, publica un artículo entero sobre "loop engineering", ingeniería del bucle, con la misma tesis que te acabo de dar: el potencial de un agente está en los bucles que construyes a su alrededor, no en el modelo. Van más lejos incluso: describen cuatro bucles apilados, el del agente, el de verificación, el que disparan los eventos y el de mejora, y lo resumen así, los tres primeros automatizan el trabajo y el cuarto automatiza la mejora. Sobre el contexto, la misma gente lo define como llenar la ventana con la información justa en cada paso, con cuatro jugadas: escribir fuera de la ventana, seleccionar, comprimir y aislar.
```

- [ ] **Step 4: Bloque 2 (Las capacidades) — añadir párrafo citado**

```markdown
> Y aquí LangChain te da la regla en una frase: un solo agente con las herramientas y el prompt adecuados consigue casi todo lo que la gente cree que necesita del multi-agente. El fallo típico que documentan es justo ese, un agente con demasiadas herramientas que elige mal cuál usar. Por eso, pocas y buenas no es estética, es lo que hace que acierte. Y cuando de verdad montas varios agentes, dicen que en el centro del diseño está la ingeniería de contexto: decidir qué ve cada uno. Sobre la memoria, su técnica es la misma que te conté: lo que no cabe en la ventana se guarda en un fichero y el agente lo consulta bajo demanda.
```

- [ ] **Step 5: Bloque 3 (La confianza) — añadir párrafo citado**

```markdown
> Estas cuatro capas también son las que LangChain trata como infraestructura de producción, no como extras. De los guardrails dicen algo que a ti te va a gustar: son middleware, y los hacen de dos formas, con reglas fijas rápidas y baratas, o con un clasificador LLM que caza lo sutil pero cuesta más. Y cuentan un fallo real, un guardrail suyo se quedó obsoleto tras un lanzamiento y bloqueó preguntas legítimas hasta que las trazas lo destaparon. De los evals y la observabilidad tienen la mejor frase de todo esto: con los agentes, la lógica de tu aplicación está en las trazas, no en el código. Por eso evaluar es un bucle, las trazas de producción se vuelven casos de prueba, y los casos deciden si despliegas. Y el humano en el bucle se apoya en algo técnico, la ejecución durable, poder parar, reanudar y reintentar sin perder el hilo.
```

- [ ] **Step 6: Añadir Anexo C tras el Anexo B (al final del fichero)**

```markdown
---

# Anexo C · Fuentes y lecturas (si te las piden)

Todo el mapa es verificable en la fuente. Las de más calidad:

- **Andrej Karpathy** — el modelo mental "LLM = CPU, contexto = RAM".
- **LangChain, The Art of Loop Engineering** — los cuatro bucles apilados; "el potencial está en los bucles que construyes alrededor". `langchain.com/blog/the-art-of-loop-engineering`
- **LangChain, Context Engineering** — llenar la ventana con lo justo; escribir, seleccionar, comprimir, aislar. `blog.langchain.com/context-engineering-for-agents`
- **LangChain, How and when to build multi-agent systems** — herramientas y orquestación; multi-agente solo cuando compensa. `langchain.com/blog/how-and-when-to-build-multi-agent-systems`
- **LangChain, The Runtime Behind Production Deep Agents** — harness frente a runtime; el humano en el bucle sobre ejecución durable. `langchain.com/blog/runtime-behind-production-deep-agents`
- **LangChain, AI Agent Observability & Evals** — "la lógica está en las trazas, no en el código"; el eval como bucle. `langchain.com/resources/agent-observability`
- **SwirlAI** — el framework de los 10 pilares aquí adaptado.
```

- [ ] **Step 7: Verificar presupuesto de tiempo**

Run:
```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup
wc -w agentes-fundamentos-guion.md   # base 2385; espera <= ~3800
grep -c '—' agentes-fundamentos-guion.md  # solo en-dash de cabeceras de tiempo, sin em-dash nuevos en prosa
```
Expected: total ≤ ~3.800 palabras (los ~1.400 añadidos ≈ 10 min a ~140 wpm). Revisa a ojo que la prosa nueva no mete em-dash.

- [ ] **Step 8: Commit**

```bash
git add agentes-fundamentos-guion.md
git commit -m "docs(guion): extend talk by ~10 min with cited LangChain depth and sources annex

Duración 12-15 -> 22-25 min. Un párrafo citado por bloque + Anexo C de fuentes,
mapeado 1:1 con los asides del HTML.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Change report + verificación global

**Files:**
- Modify: `agentes-fundamentos-cambios.md` (añadir entrada BUILD 5)

**Interfaces:**
- Consumes: el estado final de Tasks 1-7.

- [ ] **Step 1: Añadir entrada de change report**

Al final de `agentes-fundamentos-cambios.md`, antes de "Fuera de scope" (o como sección nueva), añade:

```markdown
## BUILD 5 — Enriquecimiento con fuentes LangChain + blindaje del repo (24 jul 2026)

Encargo: profundizar el deck con fuentes de máxima calidad (LangChain) sumando <=10 min de guion, y
dejar el repo listo para compartir de forma profesional y segura.

| Cambio | Qué | Cómo verificado |
|--------|-----|-----------------|
| Beat de validación (01) | LangChain converge con Karpathy y acuña "context engineering" | Render ambos temas; párrafo en `#cambio` |
| 10 asides de fuente | Un `.pillar-source` atribuido por pilar (harness/runtime, loop, context, tools, memory, orchestration, guardrails, evals, HITL, observability) | `grep -c 'class="pillar-source"'` = 10; AA sobre `--field-soft` |
| Sección "Para profundizar" | `#fuentes` con 7 fuentes + footer ampliado | `grep id="fuentes"` = 1; render ambos temas |
| Guion +~10 min | Párrafo citado por bloque + Anexo C; cabecera 22-25 min | `wc -w` <= ~3800; sin em-dash nuevos |
| Repo | README + LICENSE (CC BY 4.0) + .gitignore + git init | `data/` ignorado; escaneo sin secretos; commits atómicos |

Decisiones: acento `--field` respetado (asides ámbar); cero cifras inventadas (citas atribuidas, sin
números); em-dash cero en prosa; hermano de setup intacto; `data/` fuera del repo por no profesional.
```

- [ ] **Step 2: Verificación global de contenido**

Run:
```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup
echo "asides:"; grep -c 'class="pillar-source"' agentes-fundamentos.html      # 10
echo "fuentes:"; grep -c 'id="fuentes"' agentes-fundamentos.html              # 1
echo "em-dash prosa HTML:"; grep -n '—' agentes-fundamentos.html | grep -iv 'kd-\|<desc\|<title' | wc -l   # 0
echo "palabras guion:"; wc -w agentes-fundamentos-guion.md                    # <= ~3800
echo "repo limpio de secretos:"; grep -rnoE '(sk-[A-Za-z0-9]{20,}|-----BEGIN|AKIA[0-9A-Z]{16})' --include='*.html' --include='*.md' . || echo OK
```
Expected: 10 / 1 / 0 / ≤3800 / OK.

- [ ] **Step 3: Render final en navegador (checkpoint humano)**

Abre `agentes-fundamentos.html` en claro y oscuro. Recorre: hero → cambio (con beat) → los 3 bloques de pilares (cada uno con su aside) → puente → "Para profundizar" → footer. Confirma: 0 errores de consola, sin desbordes, reveal-on-scroll funciona, tema alterna sin FOUC.

- [ ] **Step 4: Commit final**

```bash
git add agentes-fundamentos-cambios.md
git commit -m "docs: log BUILD 5 (LangChain enrichment + repo hardening) in change report

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 5: (Opcional) Preparar para push**

Si tienes ya un remoto para este repo:
```bash
git remote add origin <URL-de-tu-repo>
git log --oneline           # revisa los commits atómicos antes de subir
# git push -u origin main   # ejecútalo tú tras revisar (no lo hago sin tu confirmación)
```

---

## Self-Review

**1. Cobertura del encargo:**
- "Mejora el HTML y el MD de agentes fundamentos con fuentes de máxima calidad (LangChain loop engineering)" → Tasks 2-7 (beat + 10 asides + sección Fuentes + guion), banco de citas verificado incluyendo el artículo pedido.
- "Máximo 10 minutos extra" → Global Constraint + Task 7 Step 7 (presupuesto ≤1.400 palabras / ~10 min, header 22-25 min).
- "Busca en LangChain más info sobre el resto de temas" → investigación ya hecha (context, multi-agente, tools, memory, guardrails, evals, observability, HITL, harness/runtime); banco de citas cubre los 10 pilares.
- "Revisa setup-claude-code-definitiva para tener el repo listo para compartir seguro y profesional" → Task 1 (README/LICENSE/.gitignore/git) + escaneo de secretos (limpio) + disclaimer de cifras en README.
- "Ya tengo una versión en git para compartirlo con compañeros" → Task 1 git init + Task 8 Step 5 push opcional bajo confirmación.

**2. Placeholders:** ninguno. Cada aside y párrafo lleva su copy final en español; cada paso, su comando y salida esperada. Único fetch en ejecución: el texto legal canónico de CC BY 4.0 (Task 1 Step 3), con URL exacta.

**3. Consistencia de tipos/nombres:** `.pillar-source` y `.sources` se definen en Task 2 y se consumen con el mismo nombre en Tasks 3-6; `#fuentes` definido en Task 6 y verificado en Task 8; tokens `--field*` usados verbatim de los existentes; el patrón de inserción (tras `pillar-why`) es idéntico en las 10 inserciones.
