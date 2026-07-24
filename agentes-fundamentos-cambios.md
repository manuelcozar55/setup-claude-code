# Change report — agentes-fundamentos (deck de conceptos, previo al de setup)

Generado: 23 jul 2026 · Ubicación: `Downloads/CC-Setup/`
Encargo: a partir de las 10 diapositivas de `data/`, un HTML + guion que expliquen a un jefe (manager técnico) los
conceptos de ingeniería de agentes y el modelo mental de Karpathy, como charla PREVIA a enseñar el setup real.
Diseño: `taste-skill` + `emil-design-eng`, hermano coherente de `setup-claude-code-definitiva.html`, mismo tono tú-a-tú.
Método: brainstorming (gate de diseño, aprobado por el usuario) → ejecución dirigida por subagentes (implementación →
revisión spec/calidad por build → checkpoint de render en navegador) → revisión global final. Todas Approved, 0 Critical/Important.

## Qué son las imágenes de `data/`
10 diapositivas de un framework de "los 10 pilares de la ingeniería de agentes" (estilo SwirlAI, con el modelo mental
de Karpathy). Se **recrearon** como diagramas SVG/CSS on-brand (claro+oscuro) en vez de incrustar las capturas de
WhatsApp (barras de estado, fondo negro) que romperían el diseño.

## Artefacto 1 — `agentes-fundamentos.html` (creado, 1558 líneas)
HTML autocontenido (CSS+JS inline, solo Google Fonts), tema claro+oscuro, hermano del deck de setup.

| Build | Qué | Cómo verificado |
|---|-----|-----------------|
| 1 | Fundación: sistema de diseño heredado del hermano + acento nuevo `--field` (ámbar); hero «El prompt ya no es el trabajo»; sección 01 «El cambio» (Karpathy: LLM=CPU, contexto=RAM; escalera prompt→context→harness→loop) | Navegador ambos temas, 0 errores; AA `--field` medido 4,95-5,57 claro / ≥8 oscuro |
| 2 | 02 El motor (PILAR 01 Harness · 02 Loop · 03 Context) y 03 Las capacidades (04 Tools · 05 Memory · 06 Orchestration), cada pilar con diagrama distinto + "por qué le importa" | Render ambos temas; 6 diagramas SVG distintos; sin hex ni em-dash; acento solo `--field` |
| 3 | 04 La confianza (07 Guardrails · 08 Evals · 09 Human-in-the-loop · 10 Observability) + puente que mapea los 10 pilares a superpowers/Sentinel/Headroom + footer | Puente cubre los 10 pilares (unión {01..10}); AA acentos del setup 4,84-6,47 claro; atribución honesta |
| 4 | Reveal-on-scroll (24 bloques + IntersectionObserver protegido), pase a11y + rendimiento | Scroll suave revela los 24; hero visible al cargar; reduced-motion/print/JS-off muestran todo; no-throw; 0 errores |

**Decisiones de diseño (aprobadas):**
- **Hermano coherente**: mismas fuentes (Newsreader/IBM Plex/JetBrains), tokens claro+oscuro, toggle anti-FOUC. Acento
  propio **ámbar** (`--field`) para "el campo/los fundamentos"; los 3 colores del setup (violeta/verde/azul) aparecen
  SOLO en el puente (#puente) como gancho visual al segundo deck.
- **Audiencia manager**: cada pilar aterriza su "por qué le importa" (riesgo/coste/producto) en prosa.
- **Puente explícito ligero**: mapea los 10 pilares a superpowers (bucle/orquestación/humano), Sentinel (barreras),
  Headroom (contexto), verificación+logs (evals/observabilidad) y el entorno (harness/tools/memoria), y entrega al setup.
- **Honestidad**: framework atribuido en el footer (material divulgativo tipo SwirlAI + modelo mental de Karpathy);
  **cero cifras inventadas** (deck conceptual); los números reales se difieren al deck de setup.

## Artefacto 2 — `agentes-fundamentos-guion.md` (creado, ~120 líneas / ~14 min)
Guion hablado tú-a-tú, mapeado 1:1 a las 5 secciones y los 10 pilares. Por bloque: objetivo, guion hablado, frase-gancho
y qué señalar en pantalla. Cada pilar con su encuadre de negocio. Anexos: Q&A honesto (¿no basta un buen prompt?, ¿no es
sobre-ingeniería?, ¿cuánto cuesta?) y chuleta de una línea por pilar. Cierre que entrega al deck de setup («esto es el
mapa; ahora te enseño el territorio, con las cifras reales»). 0 em-dash, sin cifras inventadas.

## Fuera de scope / notas
- No se modificaron `setup-claude-code-definitiva.html` ni su guion (el hermano queda intacto).
- Minors cosméticos aceptados (hero de 5 bloques como el hermano; toggle antes que el reveal en el mismo IIFE, riesgo
  teórico y desmentido; en-dash solo en cabeceras de tiempo del guion, igual que el guion de setup). Ninguno bloquea.
- Las capturas originales siguen en `data/` por si quieres conservarlas o enlazarlas.
