#!/usr/bin/env python3
"""Extrae metricas de uso reales desde los transcripts de Claude Code.

Absorbido desde ai-mastery/bucle/analyze.py: mismas ~50 metricas, mismas
claves y valores. Cambios respecto al original:
  - Rutas configurables via CLAUDE_PROJECTS_DIR / METRICS_OUT_DIR (mismos
    defaults que el original) para poder testear sin tocar datos reales.
  - El filtro de subagentes es explicito por contenido de ruta ("/subagents/")
    en vez de depender de la profundidad de dos globs distintos. Se declara
    en la clave de salida "filter_applied".
  - Metricas nuevas: rework_sessions / rework_sessions_pct (distinta de
    rework_rate_pct, que divide por turnos y no por sesiones),
    sessions_with_correction_pct (alias de rework_sessions_pct),
    tool_calls_per_session_median / _p90, sessions_with_oracle(_pct).
"""
import json, os, sys, re, glob
from collections import Counter
from datetime import datetime, timezone

ROOT = os.environ.get("CLAUDE_PROJECTS_DIR") or os.path.expanduser("~/.claude/projects")
ALL_JSONL = os.path.join(ROOT, "**", "*.jsonl")
OUT = os.environ.get("METRICS_OUT_DIR") or os.path.expanduser("~/ai-mastery/bucle/data")

# precio por millon de tokens (Opus 5 / Sonnet 5 / Haiku 4.5), solo para valorar
# el consumo en equivalente-API frente al coste fijo de la suscripcion
PRICE = {
    "opus":   {"in": 5.00, "out": 25.00, "cw": 6.25,  "cr": 0.50},
    "sonnet": {"in": 3.00, "out": 15.00, "cw": 3.75,  "cr": 0.30},
    "haiku":  {"in": 1.00, "out": 5.00,  "cw": 1.25,  "cr": 0.10},
}
def fam(model):
    m = (model or "").lower()
    for k in PRICE:
        if k in m: return k
    return "opus"

REWORK = re.compile(r"\b(no,|no\.|mal|error|falla|fallo|otra vez|de nuevo|te dije|no era|no funciona|revierte|deshaz|vuelve a|corrige|arregla eso)\b", re.I)
VAGUE  = re.compile(r"^(sigue|continua|continúa|ok|dale|vale|adelante|hazlo|si|sí|más|mas)\b[\s.!]*$", re.I)

# Heuristica: un tool_use de Bash cuyo "command" contenga uno de estos
# fragmentos se cuenta como "corrio el oraculo". Falso negativo conocido: un
# oraculo con otro nombre (p.ej. un test runner propio, `tox`, `go test`) no
# se detecta porque no esta en esta lista.
ORACLE_CMDS = ("make test", "pytest", "shellcheck", "gitleaks")

def is_subagent_path(path):
    return "/subagents/" in path.replace(os.sep, "/")

def analyze():
    s = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "sessions": 0, "projects": Counter(), "models": Counter(),
        "tok": Counter(), "cost_usd": 0.0,
        "tools": Counter(), "tool_errors": Counter(),
        "user_turns": 0, "assistant_turns": 0,
        "prompt_chars": [], "turns_per_session": [],
        "hour": Counter(), "dow": Counter(), "day": Counter(),
        "interrupts": 0, "compactions": 0, "rework_turns": 0, "vague_turns": 0,
        "skills_used": Counter(), "agents_used": Counter(), "mcp_used": Counter(),
        "sessions_with_skill": 0, "sessions_with_agent": 0, "sessions_with_plan": 0,
        "thinking_tokens": 0, "web_search": 0, "web_fetch": 0,
        "session_len_min": [], "permission_denied": 0,
        "sessions_one_shot": 0, "sessions_long": 0,
        "top_words": Counter(),
        "slash_commands": Counter(), "task_notifications": 0,
        "sub_transcripts": 0, "sub_tok": Counter(), "sub_cost": 0.0, "sub_tools": Counter(),
        "sessions_with_rework": 0, "sessions_with_oracle": 0,
        "tool_calls_per_session": [],
    }
    STOP = set("de la el en y a los las un una que con por para del al se es su lo como mas más este esta esto o si no me te lo le nos ya pero sin sobre tambien también hay ser son fue muy cuando donde todo todos cada e u i the to and of in for it is you my me a an on".split())

    main_files = [f for f in glob.glob(ALL_JSONL, recursive=True) if not is_subagent_path(f)]
    sub_files = [f for f in glob.glob(ALL_JSONL, recursive=True) if is_subagent_path(f)]

    for f in main_files:
        proj = os.path.basename(os.path.dirname(f))
        if proj.startswith("."): continue
        n_user = 0; has_skill = has_agent = has_plan = False
        has_rework = has_oracle = False; n_tool_calls = 0
        ts_first = ts_last = None
        s["sessions"] += 1; s["projects"][proj] += 1
        try:
            fh = open(f, encoding="utf-8", errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                line = line.strip()
                if not line or line[0] != "{": continue
                try: r = json.loads(line)
                except Exception: continue
                t = r.get("type")
                ts = r.get("timestamp")
                if ts:
                    try:
                        d = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                        ts_first = ts_first or d; ts_last = d
                    except Exception: pass
                if t == "user":
                    msg = r.get("message") or {}
                    c = msg.get("content")
                    if isinstance(c, str) and c.strip():
                        if r.get("isMeta") or r.get("isSidechain"): continue
                        cs = c.lstrip()
                        if cs.startswith("<"):   # command-*, task-notification, system-reminder, local-command-*
                            m = re.match(r"<command-name>(/[\w:-]+)", cs)
                            if m: s["slash_commands"][m.group(1)] += 1
                            if "task-notification" in cs[:40]: s["task_notifications"] += 1
                            continue
                        if "[Request interrupted" in cs:
                            s["interrupts"] += 1; continue
                        n_user += 1; s["user_turns"] += 1
                        s["prompt_chars"].append(len(c))
                        if "[Request interrupted" in c: s["interrupts"] += 1
                        if REWORK.search(c[:400]): s["rework_turns"] += 1; has_rework = True
                        if VAGUE.match(c.strip()): s["vague_turns"] += 1
                        if ts_last:
                            s["hour"][ts_last.hour] += 1
                            s["dow"][ts_last.strftime("%a")] += 1
                            s["day"][ts_last.strftime("%Y-%m-%d")] += 1
                        for w in re.findall(r"[a-záéíóúñ]{4,}", c.lower())[:120]:
                            if w not in STOP: s["top_words"][w] += 1
                    elif isinstance(c, list):
                        for b in c:
                            if not isinstance(b, dict): continue
                            if b.get("type") == "tool_result" and b.get("is_error"):
                                s["tool_errors"]["_total"] += 1
                                txt = str(b.get("content"))[:200]
                                if "permission" in txt.lower() or "denied" in txt.lower():
                                    s["permission_denied"] += 1
                elif t == "assistant":
                    s["assistant_turns"] += 1
                    msg = r.get("message") or {}
                    model = msg.get("model", ""); s["models"][model] += 1
                    u = msg.get("usage") or {}
                    it = u.get("input_tokens", 0) or 0
                    ot = u.get("output_tokens", 0) or 0
                    cw = u.get("cache_creation_input_tokens", 0) or 0
                    cr = u.get("cache_read_input_tokens", 0) or 0
                    s["tok"]["in"] += it; s["tok"]["out"] += ot
                    s["tok"]["cache_write"] += cw; s["tok"]["cache_read"] += cr
                    th = (u.get("output_tokens_details") or {}).get("thinking_tokens", 0) or 0
                    s["thinking_tokens"] += th
                    stu = u.get("server_tool_use") or {}
                    s["web_search"] += stu.get("web_search_requests", 0) or 0
                    s["web_fetch"] += stu.get("web_fetch_requests", 0) or 0
                    p = PRICE[fam(model)]
                    s["cost_usd"] += (it*p["in"] + ot*p["out"] + cw*p["cw"] + cr*p["cr"]) / 1e6
                    for b in (msg.get("content") or []):
                        if isinstance(b, dict) and b.get("type") == "tool_use":
                            name = b.get("name", "?")
                            s["tools"][name] += 1
                            n_tool_calls += 1
                            inp = b.get("input") or {}
                            if name == "Skill":
                                sk = inp.get("skill", "?"); s["skills_used"][sk] += 1; has_skill = True
                            elif name in ("Task", "Agent"):
                                ag = inp.get("subagent_type", "?"); s["agents_used"][ag] += 1; has_agent = True
                            elif name.startswith("mcp__"):
                                s["mcp_used"][name.split("__")[1]] += 1
                            elif name in ("ExitPlanMode", "EnterPlanMode"):
                                has_plan = True
                            if name == "Bash" and any(oc in str(inp.get("command", "")) for oc in ORACLE_CMDS):
                                has_oracle = True
                elif t == "system" and "compact" in str(r.get("subtype", "")).lower():
                    s["compactions"] += 1
        s["turns_per_session"].append(n_user)
        s["tool_calls_per_session"].append(n_tool_calls)
        if n_user <= 1: s["sessions_one_shot"] += 1
        if n_user >= 20: s["sessions_long"] += 1
        if has_skill: s["sessions_with_skill"] += 1
        if has_agent: s["sessions_with_agent"] += 1
        if has_plan: s["sessions_with_plan"] += 1
        if has_rework: s["sessions_with_rework"] += 1
        if has_oracle: s["sessions_with_oracle"] += 1
        if ts_first and ts_last:
            s["session_len_min"].append(round((ts_last - ts_first).total_seconds() / 60, 1))

    # --- transcripts de subagentes: coste y actividad delegada ---
    for f in sub_files:
        s["sub_transcripts"] += 1
        try: fh = open(f, encoding="utf-8", errors="replace")
        except OSError: continue
        with fh:
            for line in fh:
                if not line.startswith("{"): continue
                try: r = json.loads(line)
                except Exception: continue
                if r.get("type") != "assistant": continue
                msg = r.get("message") or {}
                u = msg.get("usage") or {}
                it = u.get("input_tokens", 0) or 0; ot = u.get("output_tokens", 0) or 0
                cw = u.get("cache_creation_input_tokens", 0) or 0
                cr = u.get("cache_read_input_tokens", 0) or 0
                s["sub_tok"]["in"] += it; s["sub_tok"]["out"] += ot
                s["sub_tok"]["cache_write"] += cw; s["sub_tok"]["cache_read"] += cr
                p = PRICE[fam(msg.get("model"))]
                s["sub_cost"] += (it*p["in"] + ot*p["out"] + cw*p["cw"] + cr*p["cr"]) / 1e6
                for b in (msg.get("content") or []):
                    if isinstance(b, dict) and b.get("type") == "tool_use":
                        s["sub_tools"][b.get("name", "?")] += 1

    def pct(a, b): return round(100.0 * a / b, 1) if b else 0.0
    def med(xs):
        xs = sorted(xs)
        return xs[len(xs)//2] if xs else 0
    def p90(xs):
        xs = sorted(xs)
        return xs[int(len(xs)*0.9)] if xs else 0

    tot_in = s["tok"]["in"] + s["tok"]["cache_read"] + s["tok"]["cache_write"]
    rework_sessions_pct = pct(s["sessions_with_rework"], s["sessions"])
    out = {
        "generated_at": s["generated_at"],
        "sessions": s["sessions"],
        "projects": dict(s["projects"].most_common()),
        "models": dict(s["models"].most_common()),
        "tokens": dict(s["tok"]),
        "tokens_total_input": tot_in,
        "cache_hit_pct": pct(s["tok"]["cache_read"], tot_in),
        "cost_equiv_api_usd": round(s["cost_usd"], 2),
        "user_turns": s["user_turns"], "assistant_turns": s["assistant_turns"],
        "turns_per_session_median": med(s["turns_per_session"]),
        "turns_per_session_max": max(s["turns_per_session"] or [0]),
        "prompt_chars_median": med(s["prompt_chars"]),
        "prompt_chars_p90": p90(s["prompt_chars"]),
        "session_minutes_median": med(s["session_len_min"]),
        "sessions_one_shot_pct": pct(s["sessions_one_shot"], s["sessions"]),
        "sessions_long_pct": pct(s["sessions_long"], s["sessions"]),
        "interrupts": s["interrupts"],
        "interrupt_rate_pct": pct(s["interrupts"], s["user_turns"]),
        "rework_turns": s["rework_turns"],
        "rework_rate_pct": pct(s["rework_turns"], s["user_turns"]),
        "rework_sessions": s["sessions_with_rework"],
        "rework_sessions_pct": rework_sessions_pct,
        "sessions_with_correction_pct": rework_sessions_pct,
        "vague_turns": s["vague_turns"],
        "vague_rate_pct": pct(s["vague_turns"], s["user_turns"]),
        "compactions": s["compactions"],
        "tool_calls_total": sum(s["tools"].values()),
        "tool_calls_per_user_turn": round(sum(s["tools"].values()) / s["user_turns"], 1) if s["user_turns"] else 0,
        "tool_calls_per_session_median": med(s["tool_calls_per_session"]),
        "tool_calls_per_session_p90": p90(s["tool_calls_per_session"]),
        "tools_top": dict(s["tools"].most_common(25)),
        "tool_errors": s["tool_errors"]["_total"],
        "tool_error_rate_pct": pct(s["tool_errors"]["_total"], sum(s["tools"].values())),
        "permission_denied": s["permission_denied"],
        "sessions_with_oracle": s["sessions_with_oracle"],
        "sessions_with_oracle_pct": pct(s["sessions_with_oracle"], s["sessions"]),
        "thinking_tokens": s["thinking_tokens"],
        "thinking_share_of_output_pct": pct(s["thinking_tokens"], s["tok"]["out"]),
        "web_search": s["web_search"], "web_fetch": s["web_fetch"],
        "skills_used": dict(s["skills_used"].most_common()),
        "agents_used": dict(s["agents_used"].most_common()),
        "mcp_used": dict(s["mcp_used"].most_common()),
        "adoption_pct": {
            "skills": pct(s["sessions_with_skill"], s["sessions"]),
            "subagents": pct(s["sessions_with_agent"], s["sessions"]),
            "plan_mode": pct(s["sessions_with_plan"], s["sessions"]),
        },
        "hour_histogram": dict(sorted(s["hour"].items())),
        "dow": dict(s["dow"].most_common()),
        "active_days": len(s["day"]),
        "busiest_days": dict(s["day"].most_common(10)),
        "top_words": dict(s["top_words"].most_common(40)),
        "slash_commands": dict(s["slash_commands"].most_common()),
        "task_notifications": s["task_notifications"],
        "subagents": {
            "transcripts": s["sub_transcripts"],
            "tokens": dict(s["sub_tok"]),
            "cost_equiv_api_usd": round(s["sub_cost"], 2),
            "tools_top": dict(s["sub_tools"].most_common(12)),
            "share_of_total_cost_pct": pct(s["sub_cost"], s["cost_usd"] + s["sub_cost"]),
        },
        "filter_applied": {
            "main_sessions": "*.jsonl bajo CLAUDE_PROJECTS_DIR excluyendo cualquier ruta que contenga '/subagents/'",
            "subagent_transcripts": "*.jsonl cuya ruta contiene '/subagents/'",
        },
    }
    return out

if __name__ == "__main__":
    m = analyze()
    os.makedirs(OUT, exist_ok=True)
    stamp = datetime.now().strftime("%Y-%m-%d")
    for p in (os.path.join(OUT, f"metrics-{stamp}.json"), os.path.join(OUT, "latest.json")):
        with open(p, "w") as fh: json.dump(m, fh, indent=2, ensure_ascii=False)
    json.dump(m, sys.stdout, indent=2, ensure_ascii=False)
