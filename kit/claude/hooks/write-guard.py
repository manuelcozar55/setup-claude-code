#!/usr/bin/env python3
"""
write-guard.py — PreToolUse hook for Write, Edit, MultiEdit and NotebookEdit.
Scans content being written/edited for hardcoded secrets before the write
completes. Advisory output via additionalContext; blocks on high-confidence hits.

Patterns: API keys (Anthropic, OpenAI, AWS, GCP, GitHub), JWTs, PEM keys,
generic high-entropy password patterns.
"""
from __future__ import annotations
import json, re, sys
from pathlib import Path

# Los patrones de alta confianza viven en lib/secret-patterns (etiqueta, accion, ERE), la lista que
# comparte con bash-write-guard.sh; un test de paridad prueba que Python `re` y `grep -E` la leen igual.
# Aqui quedan solo los que NO caben en ERE: llevan (?i) o lookahead. Declarado, no olvidado.
PATTERNS_FILE = Path(__file__).resolve().parent / "lib" / "secret-patterns"

PYTHON_ONLY_PATTERNS: list[tuple[str, str, bool]] = [
    # (pattern, label, should_block)
    (r'(?i)twilio.{0,20}(account|auth).{0,5}[=:].{0,5}[a-f0-9]{32}', "Twilio credential", True),
    (r'(?i)(password|passwd|pwd|secret|api_?key|auth_?token)\s*[=:]\s*["\'\'](?!.*\$\{)[^"\'\']{8,}', "Hardcoded credential assignment", False),
]


def load_patterns() -> list[tuple[str, str, bool]]:
    """Lee el TSV. Si falta o una fila esta rota lanza: main() lo convierte en fail-closed."""
    patterns = []
    for line in PATTERNS_FILE.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        label, action, ere = line.split("\t")
        if action not in ("block", "advise"):
            raise ValueError(f"accion desconocida {action!r} en {PATTERNS_FILE.name}")
        patterns.append((ere, label, action == "block"))
    return patterns + PYTHON_ONLY_PATTERNS


SAFE_PATHS = {".env.example", ".env.template", ".env.sample", ".env.dist"}

# Fragmentos que delatan un valor de ejemplo: en ficheros exentos (.env.example) solo
# los secretos de alta confianza que NO los contienen bloquean.
PLACEHOLDER = re.compile(r"(?i)x{4,}|changeme|your[-_]|<[^>]*>|example")

def get_content(data: dict) -> tuple[str, str]:
    tool = data.get("tool_name", "")
    inp = data.get("tool_input", {})
    if tool == "Write":
        return inp.get("content", ""), inp.get("file_path", "")
    if tool == "Edit":
        return inp.get("new_string", ""), inp.get("file_path", "")
    if tool == "MultiEdit":
        edits = inp.get("edits", [])
        return "\n".join(e.get("new_string", "") for e in edits), inp.get("file_path", "")
    if tool == "NotebookEdit":
        return inp.get("new_source", ""), inp.get("notebook_path", "")
    return "", ""


def is_safe_path(path: str) -> bool:
    name = Path(path).name
    return name in SAFE_PATHS


def scan(content: str, compiled_patterns: list, safe: bool = False) -> list[tuple[str, bool]]:
    findings = []
    for compiled, label, block in compiled_patterns:
        if safe:
            # Fichero de ejemplo: solo alta confianza y sin pinta de placeholder.
            if block and any(not PLACEHOLDER.search(m.group(0)) for m in compiled.finditer(content)):
                findings.append((label, block))
        elif compiled.search(content):
            findings.append((label, block))
    return findings


def in_subagent(data: dict) -> bool:
    """El aviso de delegar no tiene sentido dentro de un subagente, que ya es el que escribe. Sin
    verificar contra un payload real: si ninguno de estos campos llega, se avisa como antes."""
    transcript = data.get("transcript_path")
    return bool(data.get("agent_id") or data.get("parent_tool_use_id")
                or isinstance(transcript, str) and "/subagents/" in transcript)


def main() -> None:
    data = json.load(sys.stdin)
    tool = data.get("tool_name", "")
    if tool not in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        sys.exit(0)

    content, path = get_content(data)
    if not content:
        sys.exit(0)

    compiled_patterns = [(re.compile(p), label, block) for p, label, block in load_patterns()]
    safe = is_safe_path(path)
    findings = scan(content, compiled_patterns, safe)
    if safe and not findings:
        sys.exit(0)
    if not findings:
        if tool == "Write" and len(content.splitlines()) > 150 and not Path(path).exists() and not in_subagent(data):
            print(json.dumps({
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "additionalContext": (
                        f"[WRITE-GUARD] '{path}' es un fichero nuevo de >150 líneas: "
                        "delégalo a un subagente."
                    ),
                }
            }))
        sys.exit(0)

    blocking = any(b for _, b in findings)
    labels = [label for label, _ in findings]

    if blocking:
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": (
                    f"WRITE-GUARD BLOCKED: file '{path}' appears to contain "
                    f"hardcoded secrets: {', '.join(labels)}. "
                    "Use environment variables or a secrets manager instead."
                ),
            }
        }))
    else:
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "additionalContext": (
                    f"⚠ [WRITE-GUARD ADVISORY] Writing to '{path}' matches potential "
                    f"secret patterns: {', '.join(labels)}. "
                    "Verify these are not real credentials before proceeding."
                ),
            }
        }))


# Fail-closed solo aqui: un fallo del guard no puede dejar pasar una escritura con secretos.
# stale-read-guard.py sigue fail-open por diseno (solo aconseja).
try:
    main()
except Exception as exc:
    print(f"WRITE-GUARD ERROR: no se pudo analizar la escritura ({type(exc).__name__}: {exc}); "
          "se bloquea por seguridad (fail-closed).", file=sys.stderr)
    sys.exit(2)
