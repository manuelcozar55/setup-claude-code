#!/usr/bin/env python3
"""
smart_approve.py — PreToolUse compound command decomposer.
Decomposes &&, ||, ;, |, $(), backticks and checks each fragment
against settings.json permissions.deny rules.
Protocol: JSON deny if any fragment matches; silent exit 0 otherwise.
"""
from __future__ import annotations
import json, re, sys
from pathlib import Path


def load_deny_rules() -> list[str]:
    settings = Path.home() / ".claude" / "settings.json"
    try:
        s = json.loads(settings.read_text())
        return s.get("permissions", {}).get("deny", [])
    except Exception:
        return []


def extract_bash_pattern(rule: str) -> str | None:
    m = re.match(r"^Bash\((.+)\)$", rule)
    return m.group(1) if m else None


def glob_to_regex(pattern: str) -> re.Pattern:
    regex = re.escape(pattern).replace(r"\*", ".*").replace(r"\?", ".")
    return re.compile("^" + regex + "$", re.IGNORECASE)


def split_compound(command: str) -> list[str]:
    """Split on unquoted shell operators; also extract $() and backtick bodies."""
    # Split on ||, &&, single & (background), ;, single |, and newlines — each is a
    # real command boundary. Missing & and \n previously let `echo ok & rm -rf /`
    # (or a newline-chained script) slip through as one un-checked fragment.
    parts = re.split(r"\|\||&&|&(?!&)|;(?!;)|\|(?!\|)|[\n\r]", command)
    fragments: list[str] = []
    for part in parts:
        part = part.strip()
        if part:
            fragments.append(part)
        # Extract $(...) bodies (non-nested)
        for sub in re.findall(r"\$\(([^)]+)\)", part):
            fragments.append(sub.strip())
        # Extract backtick bodies
        for sub in re.findall(r"`([^`]+)`", part):
            fragments.append(sub.strip())
    return [f for f in fragments if f]


def matches_deny(fragment: str, deny_rules: list[str]) -> str | None:
    for rule in deny_rules:
        pattern = extract_bash_pattern(rule)
        if pattern is None:
            continue
        if glob_to_regex(pattern).match(fragment):
            return rule
    return None


def main() -> None:
    data = json.load(sys.stdin)
    command = data.get("tool_input", {}).get("command", "")
    if not command:
        sys.exit(0)

    deny_rules = load_deny_rules()
    if not deny_rules:
        sys.exit(0)

    fragments = split_compound(command)
    for fragment in fragments:
        matched = matches_deny(fragment, deny_rules)
        if matched:
            print(json.dumps({
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": (
                        f"BLOCKED: compound command contains denied sub-command "
                        f"matching '{matched}': {fragment!r}"
                    ),
                }
            }))
            sys.exit(0)

    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # fail-open, like the rest of the suite: a bug here must never freeze the session
        sys.exit(0)
