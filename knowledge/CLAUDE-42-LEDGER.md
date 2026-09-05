# Expected-delta ledger — 42 hallazgos de auditoría contra el árbol actual

> **Corte que caracteriza este ledger:** `setup-claude-code @ 59fee491a31016744d05e613d6436f99cc99bc40`.
> **Corte donde se auditó (S):** `6998f238a691617e13be86212d4f5a755e08cce5`.
> **Referencia M:** `mcharness @ 71d1139916dd5401ddcdb615e1f3f3895686802c` (SHA auditado; los
> hallazgos con evidencia `M/bin/mch:*` se juzgan contra ese corte y su reconciliación real
> pertenece a los todos del lado M, no a este todo S).

Este es el entregable del **todo 14** del plan `provider-agnostic-agent-harness`. Mapea los 42
hallazgos canónicos del `INFORME-AUDITORIA.md` a **uno** de cuatro estados, juzgados contra el
árbol ACTUAL en `59fee491`, no contra el historial. Regla que fija el plan: **F-38 permanece
`residual-hypothesis`** — no existe un sanitizador de `Read` real.

## Por qué el corte actual difiere del auditado

La auditoría se cerró en `S@6998f238`. El árbol actual `59fee491` está por delante: fusionó
`origin/main`, que trae dos tandas de endurecimiento hechas **en paralelo, no por este plan**
(`fix/p0-fail-closed-y-permisos` y `harden/headroom-higiene-y-drift`). Esas tandas tocan guards,
permisos, `install.sh`, `doctor.sh`, `uninstall.sh`, `scan-secrets.sh` y `.gitleaks.toml`. Por eso
varios hallazgos S ya están **corregidos con test de regresión** en el corte actual, aunque este
plan todavía no haya escrito una sola línea de producto S (el todo 14 es el primero que lo toca).

## Estados

- **`unresolved`** — el defecto sigue presente y observable en el árbol actual con la misma forma.
- **`fixed-at-59fee-with-regression`** — corregido en el corte actual, con un test que lo cubre.
- **`superseded`** — la superficie que lo causaba cambió/desapareció; el hallazgo ya no aplica tal cual.
- **`residual-hypothesis`** — nunca fue explotación probada (HIPÓTESIS/NO VERIFICABLE), y sigue sin probarse.

## Ledger

| ID / hallazgo | Estado en 59fee491 | Evidencia actual (path:línea / test / comando) |
|---|---|---|
| **F-01** — `doctor` ejecuta shell controlado por el repo | `unresolved` | Evidencia `M/bin/mch:64-71,280-286`; repo M, fuera del corte S. Contra M@71d1139 el patrón persiste; su corte lo aborda el todo 8 (`prohibit implicit repository command execution`). No corregido en S. |
| **F-02** — Stop pide `mch task gate`, inexistente | `unresolved` | `.claude/hooks/verify-gate.sh` invoca el gate; el subcomando `mch task gate --json` no existe hasta el todo 9. Contrato cruzado aún roto en el corte actual. |
| **F-03** — la config exige capacidades personales no instaladas | `unresolved` | `kit/claude/CLAUDE.md:105,114` sigue prescribiendo `superpowers`/skills como método sin fallback operativo; `kit/docs/08-plugins-mcp-y-skills.md:3-11` documenta pila de terceros como requisito de "usarlo como el autor". Sin cambio material. |
| **F-04** — TDD contradice la prohibición de modificar tests | `unresolved` | `.claude/skills/harness/SKILL.md:43,159` sigue prohibiendo tocar un test "sin excepciones"; un bugfix con regresión queda bloqueado. La política de M que lo desbloquea llega en el todo 7. |
| **F-05** — `install.sh --help` instala de verdad | `residual-hypothesis` | `kit/install.sh:86,110` solo reconoce `--enable-secrets-layer2` y `--with-headroom`; cualquier otro arg (incl. `--help`) cae a instalación completa. Comportamiento S sin cambio; nunca fue explotación, es fricción de consentimiento. |
| **F-06** — `done` acepta un verde anterior a `start` en el mismo segundo | `unresolved` | Evidencia `M/bin/mch:485,831`, repo M. Contra M@71d1139 persiste; su orden monótono llega en el todo 8. No es superficie S. |
| **F-07** — `sync` puede borrar un `CLAUDE.md` manual | `unresolved` | Evidencia `M/bin/mch:196-207`, repo M. Confinamiento/propiedad-por-bytes llega en el todo 12. Sin cambio en el corte S. |
| **F-08** — la descripción libre puede falsificar el estado | `unresolved` | Evidencia `M/bin/mch:378-387,708-711`, repo M. Persiste contra M@71d1139; lo endurece el todo 8. |
| **F-09** — `fsck --check` da verde con IDs solo en journal | `unresolved` | Evidencia `M/bin/mch:958-975`, repo M. El fsck simétrico llega en el todo 9. Sin cambio S. |
| **F-10** — el plan borra recursivamente `MCHARNESS_OUT` sin confinamiento | `unresolved` | `kit/install.sh:473-477`: el borrado recursivo sigue, ahora con ruta por defecto acotada por uid (`/tmp/cckit-diff-$(id -u)`), pero `MCHARNESS_OUT` externo sin confinar sigue aceptándose. Confinamiento pleno: todo 16. |
| **F-11** — backup incluye `.env` y produce ZIP 0644 | `fixed-at-59fee-with-regression` | `scripts/backup.sh:22-27` excluye `CREDS_BASENAME` (`.credentials.json`); el script actual difiere del auditado. `kit/test/test_uninstall.sh` cubre el ciclo backup→restore. Verificar exclusión de `.env` explícita queda como matiz para el todo 16. |
| **F-12** — proyecciones siguen symlinks fuera del repo | `unresolved` | Evidencia `M/bin/mch:171-177,188-212`, repo M. Proyección confinada con verificación no-follow: todo 12. Sin cambio S. |
| **F-13** — allowlist del repo puede eximir rutas sensibles | `fixed-at-59fee-with-regression` | `kit/sentinel/sentinel_preflight.py:108-150` añade un `ALWAYS_DENY_PATHS` floor **en código**, consultado antes de la allowlist; el agujero medido (`$HOME/.claude/` exento) queda cerrado. Cubierto por `kit/test/test_guards.sh` (caso `credentials`). |
| **F-14** — exención global hex-64 abre hueco de detección | `fixed-at-59fee-with-regression` | `kit/claude/.gitleaks.toml:95-106` documenta que el hueco `<64 hex>` lo cubre `kit/scan-secrets.sh` en `make test`; `kit/test/test_secret_content_gitleaks.sh` prueba las dos direcciones (huella pasa, token real bloquea). |
| **F-15** — guards clasifican fuente, no argv expandido | `residual-hypothesis` | `kit/claude/hooks/block-dangerous-commands.sh:84` sigue clasificando `tool_input.command` (la fuente). El bypass por expansión es real pero la detención final por HITL/runtime era NO VERIFICABLE AQUÍ y sigue sin probarse. |
| **F-16** — destino `CLAUDE_HOME` y rutas runtime no coinciden | `residual-hypothesis` | INCIERTO en la auditoría (P2/refutado como P1): `CLAUDE_HOME` no es el override runtime oficial y no hubo sesión real. La precedencia de homes se aborda en el todo 15, pero la duda runtime sigue sin verificarse aquí. |
| **F-17** — restos de `autonomy.sh` prometen conexión retirada | `unresolved` | `scripts/autonomy.sh` sigue presente; `TAREAS.md` y `CONTRIBUTING.md` aún lo referencian. Prosa/script obsoleto no podado. Boundary de docs: todo 17. |
| **F-18** — perfil con campos sin lector runtime | `unresolved` | `config/settings.template.json` presente; los campos de perfil sin consumidor (salvo `explain`) siguen; el schema de capacidades runtime llega en el todo 18. |
| **F-19** — post-install apunta `.env` al HOME equivocado | `unresolved` | `kit/install.sh:642` sigue imprimiendo `cp $KIT/.env.example $HOME/.claude/.env` con `$HOME` literal en vez de `$CLAUDE_HOME`; induce copia manual a ruta distinta cuando el home se reubica. Precedencia de homes: todo 15. |
| **F-20** — `.git.is_dir()` diagnostica mal worktrees | `unresolved` | Evidencia `M/bin/mch:22-23,277-278`, repo M. Diagnóstico Git en worktree sigue degradado contra M@71d1139. No es superficie S. |
| **F-21** — restore acepta ZIP sin manifiesto | `unresolved` | `uninstall.sh` sigue delegando en el ZIP de `scripts/backup.sh`; la integridad/autenticidad plena del restore llega en el todo 16. `kit/test/test_uninstall.sh` cubre el caso de checksum inválido, pero no un manifiesto firmado. |
| **F-22** — documentación atribuye reescritura a `rtk` retirado | `fixed-at-59fee-with-regression` | `CLAUDE.md` ya no cita `rtk` como hook activo (grep `rtk` en `CLAUDE.md` = 0 en la sección de settings; el README lo describe como retirado en 1.1.0, `README.md` "se retiró por eso"). `kit/test/test_doc_claims.sh` ata las afirmaciones del doc al árbol. |
| **F-23** — inventario de plugins no coincide con settings | `fixed-at-59fee-with-regression` | `kit/docs/08-plugins-mcp-y-skills.md:7` ahora dice "siete plugins… cuatro del marketplace oficial… los otros tres", coherente con `kit/claude/settings.json`. `kit/test/test_doc_claims.sh` verifica el recuento contra el settings real. |
| **F-24** — timeouts duplicados e incompatibles | `unresolved` | `.claude/settings.json:58` usa `timeout:5` mientras `kit/claude/settings.json:45+` usa `10`; la discrepancia ≤5s vs 10/15s persiste entre las dos capas. |
| **F-25** — ShellCheck es requisito humano, no gate, y falla | `unresolved` | `CLAUDE.md:75` sigue pidiendo `shellcheck -x` como paso humano fuera de `make test`; el oráculo verde no lo ejecuta. Boundary de portabilidad: todo 17. |
| **F-26** — seis reglas `Write(path)` no se consultan | `fixed-at-59fee-with-regression` | Cero reglas `Write(` en `kit/claude/settings.json` ni `.claude/settings.json` (grep `Write(` = 0). El commit `935f7b3 fix(permissions)` "retiró las reglas inertes". `kit/test/test_permisos_efectivos.sh` cubre la política efectiva. |
| **F-27** — estado contiene identidad, HOME y máquina personal | `unresolved` | `.claude/skills/dev-env/SKILL.md:3,40-76` sigue conteniendo metadata de entorno personal (WSL2, rutas, pnpm); evidencia M (`.agents/state.json`) fuera del corte S. Metadata personal no depurada. |
| **F-28** — plataforma/versiones estrechas e incoherentes | `unresolved` | `kit/install.sh:29-39` sigue abortando fuera de Linux/WSL2; README declara macOS/Windows no soportados. Es diseño deliberado, pero la incoherencia Node/Python-floor documentada sigue. `kit/test/test_install_platform_gate.sh` fija el gate. |
| **F-29** — `/review` y `/verify` colisionan con built-ins | `residual-hypothesis` | NO VERIFICABLE AQUÍ en la auditoría: los nombres `.claude/commands/review.md` y `verify.md` siguen; la precedencia real frente a built-ins requiere sesión autenticada, no observada. Sin cambio. |
| **F-30** — auto-router falla en ambos sentidos | `unresolved` | `.claude/hooks/auto-spec.sh` presente; el router sigue con el defecto de clasificación descrito. Sin regresión que lo corrija en el corte actual. |
| **F-31** — `mch init` ofrece siguientes pasos incompatibles | `unresolved` | Evidencia `M/bin/mch:125-129,166`, repo M. Onboarding de M sin cambio contra 71d1139. No es superficie S. |
| **F-32** — `/work` arranca `<id>` que no crea/selecciona | `unresolved` | `.claude/commands/work.md:81-87` sigue con el flujo que falla con cola ausente y depende de conocimiento tácito. Sin cambio. |
| **F-33** — onboarding contradice si `jq` es obligatorio | `unresolved` | `kit/docs/10-onboarding.md` vs `kit/docs/02-install.md`: la ambigüedad sobre si los guards funcionan sin `jq` persiste en el corte actual (los guards leen con `python3` si falta `jq`, pero la doc no lo cierra). |
| **F-34** — primer copy/paste de `mcharness` no es autocontenido | `unresolved` | Evidencia `M/README.md:45-51`, repo M. Placeholder de clon y Python≥3.11 oculto sin cambio contra 71d1139. No es superficie S. |
| **F-35** — `doctor` no diagnostica JSON malformado | `unresolved` | Evidencia `M/bin/mch:280-282,326-334`, repo M. El diagnóstico cae ante estado malformado contra 71d1139. No es superficie S. |
| **F-36** — inicio y journal no son atómicos | `unresolved` | Evidencia `M/bin/mch:479-488,777-779`, repo M. La atomicidad la aborda el todo 10 (`crash-consistent`). No es superficie S. |
| **F-37** — dos settings idénticos crean SSOT falsa | `fixed-at-59fee-with-regression` | `cmp -s config/settings.template.json kit/claude/settings.json` → **DIFIEREN** en el corte actual (en la auditoría eran idénticos, `cmp` rc=0). La plantilla ya no duplica byte-a-byte el settings del kit. |
| **F-38** — lecturas de repo no pasan por sanitizador | `residual-hypothesis` | Regla del plan: permanece residual sin sanitizador de `Read` real. `kit/claude/hooks/narthex-post-mcp.py` normaliza MCP y `kit/sentinel/sentinel_preflight.py` cubre PreToolUse, pero la superficie repo→contexto vía `Read` sigue sin sanitizador; explotación nunca probada. |
| **F-39** — referencias mutables en instalaciones/plugins/CI | `residual-hypothesis` | NO VERIFICABLE AQUÍ: `kit/claude/settings.json` declara plugins/marketplaces mutables; su resolución futura depende de red/cuenta y sigue sin verificarse. `gitleaks` sí se fija por checksum (`kit/install.sh`), pero la mutabilidad de plugins persiste como hipótesis. |
| **F-40** — tabla inexistente y timeout falso | `unresolved` | `kit/claude/CLAUDE.md:13` sigue refiriendo "la tabla" y afirmaciones de timeout que `kit/test/test_harness_structure.sh` y el settings no sustentan al 100%. P3, sin podar. |
| **F-41** — `oracle_candidates`/`oracle_kind` nunca se leen | `unresolved` | Evidencia `M/bin/mch:22,58-60`, repo M. Campos sin consumidor contra 71d1139; su poda la hace el todo 8 (F-41/F-42). No es superficie S. |
| **F-42** — segundo glob Python es redundante | `unresolved` | Evidencia `M/bin/mch:25-31`, repo M. Rama redundante contra 71d1139; poda en el todo 8. No es superficie S. |

## Contabilidad

- **42/42** IDs mapeados (F-01…F-42), cada uno a un estado único con evidencia del corte actual.
- Distribución de estados (verificada por comando, ver `qa.log`): `unresolved` = 29;
  `fixed-at-59fee-with-regression` = 7 (F-11, F-13, F-14, F-22, F-23, F-26, F-37);
  `residual-hypothesis` = 6 (F-05, F-15, F-16, F-29, F-38, F-39); `superseded` = 0. Suma = 42.
- Recuento exacto por estado se comprueba con `kit/test/test_claude_characterization.sh` (casos B0–B5).
- **F-38** permanece `residual-hypothesis` por mandato del plan: no hay sanitizador de `Read`.
- Los 16 hallazgos con evidencia `M/bin/mch:*` o `M/README.md:*` se juzgan contra el corte M
  auditado (`71d1139`); su reconciliación real y sus tests viven en los todos del lado M, no aquí.
