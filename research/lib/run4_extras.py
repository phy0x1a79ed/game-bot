"""Extra cuts on the run-4 pickle: net-of-sleep tool time, single-call latency, output tokens by action class."""
import pickle, sys, os, collections, statistics
HERE = os.path.dirname(os.path.abspath(__file__))
D = pickle.load(open(f'{HERE}/run4_{sys.argv[1] if len(sys.argv)>1 else "win"}.pkl', 'rb'))
CREW = {'chair', 'ops-s55', 'ops', 'builder1', 'builder2', 'military'}
SS = [s for s in D['sessions'] if s['group'] in CREW]
med = lambda x: statistics.median(x) if x else 0
def pct(xs, p):
    xs = sorted(xs); return xs[min(len(xs)-1, int(round(p/100*(len(xs)-1))))] if xs else 0
ck = lambda c: 'game:' + c['sub'] if c['cls'] == 'game' else c['cls']
calls = [c for s in SS for c in s['calls'] if 't1' in c]

print('-- A. tool time net of literal sleeps (agent-hours, crew)')
b = collections.Counter()
for c in calls:
    e = c['excl']
    if c['cls'] == 'game':
        sl = min(c['sleep_static'], e); b['embedded sleep'] += sl; e -= sl
        has_walk = any(v in ('walk', 'move') for v in c['verbs']) or any('walk' in s for s in c['scripts'])
        has_wait = 'wait' in c['verbs']
        key = ck(c)
        if key == 'game:mutate' and has_walk: key = 'game:mutate (call also walks)'
        if key in ('game:read', 'game:mutate') and has_wait: key += ' +engine wait'
        if key == 'game:read' and c['loop']: key = 'game:read (shell loop)'
        b[key] += e
    else:
        b[ck(c)] += e
T = sum(b.values())
for k_, v in b.most_common(14): print(f"   {k_:34} {v/3600:6.2f} h  {100*v/T:5.1f}%")
print(f"   total tool {T/3600:.2f} h")

print('-- B. latency of a single game call: Bash calls with exactly one static invocation, no sleep, no shell loop, no walk/wait')
for label, f in (('read exec', lambda c: c['sub'] == 'read' and c.get('lua_len')), ('mutate exec', lambda c: c['sub'] == 'mutate' and c.get('lua_len')),
                 ('mutate verb (take/insert/build..)', lambda c: c['sub'] == 'mutate' and c.get('lua_len') is None)):
    v = [c for c in calls if c['cls'] == 'game' and f(c) and c['n_inv'] == 1 and not c['sleep_static'] and not c['loop']
         and not any(x in ('walk', 'move', 'wait') for x in c['verbs']) and not any('walk' in s for s in c['scripts']) and not c['bg']]
    d = [c['excl'] for c in v]
    print(f"   {label:34} n={len(d):5d} med {med(d):5.2f}s p75 {pct(d,75):5.2f}s p90 {pct(d,90):5.2f}s p99 {pct(d,99):6.1f}s  total {sum(d)/3600:.2f} h")
for lo, hi in ((0, 500), (500, 1000), (1000, 2000), (2000, 4000), (4000, 10**9)):
    v = [c['excl'] for c in calls if c['cls'] == 'game' and c.get('lua_len') and lo <= c['lua_len'] < hi and c['n_inv'] == 1
         and not c['sleep_static'] and not c['loop'] and 'walk' not in c['verbs'] and 'wait' not in c['verbs'] and not c['scripts']]
    print(f"   single exec, lua {lo}-{hi if hi < 10**9 else 'inf'} chars: n={len(v):5d} med {med(v):.2f}s p90 {pct(v,90):.2f}s")
print('   walk-only calls: med %.1fs p90 %.1fs' % (med([c['excl'] for c in calls if ck(c)=='game:walk']), pct([c['excl'] for c in calls if ck(c)=='game:walk'], 90)))
mu = [c for c in calls if ck(c) == 'game:mutate']
mw = [c for c in mu if any(v in ('walk', 'move') for v in c['verbs']) or any('walk' in s for s in c['scripts'])]
print(f"   mutate calls that also walk in the same Bash call: {len(mw)}/{len(mu)}, {sum(c['excl'] for c in mw)/3600:.2f} h of {sum(c['excl'] for c in mu)/3600:.2f} h mutate time")
print(f"   background (run_in_background) Bash calls: {sum(1 for c in calls if c['bg'])}; game calls among them {sum(1 for c in calls if c['bg'] and c['cls']=='game')}")
to = [c for c in calls if c['cls'] == 'game' and c['excl'] >= 119]
print(f"   game calls lasting >=119 s (timeouts/long blocks): {len(to)}, {sum(c['excl'] for c in to)/3600:.2f} h")

print('-- C. output tokens and model time by what the assistant message did (primary class of its tool calls)')
PRI = ['game:mutate', 'game:walk', 'game:wait', 'game:admin', 'game:read', 'agent-spawn', 'sendmessage', 'doc-write', 'script-write', 'wait',
       'doc-read', 'file-read', 'monitor', 'compute', 'sysadmin', 'harness', 'other']
for role in ('lead', 'sub', None):
    out = collections.Counter(); gen = collections.Counter(); n = collections.Counter()
    for s in SS:
        if role and s['role'] != role: continue
        bym = collections.defaultdict(list)
        for c in s['calls']: bym[c['mid']].append(ck(c))
        for mid, m in s['msgs'].items():
            ks = bym.get(mid)
            key = 'no tool (text / end of turn)' if not ks else min(ks, key=PRI.index)
            out[key] += max(m['usage'].get('output_tokens', 0), m['max_out']); gen[key] += m['t1'] - m['trig']; n[key] += 1
    To = sum(out.values()); Tg = sum(gen.values())
    print(f"   [{role or 'crew all'}] total output {To/1e6:.2f}M, model time {Tg/3600:.1f} h")
    for k_, v in out.most_common(12):
        print(f"      {k_:30} msgs {n[k_]:6d}  out {v/1e6:6.2f}M {100*v/To:5.1f}%  tok/msg {v/n[k_]:6.0f}  gen {gen[k_]/3600:5.2f} h {100*gen[k_]/Tg:5.1f}%")

print('-- D. per-unit costs (crew)')
o = sum(max(m['usage'].get('output_tokens', 0), m['max_out']) for s in SS for m in s['msgs'].values())
cr = sum(m['usage'].get('cache_read_input_tokens', 0) for s in SS for m in s['msgs'].values())
api = sum(len(s['msgs']) for s in SS)
g = [c for c in calls if c['cls'] == 'game']
print(f"   api calls {api}; per game-mutating call: {api/len(mu):.1f} api calls, {o/len(mu):.0f} output tok, {cr/len(mu)/1e6:.2f}M cache-read tok")
print(f"   per game call of any kind: {api/len(g):.2f} api calls, {o/len(g):.0f} output tok")
print(f"   tool calls per api call: {len(calls)/api:.2f}")
rs = [(s['group'], s['role'], s['notif'], len(s['msgs'])) for s in SS if s['role'] == 'lead']
print('   lead notifications -> api calls:', rs)
