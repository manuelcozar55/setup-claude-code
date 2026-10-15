#!/usr/bin/env python3
"""
sentinel_preflight.py — PreToolUse hook for ALL tools (matcher: "").

Reads the tool call JSON from stdin, checks it against the IOC library
(iocs.json) + user allowlist, and returns allow/deny/warn on stdout.

Zero LLM cost. Pure local Python. Fail-closed: a crash or malformed input exits 2 (block).
A malformed allowlist/iocs.json is ignored instead: it is data, and exit 2 on it blocks every tool.

Output protocol (Claude Code PreToolUse):
  deny  → {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "..."}}
  warn  → {"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": "⚠ [SENTINEL] ..."}}
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
                data = json.loads(path.read_text())
            except Exception:
                continue
            if isinstance(data, dict):
                return data
    return {}


def load_user_allowlist() -> dict:
    # Never $CWD/.security/: a cloned repo could ship its own exemptions.
    candidate = Path.home() / ".claude" / "sentinel-allowlist.json"
    if candidate.exists():
        try:
            data = json.loads(candidate.read_text())
            if isinstance(data, dict):
                return data
        except Exception:
            pass
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


def _search(rx: str, text: str):
    """re.search for regexes that come from data files: an invalid one is skipped, not fatal."""
    try:
        return re.search(rx, text)
    except re.error:
        return None


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


# ── Never-exempt floor ───────────────────────────────────────────────────────
# Both the allowlist and iocs.json are data files the agent can write to, so any
# rule that lives only in that data is a rule the agent can delete. These two
# lists live in CODE and are consulted before the allowlist:
#
#   ALWAYS_DENY_PATHS — live credential material. Denied even if a prefix of it
#     is allowlisted and even if iocs.json is missing or emptied. Measured hole:
#     '$HOME/.claude/' was in the allowlist `paths`, which exempted the whole
#     config dir, so a Read of ~/.claude/.credentials.json (a live OAuth token)
#     returned allow while ~/.aws/credentials, ~/.ssh/id_rsa and ~/.npmrc all
#     returned deny. Worse, the same file was denied when *named* in a command
#     and allowed when *opened* by file_path: the guard blocked talking about
#     the file and permitted reading it. The three entries are key material no
#     false positive can justify exempting, and for the last two the kit already
#     says so in prose: docs/09 tells the user not to put '~/.ssh/' in the
#     allowlist "para salir del paso". Prose is not enforcement; this list is.
#     Second measured vector: load_user_allowlist() used to prefer
#     '$CWD/.security/sentinel-allowlist.json', so a *cloned repo* could ship
#     its own exemptions (paths ["/"] turned the ~/.aws and ~/.ssh denies into
#     allows). It no longer reads $CWD; this floor stays for the user's own file.
#   PROTECTED_CONFIG — the guards and the config that drives them. These carry
#     no deny of their own (blocking the write is permissions.deny's job, in the
#     settings template); what they guarantee is that no allowlist entry — this
#     one or a wider one added later — can exempt them from detection, and that
#     every decision touching them reaches the audit log, `allow` included.
#     Without the allow-side log, disabling a guard leaves no trace at all.
ALWAYS_DENY_PATHS = [
    r"(?i)\.credentials\.json(?![a-z0-9])",
    r"(?i)/\.ssh/id_[a-z0-9_]+(?![a-z0-9._-])",
    r"(?i)/\.aws/credentials(?![a-z0-9])",
]

PROTECTED_CONFIG = [
    r"(?i)\.claude/settings[^/]*\.json(?![a-z0-9])",
    r"(?i)\.claude/hooks/",
    r"(?i)\.claude/sentinel/",
    r"(?i)sentinel-allowlist\.json(?![a-z0-9])",
    r"(?i)iocs\.json(?![a-z0-9])",
    r"(?i)\.gitleaks\.toml(?![a-z0-9])",
]

# Fields that carry a path/target. Shared so the never-exempt checks and the
# sensitive-path check can never drift apart on what counts as a "target".
PATH_FIELDS = ["file_path", "path", "paths", "command", "url", "endpoint", "uri", "href", "target"]


def always_deny_hit(tool_input: dict) -> str | None:
    """Text of the first field naming never-exempt credential material."""
    for text in collect_fields(tool_input, PATH_FIELDS):
        for rx in ALWAYS_DENY_PATHS:
            if re.search(rx, text):
                return text
    return None


def protected_config_hit(tool_input: dict) -> str | None:
    """Text of the first field touching guard/config paths (allow or deny)."""
    for text in collect_fields(tool_input, PATH_FIELDS):
        for rx in PROTECTED_CONFIG:
            if re.search(rx, text):
                return text
    return None


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


# ── Key files by name ────────────────────────────────────────────────────────
# A regex over the whole command cannot tell `cat .server.key` from the jq filter
# '.data.key', nor `cat x.key` from `grep "event.key"`: the difference is the
# role of the argument, not its text. So the command is lexed into shell words,
# the words that name no file (grep pattern, jq filter, commit message) are
# skipped, interpreter code is checked only in its string literals, and every
# other word is checked by its path components against key_file_extensions.
# The body of a $( ) or backtick is read as a command of its own, whatever the
# role of the word around it. Whatever cannot be classified is checked: this
# guard may deny more, never less.
DEFAULT_KEY_EXTS = ["pem", "key", "p12", "pfx", "jks", "keystore"]
_BRACE_CAP, _BRACE_BUDGET = 64, 256  # brace expansions per word / per command
_GREP_LONG = {"--regexp": 1, "--file": 1, "--max-count": 1, "--after-context": 1,
              "--before-context": 1, "--context": 1}
# Per tool: short options with a value, long options with N values, whether options
# end at the first positional (interpreters: the script), options after whose value
# they end. A flag listed here by mistake would move the pattern onto a file and skip
# it; a missing option only denies more. So only options known to take a value.
_OPTS = {
    "grep": ("efmABCdD", {**_GREP_LONG, "--include": 1, "--exclude": 1, "--exclude-dir": 1,
                          "--exclude-from": 1, "--label": 1}, False, set()),
    "rg": ("efmABCtTgjMdEr", {**_GREP_LONG, "--type": 1, "--type-not": 1, "--glob": 1,
                              "--iglob": 1, "--max-depth": 1, "--replace": 1, "--encoding": 1,
                              "--threads": 1}, False, set()),
    "jq": ("fL", {"--from-file": 1, "--indent": 1, "--arg": 2, "--argjson": 2,
                  "--slurpfile": 2, "--rawfile": 2}, False, set()),
    "git-message": ("mFCct", {"--message": 1, "--file": 1, "--author": 1, "--date": 1,
                              "--template": 1, "--reuse-message": 1, "--reedit-message": 1},
                    False, set()),
    "python": ("cmWX", {}, True, {"-c", "-m"}),
    "node": ("eprC", {"--eval": 1, "--print": 1, "--require": 1, "--import": 1}, True,
             {"-e", "-p", "--eval", "--print"}),
    "perl": ("eE", {}, True, {"-e", "-E"}),
    "ruby": ("erI", {}, True, {"-e"}),
}
_OPTS["egrep"] = _OPTS["fgrep"] = _OPTS["grep"]
_GREP_NO_PATTERN = {"-e", "--regexp", "-f", "--file", "--files", "--type-list"}
_NO_PATTERN = {"grep": _GREP_NO_PATTERN, "egrep": _GREP_NO_PATTERN, "fgrep": _GREP_NO_PATTERN,
               "rg": _GREP_NO_PATTERN, "jq": {"-f", "--from-file"}}
_SKIP_VALUE = {"grep": {"-e", "--regexp"}, "egrep": {"-e", "--regexp"}, "fgrep": {"-e", "--regexp"},
               "rg": {"-e", "--regexp"}, "git-message": {"-m", "--message"}}
_CODE_VALUE = {"node": {"-e", "-p", "--eval", "--print"}, "perl": {"-e", "-E"},
               "ruby": {"-e"}, "python": {"-c"}}
_OPS = ("&&", "||", ";;", "|&", ">>", "<<", "&>", ">&", "<&", ">|", "|", "&", ";", "(", ")", "<", ">")
_MASK = str.maketrans("{},", "\ue000\ue001\ue002")  # quoted braces do not expand
_UNMASK = str.maketrans("\ue000\ue001\ue002", "{},")
_BRACE = re.compile(r"\{([^{}]*,[^{}]*)\}")
_QUOTED = re.compile(r"'[^']*'|\"(?:\\.|[^\"\\])*\"")
_BACKTICK_BODY = re.compile(r"(?:\\.|[^`\\])*")
_HEREDOC_OP = re.compile(r"<<-?[ \t]*(['\"]?)\\?(\w+)\1")
# $(cat <<'EOF' ... EOF) outputs the heredoc as is: Claude Code's commit message.
_CAT_HEREDOC = re.compile(r"\s*cat\s*<<-?[ \t]*(['\"]?)(\w+)\1[ \t]*\n(.*?)\n\t*\2\n?\s*", re.S)
_SHELL_META = re.compile(r"[\s()|;&<>\"'`]")
_NAME_CHAR = re.compile(r"[\w@+~*?${}\[\]-]")


def _key_file_rx(exts: list[str]):
    alt = "|".join(re.escape(e) for e in exts)
    # Name, extension and an optional copy suffix (~ # + -old, .bak, .1, glob).
    # Any other extension after it is another file type: a.key.json, config.key.ts.
    return re.compile(
        rf"(?i)(.*)\.(?:{alt})"
        r"(?:[~#+*?\[\]{}-].*|\.(?:bak|old|orig|backup|save|sav|swp|tmp|copy|prev|\d+)|\.[*?\[].*)?"
    )


def _subst_end(text: str, i: int) -> int:
    """Index of the ) that closes a $( opened just before i: past quotes, nesting and heredocs."""
    depth, n, docs = 1, len(text), []
    while i < n:
        c = text[i]
        m = _HEREDOC_OP.match(text, i) if text.startswith("<<", i) and not text.startswith("<<<", i) else None
        if m:
            docs.append(m.group(2))
            i = m.end()
        elif c == "\n" and docs:
            for d in docs:
                end = re.compile(rf"^\t*{d}$", re.M).search(text, i + 1)
                i = end.end() if end else n
            docs = []
        elif c == "\\":
            i += 2
        elif c in "'\"":
            q = _QUOTED.match(text, i)
            i = q.end() if q else n
        else:
            depth += c == "("
            depth -= c == ")"
            if depth == 0:
                return i
            i += 1
    return n


def _substitution(text: str, i: int) -> tuple[str, int]:
    """Body of the $( ) or backtick at i, and the index after it."""
    if text[i] == "`":
        body = _BACKTICK_BODY.match(text, i + 1).group(0)
        return body, i + 2 + len(body)
    end = _subst_end(text, i + 2)
    return text[i + 2:end], end + 1


def _lex_char(text: str, i: int, quoted: bool, cur: str, subs: list) -> tuple[str, int]:
    """One character, escape or substitution of a word: the word so far and the next index."""
    c, nxt = text[i], text[i + 1:i + 2]
    if c == "\\":
        if quoted and nxt not in ("$", "`", '"', "\\", "\n"):
            return cur + "\\", i + 1
        return cur + ("" if nxt == "\n" else nxt.translate(_MASK)), i + 2
    if text.startswith("$(", i) or c == "`":
        body, i = _substitution(text, i)
        lit = _CAT_HEREDOC.fullmatch(body)
        # Literal only if the heredoc ends at its first delimiter line and, unquoted, expands nothing.
        if (lit and not re.search(rf"^\t*{lit.group(2)}$", lit.group(3), re.M)
                and (lit.group(1) or not re.search(r"\$\(|`", lit.group(3)))):
            return cur + lit.group(3).translate(_MASK), i
        subs.append(body)
        return cur + "$", i
    return cur + (c.translate(_MASK) if quoted else c), i + 1


def _lex(text: str) -> list:
    """Operators as str; words as (text, brace form, substitution bodies).

    Quotes are dropped from the text; in the brace form quoted braces are masked,
    since bash does not expand them. A substitution leaves a "$" in the word and
    its body in the list, except $(cat <<'EOF' ...) whose output is the heredoc."""
    toks, cur, subs, i, n = [], None, [], 0, len(text)
    while i < n:
        c = text[i]
        op = None if c in " \t\n" else next((o for o in _OPS if text.startswith(o, i)), None)
        if c in " \t\n" or op:
            if cur is not None:
                toks.append((cur.translate(_UNMASK), cur, subs))
                cur, subs = None, []
            if op:
                toks.append(op)
            elif c == "\n":
                toks.append(";")
            i += len(op) if op else 1
            continue
        cur = cur or ""
        if c == "'":
            j = text.find("'", i + 1)
            j = n if j < 0 else j
            cur, i = cur + text[i + 1:j].translate(_MASK), j + 1
        elif c == '"':
            i += 1
            while i < n and text[i] != '"':
                cur, i = _lex_char(text, i, True, cur, subs)
            i += 1
        else:
            cur, i = _lex_char(text, i, False, cur, subs)
    if cur is not None:
        toks.append((cur.translate(_UNMASK), cur, subs))
    return toks


def _parse(args: list[str], short: str, long: dict, stop: bool, ends: set) -> list[tuple[str, str | None]]:
    """(kind, option) per word: kind is opt, optval (value inside the word), val or pos."""
    out, pending, opt, opts = [], 0, None, True
    for a in args:
        if pending:
            out.append(("val", opt))
            pending -= 1
            opts = opts and not (pending == 0 and opt in ends)
        elif opts and a == "--":
            out.append(("opt", None))
            opts = False
        elif opts and a.startswith("-") and len(a) > 1:
            if a.startswith("--"):
                opt, attached = a.split("=", 1)[0], "=" in a
                pending = 0 if attached else long.get(opt, 0)
            else:
                k = next((j for j, ch in enumerate(a[1:], 1) if ch in short), 0)
                opt, attached = ("-" + a[k] if k else None), 0 < k < len(a) - 1
                pending = int(bool(k) and not attached)
            out.append(("optval" if attached else "opt", opt))
            opts = opts and not (pending == 0 and opt in ends)
        else:
            out.append(("pos", None))
            opts = opts and not stop
    return out


def _command_roles(cmd: list) -> list:
    """(word, role) for one simple command; role is path, code or skip."""
    roles = []
    while cmd and re.match(r"\w+=", cmd[0][0]):
        roles.append((cmd.pop(0), "path"))
    if not cmd:
        return roles
    name = re.sub(r"[\d.]+$", "", os.path.basename(cmd[0][0]).lower())
    roles.append((cmd[0], "path"))
    args = cmd[1:]
    if name == "git" and args and args[0][0] in ("grep", "commit", "tag", "merge"):
        name = "grep" if args[0][0] == "grep" else "git-message"
        roles.append((args.pop(0), "path"))
    if name not in _OPTS:
        return roles + [(a, "path") for a in args]
    parsed = _parse([a[0] for a in args], *_OPTS[name])
    first = name in _NO_PATTERN and not {o for _, o in parsed} & _NO_PATTERN[name]
    for a, (kind, opt) in zip(args, parsed):
        role = "path"
        if kind in ("val", "optval") and opt in _SKIP_VALUE.get(name, ()):
            role = "skip"
        elif kind in ("val", "optval") and opt in _CODE_VALUE.get(name, ()):
            role = "code"
        elif kind == "pos" and first:
            role, first = "skip", False
        roles.append((a, role))
    return roles


def _word_roles(toks: list) -> list:
    out, cmd, redirect = [], [], False
    for t in toks + [";"]:
        if isinstance(t, str):
            if "<" in t or ">" in t:
                redirect = True
                continue
            out += _command_roles(cmd)
            cmd = []
        elif redirect:
            out.append((t, "path"))
            redirect = False
        else:
            cmd.append(t)
    return out


def _brace_expand(form: str) -> list[str] | None:
    """Distinct expansions of the unmasked {a,b} groups, or None past the cap."""
    done, todo, seen = [], [form], {form}
    while todo:
        w = todo.pop()
        m = _BRACE.search(w)
        if not m:
            done.append(w)
            continue
        for alt in m.group(1).split(","):
            x = w[:m.start()] + alt + w[m.end():]
            if x not in seen:
                seen.add(x)
                todo.append(x)
        if len(seen) > 4 * _BRACE_CAP:
            return None
    return done if len(done) <= _BRACE_CAP else None


def _brace_linear(form: str) -> list[str]:
    """One group at a time, the others at their first alternative: bounded, not exhaustive."""
    groups = list(_BRACE.finditer(form))[:_BRACE_CAP]
    firsts = [g.group(1).split(",")[0] for g in groups]
    out = []
    for k, g in enumerate(groups):
        for alt in list(dict.fromkeys(g.group(1).split(",")))[:_BRACE_CAP]:
            parts, last = [], 0
            for j, h in enumerate(groups):
                parts += [form[last:h.start()], alt if j == k else firsts[j]]
                last = h.end()
            out.append("".join(parts) + form[last:])
            if len(out) >= _BRACE_BUDGET:
                return out
    return out or [form]


def _key_file_word(word: str, rx) -> bool:
    for piece in re.split(r"[\s=:,;|&()<>\"'`]+", word):
        for i, comp in enumerate(piece.split("/")):
            m = rx.fullmatch(comp)
            # A bare .key needs a slash before it (./.key): in prose or jq it is a field.
            if m and (_NAME_CHAR.search(m.group(1)) or (i > 0 and not m.group(1))):
                return True
    return False


def key_file_hit(text: str, rx, real: bool = True, depth: int = 0) -> str | None:
    """Why text names a key file, or None. real: text the shell runs as is (not a
    quoted string read again as a command), where an expansion past the cap denies."""
    if depth > 4:
        return "key file name" if _key_file_word(text, rx) else None
    spent = 0
    for (word, form, subs), role in _word_roles(_lex(text)):
        for body in subs:
            reason = key_file_hit(body, rx, real, depth + 1)
            if reason:
                return reason
        if role == "code":
            for lit in re.findall(r"'([^']*)'|\"([^\"]*)\"|`([^`]*)`", word):
                for s in lit:
                    reason = s and key_file_hit(s, rx, False, depth + 1)
                    if reason:
                        return reason
        elif role == "path" and _SHELL_META.search(word):
            reason = key_file_hit(word, rx, False, depth + 1)
            if reason:
                return reason
        elif role == "path":
            words = _brace_expand(form)
            if words is None or len(words) > 1 and spent + len(words) > _BRACE_BUDGET:
                if real:
                    return "brace expansion too large"
                words = _brace_linear(form)
            spent += len(words) if len(words) > 1 else 0
            if any(_key_file_word(w.translate(_UNMASK), rx) for w in words):
                return "key file name"
    return None


# ── Checks ───────────────────────────────────────────────────────────────────

def check_sensitive_paths(tool_input: dict, iocs: dict, allowlist: dict):
    patterns = iocs.get("sensitive_paths", {}).get("patterns", [])
    regexes = iocs.get("sensitive_paths", {}).get("regex_patterns", [])
    allowed = (allowlist.get("paths") or []) + iocs.get("allowlist", {}).get("paths", [])
    # The extension regex left regex_patterns for this list: an iocs.json without it (older,
    # own, trimmed from the example) must not turn the check off, so the code has a default
    # and the deny reason says it was used.
    exts = iocs.get("sensitive_paths", {}).get("key_file_extensions")
    valid = isinstance(exts, list) and exts and all(isinstance(e, str) and e for e in exts)
    key_rx = _key_file_rx(exts if valid else DEFAULT_KEY_EXTS)
    key_note = "" if valid else " (default extensions: iocs.json has no valid key_file_extensions)"

    for text in collect_fields(tool_input, PATH_FIELDS):
        for rx in ALWAYS_DENY_PATHS:
            m = re.search(rx, text)
            if m:
                return (f"never-exempt credential material: {m.group(0)}", "critical")
        # The allowlist may not exempt the guards or their config.
        if not protected_config_hit({"path": text}) and is_allowed_path(text, allowed):
            continue
        for p in patterns:
            if path_matches(text, p):
                return (f"sensitive path: {p}", "critical")
        for rx in regexes:
            if _search(rx, text):
                return (f"sensitive path pattern", "critical")
        key_reason = key_file_hit(text, key_rx)
        if key_reason:
            return (f"sensitive {key_reason}{key_note}", "critical")
    return (None, None)


def check_sensitive_env(tool_input: dict, iocs: dict, allowlist: dict):
    patterns = iocs.get("sensitive_env_vars", {}).get("patterns", [])
    regexes = iocs.get("sensitive_env_vars", {}).get("regex_patterns", [])
    allowed_vars = (allowlist.get("env_vars") or []) + iocs.get("allowlist", {}).get("env_vars", [])

    for text in collect_fields(tool_input, ["command", "url"]):
        for var in patterns:
            if var in allowed_vars:
                continue
            if re.search(rf"\b{re.escape(var)}\b", text):
                return (f"sensitive env var: {var}", "medium")
        for rx in regexes:
            if _search(rx, text):
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
            if _search(rx, text):
                return ("prompt injection attempt", "high")
    # Content being written/read: warn, not deny. Hard-denying here blocks the
    # legitimate act of writing docs, tests or reports that quote an injection
    # phrase (a confirmed false positive); warn keeps it logged and visible
    # without freezing the session.
    for text in collect_fields(tool_input, ["content", "new_string", "new_str", "contents", "body"]):
        for rx in patterns:
            if _search(rx, text):
                return ("prompt injection phrase in written content", "medium")
    return (None, None)


def check_suspicious_network(tool_input: dict, iocs: dict, allowlist: dict):
    net = iocs.get("suspicious_network", {})
    known_malicious = net.get("known_malicious_domains", [])
    suspicious_tlds = net.get("suspicious_tlds", [])
    pastebin = net.get("pastebin_style", [])
    suspicious_patterns = net.get("suspicious_patterns", [])
    allowed_domains = (allowlist.get("domains") or []) + iocs.get("allowlist", {}).get("domains", [])

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
            if _search(rx, text):
                return ("raw IP address in URL", "high")

        for tld in suspicious_tlds:
            if re.search(rf"https?://[^\s/]+{re.escape(tld)}(/|\s|$|\"|')", text):
                return (f"suspicious TLD: {tld}", "medium")

    return (None, None)


def check_dangerous_commands(tool_input: dict, iocs: dict, allowlist: dict):
    patterns = iocs.get("dangerous_commands", {}).get("patterns", [])
    allowed_cmds = allowlist.get("commands") or []

    for text in collect_fields(tool_input, ["command"]):
        if text in allowed_cmds:
            continue
        for rx in patterns:
            if _search(rx, text):
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
    try:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with log_path.open("a") as f:
            json.dump({
                "ts": datetime.now(timezone.utc).isoformat(),
                "tool": tool,
                "decision": decision,
                "reason": reason,
            }, f)
            f.write("\n")
    except OSError:
        pass  # an unwritable log must not turn a warn into a block


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError:
        print("SENTINEL BLOCKED (fail-closed): payload de PreToolUse no es JSON.", file=sys.stderr)
        sys.exit(2)

    tool_name = payload.get("tool_name") or payload.get("tool", "<unknown>")
    tool_input = payload.get("tool_input") or payload.get("input") or {}
    decision, reason = decide(payload)

    if decision == "allow":
        # An allow on a guard/config path is the one allow worth keeping: it is
        # the only trace left when a guard, the settings or this allowlist are
        # rewritten. Everything else stays silent (zero-noise design).
        touched = protected_config_hit(tool_input)
        if touched:
            audit_log(tool_name, "allow", f"config path touched: {touched[:200]}")
        sys.exit(0)

    audit_log(tool_name, decision, reason)

    if decision == "deny":
        # The allowlist hint is a lie for a never-exempt deny (no allowlist
        # entry can lift it) and it is also the instruction sheet for disabling
        # the guard, so it is printed only where it is actually true.
        hint = (
            "" if always_deny_hit(tool_input)
            else "\nTo allowlist a false positive: add to ~/.claude/sentinel-allowlist.json"
        )
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": (
                    f"SENTINEL BLOCKED [{tool_name}]: {reason}{hint}"
                ),
            }
        }))
    else:
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "additionalContext": (
                    f"⚠ [SENTINEL WARNING] {tool_name}: {reason}\n"
                    "Proceed only if this is expected. Add to allowlist to suppress."
                ),
            }
        }))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"SENTINEL BLOCKED (fail-closed): error interno del preflight: {e!r}", file=sys.stderr)
        sys.exit(2)
