#!/usr/bin/env python3
"""nucleo_audit.py — ¿se usa .claude/estado/nucleo.md alrededor de las compactaciones?

Uso: python3 scripts/nucleo_audit.py
Lee las sesiones de los últimos 60 días en $CLAUDE_PROJECTS_DIR (por defecto
~/.claude/projects), sin subagentes. Por compactación: si en los 6 turnos siguientes se
vuelve a tocar nucleo.md, si se escribió en los 5 previos, y si un aviso de contexto alto
del hook Stop fue seguido de una escritura o un /handoff.
"""
import glob, json, os, re, time, statistics as st
from collections import defaultdict
H = os.environ.get('CLAUDE_PROJECTS_DIR') or os.path.expanduser('~/.claude/projects')
cut = time.time() - 60*86400
files = [f for f in glob.glob(H+'/*/*.jsonl') if os.path.getmtime(f) >= cut]
nsub = len([f for f in glob.glob(H+'/*/*/subagents/*.jsonl') if os.path.getmtime(f) >= cut])
if not files: raise SystemExit(f'sin sesiones de los últimos 60 días en {H}')
mt = [os.path.getmtime(f) for f in files]
fmt = lambda t: time.strftime('%Y-%m-%d', time.localtime(t))
SR = re.compile(r'<system-reminder>.*?</system-reminder>', re.S)

def med(l): return (min(l), int(st.median(l)), max(l)) if l else None
def blocks(m):
    c = (m or {}).get('content') if isinstance(m, dict) else None
    if isinstance(c, str): return [{'type': 'text', 'text': c}]
    return [b for b in c if isinstance(b, dict)] if isinstance(c, list) else []

S = dict(n=0, sc=0, comp=0, ref_yes=0, ref_no=0, inj=0, writes=[], wpos=defaultdict(int),
         w_pre5=0, comp_nowrite20=0, ss=[], ss_trunc=0, stop=0, stop_fu=0,
         lenc=[], lenn=[], endcomp=0)
cwdinfo = defaultdict(lambda: [0, False])  # cwd -> [sessions, touched]
for f in files:
    turns = 0; seen = set(); recs = []; cwd = None; first_user_done = False
    ss_blk = None; sawA = False; last_comp = False
    for line in open(f, errors='replace'):
        try: r = json.loads(line)
        except Exception: continue
        t = r.get('type'); cwd = cwd or r.get('cwd')
        comp = False; refs = []; wr = False; inj = False; stopw = False; handoff = False
        if t == 'assistant':
            mid = (r.get('message') or {}).get('id')
            if mid is None or mid not in seen:
                turns += 1
                if mid: seen.add(mid)
            sawA = True
            for b in blocks(r.get('message')):
                if b.get('type') == 'tool_use':
                    inp = json.dumps(b.get('input', {}), ensure_ascii=False)
                    if 'handoff' in inp.lower(): handoff = True
                    if 'nucleo.md' in inp:
                        refs.append(1)
                        i = b.get('input', {}); nm = b.get('name')
                        if nm in ('Edit', 'Write', 'MultiEdit') and str(i.get('file_path', '')).endswith('estado/nucleo.md'): wr = True
                        elif nm == 'Bash' and re.search(r'(>|tee\b|cat\s*<<|sed\s+-i)', str(i.get('command', ''))) and re.search(r'(>>?|tee)\s*\S*nucleo\.md|sed\s+-i[^|]*nucleo\.md|cat\s*<<', str(i.get('command', ''))): wr = True
        else:
            txt = ''
            if t == 'user':
                bl = blocks(r.get('message'))
                texts = [b.get('text', '') for b in bl if b.get('type') == 'text']
                full = '\n'.join(texts)
                if r.get('isCompactSummary') or full.startswith('This session is being continued from a previous conversation'): comp = True
                else:
                    txt = '\n'.join(SR.findall(full)) + ('\n' + full if 'Stop hook' in full else '')
                    if '<command-name>/handoff' in full or full.strip().startswith('/handoff'): handoff = True
                    if not first_user_done and not sawA:
                        first_user_done = True
                        for s in SR.findall(full):
                            if 'nucleo' in s.lower(): ss_blk = s
            elif t in ('system', 'attachment'):
                txt = json.dumps(r, ensure_ascii=False)
                if not sawA and 'nucleo' in txt.lower() and ss_blk is None: ss_blk = txt
            low = txt.lower()
            if 'nucleo' in low: inj = True
            if 'contexto alto' in low or 'handoff' in low: stopw = True
        if comp or r.get('isCompactSummary'): comp = True
        last_comp = comp if t != 'summary' else last_comp
        recs.append((t, turns, comp, bool(refs), wr, inj, stopw, handoff))
    if not recs: continue
    S['n'] += 1
    comps = [x for x in recs if x[2]]
    allw = [x[1] for x in recs if x[4]]
    touched = any(x[3] for x in recs)
    ci = cwdinfo[cwd]; ci[0] += 1; ci[1] |= touched
    if comps: S['sc'] += 1; S['lenc'].append(turns)
    else: S['lenn'].append(turns)
    S['comp'] += len(comps)
    if recs[-1][2]: S['endcomp'] += 1
    S['writes'].append(len(allw))
    for w in allw:
        p = w / max(turns, 1)
        S['wpos']['first10' if p <= .1 else 'last10' if p >= .9 else 'middle'] += 1
    for k, x in enumerate(recs):
        if not x[2]: continue
        tc = x[1]
        win = [y for y in recs[k+1:] if y[1] <= tc + 6 and not y[2]]
        S['ref_yes' if any(y[3] for y in win) else 'ref_no'] += 1
        if any(y[5] for y in win): S['inj'] += 1
        if any(w for w in allw if tc - 5 <= w <= tc): S['w_pre5'] += 1
        if not any(tc - 20 <= w <= tc for w in allw): S['comp_nowrite20'] += 1
    if ss_blk:
        S['ss'].append(len(ss_blk))
        e = ss_blk.rstrip()
        if re.search(r'recortad|truncad|\.\.\.|…', ss_blk, re.I) or not re.search(r'[.!?)\]`>|\-:]$', re.sub(r'</system-reminder>$', '', e).rstrip()): S['ss_trunc'] += 1
    for k, x in enumerate(recs):
        if x[6]:
            S['stop'] += 1
            win = [y for y in recs[k+1:] if y[1] <= x[1] + 3]
            if any(y[4] or y[7] for y in win): S['stop_fu'] += 1
ex = [c for c in cwdinfo if c and os.path.exists(os.path.join(c, '.claude/estado/nucleo.md'))]
mean = lambda l: round(sum(l)/len(l), 1) if l else None
print('range', fmt(min(mt)), fmt(max(mt)), 'subagent files excluded', nsub)
print('1 sessions', S['n'], 'with_comp', S['sc'], 'compactions', S['comp'])
print('2 comp: nucleo tool_use in next6 yes/no', S['ref_yes'], S['ref_no'], '| nucleo text injection in window', S['inj'])
print('3 sessions with >=1 write', sum(1 for w in S['writes'] if w), 'total writes', sum(S['writes']), 'per-session max', max(S['writes'], default=0), dict(S['wpos']))
print('3 comps w/ write within 5 turns before', S['w_pre5'], '| comps with no write in prior 20 turns', S['comp_nowrite20'])
print('4 sessionstart nucleo injection sessions', len(S['ss']), 'chars min/med/max', med(S['ss']), 'looks truncated', S['ss_trunc'])
print('5 stop/handoff records', S['stop'], 'followed by write/handoff in 3 turns', S['stop_fu'])
print('6 distinct cwd', len(cwdinfo), 'with nucleo.md on disk', len(ex), 'of those touched by a session', sum(1 for c in ex if cwdinfo[c][1]))
print('7 turns with comp: n/mean/median', len(S['lenc']), mean(S['lenc']), st.median(S['lenc']) if S['lenc'] else None, '| without:', len(S['lenn']), mean(S['lenn']), st.median(S['lenn']) if S['lenn'] else None)
print('8 sessions ending on compaction', S['endcomp'])
