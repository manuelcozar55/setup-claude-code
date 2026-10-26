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
import signal
import sys
from datetime import datetime, timezone
from fnmatch import fnmatchcase
from pathlib import Path

# Contract with iocs.json ("min_preflight_version"): bump it when this code starts to rely on
# something the data file must carry, and doctor.sh warns when the installed code is older.
PREFLIGHT_VERSION = 2


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
    # A leading `.*` changes nothing for a search, but retried at every start it is quadratic:
    # `(?i).*_TOKEN$` took 10 s on one 64 KB word, past the hook timeout (which fails open).
    rx = re.sub(r"^((?:\(\?[a-z]+\))?)\.\*(?=.)", r"\1", rx)
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
    r"(?i)(?<![a-z0-9_-])\.aws[\"']?/(credentials|config)(?![a-z0-9])",
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
# glob/pattern/notebook_path/file/filename are what Grep, Glob, NotebookEdit and
# third-party tools name their path in; the alternative (scanning every string of
# tool_input) would read the content of every Write/Edit, which this guard avoids on
# purpose. Limit: a tool that calls its path something else is not seen.
PATH_FIELDS = ["file_path", "path", "paths", "notebook_path", "file", "filename", "glob", "pattern",
               "command", "url", "endpoint", "uri", "href", "target"]
# The fields that hold ONE path and nothing else: the only ones an allowlisted path may
# exempt. A command or URL is text, and its first word living under /tmp says nothing
# about the arguments that follow it.
EXEMPTABLE_FIELDS = {"file_path", "path", "paths", "notebook_path", "file", "filename", "glob", "pattern"}


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


def is_allowed_domain(url: str, allowed: list[str]) -> bool:
    """Match one URL on its parsed host, not a raw substring.

    'github.com.evil-phish.tk' no longer counts as allowlisted just because it
    contains the substring 'github.com'.
    """
    hosts = _url_hosts(url)
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


def without_allowed_urls(text: str, allowed: list[str]) -> str:
    """text with every allowlisted URL cut out, each URL judged on its own.

    An allowed host somewhere in a command (a comment, a second URL, a query value) used to
    exempt the whole command; now it exempts only its own URL, and the rest is still checked.
    A URL ends at whitespace, a quote or the next scheme, so one embedded in another's query
    is a URL of its own.
    """
    starts = [m.start() for m in re.finditer(r"https?://", text)]
    out, last = [], 0
    for i, st in enumerate(starts):
        end = starts[i + 1] if i + 1 < len(starts) else len(text)
        m = re.search(r"[\s\"'`<>)]", text[st:end])
        if m:
            end = st + m.start()
        if is_allowed_domain(text[st:end], allowed):
            out.append(text[last:st])
            last = end
    out.append(text[last:])
    return " ".join(out)


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


def collect_pairs(tool_input: dict, keys: list[str]) -> list[tuple[str, str]]:
    """(key, string) for specific top-level keys only, avoiding file content."""
    out = []
    for key in keys:
        val = tool_input.get(key)
        if val is not None:
            out.extend((key, t) for t in collect_strings(val))
    return out


def collect_fields(tool_input: dict, keys: list[str]) -> list[str]:
    """Extract strings from specific top-level keys only, avoiding file content."""
    return [t for _, t in collect_pairs(tool_input, keys)]


# ── Key files by name ────────────────────────────────────────────────────────
# A regex over the whole command cannot tell `cat .server.key` from the jq filter
# '.data.key', nor `cat x.key` from `grep "event.key"`: the difference is the
# role of the argument, not its text. So the command is lexed into shell words,
# the words that name no file (grep pattern, jq filter, commit message) are
# skipped, interpreter code is checked only in its string literals, quote forms
# and slashed runs, and every other word is checked by its path components against
# key_file_extensions. The body of a $( ) or backtick is read as a command of its
# own, whatever the role of the word around it; a heredoc body is read as commands
# unless the command that carries its << is a known data sink (code for an
# interpreter). Whatever cannot be classified is checked: this guard may deny more,
# never less.
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
# Who reads a heredoc body. Only these sinks make it data, and git, curl, wget, sed and awk only
# when their arguments say so (_stdin_role); interpreters read it as code (as commands if their
# inline code runs what it reads: perl -ne 'system $_'); anything else (ssh,
# sudo -s, fish, xargs, psql, unknown) as commands. psql, mysql and sqlite3 run shell escapes
# (\!, system, .shell) and mailx ~! ones, so they are not sinks.
_SINKS = {"cat", "tee", "head", "tail", "wc", "sort", "uniq", "tr", "cut", "sed", "awk", "grep", "egrep",
          "fgrep", "rg", "ag", "ack", "jq", "yq", "base64", "md5sum", "sha1sum", "sha224sum", "sha256sum",
          "sha384sum", "sha512sum", "gzip", "xz", "git", "curl", "wget", "man", "sponge"}
_GIT_SINKS = {"commit", "tag", "notes", "apply", "am"}
# curl reads data from stdin with @- (-d @-, -F f=@-) and -T -, wget with -i -. A config from
# stdin (-K -, --config -) wins: it may say upload-file = <key>.
_STDIN_DATA = {"curl": re.compile(r"@-$|^(?:-T|--upload-file)(?:\n|=)?-$", re.M),
               "wget": re.compile(r"^(?:-i|--input-file)(?:\n|=)?-$", re.M)}
_STDIN_CONFIG = re.compile(r"^(?:-K|--config)(?:\n|=)?-$", re.M)
# Inline code that runs what it reads (perl -ne 'system $_', open P,"|sh"): the body is commands.
# Any word with exec or spawn counts (os.execlpe, spawnle, execa, pcntl_exec) except the whole
# words of a closed list of prose (execution, executor, spawned...); other prose only denies more.
_RUNS_INPUT = re.compile(r"\b(?!(?:executions?|executors?|executables?|executed|executing|executives?"
                         r"|spawned|spawning|spawns)\b)\w*(?:exec|spawn)\w*"
                         r"|\b(?:eval|system2?|popen\w*|fork|subprocess|passthru|proc_open|qx"
                         r"|child_process|os\.execute|io\.popen|Deno\.(?:Command|run))\b|`|\bopen\b[^;]*\|"
                         r"|\|\s*['\"]?(?:sh|bash|zsh|dash)\b")
# Inline code options per interpreter (deno: what follows eval, or repl --eval); one without a table has all its
# arguments checked.
_INLINE = {**{n: (_OPTS[n], _CODE_VALUE[n]) for n in ("python", "node", "perl", "ruby")},
           "php": (("r", {}, True, set()), {"-r"}), "lua": (("el", {}, True, set()), {"-e"}),
           "rscript": (("e", {}, True, set()), {"-e"}),
           "bun": (("ep", {"--eval": 1, "--print": 1}, True, set()), {"-e", "-p", "--eval", "--print"})}
_DENO_SUBS = {"run", "eval", "repl", "test", "bench", "compile", "bundle", "cache", "check", "doc", "fmt", "lint",
              "info", "install", "uninstall", "upgrade", "task", "types", "vendor", "publish", "add", "remove",
              "init", "jupyter", "serve", "coverage", "completions"}
# What runs a program or a file (_executes): these commands, find/fd with their exec options
# (also attached: fd -xsh, --exec=sh, and in a cluster: fd -Hx), and a command word with a slash
# outside the system's binary directories unless its basename is a known tool in _TOOL_DIRS.
_EXECUTORS = {"bash", "sh", "zsh", "dash", "ksh", "fish", "source", ".", "eval", "chmod", "xargs", "su"}
_EXEC_FLAGS = {"find": {"-exec", "-execdir", "-ok", "-okdir"},
               "fd": {"-x", "--exec", "-X", "--exec-batch"}, "fdfind": {"-x", "--exec", "-X", "--exec-batch"}}
# fd's short cluster: an x or X before the first letter that takes a value (-ex is -e x; digits
# take none: -1Hx).
_FD_EXEC = re.compile(r"-[^\W_deEtSocjxX]*[xX]")
_BIN_DIRS = {"/bin/", "/sbin/", "/usr/bin/", "/usr/sbin/"}
# Where a known tool is not an executor: absolute directories of a closed list (./bin/git, ~/bin/git
# or node_modules/.bin/x may have been written by the heredoc). Declared limit: on macOS
# /usr/local/bin and /opt/homebrew/bin belong to the user, so a heredoc that writes a known tool
# there and runs it in the same order (cat <<EOF >/opt/homebrew/bin/git; /opt/homebrew/bin/git) is
# not seen; on Linux those directories need root. Linuxbrew's bin is left out: kit/scan-secrets.sh
# reads its path as a personal home, so it denies more.
_TOOL_DIRS = _BIN_DIRS | {"/usr/local/bin/", "/usr/local/sbin/", "/opt/homebrew/bin/", "/opt/homebrew/sbin/",
                          "/opt/local/bin/", "/snap/bin/"}
_INTERPRETERS = {"python", "node", "deno", "bun", "perl", "ruby", "php", "lua", "rscript"}
_RUNNERS = _EXECUTORS | _INTERPRETERS
# Tools that do not run their argument: /usr/local/bin/git counts as the bare word (_TOOL_DIRS).
_KNOWN_TOOLS = _SINKS | {"grep", "rg", "ag", "ack", "jq", "git", "gh", "pnpm", "npm", "npx", "yarn", "corepack",
                         "cargo", "go", "pip", "pip3", "docker", "podman", "kubectl", "code", "cursor", "yq",
                         "curl", "wget", "rsync", "tar", "gzip", "zip", "unzip", "ls", "cp", "mv", "mkdir",
                         "touch", "echo", "printf", "sort", "head", "tail", "wc", "diff", "patch", "make", "cmake",
                         "tsc", "prettier", "eslint", "shellcheck", "gitleaks", "claude"}
# Prefixes that run the next word: short options and long options that take a value.
_PREFIXES = {"sudo": ("ugpChDRrTU", {"--user", "--group", "--host", "--prompt", "--chdir", "--role",
                                     "--type", "--other-user", "--close-from", "--command-timeout"}),
             "env": ("uCS", {"--unset", "--chdir", "--split-string"}), "nice": ("n", {"--adjustment"}),
             "time": ("fo", {"--format", "--output"}), "command": ("", set()), "exec": ("a", set()),
             "timeout": ("sk", {"--signal", "--kill-after"}), "flock": ("wEc", {"--wait", "--timeout",
             "--conflict-exit-code", "--command"}), "stdbuf": ("ioe", {"--input", "--output", "--error"}),
             "busybox": ("", set()), "nohup": ("", set()), "setsid": ("", set()),
             "ionice": ("cnp", {"--class", "--classdata", "--pid"}), "chroot": ("", {"--userspec", "--groups"}),
             "unshare": ("RwSG", {"--root", "--wd", "--setuid", "--setgid", "--map-user", "--map-group",
             "--propagation", "--setgroups", "--monotonic", "--boottime", "--map-users", "--map-groups"}),
             "strace": ("abeEIoOpPsSuX", set()), "ltrace": ("aeEFlnopsuwx", set()),
             "watch": ("n", {"--interval"}), "doas": ("uC", set()), "chrt": ("TPD", set()),
             "taskset": ("", set()),
             "setpriv": ("", {"--reuid", "--regid", "--euid", "--egid", "--ruid", "--rgid", "--groups",
                              "--inh-caps", "--ambient-caps", "--bounding-set", "--securebits", "--pdeathsig",
                              "--selinux-label", "--apparmor-profile", "--landlock-access", "--landlock-rule",
                              "--seccomp-filter"}),
             # The namespace flags (-m -u -i -n -p -C -U -T) and -w/-r take a value only with =.
             "nsenter": ("tSG", {"--target", "--setuid", "--setgid"})}
# Prefixes with positional arguments before the command, options around them: timeout 5 cmd,
# flock lockfile -c cmd.
_PREFIX_ARGS = {"timeout": 1, "flock": 1, "chroot": 1, "taskset": 1, "chrt": 1}
# Whether each prefix of _PREFIXES left without command runs something: True if it opens a shell
# by design (chroot, unshare and nsenter run $SHELL; exec with only redirections hands its stdin to
# the rest of the call), False if not (timeout 5, flock -n 9), or the short letters, also inside a
# cluster, and long options that open one (sudo/doas -s, -i) or carry the command in a value
# (flock -c, env -S). Every prefix is declared (test_guards checks it); an undeclared one is a shell.
_BARE_SHELL = {"sudo": ("si", {"--shell", "--login"}), "doas": ("si", {"--shell", "--login"}),
               "flock": ("c", {"--command"}), "env": ("S", {"--split-string"}),
               "chroot": True, "unshare": True, "nsenter": True, "exec": True,
               **dict.fromkeys(("nice", "time", "command", "timeout", "stdbuf", "busybox", "nohup", "setsid",
                                "ionice", "strace", "ltrace", "watch", "chrt", "taskset", "setpriv"), False)}
_KEYWORDS = {"!", "{", "if", "then", "else", "elif", "while", "until", "do"}
_OPENERS, _CLOSERS = {"{", "if", "while", "until", "for", "case", "select"}, {"}", "fi", "done", "esac"}
_NO_STDIN = _CLOSERS | {"for", "case", "select", "function"}
_RANK = {None: 0, "data": 0, "code": 1, "qcode": 2, "shell": 3}  # qcode also sees q() forms
_OPS =("&&", "||", ";;", "|&", ">>", "<<<", "<<", "&>", ">&", "<&", ">|", "|", "&", ";", "(", ")",
        "<", ">")
_MASK = str.maketrans("{},", "\ue000\ue001\ue002")  # quoted braces do not expand
_UNMASK = str.maketrans("\ue000\ue001\ue002", "{},")
# {a,b} | {1..9[..2]} | {a..z[..2]}
_BRACE = re.compile(r"\{(?:([^{}]*,[^{}]*)|(-?\d+)\.\.(-?\d+)(?:\.\.(-?\d+))?"
                    r"|([A-Za-z])\.\.([A-Za-z])(?:\.\.(-?\d+))?)\}")
_QUOTED = re.compile(r"'[^']*'|\"(?:\\.|[^\"\\])*\"")
_BACKTICK_BODY = re.compile(r"(?:\\.|[^`\\])*")
_PLAIN = re.compile(r"[^ \t\n&|;()<>'\"\\`$]+")  # unquoted characters the word keeps as they are
# The delimiter must end the word: with `<<EOF.x` bash waits for an EOF.x line.
_HEREDOC_OP = re.compile(r"<<(-?)[ \t]*(['\"]?)(\\?)(\w+)\2(?=[\s;&|<>()]|$)")
# Interpreter code: quote forms %q() %Q{} %w<> %i[] %x() with () {} [] <> / | delimiters, the
# letter required (in python a %( is a modulo); only in perl/ruby, q() qq{} qw[] qx() after a
# start, space, bracket, comma or operator, and ruby's bare %() glued to its delimiter.
_QUOTE_FORM = re.compile(r"%[qQwWiIx]([(\[{<|/])")
_PERL_QUOTE = re.compile(r"(?:(?:^|(?<=[\s(,=!~<>|+*/^?:;.{\[-]))q[qwx]?\s*|%)([(\[{<|/])")
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


def _joined_delim(text: str, i: int, d: dict) -> tuple[int, int] | None:
    """Span of the delimiter line of an unquoted heredoc, whose lines bash joins at a
    backslash-newline before comparing (EO\\ + newline + F ends an EOF heredoc)."""
    start, parts, n = i, [], len(text)
    while True:
        e = text.find("\n", i)
        e = n if e < 0 else e
        seg = text[i:e]
        if e < n and (len(seg) - len(seg.rstrip("\\"))) % 2:
            parts.append(seg[:-1])
            i = e + 1
            continue
        line = "".join(parts) + seg
        if (line.lstrip("\t") if d["strip"] else line) == d["delim"]:
            return start, e
        if e >= n:
            return None
        start, parts, i = e + 1, [], e + 1


def _heredoc_bodies(text: str, i: int, docs: list) -> int:
    """Fill the bodies of the heredocs opened on the line that ends at i; the index after them.
    Without its delimiter line a body stays None and the rest is lexed as commands. The join
    of a backslash-newline only finds the delimiter: the body keeps the role of its reader."""
    for d in docs:
        tabs = "\\t*" if d["strip"] else ""
        end = re.compile(rf"^{tabs}{d['delim']}$", re.M).search(text, i)
        span = end.span() if end else None
        if not d["quoted"] and "\\\n" in text[i:span[0] if span else len(text)]:
            span = _joined_delim(text, i, d)
        if not span:
            return i
        d["body"], i = text[i:span[0]], span[1]
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
        op = next((o for o in _OPS if text.startswith(o, i)), None) if c in "&|;()<>" else None
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
        elif m := _PLAIN.match(text, i):
            cur, i = cur + m.group(), m.end()
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
    """(word, role) for one simple command; role is path, code (qcode in perl/ruby) or skip."""
    roles = []
    while cmd and re.match(r"\w+=", cmd[0][0]):
        roles.append((cmd.pop(0), "path"))
    if not cmd:
        return roles
    name = _cmd_name(cmd[0][0])
    roles.append((cmd[0], "path"))
    args = cmd[1:]
    if name == "git" and args and args[0][0] in ("grep", "commit", "tag", "merge"):
        name = "grep" if args[0][0] == "grep" else "git-message"
        roles.append((args.pop(0), "path"))
    if name not in _OPTS:
        return roles + [(a, "path") for a in args]
    parsed = _parse([a[0] for a in args], *_OPTS[name])
    # Short flags too (ack -f): every letter of a short-option word counts, an attached value
    # included (rg -tf), which only denies more; a value in a word of its own (-t golang) does not.
    seen = {o for _, o in parsed} | {"-" + ch for a, (kind, _) in zip(args, parsed)
                                     if kind in ("opt", "optval") and not a[0].startswith("--")
                                     for ch in a[0][1:]}
    first = name in _NO_PATTERN and not seen & _NO_PATTERN[name]
    for a, (kind, opt) in zip(args, parsed):
        role = "path"
        if kind in ("val", "optval") and opt in _SKIP_VALUE.get(name, ()):
            role = "skip"
        elif kind in ("val", "optval") and opt in _CODE_VALUE.get(name, ()):
            role = "qcode" if name in ("perl", "ruby") else "code"
        elif kind == "pos" and first:
            role, first = "skip", False
        roles.append((a, role))
    return roles


def _cmd_name(word: str) -> str:
    """Command name without directory, case and trailing version: python3.12 is python."""
    base = os.path.basename(word).lower()
    name = re.sub(r"[\d.]+$", "", base) or base
    return "node" if name == "nodejs" else name


def _command_word(words: list[str]) -> tuple[int, bool]:
    """Index of the command word past assignments, keywords and prefixes with their options
    (len(words) if none), and whether a skipped prefix runs a shell or a command of its own
    without a command word (_BARE_SHELL)."""
    i, n, shell = 0, len(words), False
    while i < n and (words[i] in _KEYWORDS or re.match(r"\w+=", words[i])):
        i += 1
    while i < n and _cmd_name(words[i]) in _PREFIXES:
        name = _cmd_name(words[i])
        short, long = _PREFIXES[name]
        bare = _BARE_SHELL.get(name, True)
        sh_short, sh_long = bare if isinstance(bare, tuple) else ("", set())
        i, pos = i + 1, _PREFIX_ARGS.get(name, 0)
        shell = shell or bare is True
        while i < n and (re.match(r"\w+=", words[i]) or words[i].startswith("-") and words[i] != "-" or pos):
            w, i = words[i], i + 1
            if w == "--":
                i += pos
                break
            if w.startswith("--"):
                i += "=" not in w and w in long
                shell = shell or w.partition("=")[0] in sh_long
            elif w.startswith("-") and w != "-":
                # Letters up to the first that takes a value; with = the value is attached.
                j = next((j for j, ch in enumerate(w[1:], 1) if ch in short), len(w) - 1)
                i += "=" not in w and j == len(w) - 1 and w[j] in short
                shell = shell or any(ch in sh_short for ch in w[1:j + 1])
            elif not re.match(r"\w+=", w):
                pos -= 1
    return min(i, n), shell


def _program(args: list[str]) -> str:
    """The sed/awk/yq program in its arguments, also attached to its option: -e1e,
    --expression=e, --source='{...}'."""
    return "\n".join(a.partition("=")[2] if a.startswith("--") else a.partition("e")[2]
                     if a.startswith("-") else a for a in args)


def _stdin_role(words: list[str]) -> str | None:
    """How a simple command reads its stdin: data (a known sink), code or qcode (an
    interpreter), shell (anything else, also a prefix left without command that opens a shell:
    sudo -s). None without a command word."""
    i, shell = _command_word(words)
    if i >= len(words):
        return "shell" if shell else None
    base, name, args = os.path.basename(words[i]).lower(), _cmd_name(words[i]), words[i + 1:]
    if name in _NO_STDIN:
        return None
    if name in _INTERPRETERS:
        if name == "python" and args[:2] == ["-m", "json.tool"]:
            return "data"
        inline = args
        if name == "deno":
            # The subcommand is the first word of _DENO_SUBS that is not the value of -L/--log-level
            # (deno run eval runs a script; other words before it are flag values); without one, all
            # the arguments are inline code. deno eval and repl --eval take inline code; deno run -
            # and eval - read it from stdin.
            sub = next((k for k, a in enumerate(args) if a in _DENO_SUBS
                        and args[k - 1:k] not in (["-L"], ["--log-level"])), None)
            what, rest = (args[sub:sub + 1], args[sub + 1:]) if sub is not None else ([], args)
            inline = args if sub is None else []
            if what == ["eval"]:
                inline = rest
            elif what == ["repl"]:
                inline = [a[7:] if a.startswith("--eval=") else b for a, b in zip(rest, rest[1:] + [""])
                          if a == "--eval" or a.startswith("--eval=")]
        elif name in _INLINE:
            (short, long, stop, ends), values = _INLINE[name]
            inline = [a for a, (kind, opt) in zip(args, _parse(args, short, long, stop, ends))
                      if kind in ("val", "optval") and opt in values]
        if _RUNS_INPUT.search("\n".join(inline)):
            return "shell"
        return "qcode" if name in ("perl", "ruby") else "code"
    prog = _program(args)
    runs = (base not in _SINKS and name not in _SINKS
            or name == "git" and (not args or args[0] not in _GIT_SINKS)
            or name in _STDIN_DATA and (not _STDIN_DATA[name].search("\n".join(args))
                                        or _STDIN_CONFIG.search("\n".join(args)))
            # Their program is an argument, unless -f reads it from the heredoc; awk's
            # system/getline/| and sed's e command or s///e flag run what they read.
            or name in ("sed", "awk") and any(re.match(r"-[^-]*f|--file", a) for a in args)
            or name == "awk" and re.search(r"system|getline|\|", prog)
            or name == "sed" and re.search(r"e[gpiImMw\d]*(?:$|[\s;}])", prog, re.M)
            or name == "yq" and "load" in prog)
    return "shell" if runs else "data"


def _simple_commands(toks: list) -> list:
    """The words of each simple command of lexed text, without redirection targets."""
    out, cmd, redirect = [], [], False
    for t in toks:
        if isinstance(t, str):
            redirect = "<" in t or ">" in t
            if not redirect:
                out.append(cmd)
                cmd = []
        elif isinstance(t, tuple) and not redirect:
            cmd.append(t)
        elif isinstance(t, tuple):
            redirect = False
    return out + [cmd]


def _executes(cmd: list, depth: int = 0) -> bool:
    """Whether a simple command (lexed words) runs a program or a file: a shell, an
    interpreter, source, eval, chmod, xargs, su, find/fd with -exec/-x (fd -Hx too), a command
    word with a slash outside _BIN_DIRS (./run.sh, /usr/local/bin/x) unless its basename is in
    _KNOWN_TOOLS and its directory, absolute, in _TOOL_DIRS (/usr/local/bin/git; not ./bin/git),
    or a prefix without command that opens a shell or carries one (sudo -s, chroot /, unshare -r,
    flock -c cmd lockfile, env -S cmd; not timeout 5 or flock -n 9); also inside its $( ) and
    backtick bodies. A later executor makes a heredoc commands in any line of the call: the
    declared cost of not following file names (_word_roles)."""
    words = [w[0] for w in cmd]
    i, shell = _command_word(words)
    if i >= len(words):
        runs = shell
    else:
        w, name = words[i], _cmd_name(words[i])
        flags = _EXEC_FLAGS.get(name, set())
        tool = name in _KNOWN_TOOLS and w.startswith("/") and os.path.dirname(w) + "/" in _TOOL_DIRS
        runs = (name in _RUNNERS or any(a.partition("=")[0] in flags or a[:2] in flags and a[1] != "-"
                                        or name in ("fd", "fdfind") and _FD_EXEC.match(a)
                                        for a in words[i + 1:])
                or "/" in w and os.path.dirname(w) + "/" not in _BIN_DIRS and not tool)
    if runs:
        return True
    return depth < 4 and any(_executes(c, depth + 1) for w in cmd for body in w[2]
                             for c in _simple_commands(_lex(body)))


def _word_roles(toks: list, sink: str = "data") -> list:
    """(word, role) per word, role path, code, qcode or skip; and (heredoc, role) per body,
    role shell, code, qcode or data. A body is read by the command that carries its <<
    (_stdin_role) and by the rest of its pipeline: the worst of them counts, and if all
    are sinks, sink (what reads the output: the role of the word around a $( )). Inside a
    group, loop or condition, on its closing word, or with a group down its pipeline, the
    worst reader of the whole text counts: the output may go anywhere. Any executor
    (_executes) after its pipeline makes the body commands, whether its readers wrote a file
    or not: writers and names are not followed."""
    out, cmd, redirect, docs, stages, cmds = [], [], False, [], [], []
    pipe, pdepth, kdepth, closed, prev = 0, 0, 0, False, None
    for t in toks + ["\n"]:
        if isinstance(t, dict):
            docs.append((t, len(stages)))
        elif isinstance(t, str) and ("<" in t or ">" in t):
            redirect = True
        elif isinstance(t, str):
            words = [w[0] for w in cmd if not re.match(r"\w+=", w[0]) and w[0] != "!"]
            first = words[0] if words else ""
            group = pdepth or kdepth or closed or first in _OPENERS | _CLOSERS
            stages.append((_stdin_role([w[0] for w in cmd]), pipe, bool(group)))
            cmds.append(cmd)
            kdepth = max(0, kdepth + (first in _OPENERS) - (first in _CLOSERS))
            pdepth = max(0, pdepth + (t == "(") - (t == ")"))
            closed = t == ")"
            # A newline after | (the heredoc body comes in between) does not end the pipeline.
            if t == "\n" and prev in ("|", "|&"):
                t = prev
            pipe += t not in ("|", "|&", "(", ")")
            out += _command_roles(cmd)
            cmd, redirect, prev = [], False, t
        elif redirect:
            out.append((t, "path"))
            redirect = False
        else:
            cmd.append(t)
    worst = max((s[0] for s in stages), key=_RANK.get, default=None)
    execs = None
    for doc, k in docs:
        if doc["body"] is None:
            continue
        line = stages[k][1]
        pipeline = [j for j in range(k, len(stages)) if stages[j][1] == line]
        role = worst if any(stages[j][2] for j in pipeline) else max(
            (stages[j][0] for j in pipeline), key=_RANK.get)
        execs = execs if execs is not None else [_executes(c) for c in cmds]
        role = "shell" if any(execs[pipeline[-1] + 1:]) else role
        out.append((doc, role if _RANK[role] else sink))
    return out


def _alts(m) -> list[str]:
    """Distinct alternatives of one {a,b} or {a..z} group. A numeric sequence brings no letter,
    so it cannot form an extension: its first value stands for all of them, outside the caps."""
    if m.group(1) is not None:
        return list(dict.fromkeys(m.group(1).split(",")))
    if m.group(2) is not None:
        return [m.group(2)]
    a, b = ord(m.group(5)), ord(m.group(6))
    step = abs(int(m.group(7) or 1)) or 1
    return [chr(v) for v in (range(a, b + 1, step) if a <= b else range(a, b - 1, -step))]


def _brace_expand(form: str) -> list[str] | None:
    """Distinct expansions of the unmasked brace groups, or None past the cap."""
    done, todo, seen = [], [form], {form}
    while todo:
        w = todo.pop()
        m = _BRACE.search(w)
        if not m:
            done.append(w)
            continue
        for alt in _alts(m):
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
        if len(groups) > _BRACE_CAP:
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


# A word that names a .env file: .env, .envrc, .env.local... (not the template variants), also
# glued to a redirection or a curl upload (@.env). The raw-text regex of iocs.json only sees one
# behind a slash, so `cat .env` (a space before it) went through; the lexer sees the word.
_ENV_FILE = re.compile(r"(?i)@?\.env(?:rc|\.(?!(?:example|template|sample|dist)(?:$|[~#+.*?\[{-]))[a-z0-9_*?\[{-][^/]*)?(?:[~#+-].*|\.(?:bak|old|orig|backup|save|swp|tmp|copy|prev))?")


def _key_file_word(word: str, rx) -> bool:
    if "." not in word:  # every name with an extension has one, after expansion too
        return False
    for piece in re.split(r"[\s=:,;|&()<>\"'`]+", word):
        for i, comp in enumerate(piece.split("/")):
            if _ENV_FILE.fullmatch(comp):
                return True
            m = rx.fullmatch(comp)
            # A bare .key needs a slash before it (./.key): in prose or jq it is a field.
            if m and (_NAME_CHAR.search(m.group(1)) or (i > 0 and not m.group(1))):
                return True
    return False


def _code_strings(code: str, perl: bool = False) -> list[str]:
    """What interpreter code may name a file with, each text once: quoted literals, quote
    forms (nested brackets and escapes followed; one never closed is dropped, not swallowed)
    and the last component of any run of path characters with a slash (opts.key/2 divides).
    A name without slash or quoting (o.key) is a property access and is not returned."""
    out = [s for lit in re.findall(r"'([^']*)'|\"([^\"]*)\"|`([^`]*)`", code) for s in lit if s]
    for m in list(_QUOTE_FORM.finditer(code)) + (list(_PERL_QUOTE.finditer(code)) if perl else []):
        o = m.group(1)
        c, depth, i = _PAIRS.get(o, o), 1, m.end()
        while i < len(code):
            if code[i] == "\\":
                i += 2
                continue
            depth += (code[i] == o and o != c) - (code[i] == c)
            if depth == 0:
                out.append(code[m.end():i])
                break
            i += 1
    out += [r if r.startswith(("/", "./", "../", "~/")) else r.rsplit("/", 1)[1]
            for r in _PATH_RUN.findall(code) if "/" in r]
    return list(dict.fromkeys(s for s in out if s))


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


def _expanded_hit(form: str, rx, real: bool, budget: list, code: bool) -> str | None:
    words = _brace_expand(form)
    if words is None and not real:
        words = _brace_linear(form)
    if words is not None and len(words) > 1:
        budget[0] += len(words)
        words = words if budget[0] <= _BRACE_BUDGET else None
    if words is None and code:
        words = [form]  # a code literal past the caps is checked as written, not expanded
    if words is None:
        return "brace expansion too large"
    return "key file name" if any(_key_file_word(w.translate(_UNMASK), rx) for w in words) else None


def key_file_hit(text: str, rx, real: bool = True, depth: int = 0, budget: list | None = None,
                 code: bool = False, sink: str = "data") -> str | None:
    """Why text names a key file, or None. real: text the shell runs as is (not a quoted
    string read again as a command), where an expansion past the cap denies; read again,
    the expansion goes group by group and only past that cap denies. budget: brace
    expansions spent by the whole command, substitutions and strings read again included.
    code: text from an interpreter's literals, checked unexpanded past the caps. sink: who
    reads the output of a heredoc that only goes through data sinks (_word_roles)."""
    budget = [0] if budget is None else budget
    if depth > 4:
        return "key file name" if _key_file_word(text, rx) else None
    for item, role in _word_roles(_lex(text, real), sink):
        reason = None
        if isinstance(item, dict):
            body, unquoted = item["body"], not item["quoted"]
            if role == "shell":
                reason = key_file_hit(body, rx, real, depth + 1, budget, code)
            for s in _doc_subs(body) if unquoted else []:
                reason = reason or key_file_hit(s, rx, False, depth + 1, budget, code, role)
            for s in _code_strings(body, role == "qcode") if role in ("code", "qcode") else []:
                reason = reason or key_file_hit(s, rx, False, depth + 1, budget, True)
        else:
            word, form, subs = item
            for body in subs:
                # The output lands in this word: a skipped one is data, any other is read.
                out_role = "data" if role == "skip" else role if role in ("code", "qcode") else "shell"
                reason = reason or key_file_hit(body, rx, real, depth + 1, budget, code, out_role)
            if role in ("code", "qcode"):
                for s in _code_strings(word, role == "qcode"):
                    reason = reason or key_file_hit(s, rx, False, depth + 1, budget, True)
            elif role == "path" and _SHELL_META.search(word):
                reason = reason or key_file_hit(word, rx, False, depth + 1, budget, code)
            elif role == "path":
                reason = reason or _expanded_hit(form, rx, real, budget, code)
        if reason:
            return reason
    return None


# ── Checks ───────────────────────────────────────────────────────────────────

_WORD_RUN = re.compile(r"[^\s'\"`;&|<>():=]+")
_WILD_ONLY = re.compile(r"\.?[*?]+")
_GENERIC_BASENAMES = {"config", "known_hosts"}


def _path_forms(text: str, is_path: bool) -> dict[str, bool]:
    """The text itself and every shell word in it, brace groups expanded, normalized; each
    with whether it is a whole path (a path field, or a word with a slash) and not a bare word."""
    words = {text: is_path}
    for w in _WORD_RUN.findall(text):
        for x in (_brace_expand(w) or [w]) if "{" in w else [w]:
            words[x] = words.get(x, False) or "/" in x
    out: dict[str, bool] = {}
    for w, whole in words.items():
        if w:
            f = os.path.normpath(expand(w))
            out[f] = out.get(f, False) or whole
    return out


def _comp_match(tc: str, pc: str, inside_dotdir: bool) -> bool:
    """One component of a glob against one of a path, as the shell reads it: a wildcard never
    matches a leading dot, and a bare * or ? names nothing in particular unless it is the
    file level of a dot directory (~/.aws/* reads credentials; /etc/* or ~/.config/* are listings)."""
    if pc.startswith(".") and not tc.startswith("."):
        return False
    if _WILD_ONLY.fullmatch(tc):
        return inside_dotdir
    return fnmatchcase(pc, tc)


def _glob_reaches(glob: str, path: str) -> bool:
    """Does the glob name path, or something inside it, or a parent of it (an ancestor glob
    reads the path too)? Components are compared up to the shorter of the two."""
    gc, pc = glob.strip("/").split("/"), path.strip("/").split("/")
    n = min(len(gc), len(pc))
    return n > 0 and all(_comp_match(gc[i], pc[i], i == len(pc) - 1 and i > 0 and pc[i - 1].startswith(".")) for i in range(n))


def _sensitive_path_hit(text: str, patterns: list[str], is_path: bool) -> str | None:
    """The sensitive_paths pattern that text reaches once normalized ('..', '~', $HOME), as a
    glob (~/.s*/id_rsa, **/.ssh/*) or by the base name of a credential file (id_ed25519).
    The base name alone counts only for a whole path: as a bare word of a command it is as
    often prose (a commit message, a grep pattern)."""
    home = os.path.expanduser("~").rstrip("/")
    pats = [(p, os.path.normpath(expand(p))) for p in patterns if isinstance(p, str) and p.strip()]
    bases = {os.path.basename(pn) for _, pn in pats
             if os.path.basename(os.path.dirname(pn)) == ".ssh" and os.path.basename(pn) not in _GENERIC_BASENAMES}
    for form, whole in _path_forms(text, is_path).items():
        for p, pn in pats:
            if pn and pn != "." and pn in form:
                return p
        if re.search(r"[*?\[]", form):
            rel = form.lstrip("/") if not form.startswith("/") else None
            while rel and re.fullmatch(r"\*+", rel.split("/")[0]):
                rel = rel.partition("/")[2]
            for p, pn in pats:
                if form.startswith("/") and _glob_reaches(form, pn):
                    return p
                if rel and "/" in rel and home and pn.startswith(home + "/") and _glob_reaches(rel, pn[len(home) + 1:]):
                    return p
        base = os.path.basename(form)
        lit = re.split(r"[*?\[]", base)[0]
        if whole and (base in bases or (lit != base and len(lit) >= 2 and any(fnmatchcase(b, base) for b in bases))):
            return form
    return None


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

    for key, text in collect_pairs(tool_input, PATH_FIELDS):
        for rx in ALWAYS_DENY_PATHS:
            m = re.search(rx, text)
            if m:
                return (f"never-exempt credential material: {m.group(0)}", "critical")
        # The allowlist may not exempt the guards or their config, and only a field that is a
        # path can be exempted: never a command, whatever its first word is.
        if key in EXEMPTABLE_FIELDS and not protected_config_hit({"path": text}) and is_allowed_path(text, allowed):
            continue
        for p in patterns:
            if path_matches(text, p):
                return (f"sensitive path: {p}", "critical")
        hit = _sensitive_path_hit(text, patterns, key in EXEMPTABLE_FIELDS)
        if hit:
            return (f"sensitive path: {hit}", "critical")
        for rx in regexes:
            if _search(rx, text):
                return (f"sensitive path pattern", "critical")
        key_reason = key_file_hit(text, key_rx)
        if key_reason:
            return (f"sensitive {key_reason}{key_note}", "critical")
    return (None, None)


_ENV_REF = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)")
_PRINTENV = re.compile(r"\bprintenv\b((?:[ \t]+[^\s;&|<>()]+)*)")
_ENV_WORD = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def _env_read(text: str) -> set[str]:
    """Names of the variables the command reads: $X, ${X...} and the operands of printenv."""
    names = set(_ENV_REF.findall(text))
    for m in _PRINTENV.finditer(text):
        names.update(w.strip("'\"") for w in m.group(1).split() if not w.startswith("-"))
    return names


def check_sensitive_env(tool_input: dict, iocs: dict, allowlist: dict):
    patterns = iocs.get("sensitive_env_vars", {}).get("patterns", [])
    regexes = iocs.get("sensitive_env_vars", {}).get("regex_patterns", [])
    allowed_vars = (allowlist.get("env_vars") or []) + iocs.get("allowlist", {}).get("env_vars", [])

    def sensitive(name: str) -> bool:
        return name not in allowed_vars and (name in patterns or any(_search(rx, name) for rx in regexes))

    for text in collect_fields(tool_input, ["command", "url"]):
        # The regexes judge one NAME at a time: matched against the whole command, an
        # end anchor ('_TOKEN$') only ever saw the last word of it.
        for name in sorted(_env_read(text)):
            if sensitive(name):
                return (f"sensitive env var read: {name}", "high")
        # Only named (a commit message, an assignment): not a read, so a warning.
        for var in patterns:
            if var in allowed_vars:
                continue
            if re.search(rf"\b{re.escape(var)}\b", text):
                return (f"sensitive env var: {var}", "medium")
        if any(sensitive(w) for w in _ENV_WORD.findall(text)):
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

        text = without_allowed_urls(text, allowed_domains)

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


# ── K1 narrow exception: download piped to a data-only reader ───────────────────
# The one relaxation over main's behaviour. A `curl`/`wget` whose output feeds, through a
# single pipe, a reader that only *consumes* the bytes as data is allowed: a Python
# interpreter that carries its own program in `-c`, `python -m json.tool`, or `jq`. Nothing
# that executes the download runs. Every condition fails CLOSED (deny): if the shape is not
# exactly one of these, main's block stands. This is the companion of the same logic in
# block-dangerous-commands.sh (`fetch_safe_reader`); both must decide alike.

# Names the `-c` program may use outside its string literals: read JSON from stdin, filter it,
# print it. An ALLOW list on purpose: Python reaches code execution through too many doors
# (exec, pdb, code, timeit, `sys._getframe`, `operator.attrgetter`...) to shut them one by one.
# Any one-letter name and plain integers are fine too. None of these turns text into code, so
# what is inside the string literals does not count. Same list as PYC_NAMES in the bash guard.
_PYC_NAMES = frozenset("""
    import from as for in if else elif and or not is None True False lambda
    json sys stdin load loads dumps read readlines get keys values items
    print sep end len sorted reversed str int float bool list dict set tuple min max sum any all
    enumerate range zip round abs isinstance map filter
    strip lstrip rstrip split splitlines join lower upper replace startswith endswith append
    indent sort_keys ensure_ascii key reverse
    data obj item row line res resp out name value val entry tag
""".split())
_PYC_LIT = re.compile(r"""^([^"']*)("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')""", re.S)
_PYC_TOKEN = re.compile(r"[A-Za-z0-9_]+")
_PYC_SMALL = re.compile(r"[0-9]+|[A-Za-z_]")

# The reader goes without a path (or `.venv/bin/`, `venv/bin/`): `/tmp/x/python3` or `./python3` is
# whatever binary someone left there. The download may not touch files either: -o/-O/--output,
# -K/--config, -T/--upload-file and `@file` data (wget: -O- is stdout, any other -O is a file). jq may
# not load a program (`-f`, `--from-file`, `--rawfile`) or read the environment (`env`, `$ENV`).
# Same expressions as fetch_shape_ok in block-dangerous-commands.sh.
_PY = r"(?:\.?venv/bin/)?python[0-9.]*"
_FETCH = r"\s*(?:curl|wget)\b[^|]*\|\s*"
# The output flags are looked for outside quoted strings (a header value is not an option) and only in
# clusters whose letters before o/O/K/T take no value: in `-XPOST` the O belongs to the method.
_BAD_CURL_OUT = re.compile(
    r"(?:^|\s)(?:-[0-9#aBfgGhiIjJklLMnNpqRsSvVZ]*[oOKT]|--(?:output|remote-name|remote-name-all|config|upload-file|output-dir)(?:[\s=]|$))")
_BAD_CURL_DATA = re.compile(
    r"(?:^|\s)(?:-[A-Za-z]*d|--data(?:-binary|-raw|-urlencode|-ascii)?|-F|--form|--json)[\s=]*[\"']?(?:[A-Za-z0-9_]*=)?@")
_QUOTED = re.compile(r"\"[^\"]*\"|'[^']*'")
_BAD_WGET = re.compile(
    r"(?:^|\s)(?:-[A-Za-z]*[oiP]|--(?:output-file|input-file|directory-prefix|post-file|body-file|config))(?:[\s=]|$)"
    r"|(?:^|\s)-[A-Za-z]*O(?:\s+[^-\s]|[^-\s])|(?:^|\s)--output-document[\s=]*[^-\s]")
_BAD_JQ = re.compile(
    r"(?:^|\s)(?:-[A-Za-z]*f|-L|--(?:from-file|rawfile|slurpfile|argfile|library-path))(?:[\s=]|$)"
    r"|(?:^|[^.\w$])(?:env|input_filename)(?:\W|$)|\$(?:ENV|__prog_args)")
_PYC_SAFE = re.compile(
    r"^" + _FETCH + _PY + r"\s+-[ISEBsu]*c\s+(?:'([^']*)'|\"([^\"]*)\")\s*$")
_JSONTOOL_SAFE = re.compile(
    r"^" + _FETCH + _PY +
    r"\s+-m\s*json\.tool(?:\s+(?:--sort-keys|--compact|--indent(?:=\d+|\s+\d+)))*\s*$")
_JQ_SAFE = re.compile(r"^" + _FETCH + r"jq\b[^|]*$")


def _strict_pyc_ok(code: str, quote: str) -> bool:
    """True iff the `-c` program names only _PYC_NAMES outside its string literals. Fails
    closed: non-ASCII (Python NFKC-normalises identifiers), `$`, backtick or `\\` inside shell
    double quotes (the shell expands them first), a prefixed literal (f"{...}" evaluates), a
    `#` or `\\` outside a literal, or a stray quote."""
    if len(code) > 1024 or not all(" " <= ch <= "~" or ch in "\t\n\v\f\r" for ch in code):
        return False
    if quote == '"' and any(ch in code for ch in "$`\\"):
        return False
    out, rest = [], code
    m = _PYC_LIT.match(rest)
    while m:
        if re.search(r"[A-Za-z0-9_]$", m.group(1)):
            return False
        out.append(m.group(1) + " ")
        rest = rest[m.end():]
        m = _PYC_LIT.match(rest)
    out = "".join(out) + rest
    if any(ch in out for ch in "\"'#\\"):
        return False
    return all(_PYC_SMALL.fullmatch(t) or t in _PYC_NAMES for t in _PYC_TOKEN.findall(out))


def _safe_shape_stmt(st: str) -> bool:
    dl, _, rest = st.partition("|")
    if re.match(r"\s*curl", st):
        # A backslash can open a string the shell does not see (`\"`): then the text is read whole.
        dq = dl if "\\" in dl else _QUOTED.sub("Q", dl)
        if _BAD_CURL_OUT.search(dq) or _BAD_CURL_DATA.search(dl):
            return False
    if re.match(r"\s*wget", st) and _BAD_WGET.search(dl):
        return False
    m = _PYC_SAFE.match(st)
    if m:
        if m.group(1) is not None:
            return _strict_pyc_ok(m.group(1), "'")
        return _strict_pyc_ok(m.group(2), '"')
    return bool(_JSONTOOL_SAFE.match(st) or (_JQ_SAFE.match(st) and not _BAD_JQ.search(rest)))


def _split_statements(text: str):
    out, cur, i, n, q = [], [], 0, len(text), None
    while i < n:
        c = text[i]
        if q is not None:
            cur.append(c)
            if c == "\\" and q == '"' and i + 1 < n:
                cur.append(text[i + 1]); i += 2; continue
            if c == q:
                q = None
            i += 1; continue
        if c in ("'", '"'):
            q = c; cur.append(c); i += 1; continue
        if c == "\\" and i + 1 < n:
            cur.append(c); cur.append(text[i + 1]); i += 2; continue
        if c in (";", "\n", "(", ")"):
            out.append("".join(cur)); cur = []; i += 1; continue
        if c == "&":
            if i + 1 < n and text[i + 1] == ">":
                cur.append(c); i += 1; continue
            if i + 1 < n and text[i + 1] == "&":
                i += 1
            out.append("".join(cur)); cur = []; i += 1; continue
        if c == "|":
            if i + 1 < n and text[i + 1] == "|":
                out.append("".join(cur)); cur = []; i += 2; continue
            cur.append(c); i += 1; continue
        cur.append(c); i += 1
    out.append("".join(cur))
    return out


def _fetch_patterns(patterns: list) -> list:
    return [rx for rx in patterns if "\\|&?" in rx and ("\\bcurl" in rx or "\\bwget" in rx)]


def fetch_safe_reader(text: str, fetch_patterns: list) -> bool:
    """True iff every download-piped-to-interpreter statement is one of the allowed
    data-only readers (and at least one such statement exists). Fails closed."""
    if not fetch_patterns:
        return False
    # A pipe into a group (`| (bash)`, `| { bash; }`) splits the statement at the `(`: the half with
    # the download no longer names the interpreter, and another safe statement would pardon the lot.
    if re.search(r"\|&?\s*[({]", text):
        return False
    stmts = _split_statements(text)
    if len(stmts) > 64:
        return False
    safe = 0
    for st in stmts:
        if not any(_search(rx, st) for rx in fetch_patterns):
            continue
        if _safe_shape_stmt(st):
            safe += 1
        else:
            return False
    return safe > 0


# Bash writes over what the kit protects (~/.claude/settings*.json, ~/.claude/hooks/**,
# ~/.claude/sentinel/**, sentinel-allowlist.json). `Edit(...)` rules only cover the file commands Claude
# Code recognises; rm, mv, cp, chmod, install, ln or `: > file` reach the guards as plain Bash, and
# before this a session could take its own guards apart with them. Reads (cat, cp FROM, diff) pass.
# Never exempt: the allowlist does not apply. Limit: code inside python -c / node -e is not read.
_HOME_RX = r"(?:/home/[^/]+|/root|/Users/[^/]+)"
_PROTECTED_CFG = re.compile(
    rf"^(?:{_HOME_RX}/\.claude/(?:hooks|sentinel)(?:/.*)?|{_HOME_RX}/\.claude/settings[^/]*\.json|.*/sentinel-allowlist\.json)$")
_WRITE_ALL = {"rm", "unlink", "rmdir", "chmod", "chown", "chgrp", "touch", "truncate", "tee", "shred",
              "mv", "sponge", "patch", "ed", "curl", "wget"}
_WRITE_DEST = {"cp", "install", "ln", "rsync"}
_SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "ash", "fish", "eval", "su"}


def _protected_path(word: str, cwd: str) -> bool:
    if not word or word.startswith("-") and "=" not in word:
        return False
    word = word.partition("=")[2] if re.match(r"^(?:of|-[^=]*)=", word) else word
    path = expand(word)
    if not os.path.isabs(path):
        path = os.path.join(cwd, path)
    path = os.path.normpath(path)
    home = os.path.expanduser("~").rstrip("/")
    return bool(_PROTECTED_CFG.match(path)
                or home and (path in (f"{home}/.claude/hooks", f"{home}/.claude/sentinel")
                             or path.startswith((f"{home}/.claude/hooks/", f"{home}/.claude/sentinel/"))
                             or re.fullmatch(re.escape(home) + r"/\.claude/settings[^/]*\.json", path)))


def _is_claude_home(word: str, cwd: str) -> bool:
    """The whole ~/.claude directory (not a child of it): `mv` or `rm -r` on it takes hooks and settings along."""
    if not word or word.startswith("-"):
        return False
    path = expand(word)
    if not os.path.isabs(path):
        path = os.path.join(cwd, path)
    path, home = os.path.normpath(path), os.path.expanduser("~").rstrip("/")
    return bool(re.fullmatch(_HOME_RX + r"/\.claude", path) or home and path == f"{home}/.claude")


def _writes_protected(words: list[str], cwd: str, depth: int) -> str | None:
    i, _ = _command_word(words)
    if i >= len(words):
        return None
    name, args = _cmd_name(words[i]), words[i + 1:]
    if name in _SHELLS:
        for a in args:
            if re.search(r"\s|;|&|\|", a) and (hit := _protected_write(a, cwd, depth + 1)):
                return hit
        return None
    pos, dd = [], False
    for a in args:
        if not dd and a == "--":
            dd = True
        elif dd or not a.startswith("-"):
            pos.append(a)
    if name == "mv" or (name == "rm" and any(re.match(r"-[A-Za-z]*[rR]", a) or a == "--recursive" for a in args if not dd)):
        # The parent directory itself as the thing moved or removed; as the last operand of `mv` it is only the destination.
        tdir = [b for a, b in zip(args, args[1:]) if a == "-t"] + [a.partition("=")[2] for a in args if a.startswith("--target-directory=")]
        moved = [p for p in pos if p not in tdir] if name == "mv" and tdir else pos[:-1] if name == "mv" else pos
        if (hit := next((p for p in moved if _is_claude_home(p, cwd)), None)):
            return hit
    if name in _WRITE_ALL:
        cand = args if name in ("curl", "wget") else pos
    elif name in _WRITE_DEST:
        cand = pos[-1:]
        cand += [b for a, b in zip(args, args[1:]) if a == "-t"]
        cand += [a.partition("=")[2] for a in args if a.startswith("--target-directory=")]
        cand += [a[2:] for a in args if a.startswith("-t") and len(a) > 2 and not a.startswith("--")]
    elif name in ("sed", "perl", "ruby"):
        inplace = any(re.match(r"-[A-Za-z]*i", a) or a.startswith("--in-place") for a in args
                      if not (name != "sed" and a.startswith("--")))
        cand = pos if inplace else []
    elif name == "dd":
        cand = [a for a in args if a.startswith("of=")]
    elif name in ("find", "fd", "fdfind"):
        cand = pos if any(a in ("-delete", "-exec", "-execdir", "-ok", "-okdir") for a in args) else []
    else:
        cand = []
    return next((c for c in cand if _protected_path(c, cwd)), None)


def _protected_write(text: str, cwd: str, depth: int = 0) -> str | None:
    if depth > 3:
        return None
    cmd, pending = [], None

    def flush():
        nonlocal cmd, cwd
        words = [w[0] for w in cmd]
        hit = _writes_protected(words, cwd, depth)
        i, _ = _command_word(words)
        if not hit and i < len(words) and _cmd_name(words[i]) == "cd" and len(words) > i + 1:
            d = expand(words[i + 1])
            cwd = os.path.normpath(d if os.path.isabs(d) else os.path.join(cwd, d))
        cmd = []
        return hit

    for t in _lex(text) + ["\n"]:
        if isinstance(t, str):
            if "<" in t or ">" in t:
                pending = "w" if ">" in t else "r"
                continue
            pending = None
            if hit := flush():
                return hit
        elif isinstance(t, tuple):
            for body in t[2]:
                if hit := _protected_write(body, cwd, depth + 1):
                    return hit
            if pending == "w" and _protected_path(t[0], cwd):
                return t[0]
            if pending:
                pending = None
            else:
                cmd.append(t)
    return None


def check_protected_writes(tool_input: dict, iocs: dict, allowlist: dict):
    for text in collect_fields(tool_input, ["command"]):
        hit = _protected_write(text, os.getcwd())
        if hit:
            return (f"write to a file the kit protects (hooks, settings, sentinel): {hit}", "critical")
    return (None, None)


def check_dangerous_commands(tool_input: dict, iocs: dict, allowlist: dict):
    patterns = iocs.get("dangerous_commands", {}).get("patterns", [])
    fetch_patterns = _fetch_patterns(patterns)
    allowed_cmds = allowlist.get("commands") or []

    for text in collect_fields(tool_input, ["command"]):
        if text in allowed_cmds:
            continue
        # A backslash-newline is a continuation: the shell reads it as one line, so must the regexes.
        text = re.sub(r"\\\r?\n[ \t]*", " ", text)
        safe_fetch = fetch_safe_reader(text, fetch_patterns)
        for rx in patterns:
            if safe_fetch and rx in fetch_patterns:
                continue
            if _search(rx, text):
                return (f"dangerous command pattern", "critical")
    return (None, None)


# ── Decision engine ───────────────────────────────────────────────────────────

MAX_COMMAND_BYTES = 131072  # el mismo tope que CMDN_MAX_BYTES de cmdnorm.sh

# A hook past its timeout (10 s in settings.json) does not block: the tool runs. Some patterns of iocs.json
# backtrack quadratically on a padded command (`curl x | ((((…`: 40 KB = 9 s) well under MAX_COMMAND_BYTES,
# so size alone cannot keep Sentinel inside the timeout. It also gets a wall-clock budget: past it the answer
# is `ask`, as above the size cap, never an allow. BaseException on purpose: the `except Exception` blocks of
# the checks must not swallow it and carry on without a budget.
ANALYSIS_BUDGET_S = 1.5


class _OverBudget(BaseException):
    pass


def _over_budget(signum, frame):
    raise _OverBudget()


def decide_within_budget(payload: dict):
    """decide(payload), or None when the analysis does not fit ANALYSIS_BUDGET_S."""
    if not hasattr(signal, "setitimer"):
        return decide(payload)
    previous = signal.signal(signal.SIGALRM, _over_budget)
    signal.setitimer(signal.ITIMER_REAL, ANALYSIS_BUDGET_S)
    try:
        return decide(payload)
    except _OverBudget:
        return None
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)

SEVERITY_RANK = {"medium": 1, "high": 2, "critical": 3}


def effective_input(payload: dict) -> dict:
    """tool_input as the checks must see it. Grep's pattern is a regex over file content, not
    a path; the same word names the path in Glob, so it is dropped for Grep alone."""
    tool_input = payload.get("tool_input") or payload.get("input") or {}
    if (payload.get("tool_name") or payload.get("tool")) == "Grep":
        tool_input = {k: v for k, v in tool_input.items() if k != "pattern"}
    return tool_input


def decide(payload: dict):
    iocs = load_iocs()
    allowlist = load_user_allowlist()
    tool_input = effective_input(payload)

    checks = [
        check_sensitive_paths,
        check_suspicious_network,
        check_dangerous_commands,
        check_protected_writes,
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
    tool_input = effective_input(payload)
    command = tool_input.get("command")
    if tool_name == "Bash" and isinstance(command, str) and len(command.encode()) > MAX_COMMAND_BYTES:
        # A hook past its timeout does not block: the tool runs. Above the cap, ask instead of risking it.
        kb = len(command.encode()) // 1024
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "ask",
                "permissionDecisionReason": (
                    f"Confirm: el comando pesa {kb} KB (tope {MAX_COMMAND_BYTES // 1024} KB): Sentinel no puede "
                    "analizarlo dentro de su timeout, y un guard que se pasa de tiempo deja ejecutar la "
                    "herramienta. Escribe los contenidos grandes con la herramienta Write y ejecuta un "
                    "comando corto."
                ),
            }
        }))
        sys.exit(0)
    result = decide_within_budget(payload)
    if result is None:
        audit_log(tool_name, "ask", "analysis over budget")
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "ask",
                "permissionDecisionReason": (
                    f"Confirm: Sentinel no pudo analizar la llamada en {ANALYSIS_BUDGET_S:g} s (un comando relleno de "
                    "parentesis o de `$(` encarece sus patrones), y un guard que se pasa de tiempo deja ejecutar la "
                    "herramienta. Escribe los contenidos grandes con la herramienta Write y ejecuta un comando corto."
                ),
            }
        }))
        sys.exit(0)
    decision, reason = result

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
        # A blocked command or a write to the kit's own config gets the way out instead: the
        # allowlist is no way past a command block (the policy says never widen it to get past one).
        if reason and "kit protects" in reason:
            hint = "\nLa configuracion del kit (hooks, settings, sentinel) la cambia la persona, no una sesion."
        elif reason and "dangerous command pattern" in reason:
            hint = (
                "\nAlternativa: descarga a fichero (-o), revisalo y ejecutalo aparte; para JSON, jq o "
                "python -c que solo lea e imprima (json, sys, print)."
            )
        else:
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
