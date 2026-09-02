#!/usr/bin/env python3
"""
write-guard.py — PreToolUse hook for Write and Edit tools.
Scans content being written/edited for hardcoded secrets before the write
completes. Advisory output via additionalContext; blocks on high-confidence hits.

Patterns: API keys (Anthropic, OpenAI, AWS, GCP, GitHub), JWTs, PEM keys,
generic high-entropy password patterns.
"""
from __future__ import annotations
import json, re, sys
from pathlib import Path

SECRET_PATTERNS: list[tuple[str, str, bool]] = [
    # (pattern, label, should_block)
    (r"sk-ant-[a-zA-Z0-9\-_]{20,}", "Anthropic API key", True),
    (r"sk-[a-zA-Z0-9]{20,}", "OpenAI API key", True),
    (r"sk_live_[a-zA-Z0-9]{24}", "Stripe live secret key", True),
    (r"sk_test_[a-zA-Z0-9]{24}", "Stripe test secret key", True),
    (r"AKIA[0-9A-Z]{16}", "AWS Access Key ID", True),
    (r"AIza[0-9A-Za-z\-_]{35}", "Google API key", True),
    (r"ghp_[a-zA-Z0-9]{36}", "GitHub Personal Access Token", True),
    (r"gho_[a-zA-Z0-9]{36}", "GitHub OAuth token", True),
    (r"github_pat_[a-zA-Z0-9_]{82}", "GitHub fine-grained PAT", True),
    (r"xoxb-[0-9]+-[0-9A-Za-z\-]+", "Slack bot token", True),
    (r"xoxp-[0-9]+-[0-9A-Za-z\-]+", "Slack user token", True),
    (r"-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----", "PEM private key", True),
    (r"npm_[a-zA-Z0-9]{36}", "npm access token", True),
    (r"SG\.[a-zA-Z0-9_\-]{22}\.[a-zA-Z0-9_\-]{43}", "SendGrid API key", True),
    (r"dapi[a-z0-9]{32}", "Databricks API token", True),
    (r"DefaultEndpointsProtocol=https;AccountName=", "Azure storage connection string", True),
    (r'(?i)twilio.{0,20}(account|auth).{0,5}[=:].{0,5}[a-f0-9]{32}', "Twilio credential", True),
    (r'(?i)(password|passwd|pwd|secret|api_?key|auth_?token)\s*[=:]\s*["\'\'](?!.*\$\{)[^"\'\']{8,}', "Hardcoded credential assignment", False),
    (r"eyJ[a-zA-Z0-9_\-]{10,}\.eyJ[a-zA-Z0-9_\-]{10,}\.[a-zA-Z0-9_\-]{10,}", "JWT token (hardcoded)", False),
]

SAFE_PATHS = {".env.example", ".env.template", ".env.sample", ".env.dist"}

COMPILED = [(re.compile(p), label, block) for p, label, block in SECRET_PATTERNS]


def get_content(data: dict) -> tuple[str, str]:
    tool = data.get("tool_name", "")
    inp = data.get("tool_input", {})
    if tool == "Write":
        return inp.get("content", ""), inp.get("file_path", "")
    if tool == "Edit":
        return inp.get("new_string", ""), inp.get("file_path", "")
    return "", ""


def is_safe_path(path: str) -> bool:
    name = Path(path).name
    return name in SAFE_PATHS


def scan(content: str) -> list[tuple[str, bool]]:
    findings = []
    for compiled, label, block in COMPILED:
        if compiled.search(content):
            findings.append((label, block))
    return findings


def main() -> None:
    data = json.load(sys.stdin)
    tool = data.get("tool_name", "")
    if tool not in ("Write", "Edit"):
        sys.exit(0)

    content, path = get_content(data)
    if not content or is_safe_path(path):
        sys.exit(0)

    findings = scan(content)
    if not findings:
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
            "additionalContext": (
                f"⚠ [WRITE-GUARD ADVISORY] Writing to '{path}' matches potential "
                f"secret patterns: {', '.join(labels)}. "
                "Verify these are not real credentials before proceeding."
            )
        }))


try:
    main()
except Exception:
    sys.exit(0)
