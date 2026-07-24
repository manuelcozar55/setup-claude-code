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

## Cómo se construyó

Este repo es también un ejemplo del método: el plan de implementación seguido para enriquecer y
preparar los decks vive en [`docs/superpowers/plans/`](docs/superpowers/plans/). Documenta las
decisiones de diseño, el presupuesto de tiempo y las fuentes citadas.

## Licencia

[CC BY 4.0](LICENSE). Comparte y adapta con atribución.
