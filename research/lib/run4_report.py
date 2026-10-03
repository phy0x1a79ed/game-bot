"""Print the run-4 effort report from the pickle written by run4_parse.py."""
import pickle, sys, os, collections, statistics
from datetime import datetime, timezone, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
TAG = sys.argv[1] if len(sys.argv) > 1 else 'win'
D = pickle.load(open(f'{HERE}/run4_{TAG}.pkl', 'rb'))
SS = D['sessions']
PDT = timezone(timedelta(hours=-7))
GROUPS = ['chair', 'ops-s55', 'ops', 'builder1', 'builder2', 'military']
CREW = set(GROUPS)
ALLG = GROUPS + ['perf-tool']


def lt(t):
    return datetime.fromtimestamp(t, PDT).strftime('%d %H:%M')


def pct(xs, p):
    if not xs: return 0.0
    xs = sorted(xs); i = min(len(xs) - 1, max(0, int(round(p / 100 * (len(xs) - 1)))))
    return xs[i]


def med(xs):
    return statistics.median(xs) if xs else 0.0


def k(n):
    return f'{n/1e6:.2f}M' if n >= 1e6 else f'{n/1e3:.0f}k'


def sel(group=None, role=None, crew=False):
    return [s for s in SS if (group is None or s['group'] == group) and (role is None or s['role'] == role)
            and (not crew or s['group'] in CREW)]


def calls_of(ss):
    return [c for s in ss for c in s['calls'] if 't1' in c]


def ckey(c):
    return 'game:' + c['sub'] if c['cls'] == 'game' else c['cls']


def tok(ss):
    o = i = cr = cc = n = 0
    ctx = []
    for s in ss:
        for m in s['msgs'].values():
            u = m['usage']; n += 1
            o += max(u.get('output_tokens', 0), m['max_out']); i += u.get('input_tokens', 0)
            cr += u.get('cache_read_input_tokens', 0); cc += u.get('cache_creation_input_tokens', 0)
            ctx.append(u.get('input_tokens', 0) + u.get('cache_read_input_tokens', 0) + u.get('cache_creation_input_tokens', 0))
    return n, o, i, cr, cc, ctx


print(f"WINDOW {lt(D['W0'])} -> {lt(D['W1'])} PDT  ({(D['W1']-D['W0'])/3600:.2f} h)   [day HH:MM, PDT=UTC-7]\n")

# ---------------------------------------------------------------- 1 sessions
print('== 1. SESSIONS (events inside the window only)')
print(f"{'group':10} {'lead model':17} {'lead span PDT':19} {'h':>5} {'cmpct':>5} {'human':>5} {'notif':>5} {'peer':>5} | {'subs':>4} {'sub models':34} {'sub cmpct':>9}")
for g in ALLG:
    L = sel(g, 'lead'); S = sel(g, 'sub')
    if not L: continue
    l = L[0]
    sm = collections.Counter()
    for s in S:
        sm[max(s['models'], key=s['models'].get) if s['models'] else '?'] += 1
    print(f"{g:10} {'+'.join(m for m in l['models']):17} {lt(l['first'])+'-'+lt(l['last'])[3:]:19} {(l['last']-l['first'])/3600:5.1f} "
          f"{l['n_compact']:5d} {l['human']:5d} {l['notif']:5d} {l['peer']:5d} | {len(S):4d} "
          f"{' '.join(f'{m.replace(chr(99)+chr(108)+chr(97)+chr(117)+chr(100)+chr(101)+chr(45), str())}x{n}' for m, n in sm.most_common()):34} {sum(s['n_compact'] for s in S):9d}")
print()

# ---------------------------------------------------------------- 2 tokens
print('== 2. TOKENS (deduped: one usage record per message.id, the final line; see caveats)')
print(f"{'group':10} {'role':5} {'api calls':>9} {'output':>8} {'input':>8} {'cache_rd':>9} {'cache_wr':>9} {'naive_out':>9} {'ctx p50':>8} {'ctx p90':>8} {'ctx max':>8}")
tot = collections.Counter()
for g in ALLG + ['CREW']:
    for role in ('lead', 'sub'):
        ss = sel(None, role, crew=True) if g == 'CREW' else sel(g, role)
        if not ss: continue
        n, o, i, cr, cc, ctx = tok(ss)
        naive = sum(s['naive_out'] for s in ss)
        print(f"{g:10} {role:5} {n:9d} {k(o):>8} {k(i):>8} {k(cr):>9} {k(cc):>9} {k(naive):>9} {k(med(ctx)):>8} {k(pct(ctx,90)):>8} {k(max(ctx) if ctx else 0):>8}")
n, o, i, cr, cc, ctx = tok(sel(crew=True))
print(f"{'CREW':10} {'all':5} {n:9d} {k(o):>8} {k(i):>8} {k(cr):>9} {k(cc):>9}")
low = sum(1 for s in SS for m in s['msgs'].values() if m['usage'].get('output_tokens', 0) < m['max_out'])
multi = sum(1 for s in SS for m in s['msgs'].values() if m['lines'] > 1)
nofinal = sum(1 for s in SS for m in s['msgs'].values() if not m['final'])
print(f"dedupe check: {sum(len(s['msgs']) for s in SS)} unique message ids, {multi} span >1 line, "
      f"{nofinal} have no line with a stop_reason, {low} where the kept usage was below an earlier line (max used)\n")

# ---------------------------------------------------------------- 3 tool classes
ORDER = ['game:mutate', 'game:walk', 'game:wait', 'game:read', 'game:admin', 'wait', 'doc-read', 'doc-write',
         'script-write', 'file-read', 'compute', 'sysadmin', 'agent-spawn', 'sendmessage', 'monitor', 'harness', 'other']


def class_table(cs, title):
    print(title)
    print(f"{'class':13} {'n':>6} {'%n':>5} {'tot_min':>8} {'%t':>5} {'med_s':>6} {'p90_s':>6} {'max_s':>6} {'res_KB/call':>11}")
    agg = collections.defaultdict(list)
    for c in cs: agg[ckey(c)].append(c)
    T = sum(c['excl'] for c in cs) or 1
    for key in ORDER:
        v = agg.get(key)
        if not v: continue
        d = [c['excl'] for c in v]
        print(f"{key:13} {len(v):6d} {100*len(v)/len(cs):5.1f} {sum(d)/60:8.1f} {100*sum(d)/T:5.1f} {med(d):6.1f} {pct(d,90):6.1f} {max(d):6.0f} {sum(c['res_size'] for c in v)/len(v)/1024:11.1f}")
    print(f"{'TOTAL':13} {len(cs):6d} {'':5} {T/60:8.1f}")
    print()


print('== 3. TOOL CALLS BY CLASS (seconds = exclusive wall time from previous event to the tool result)')
class_table(calls_of(sel(crew=True)), '-- crew total (leads + subagents)')
class_table(calls_of(sel(role='lead', crew=True)), '-- lead sessions only')
class_table(calls_of(sel(role='sub', crew=True)), '-- subagents only')
print('-- per group (lead+subs): calls / minutes')
hdr = ['game:mutate', 'game:walk', 'game:wait', 'game:read', 'wait', 'doc-read', 'doc-write', 'script-write', 'file-read', 'agent-spawn', 'sendmessage', 'monitor']
print(f"{'group':10} {'role':5} " + ' '.join(f'{h[:11]:>11}' for h in hdr))
for g in ALLG:
    for role in ('lead', 'sub'):
        cs = calls_of(sel(g, role))
        if not cs: continue
        agg = collections.defaultdict(lambda: [0, 0.0])
        for c in cs:
            a = agg[ckey(c)]; a[0] += 1; a[1] += c['excl']
        print(f"{g:10} {role:5} " + ' '.join(f"{agg[h][0]:5d}/{agg[h][1]/60:5.0f}" for h in hdr))
print()

cs = calls_of(sel(crew=True))
pure_wait = [c for c in cs if c['cls'] == 'wait']
blocked = [c for c in pure_wait if c['is_error'] and c['dur'] < 2]
game_sleep = [c for c in cs if c['cls'] == 'game' and c['sleep_static'] > 0]
print('-- sleeping / waiting (crew)')
print(f"pure sleep/poll Bash calls (no game call inside): n={len(pure_wait)}  total {sum(c['excl'] for c in pure_wait)/3600:.2f} h  "
      f"med {med([c['excl'] for c in pure_wait]):.0f}s p90 {pct([c['excl'] for c in pure_wait],90):.0f}s ; rejected instantly (is_error, <2s): {len(blocked)}")
ow = [c for c in pure_wait if 'ops-watch' in ' '.join(c['scripts']) or False]
print(f"game calls with an embedded `sleep`: n={len(game_sleep)}  literal sleep seconds (capped at call duration) {sum(min(c['sleep_static'], c['excl']) for c in game_sleep)/3600:.2f} h  "
      f"(total duration of those calls {sum(c['excl'] for c in game_sleep)/3600:.2f} h)")
gw = [c for c in cs if ckey(c) == 'game:wait']; wk = [c for c in cs if ckey(c) == 'game:walk']
print(f"engine waits (factorio_wait): n={len(gw)} total {sum(c['excl'] for c in gw)/3600:.2f} h ; walks: n={len(wk)} total {sum(c['excl'] for c in wk)/3600:.2f} h")
allsleep = sum(c['excl'] for c in pure_wait) + sum(min(c['sleep_static'], c['excl']) for c in game_sleep) + sum(c['excl'] for c in gw)
print(f"=> blocked-on-clock total (pure waits + embedded sleeps + engine waits): {allsleep/3600:.2f} agent-hours ; + walking {sum(c['excl'] for c in wk)/3600:.2f} h")
for g in GROUPS:
    c2 = calls_of(sel(g))
    pw = sum(c['excl'] for c in c2 if c['cls'] == 'wait')
    es = sum(min(c['sleep_static'], c['excl']) for c in c2 if c['cls'] == 'game')
    ew = sum(c['excl'] for c in c2 if ckey(c) == 'game:wait')
    print(f"   {g:10} pure-wait {pw/3600:5.2f} h  embedded-sleep {es/3600:5.2f} h  engine-wait {ew/3600:5.2f} h")
print()

# ---------------------------------------------------------------- 4 time split
print('== 4. TIME SPLIT (agent-hours; sums over parallel sessions, so totals exceed wall time)')
print(f"{'group':10} {'role':5} {'span_h':>7} {'model_h':>8} {'tool_h':>7} {'idle_h':>7} {'cmpct_h':>7} {'%model':>6} {'%tool':>6} {'%idle':>6} | {'gen med':>7} {'p90':>6} {'ttfb med':>8} {'api':>6}")


def split_row(label, role, ss):
    if not ss: return
    span = sum(s['last'] - s['first'] for s in ss)
    gen = sum(s['gen'] for s in ss); tool = sum(s['tool'] for s in ss); idle = sum(s['idle'] for s in ss); cp = sum(s['compact'] for s in ss)
    g1 = [m['t1'] - m['trig'] for s in ss for m in s['msgs'].values()]
    g0 = [m['t0'] - m['trig'] for s in ss for m in s['msgs'].values()]
    T = gen + tool + idle + cp or 1
    print(f"{label:10} {role:5} {span/3600:7.1f} {gen/3600:8.2f} {tool/3600:7.2f} {idle/3600:7.2f} {cp/3600:7.2f} {100*gen/T:6.1f} {100*tool/T:6.1f} {100*idle/T:6.1f} | {med(g1):7.1f} {pct(g1,90):6.1f} {med(g0):8.1f} {len(g1):6d}")


for g in ALLG:
    for role in ('lead', 'sub'):
        split_row(g, role, sel(g, role))
split_row('CREW', 'lead', sel(role='lead', crew=True))
split_row('CREW', 'sub', sel(role='sub', crew=True))
split_row('CREW', 'all', sel(crew=True))
print("gen = trigger (tool result / user event) -> last content block of the reply; ttfb = trigger -> first block.\n")

# ---------------------------------------------------------------- 5 throughput
print('== 5. THROUGHPUT AND ERROR RATE (game-touching calls = game:mutate+walk+wait+read+admin)')
print(f"{'group':10} {'wall_h':>6} {'game':>6} {'/h':>6} {'mutate':>6} {'/h':>6} {'walk':>5} {'read':>6} {'read:mut':>8} {'static_inv':>10} {'err_strict':>10} {'err_loose':>9} {'mut_err':>8}")
W = (D['W1'] - D['W0']) / 3600


def thr(label, ss, wall):
    cs = [c for c in calls_of(ss) if c['cls'] == 'game']
    if not cs: return
    mu = [c for c in cs if c['sub'] == 'mutate']; rd = [c for c in cs if c['sub'] == 'read']; wkk = [c for c in cs if c['sub'] == 'walk']
    print(f"{label:10} {wall:6.1f} {len(cs):6d} {len(cs)/wall:6.1f} {len(mu):6d} {len(mu)/wall:6.1f} {len(wkk):5d} {len(rd):6d} {len(rd)/max(1,len(mu)):8.1f} "
          f"{sum(c['n_inv'] for c in cs):10d} {100*sum(c['err_strict'] for c in cs)/len(cs):9.1f}% {100*sum(c['err_loose'] for c in cs)/len(cs):8.1f}% {100*sum(c['err_strict'] for c in mu)/max(1,len(mu)):7.1f}%")


for g in ALLG:
    L = sel(g, 'lead')
    if L: thr(g, sel(g), (L[0]['last'] - L[0]['first']) / 3600)
thr('CREW', sel(crew=True), W)
cs = [c for c in calls_of(sel(crew=True)) if c['cls'] == 'game']
print(f"is_error flag only (harness-level failure): {100*sum(c['is_error'] for c in cs)/len(cs):.1f}% of game calls")
print()

# ---------------------------------------------------------------- 6 lua payloads
print('== 6. LUA PAYLOADS (crew; exec_lua-type calls where Lua text could be measured)')
ex = [c for c in cs if c.get('lua_len')]
for label, v in (('all exec', ex), ('mutating exec', [c for c in ex if c['sub'] == 'mutate']), ('read exec', [c for c in ex if c['sub'] == 'read'])):
    L = [c['lua_len'] for c in v]
    b = collections.Counter('<200' if x < 200 else '200-500' if x < 500 else '500-1k' if x < 1000 else '1k-2k' if x < 2000 else '2k-4k' if x < 4000 else '>4k' for x in L)
    print(f"{label:14} n={len(L):5d} chars p10={pct(L,10):.0f} p50={med(L):.0f} p90={pct(L,90):.0f} max={max(L) if L else 0}  buckets: " +
          ' '.join(f"{kk}:{100*b[kk]/max(1,len(L)):.0f}%" for kk in ['<200', '200-500', '500-1k', '1k-2k', '2k-4k', '>4k']))
mu = [c for c in cs if c['sub'] == 'mutate']
mex = [c for c in mu if c.get('lua_len') is not None]
ops = [c['lua_ops'] for c in mex]
b = collections.Counter('0' if x == 0 else '1' if x == 1 else '2-5' if x <= 5 else '6-20' if x <= 20 else '>20' for x in ops)
print(f"mutating Lua calls: static count of mutating statements per call: " + ' '.join(f"{kk}:{100*b[kk]/max(1,len(ops)):.0f}%" for kk in ['0', '1', '2-5', '6-20', '>20']) +
      f" ; contains a Lua for-loop: {100*sum(1 for c in mex if c.get('lua_loop'))/max(1,len(mex)):.0f}%")
vd = [c for c in mu if c.get('lua_len') is None]
print(f"mutating calls without Lua (single verbs take/insert/build/mine/craft via act.sh|rlm.sh|lib script): n={len(vd)}, static verb invocations per call: med {med([c['n_inv'] for c in vd]):.0f} p90 {pct([c['n_inv'] for c in vd],90):.0f}")
print('source of game calls (all / mutate):')
sa = collections.Counter(c['src'] for c in cs); sm = collections.Counter(c['src'] for c in mu)
for s_, n in sa.most_common():
    print(f"   {s_:26} {n:6d} {100*n/len(cs):5.1f}%   mutate {sm[s_]:5d} {100*sm[s_]/max(1,len(mu)):5.1f}%")
libn = sum(n for s_, n in sa.items() if 'lib-' in s_)
libm = sum(n for s_, n in sm.items() if 'lib-' in s_)
print(f"   => any research/lib purpose-built script or .lua: {libn} ({100*libn/len(cs):.1f}%) of game calls, {libm} ({100*libm/max(1,len(mu)):.1f}%) of mutating calls; the rest inline or /tmp files")
print()

# ---------------------------------------------------------------- 7 subagents
print('== 7. SUBAGENTS (crew)')
subs = sel(role='sub', crew=True)
rows = []
for s in subs:
    c = [x for x in s['calls'] if 't1' in x]
    game = [x for x in c if x['cls'] == 'game']
    fm = next((i for i, x in enumerate(c) if x['cls'] == 'game' and x['sub'] in ('mutate', 'walk')), None)
    fg = next((i for i, x in enumerate(c) if x['cls'] == 'game'), None)
    out = tok([s])[1]
    rows.append(dict(s=s, n=len(c), game=len(game), mut=sum(1 for x in game if x['sub'] == 'mutate'), fm=fm, fg=fg, out=out,
                     life=(s['last'] - s['first']) / 60, active=(s['gen'] + s['tool']) / 60,
                     pre_t=(c[fm]['t0'] - s['first']) / 60 if fm is not None else None,
                     ctx=max(tok([s])[5] or [0])))
workers = [r for r in rows if r['game'] > 0]
movers = [r for r in rows if r['fm'] is not None]
nong = [r for r in rows if r['game'] == 0]
print(f"subagents active in window: {len(rows)} ; with >=1 game call: {len(workers)} ; with >=1 mutating/walk call: {len(movers)} ; no game call at all (planners, reviewers, misc): {len(nong)}")


def dist(label, xs, f='{:.0f}'):
    print(f"  {label:44} p10 {f.format(pct(xs,10)):>7} p50 {f.format(med(xs)):>7} p90 {f.format(pct(xs,90)):>7} max {f.format(max(xs) if xs else 0):>7} sum {f.format(sum(xs)):>9}")


for label, grp in (('game workers', workers), ('non-game subagents', nong)):
    print(f"-- {label} (n={len(grp)})")
    dist('lifetime first->last event (min)', [r['life'] for r in grp])
    dist('active = model+tool time (min)', [r['active'] for r in grp])
    dist('tool calls', [r['n'] for r in grp])
    dist('output tokens', [r['out'] for r in grp])
    dist('peak prompt size (tokens)', [r['ctx'] for r in grp])
print(f"-- orientation overhead, subagents that reached a mutating/walk call (n={len(movers)})")
dist('tool calls before first mutate/walk', [r['fm'] for r in movers])
dist('fraction of all calls before first mutate (%)', [100 * r['fm'] / r['n'] for r in movers], '{:.1f}')
dist('minutes before first mutate/walk', [r['pre_t'] for r in movers], '{:.1f}')
dist('calls before first game call of any kind', [r['fg'] for r in workers])
pre = collections.Counter()
for r in movers:
    for x in [x for x in r['s']['calls'] if 't1' in x][:r['fm']]:
        pre[ckey(x)] += 1
tp = sum(pre.values()) or 1
print('  what the pre-mutate calls were: ' + ' '.join(f"{a}:{100*n/tp:.0f}%" for a, n in pre.most_common(8)))
nomut = [r for r in workers if r['fm'] is None]
print(f"  game workers that never issued a mutating/walk call: {len(nomut)} (their calls: {sum(r['n'] for r in nomut)}, output tokens {k(sum(r['out'] for r in nomut))})")
print('-- per group')
for g in GROUPS:
    rr = [r for r in rows if r['s']['group'] == g]
    if not rr: continue
    mv = [r for r in rr if r['fm'] is not None]
    print(f"  {g:10} subs {len(rr):3d} workers {len([r for r in rr if r['game']]):3d} life p50 {med([r['life'] for r in rr]):5.0f} min  calls p50 {med([r['n'] for r in rr]):4.0f}  "
          f"out-tok p50 {k(med([r['out'] for r in rr])):>6}  pre-mutate calls p50 {med([r['fm'] for r in mv]) if mv else 0:4.0f} ({med([100*r['fm']/r['n'] for r in mv]) if mv else 0:.0f}% of calls)")
print()

# ---------------------------------------------------------------- 8 docs, messaging
print('== 8. DOCS / MESSAGING (crew)')
cs_all = calls_of(sel(crew=True))
rd = collections.Counter(); wr = collections.Counter(); rdkb = collections.Counter()
for c in cs_all:
    for m in set(c['md']):
        name = 'HANDOFF-*.md' if m.startswith('HANDOFF') else m
        if c['md_write']: wr[name] += 1
        else:
            rd[name] += 1; rdkb[name] += c['res_size'] / 1024
print('most-read docs (calls referencing the file without writing it; KB = size of those tool results):')
for name, n in rd.most_common(12):
    print(f"   {name:28} reads {n:5d}  result KB {rdkb[name]:8.0f}   writes {wr[name]:5d}")
print('most-written docs: ' + ', '.join(f"{a} {n}" for a, n in wr.most_common(8)))
sm_ = collections.Counter((c['group'], c['role']) for c in cs_all if c['cls'] == 'sendmessage')
print('SendMessage by group/role: ' + ', '.join(f"{g}/{r} {n}" for (g, r), n in sm_.most_common()))
ag = collections.Counter(c['group'] for c in cs_all if c['cls'] == 'agent-spawn')
print('Agent spawns by group: ' + ', '.join(f"{g} {n}" for g, n in ag.most_common()))
big = sorted(cs_all, key=lambda c: -c['res_size'])[:1]
tot_res = collections.Counter()
for c in cs_all: tot_res[ckey(c)] += c['res_size']
print('tool-result volume by class (MB of text returned to models): ' + ', '.join(f"{a} {n/1e6:.1f}" for a, n in tot_res.most_common(8)))
