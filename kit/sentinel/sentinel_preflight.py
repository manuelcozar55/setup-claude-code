#!/usr/bin/env python3
"""
sentinel_preflight.py — PreToolUse hook for ALL tools (matcher: "").

Reads the tool call JSON from stdin, checks it against the IOC library
(iocs.json) + user allowlist, and returns allow/deny/warn on stdout.

Zero LLM cost. Pure local Python. Fail-open: any crash defaults to allow.

Output protocol (Claude Code PreToolUse):
  deny  → {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "..."}}
  warn  → {"additionalContext": "⚠ [SENTINEL] ..."}
  allow → exit 0 silently

Audit log: ~/.claude/audit-logs/sentinel.jsonl
"""
from __future__ import annotations
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


# ── IOC loading ──────────────────────────────────────────────────────────────

def load_iocs() -> dict:
    candidates = [
        Path(__file__).parent / "iocs.json",
        Path.home() / ".claude" / "hooks" / "iocs.json",
        Path.home() / ".claude" / "skills" / "mcp-sentinel" / "references" / "iocs.json",
    ]
    for path in candidates:
        if path.exists():
            try:
                return json.loads(path.read_text())
            except Exception:
                continue
    return {}


def load_user_allowlist() -> dict:
    for candidate in (
        Path.cwd() / ".security" / "sentinel-allowlist.json",
        Path.home() / ".claude" / "sentinel-allowlist.json",
    ):
        if candidate.exists():
            try:
                return json.loads(candidate.read_text())
            except Exception:
                continue
    return {"paths": [], "domains": [], "commands": []}


# ── Matching helpers ─────────────────────────────────────────────────────────

def expand(p: str) -> str:
    return os.path.expandvars(os.path.expanduser(p))


def path_matches(text: str, pattern: str) -> bool:
    pattern_exp = expand(pattern).rstrip("/")
    pattern_raw = pattern.rstrip("/")
    for t in (text, expand(text)):
        if not t:
            continue
        if t in (pattern_exp, pattern_raw):
            return True
        if t.startswith(pattern_exp + "/") or t.startswith(pattern_raw + "/"):
            return True
        if pattern_exp and pattern_exp in t:
            return True
        if pattern_raw and pattern_raw in t:
            return True
    return False


def _norm_path(p: str) -> str:
    """Expand ~ / $VARS and collapse '..' and '//' so traversal can't hide a target."""
    return os.path.normpath(expand(p))


def is_allowed_path(text: str, allowed: list[str]) -> bool:
    """Strict, component-aware allowlist match.

    Fixes two classes of over-exemption:
      * traversal — '$HOME/.claude/../../etc/shadow' normalizes to '/etc/shadow'
        and no longer matches the '$HOME/.claude' prefix.
      * prefix collision — '$HOME/.claude-evil' no longer matches '$HOME/.claude'
        because a path boundary is required after the token.
    """
    # Match the WHOLE (normalized) field only — never a substring/token. This is
    # what closes the two bugs: a traversal like '/tmp/../etc/shadow' normalizes to
    # '/etc/shadow' (no longer under '/tmp/'), and a command that merely *mentions*
    # an allowlisted path (e.g. 'cp server.pem /tmp/x') is no longer wholesale
    # exempted — so its sensitive '.pem' hit is still caught. Commands are meant to
    # be allowlisted via the separate `commands` list, not the path list.
    norm_text = _norm_path(text.strip().strip("\"'"))
    for pat in allowed:
        pn = _norm_path(pat).rstrip("/")
        if not pn or pn == ".":
            continue
        if norm_text == pn or norm_text.startswith(pn + os.sep):
            return True
    return False


def _url_hosts(text: str) -> set[str]:
    """Extract the actual hostnames from any http(s) URLs in the text."""
    hosts = set()
    for m in re.finditer(r"https?://([^/\s\"'>)]+)", text):
        host = m.group(1).split("@")[-1].split(":")[0].lower()
        if host:
            hosts.add(host)
    return hosts


def is_allowed_domain(text: str, allowed: list[str]) -> bool:
    """Match on the parsed host, not a raw substring.

    'github.com.evil-phish.tk' no longer counts as allowlisted just because it
    contains the substring 'github.com'.
    """
    hosts = _url_hosts(text)
    if not hosts:
        return False
    for d in allowed:
        dl = d.lower().strip().rstrip("/")
        if not dl:
            continue
        for host in hosts:
            if host == dl or host.endswith("." + dl):
                return True
    return False


def collect_strings(obj, depth: int = 0) -> list[str]:
    if depth > 8:
        return []
    if isinstance(obj, str):
        return [obj]
    if isinstance(obj, dict):
        out = []
        for v in obj.values():
            out.extend(collect_strings(v, depth + 1))
        return out
    if isinstance(obj, list):
        out = []
        for v in obj:
            out.extend(collect_strings(v, depth + 1))
        return out
    return []


def collect_fields(tool_input: dict, keys: list[str]) -> list[str]:
    """Extract strings from specific top-level keys only, avoiding file content."""
    out = []
    for key in keys:
        val = tool_input.get(key)
        if val is not None:
            out.extend(collect_strings(val))
    return out


# ── Checks ───────────────────────────────────────────────────────────────────

def check_sensitive_paths(tool_input: dict, iocs: dict, allowlist: dict):
    patterns = iocs.get("sensitive_paths", {}).get("patterns", [])
    regexes = iocs.get("sensitive_paths", {}).get("regex_patterns", [])
    allowed = allowlist.get("paths", []) + iocs.get("allowlist", {}).get("paths", [])

    for text in collect_fields(tool_input, ["file_path", "path", "paths", "command", "url", "endpoint", "uri", "href", "target"]):
        if is_allowed_path(text, allowed):
            continue
        for p in patterns:
            if path_matches(text, p):
                return (f"sensitive path: {p}", "critical")
        for rx in regexes:
            if re.search(rx, text):
                return (f"sensitive path pattern", "critical")
    return (None, None)


def check_sensitive_env(tool_input: dict, iocs: dict, allowlist: dict):
    patterns = iocs.get("sensitive_env_vars", {}).get("patterns", [])
    regexes = iocs.get("sensitive_env_vars", {}).get("regex_patterns", [])
    allowed_vars = allowlist.get("env_vars", []) + iocs.get("allowlist", {}).get("env_vars", [])

    for text in collect_fields(tool_input, ["command", "url"]):
        for var in patterns:
            if var in allowed_vars:
                continue
            if re.search(rf"\b{re.escape(var)}\b", text):
                return (f"sensitive env var: {var}", "medium")
        for rx in regexes:
            if re.search(rx, text):
                return ("sensitive env var pattern", "medium")
    return (None, None)


def check_prompt_injection(tool_input: dict, iocs: dict, allowlist: dict):
    patterns = iocs.get("prompt_injection_phrases", {}).get("patterns", [])
    # Scan instruction-shaped fields only — never arbitrary file content — so that
    # writing docs or tests that legitimately quote a jailbreak phrase (as this very
    # audit report does) is not hard-denied. Injection smuggled inside tool RESPONSES
    # is Narthex's job (PostToolUse), not this pre-flight check.
    instr = ["command", "prompt", "query", "input", "text", "message", "instruction", "description", "url"]
    for text in collect_fields(tool_input, instr):
        for rx in patterns:
            if re.search(rx, text):
                return ("prompt injection attempt", "high")
    # Content being written/read: warn, not deny. Hard-denying here blocks the
    # legitimate act of writing docs, tests or reports that quote an injection
    # phrase (a confirmed false positive); warn keeps it logged and visible
    # without freezing the session.
    for text in collect_fields(tool_input, ["content", "new_string", "new_str", "contents", "body"]):
        for rx in patterns:
            if re.search(rx, text):
                return ("prompt injection phrase in written content", "medium")
    return (None, None)


def check_suspicious_network(tool_input: dict, iocs: dict, allowlist: dict):
    net = iocs.get("suspicious_network", {})
    known_malicious = net.get("known_malicious_domains", [])
    suspicious_tlds = net.get("suspicious_tlds", [])
    pastebin = net.get("pastebin_style", [])
    suspicious_patterns = net.get("suspicious_patterns", [])
    allowed_domains = allowlist.get("domains", []) + iocs.get("allowlist", {}).get("domains", [])

    for text in collect_fields(tool_input, ["url", "command", "endpoint", "uri", "href", "target"]):
        for entry in known_malicious:
            if entry.get("domain", "").lower() in text.lower():
                return (f"known-malicious domain: {entry['domain']}", "critical")

        if is_allowed_domain(text, allowed_domains):
            continue

        for ps in pastebin:
            if ps.lower() in text.lower():
                return (f"exfil service: {ps}", "high")

        for rx in suspicious_patterns:
            if re.search(rx, text):
                return ("raw IP address in URL", "high")

        for tld in suspicious_tlds:
            if re.search(rf"https?://[^\s/]+{re.escape(tld)}(/|\s|$|\"|')", text):
                return (f"suspicious TLD: {tld}", "medium")

    return (None, None)


def check_dangerous_commands(tool_input: dict, iocs: dict, allowlist: dict):
    patterns = iocs.get("dangerous_commands", {}).get("patterns", [])
    allowed_cmds = allowlist.get("commands", [])

    for text in collect_fields(tool_input, ["command"]):
        if text in allowed_cmds:
            continue
        for rx in patterns:
            if re.search(rx, text):
                return (f"dangerous command pattern", "critical")
    return (None, None)


# ── Decision engine ───────────────────────────────────────────────────────────

SEVERITY_RANK = {"medium": 1, "high": 2, "critical": 3}


def decide(payload: dict):
    iocs = load_iocs()
    allowlist = load_user_allowlist()
    tool_input = payload.get("tool_input") or payload.get("input") or {}

    checks = [
        check_sensitive_paths,
        check_suspicious_network,
        check_dangerous_commands,
        check_sensitive_env,
        check_prompt_injection,
    ]

    highest_sev = None
    highest_reason = None
    for fn in checks:
        reason, sev = fn(tool_input, iocs, allowlist)
        if sev and (not highest_sev or SEVERITY_RANK[sev] > SEVERITY_RANK[highest_sev]):
            highest_sev = sev
            highest_reason = reason

    if not highest_sev:
        return "allow", None
    if highest_sev in ("critical", "high"):
        return "deny", f"[{highest_sev.upper()}] {highest_reason}"
    return "warn", f"[{highest_sev.upper()}] {highest_reason}"


# ── Audit logging ─────────────────────────────────────────────────────────────

def audit_log(tool: str, decision: str, reason: str | None) -> None:
    log_path = Path.home() / ".claude" / "audit-logs" / "sentinel.jsonl"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a") as f:
        json.dump({
            "ts": datetime.now(timezone.utc).isoformat(),
            "tool": tool,
            "decision": decision,
            "reason": reason,
        }, f)
        f.write("\n")


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError:
        sys.exit(0)

    tool_name = payload.get("tool_name") or payload.get("tool", "<unknown>")
    decision, reason = decide(payload)

    if decision == "allow":
        sys.exit(0)

    audit_log(tool_name, decision, reason)

    if decision == "deny":
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": (
                    f"SENTINEL BLOCKED [{tool_name}]: {reason}\n"
                    "To allowlist a false positive: add to ~/.claude/sentinel-allowlist.json"
                ),
            }
        }))
    else:
        print(json.dumps({
            "additionalContext": (
                f"⚠ [SENTINEL WARNING] {tool_name}: {reason}\n"
                "Proceed only if this is expected. Add to allowlist to suppress."
            )
        }))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        sys.exit(0)
