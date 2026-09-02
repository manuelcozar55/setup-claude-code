#!/usr/bin/env python3
"""
stale-read-guard.py — PreToolUse hook for Read.

Warns when a file is about to be re-read after this same session already edited
it. Advisory only: it never blocks, because legitimate re-reads exist (external
process wrote the file, a build regenerated it, the edit failed).

Why: `headroom audit-reads` over 204 sessions measured 230 such calls — 1.3 MB,
~332k tokens, 21.1% of all Read bytes — the single largest identified waste in
the whole token budget of this machine, and larger than everything the Headroom
proxy compresses (0.27% of input). The rule already exists in CLAUDE.md; what
was missing was a check. A rule nobody verifies is not a rule.

Partial reads (offset/limit) are left alone: those are deliberate.
"""
from __future__ import annotations

import json
import os
import sys

EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
MAX_BYTES = 12_000_000  # cap on transcript scanned, newest-last files can be large


def _variants(path: str) -> set[str]:
    """The forms a path may appear as in the transcript."""
    out = {path}
    try:
        out.add(os.path.abspath(path))
        out.add(os.path.realpath(path))
    except OSError:
        pass
    return out


def _edited_in_session(transcript: str, targets: set[str], needle: str) -> bool:
    try:
        size = os.path.getsize(transcript)
    except OSError:
        return False

    try:
        with open(transcript, "r", encoding="utf-8", errors="replace") as fh:
            if size > MAX_BYTES:
                fh.seek(size - MAX_BYTES)
                fh.readline()  # discard the partial line
            for line in fh:
                # Cheap pre-filter: skip the ~99% of lines that cannot match.
                if needle not in line:
                    continue
                if not any(t in line for t in EDIT_TOOLS):
                    continue
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                content = (rec.get("message") or {}).get("content")
                if not isinstance(content, list):
                    continue
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") != "tool_use":
                        continue
                    if block.get("name") not in EDIT_TOOLS:
                        continue
                    fp = (block.get("input") or {}).get("file_path")
                    if isinstance(fp, str) and fp in targets:
                        return True
    except OSError:
        return False
    return False


def main() -> None:
    payload = json.load(sys.stdin)

    if payload.get("tool_name") != "Read":
        return

    tool_input = payload.get("tool_input") or {}
    path = tool_input.get("file_path")
    if not isinstance(path, str) or not path:
        return

    # A partial read is a deliberate act, not a stale re-read.
    if tool_input.get("offset") or tool_input.get("limit"):
        return

    transcript = payload.get("transcript_path")
    if not isinstance(transcript, str) or not transcript:
        return

    targets = _variants(path)
    needle = os.path.basename(path)
    if not needle:
        return

    if not _edited_in_session(transcript, targets, needle):
        return

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": (
                f"[STALE-READ] Ya editaste '{path}' en esta sesion. El contenido que "
                "tienes en contexto ya refleja tu edicion: Edit/Write habrian fallado "
                "si no se hubiese aplicado. Releerlo entero suele ser gasto puro "
                "(21% de los bytes de Read medidos en esta maquina). Si necesitas "
                "confirmar un tramo concreto, usa offset/limit; si el fichero pudo "
                "cambiarlo un proceso externo, ignora este aviso."
            ),
        }
    }))


try:
    main()
except Exception:
    sys.exit(0)
