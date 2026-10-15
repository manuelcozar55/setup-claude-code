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
# skipped, interpreter code is checked only in its string literals, quote forms
# and slashed runs, and every other word is checked by its path components against
# key_file_extensions. The body of a $( ) or backtick is read as a command of its
# own, whatever the role of the word around it; a heredoc body is data unless a
# shell or an interpreter on its line reads it. Whatever cannot be classified is
# checked: this guard may deny more, never less.
DEFAULT_KEY_EXTS = ["pem", "key", "p12", "pfx", "jks", "keystore"]
_BRACE_CAP, _BRACE_BUDGET = 64, 4096  # brace expansions per word / per whole command
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
    # ack's -C takes an optional number: listed, `ack -C BEGIN x.key` would skip the file.
    "ag": ("ABCGgmp", {"--ignore": 1, "--ignore-dir": 1, "--file-search-regex": 1, "--max-count": 1,
                       "--depth": 1, "--path-to-ignore": 1, "--pager": 1}, False, set()),
    "ack": ("ABgmt", {"--ignore-dir": 1, "--ignore-file": 1, "--type": 1, "--match": 1,
                      "--max-count": 1, "--files-from": 1, "--output": 1}, False, set()),
}
_OPTS["egrep"] = _OPTS["fgrep"] = _OPTS["grep"]
_GREP_NO_PATTERN = {"-e", "--regexp", "-f", "--file", "--files", "--type-list"}
_NO_PATTERN = {"grep": _GREP_NO_PATTERN, "egrep": _GREP_NO_PATTERN, "fgrep": _GREP_NO_PATTERN,
               "rg": _GREP_NO_PATTERN, "jq": {"-f", "--from-file"}, "ag": {"-g"},
               "ack": {"-f", "-g", "--match"}}
_SKIP_VALUE = {"grep": {"-e", "--regexp"}, "egrep": {"-e", "--regexp"}, "fgrep": {"-e", "--regexp"},
               "rg": {"-e", "--regexp"}, "ack": {"--match"}, "git-message": {"-m", "--message"}}
_CODE_VALUE = {"node": {"-e", "-p", "--eval", "--print"}, "perl": {"-e", "-E"},
               "ruby": {"-e"}, "python": {"-c"}}
_SHELLS, _EVALS = {"bash", "sh", "zsh", "dash", "ksh"}, {"eval", "source", "."}
_OPS = ("&&", "||", ";;", "|&", ">>", "<<<", "<<", "&>", ">&", "<&", ">|", "|", "&", ";", "(", ")",
        "<", ">")
_MASK = str.maketrans("{},", "\ue000\ue001\ue002")  # quoted braces do not expand
_UNMASK = str.maketrans("\ue000\ue001\ue002", "{},")
# {a,b} | {1..9[..2]} | {a..z[..2]}
_BRACE = re.compile(r"\{(?:([^{}]*,[^{}]*)|(-?\d+)\.\.(-?\d+)(?:\.\.(-?\d+))?"
                    r"|([A-Za-z])\.\.([A-Za-z])(?:\.\.(-?\d+))?)\}")
_QUOTED = re.compile(r"'[^']*'|\"(?:\\.|[^\"\\])*\"")
_BACKTICK_BODY = re.compile(r"(?:\\.|[^`\\])*")
# The delimiter must end the word: with `<<EOF.x` bash waits for an EOF.x line.
_HEREDOC_OP = re.compile(r"<<(-?)[ \t]*(['\"]?)(\\?)(\w+)\2(?=[\s;&|<>()]|$)")
# Interpreter code: perl/ruby quote forms (q() qq{} qw[] %q() %Q{} %w<> %() and / | delimiters).
_QUOTE_FORM = re.compile(r"(?:(?<![\w$@%&])q[qw]?\s*|%[qQwW]?)([(\[{<|/])")
_PAIRS = {"(": ")", "[": "]", "{": "}", "<": ">"}
_PATH_RUN = re.compile(r"[\w./~@%#+$*?{}\[\]-]+")
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
            docs.append(m.group(4))
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


def _heredoc_bodies(text: str, i: int, docs: list) -> int:
    """Fill the bodies of the heredocs opened on the line that ends at i; the index after them.
    Without its delimiter line a body stays None and the rest is lexed as commands."""
    for d in docs:
        tabs = "\\t*" if d["strip"] else ""
        end = re.compile(rf"^{tabs}{d['delim']}$", re.M).search(text, i)
        if not end:
            return i
        d["body"], i = text[i:end.start()], end.end()
    return i


def _lex(text: str, comments: bool = True) -> list:
    """Operators as str ("\\n" ends a line); words as (text, brace form, substitution
    bodies); heredocs as dict (quoted, strip, delim, body), where the << was.

    Quotes are dropped from the text; in the brace form quoted braces are masked,
    since bash does not expand them. A substitution leaves a "$" in the word and
    its body in the list, except $(cat <<'EOF' ...) whose output is the heredoc.
    comments: a # that starts a word comments to the end of the line, as in bash;
    off for a quoted string read again as a command, where it would hide a name."""
    toks, cur, subs, docs, i, n = [], None, [], [], 0, len(text)
    while i < n:
        c = text[i]
        if c == "#" and cur is None and comments:
            i = text.find("\n", i)
            i = n if i < 0 else i
            continue
        op = None if c in " \t\n" else next((o for o in _OPS if text.startswith(o, i)), None)
        if c in " \t\n" or op:
            if cur is not None:
                toks.append((cur.translate(_UNMASK), cur, subs))
                cur, subs = None, []
            m = _HEREDOC_OP.match(text, i) if op == "<<" else None
            if m:
                doc = {"quoted": bool(m.group(2) or m.group(3)), "strip": bool(m.group(1)),
                       "delim": m.group(4), "body": None}
                toks.append(doc)
                docs.append(doc)
                i = m.end()
                continue
            if op:
                toks.append(op)
            elif c == "\n":
                toks.append("\n")
                if docs:
                    i, docs = _heredoc_bodies(text, i + 1, docs), []
                    continue
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
    # Short flags too (ack -f): every letter of a cluster counts, which only denies more.
    seen = {o for _, o in parsed} | {"-" + ch for a, (kind, _) in zip(args, parsed)
                                     if kind != "pos" and not a[0].startswith("--") for ch in a[0][1:]}
    first = name in _NO_PATTERN and not seen & _NO_PATTERN[name]
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


def _cmd_name(word: str) -> str:
    base = os.path.basename(word).lower()
    return re.sub(r"[\d.]+$", "", base) or base


def _word_roles(toks: list) -> list:
    """(word, role) per word, role path, code or skip; and (heredoc, role) per body, role
    shell, code or data. A body is read by whatever its line runs, pipes and prefixes
    included (`cat <<EOF | sh`, `sudo bash <<EOF`): any shell or interpreter word on the
    line, or eval/source/. as a command, makes it commands or code."""
    out, cmd, redirect, docs, names = [], [], False, [], set()
    for t in toks + ["\n"]:
        if isinstance(t, dict):
            docs.append(t)
        elif isinstance(t, str) and ("<" in t or ">" in t):
            redirect = True
        elif isinstance(t, str):
            words = [w[0] for w in cmd if not re.match(r"\w+=", w[0])]
            names |= {_cmd_name(w) for w in words} | ({"eval"} if words and words[0] in _EVALS else set())
            out += _command_roles(cmd)
            cmd, redirect = [], False
            if t == "\n":
                kinds = (["shell"] if names & (_SHELLS | {"eval"}) else []) \
                    + (["code"] if names & _CODE_VALUE.keys() else [])
                out += [(d, k) for d in docs if d["body"] is not None for k in kinds or ["data"]]
                docs, names = [], set()
        elif redirect:
            out.append((t, "path"))
            redirect = False
        else:
            cmd.append(t)
    return out


def _alts(m) -> list[str] | None:
    """Distinct alternatives of one {a,b}, {1..9..2} or {a..z} group; None for a longer sequence."""
    if m.group(1) is not None:
        return list(dict.fromkeys(m.group(1).split(",")))
    num = m.group(2) is not None
    x, y, n = m.group(2, 3, 4) if num else m.group(5, 6, 7)
    a, b = (int(x), int(y)) if num else (ord(x), ord(y))
    step = abs(int(n or 1)) or 1
    if abs(b - a) // step + 1 > _BRACE_CAP:
        return None
    seq = range(a, b + 1, step) if a <= b else range(a, b - 1, -step)
    if not num:
        return [chr(v) for v in seq]
    pad = max(len(x), len(y)) if re.match(r"-?0\d", x) or re.match(r"-?0\d", y) else 0
    return [f"{v:0{pad}d}" for v in seq]


def _brace_expand(form: str) -> list[str] | None:
    """Distinct expansions of the unmasked brace groups, or None past the cap."""
    done, todo, seen = [], [form], {form}
    while todo:
        w = todo.pop()
        m = _BRACE.search(w)
        if not m:
            done.append(w)
            continue
        alts = _alts(m)
        if alts is None:
            return None
        for alt in alts:
            x = w[:m.start()] + alt + w[m.end():]
            if x not in seen:
                seen.add(x)
                todo.append(x)
        if len(seen) > 4 * _BRACE_CAP:
            return None
    return done if len(done) <= _BRACE_CAP else None


def _brace_linear(form: str) -> list[str] | None:
    """One group at a time, the others at their first alternative, level by level for nested
    groups: linear, not exhaustive. Nothing is cut off: past the caps, None."""
    out, todo = [], [form]
    while todo:
        w = todo.pop()
        groups = list(_BRACE.finditer(w))
        if not groups:
            out.append(w)
            continue
        alts = [_alts(g) for g in groups]
        if len(groups) > _BRACE_CAP or None in alts:
            return None
        for k in range(len(groups)):
            for alt in alts[k]:
                parts, last = [], 0
                for j, h in enumerate(groups):
                    parts += [w[last:h.start()], alt if j == k else alts[j][0]]
                    last = h.end()
                todo.append("".join(parts) + w[last:])
        if len(out) + len(todo) > _BRACE_BUDGET:
            return None
    return out


def _key_file_word(word: str, rx) -> bool:
    for piece in re.split(r"[\s=:,;|&()<>\"'`]+", word):
        for i, comp in enumerate(piece.split("/")):
            m = rx.fullmatch(comp)
            # A bare .key needs a slash before it (./.key): in prose or jq it is a field.
            if m and (_NAME_CHAR.search(m.group(1)) or (i > 0 and not m.group(1))):
                return True
    return False


def _code_strings(code: str) -> list[str]:
    """What interpreter code may name a file with: quoted literals, perl/ruby quote forms
    (nested brackets and escapes followed) and any run of path characters with a slash.
    A name without slash or quoting (o.key) is a property access and is not returned."""
    out = [s for lit in re.findall(r"'([^']*)'|\"([^\"]*)\"|`([^`]*)`", code) for s in lit if s]
    for m in _QUOTE_FORM.finditer(code):
        o = m.group(1)
        c, depth, i = _PAIRS.get(o, o), 1, m.end()
        while i < len(code):
            if code[i] == "\\":
                i += 2
                continue
            depth += (code[i] == o and o != c) - (code[i] == c)
            if depth == 0:
                break
            i += 1
        out.append(code[m.end():i])
    return out + [r for r in _PATH_RUN.findall(code) if "/" in r]


def _doc_subs(body: str) -> list[str]:
    """$( ) and backtick bodies of an unquoted heredoc: bash runs them, quotes or not."""
    out, i = [], 0
    while i < len(body):
        if body[i] == "\\":
            i += 2
        elif body.startswith("$(", i) or body[i] == "`":
            sub, i = _substitution(body, i)
            out.append(sub)
        else:
            i += 1
    return out


def _expanded_hit(form: str, rx, real: bool, budget: list) -> str | None:
    words = _brace_expand(form)
    if words is None and not real:
        words = _brace_linear(form)
    if words is None:
        return "brace expansion too large"
    if len(words) > 1:
        budget[0] += len(words)
        if budget[0] > _BRACE_BUDGET:
            return "brace expansion too large"
    return "key file name" if any(_key_file_word(w.translate(_UNMASK), rx) for w in words) else None


def key_file_hit(text: str, rx, real: bool = True, depth: int = 0, budget: list | None = None) -> str | None:
    """Why text names a key file, or None. real: text the shell runs as is (not a quoted
    string read again as a command), where an expansion past the cap denies; read again,
    the expansion goes group by group and only past that cap denies. budget: brace
    expansions spent by the whole command, substitutions and strings read again included."""
    budget = [0] if budget is None else budget
    if depth > 4:
        return "key file name" if _key_file_word(text, rx) else None
    for item, role in _word_roles(_lex(text, real)):
        reason = None
        if isinstance(item, dict):
            body, unquoted = item["body"], not item["quoted"]
            # Unquoted, bash joins a backslash-newline, also into the delimiter line.
            if role == "shell" or unquoted and "\\\n" in body:
                reason = key_file_hit(body, rx, real, depth + 1, budget)
            for s in (_doc_subs(body) if unquoted else []) + (_code_strings(body) if role == "code" else []):
                reason = reason or key_file_hit(s, rx, False, depth + 1, budget)
        else:
            word, form, subs = item
            for body in subs:
                reason = reason or key_file_hit(body, rx, real, depth + 1, budget)
            if role == "code":
                for s in _code_strings(word):
                    reason = reason or key_file_hit(s, rx, False, depth + 1, budget)
            elif role == "path" and _SHELL_META.search(word):
                reason = reason or key_file_hit(word, rx, False, depth + 1, budget)
            elif role == "path":
                reason = reason or _expanded_hit(form, rx, real, budget)
        if reason:
            return reason
    return None


# ── Checks ───────────────────────────────────────────────────────────────────

def check_sensitive_paths(tool_input: dict, iocs: dict, allowlist: dict):
    patterns = iocs.get("sensitive_paths", {}).get("patterns", [])
    regexes = iocs.get("sensitive_paths", {}).get("regex_patterns", [])
    allowed = (allowlist.get("paths") or []) + iocs.get("allowlist", {}).get("paths", [])
    # The extension regex left regex_patterns for this list: an iocs.json without it (older,
    # own, trimmed from the example) must not turn the check off, so the code has a default
    # and the deny reason says it was used. Entries are kept one by one (a null or "" drops
    # only itself, ".key" counts as "key"); the default only when none is left.
    raw = iocs.get("sensitive_paths", {}).get("key_file_extensions")
    exts = [e[1:] if e.startswith(".") else e for e in raw if isinstance(e, str)] if isinstance(raw, list) else []
    exts = [e.lower() for e in exts if e]
    key_rx = _key_file_rx(exts or DEFAULT_KEY_EXTS)
    key_note = "" if exts else " (default extensions: iocs.json has no valid key_file_extensions)"

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
