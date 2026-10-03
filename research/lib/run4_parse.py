"""Parse run-4 crew transcripts into per-call and per-session records (pickled for run4_report.py)."""
import json, re, os, glob, pickle, collections, sys
from datetime import datetime

ROOT = os.path.expanduser('~/.claude/projects/-home-tony-agentic-workspace-projects-game-bot-factorio')
LIB = '/home/tony/agentic_workspace/projects/game-bot/factorio/research/lib'
OUT = os.path.dirname(os.path.abspath(__file__))

# (group label, session id). Two ops sessions: the Sonnet one was replaced by the Opus one at 08:33Z.
SESSIONS = [
    ('chair', '09751804-a330-447f-81bb-34e0ec4985e0'),
    ('ops-s55', '27f04c43-71ae-4ff2-9d33-d080374c2142'),
    ('ops', '0b5e7a11-8922-4b78-99e2-c1f01df5a93e'),
    ('builder1', '43e96a94-7887-4f22-a6c4-c9a7400880d6'),
    ('builder2', '33390d46-07b2-4a76-b980-7b0767babd0e'),
    ('military', '407c2860-0096-4cd4-8a67-4d84dc36e765'),
    ('perf-tool', '982c5b73-9168-4c30-8514-9bb43607384a'),
]


def ts(s):
    return datetime.fromisoformat(s.replace('Z', '+00:00')).timestamp()


W0 = ts(sys.argv[1] if len(sys.argv) > 1 else '2026-10-03T04:45:00Z')
W1 = ts(sys.argv[2] if len(sys.argv) > 2 else '2026-10-03T21:20:00Z')
TAG = sys.argv[3] if len(sys.argv) > 3 else 'win'

ENTRY = re.compile(r'act\.sh|rlm\.sh|/invoke|rlm_factorio|awm rlm|walk\.sh|scan\.sh|-do\.sh')
LUA_TOK = re.compile(r'game\.surfaces|rcon\.print|remote\.call|game\.players|game\.forces|find_entities|game\.tick|game\.connected_players|serpent\.')
MUT_TOK = re.compile(
    r'create_entity|order_deconstruction|order_upgrade|cancel_deconstruction|cancel_upgrade|set_recipe|set_filter|'
    r'\.insert\s*[({]|remove_item|cursor_stack|use_from_cursor|shooting_state|walking_state|clear_cursor|\.rotate\(|'
    r'\.direction\s*=[^=]|\.recipe\s*=[^=]|\.bar\s*=[^=]|set_bar|add_research|research_queue\s*=|queue_research|'
    r'add_chart_tag|set_request_slot|set_logistic|\.revive|\.destroy\(|\.die\(|\.mine\s*[({]|teleport|set_stack|'
    r'swap_stack|transfer_stack|\.active\s*=[^=]|_priority\s*=[^=]|pickup_position\s*=[^=]|drop_position\s*=[^=]|'
    r'set_circuit|circuit_condition\s*=|\.clear\(\)|set_driving|riding_state|selected_gun_index\s*=|insert_plan|removal_plan')
REMOTE_VERB = re.compile(r'''remote\.call[,(]\s*['"]game_bot['"]\s*,\s*['"](\w+)''')
HELPER_CALL = re.compile(r'(?<![\w.])[TICB]\(')
READ_V = {'observe', 'scan', 'status', 'seats', 'describe', 'order', 'inventory', 'find', 'read', 'path', 'map',
          'events', 'observe_events', 'research_status', 'help', 'schema', 'list', 'get', 'state', 'position', 'tick',
          'blueprint_read', 'look', 'info', 'query', 'ping'}
WALK_V = {'walk', 'move', 'walk_to', 'stop', 'goto'}
WAIT_V = {'wait'}
ADMIN_V = {'join', 'leave', 'rejoin', 'acquire', 'release', 'world_save', 'world_load', 'world_new', 'pause',
           'resume', 'reset', 'save', 'unpause'}
MUT_V = {'take', 'insert', 'build', 'mine', 'craft', 'throw', 'place', 'research', 'set_recipe', 'filter', 'respawn',
         'put', 'pickup', 'script_run', 'script_define', 'rotate', 'drop', 'shoot', 'deconstruct', 'repair', 'equip',
         'blueprint_stamp', 'use', 'attack', 'fire'}
_WK = {}


def wrapper_kind(stem):
    if stem not in _WK:
        b = SCRIPT_BODIES.get(stem, '')
        vs = set(re.findall(r'(?:act\.sh|rlm\.sh)["\']?\s+"?([a-z_-]+)', b)) | set(re.findall(r'rlm_factorio_([a-z_]+)', b)) \
            | set(REMOTE_VERB.findall(b))
        vs = {v.replace('-', '_') for v in vs}
        generic = bool(re.search(r'exec.lua|rcon', b, re.I)) and bool(re.search(r'\$1|\$@|\$\*|sys\.argv|stdin|\$\(cat', b)) \
            and not (vs & MUT_V)
        if generic: _WK[stem] = 'generic'
        elif vs & MUT_V or MUT_TOK.search(b) or re.search(r'-do\.sh|build|place', b): _WK[stem] = 'mutate'
        elif vs & WALK_V or 'walk' in b: _WK[stem] = 'walk'
        else: _WK[stem] = 'generic'
    return _WK[stem]


EXEC_V = {'exec_lua', 'exec-lua', 'exec'}
PRIMS = {'act', 'rlm', 'walk', 'safe-walk', 'scan'}
READ_NAME = re.compile(r'scan|map|area|watch|check|status|alerts|find-|trace|fluid-net|pe-read|pe-state|readat|'
                       r'guard-enemy|guard-targets|infrab-q|audit|belt-path|survey|ops-rcon-procs|dashboard')
READ_MODE = re.compile(r'''\b(check|dry|read|plan|verify)\b|--dry|MODE=['"]?(read|check|dry|plan)''')
HEREDOC = re.compile(r'<<-?\s*([\'"]?)(\w+)\1([^\n]*)\n(.*?)\n\s*\2\b', re.S)
QUOTED = re.compile(r'"((?:[^"\\]|\\.)*)"|\'([^\']*)\'', re.S)
SLEEP = re.compile(r'\bsleep\s+(\d+(?:\.\d+)?)([smh]?)')
MD = re.compile(r'([\w.$/{}-]*[\w-]+\.md)\b')
ERR_STRICT = re.compile(r'"ok"\s*:\s*false|attempt to|nil value|path_blocked|Traceback|REFUSED|OVER_BUDGET|'
                        r'\bERR\b|"error"\s*:\s*"|Exit code [1-9]|command not found|No such file|timed out|STUCK|'
                        r'not connected|Cannot execute command')
ERR_LOOSE = re.compile(r'error|path_blocked|cannot|nil value|attempt to', re.I)


def lib_game_scripts():
    s = set()
    for f in glob.glob(LIB + '/*.sh') + glob.glob(LIB + '/*.py'):
        try:
            if ENTRY.search(open(f, errors='replace').read()):
                s.add(os.path.basename(f).rsplit('.', 1)[0])
        except OSError:
            pass
    return s


GAME_LIB = lib_game_scripts()
LIB_LUA = {os.path.basename(f) for f in glob.glob(LIB + '/*.lua')}
LIB_ALL = {os.path.basename(f) for f in glob.glob(LIB + '/*')}
WRAPPERS = set()          # ad-hoc game wrappers created outside lib (basename without extension)
SCRIPT_BODIES = {}
LUA_BODIES = {}           # basename -> last body written (heredoc or Write tool)


def split_heredocs(c):
    """Return (exec_text, writes) where writes = [(path, body)] for heredocs redirected into a file."""
    writes, out, pos = [], [], 0
    for m in HEREDOC.finditer(c):
        line_start = c.rfind('\n', 0, m.start()) + 1
        head = c[line_start:m.start()] + m.group(3)
        w = re.search(r'(?:cat|tee)\s*(?:-a\s*)?>{0,2}\s*([^\s<>;|&]+)|>{1,2}\s*([^\s<>;|&]+)', head)
        if w and re.search(r'\b(cat|tee)\b', head):
            writes.append(((w.group(1) or w.group(2) or '').strip('"\''), m.group(4)))
            out.append(c[pos:m.start()] + ' <<HEREDOC_FILE ')
        else:
            out.append(c[pos:m.end()])
        pos = m.end()
    out.append(c[pos:])
    return ''.join(out), writes


def base(p):
    return os.path.basename(p.strip('"\''))


def discover(files):
    for f in files:
        for line in open(f):
            if '"tool_use"' not in line:
                continue
            d = json.loads(line)
            for b in (d.get('message') or {}).get('content') or []:
                if not isinstance(b, dict) or b.get('type') != 'tool_use':
                    continue
                inp = b.get('input') or {}
                if b['name'] in ('Bash', 'bash'):
                    _, writes = split_heredocs(inp.get('command', ''))
                elif b['name'] == 'Write':
                    writes = [(inp.get('file_path', ''), inp.get('content', ''))]
                else:
                    continue
                for path, body in writes:
                    bn = base(path)
                    if bn.endswith('.lua'):
                        LUA_BODIES[bn] = body
                    elif bn.endswith(('.sh', '.py')):
                        SCRIPT_BODIES[bn.rsplit('.', 1)[0]] = SCRIPT_BODIES.get(bn.rsplit('.', 1)[0], '') + body
    changed = True
    while changed:
        changed = False
        for stem, body in SCRIPT_BODIES.items():
            if stem in WRAPPERS or stem in PRIMS:
                continue
            hit = ENTRY.search(body) or 'rcon' in body.lower()
            if not hit:
                for m in re.finditer(r'(?<![\w-])([\w-]+)\.(?:sh|py)\b|\bimport\s+(\w+)', body):
                    x = m.group(1) or m.group(2)
                    if x in WRAPPERS or x in GAME_LIB:
                        hit = True; break
            if hit:
                WRAPPERS.add(stem); changed = True


def lua_text_for(exec_text, writes):
    """Lua visible to the classifier: inline text, lua heredocs, and bodies of referenced .lua files."""
    parts, refs, written = [exec_text], [], set()
    for path, body in writes:
        bn = base(path)
        if bn.endswith('.lua') or LUA_TOK.search(body):
            parts.append(body); written.add(bn)
    for m in re.finditer(r'([\w./${}-]+\.lua)\b', exec_text):
        bn = base(m.group(1))
        refs.append(bn)
        if bn in written:
            continue
        p = os.path.join(LIB, bn)
        if bn in LIB_LUA:
            try:
                parts.append(open(p, errors='replace').read())
            except OSError:
                pass
        elif bn in LUA_BODIES:
            parts.append(LUA_BODIES[bn])
    return '\n'.join(parts), refs, written


def classify_bash(c):
    r = dict(cls='other', sub='', verbs=[], n_inv=0, lua_len=None, lua_ops=0, src='', sleep_static=0.0,
             loop=False, md=[], md_write=False, scripts=[], lua_loop=False)
    exec_text, writes = split_heredocs(c)
    verbs = [m.group(1).replace('-', '_') for m in re.finditer(r'act\.sh["\']?\s+"?([a-z_]+)', exec_text)]
    verbs += [m.group(1).replace('-', '_') for m in re.finditer(r'rlm\.sh["\']?\s+"?([a-z_-]+)', exec_text)]
    verbs += [m.group(1) for m in re.finditer(r'rlm_factorio_([a-z_]+)', exec_text)]
    verbs += [m.group(1).replace('-', '_') for m in re.finditer(r'rlm\s+"?factorio-([a-z_-]+)', exec_text)]
    for am in re.finditer(r'\b(\w+)=["\']?[^\s;"\']*(?:act|rlm)\.sh["\']?\s*(?:;|\n|&&)', exec_text):
        verbs += [m.group(1).replace('-', '_') for m in
                  re.finditer(r'"?\$\{?' + am.group(1) + r'\}?"?\s+"?([a-z_-]+)', exec_text)]
    n_inv = len(verbs)
    scripts = []
    for m in re.finditer(r'(?<![\w-])([\w-]+)\.(sh|py)\b', exec_text):
        stem = m.group(1)
        if stem in ('act', 'rlm'):
            continue
        if stem in GAME_LIB and (stem + '.' + m.group(2)) in LIB_ALL:
            scripts.append(('lib', stem, exec_text[m.end():m.end() + 120]))
        elif stem in WRAPPERS:
            scripts.append(('tmp', stem, exec_text[m.end():m.end() + 120]))
    for m in re.finditer(r'\bimport\s+(\w+)', exec_text):
        if m.group(1) in WRAPPERS:
            scripts.append(('tmp', m.group(1), ''))
    # a script that is only being written/read/edited (cat, sed, grep, chmod ...) is not a run
    run_scripts = []
    for kind, stem, tail in scripts:
        pat = re.compile(r'(?:^|[;&|\n(]|\bdo\b|\bthen\b|\btimeout\s+\d+|\bnohup\b|\bbash\b|\bpython3?\b)\s*'
                         r'(?:[A-Z_]+=\S+\s+)*\S*' + re.escape(stem) + r'\.(?:sh|py)\b')
        if pat.search(exec_text):
            run_scripts.append((kind, stem, tail))
    n_inv += len(run_scripts)
    lua, refs, written = lua_text_for(exec_text, writes)
    r['scripts'] = [s for _, s, _ in run_scripts]
    for m in SLEEP.finditer(exec_text):
        r['sleep_static'] += float(m.group(1)) * {'': 1, 's': 1, 'm': 60, 'h': 3600}[m.group(2)]
    r['loop'] = bool(re.search(r'\b(until|while|for)\b', exec_text))
    mds = [base(m.group(1)) for m in MD.finditer(exec_text)]
    r['md'] = mds
    r['md_write'] = bool(re.search(r'>>?\s*"?[\w./${}-]*\.md\b|sed\s+-i[^|;]*\.md\b', exec_text)) or \
        any(base(p).endswith('.md') for p, _ in writes) or bool(re.search(r'>>\s*"?\$\{?(B|BOARD)\b', exec_text)) or \
        bool(mds and re.search(r'''\.write\(|write_text|open\([^)]*,\s*['"][wa]''', exec_text))
    fallback = False
    if not (verbs or run_scripts) and LUA_TOK.search(exec_text) and re.search(
            r'(?:^|[;&|\n(]|\bdo\b)\s*(?:[A-Z_]+=\S+\s+)*\S+\.(?:sh|py)\b[^\n]*(?:["\']|<<)|python3?\s+-', exec_text):
        fallback = True
    is_game = bool(verbs or run_scripts or fallback)
    if is_game:
        allv = set(verbs) | {v for v in REMOTE_VERB.findall(lua)}
        mut = walk = wait = admin = False
        readish = bool(READ_MODE.search(exec_text))
        verbs = [v[9:] if v.startswith('factorio_') else v for v in verbs]
        for v in verbs:
            if v in WALK_V: walk = True
            elif v in WAIT_V: wait = True
            elif v in ADMIN_V: admin = True
            elif v in MUT_V: mut = True
        has_exec = any(v in EXEC_V for v in verbs) or fallback
        for kind, stem, tail in run_scripts:
            if re.search(r'walk|patrol', stem): walk = True
            elif stem == 'wait-item': wait = True
            elif stem.endswith('-do') or (kind == 'tmp' and wrapper_kind(stem) == 'generic'):
                has_exec = True
                if HELPER_CALL.search(exec_text): mut = True
            elif kind == 'tmp':
                wk = wrapper_kind(stem)
                if wk == 'mutate' and not READ_MODE.search(tail): mut = True
                elif wk == 'walk': walk = True
            elif READ_NAME.search(stem): pass
            elif READ_MODE.search(tail): pass
            else: mut = True
        if has_exec or refs:
            lua_mut = bool(MUT_TOK.search(lua)) or any(v in MUT_V for v in REMOTE_VERB.findall(lua))
            if any(v in WALK_V for v in REMOTE_VERB.findall(lua)): walk = True
            if lua_mut and not readish: mut = True
        r['sub'] = 'mutate' if mut else 'walk' if walk else 'wait' if wait else 'admin' if admin else 'read'
        r['cls'] = 'game'
        r['verbs'] = sorted(allv)
        r['n_inv'] = n_inv
        # Lua payload size and where it came from
        if has_exec or refs:
            n = 0
            for m in QUOTED.finditer(exec_text):
                q = m.group(1) if m.group(1) is not None else m.group(2)
                if LUA_TOK.search(q) or (HELPER_CALL.search(q) and any(s.endswith('-do') for s in r['scripts'])):
                    n += len(q)
            file_n = 0
            for path, body in writes:
                if base(path).endswith('.lua') or LUA_TOK.search(body):
                    file_n += len(body)
            lib_ref = [x for x in refs if x in LIB_LUA]
            tmp_ref = [x for x in refs if x not in LIB_LUA]
            for x in set(refs) - written:
                if x in LIB_LUA:
                    try: file_n += os.path.getsize(os.path.join(LIB, x))
                    except OSError: pass
                elif x in LUA_BODIES:
                    file_n += len(LUA_BODIES[x])
            r['lua_len'] = n + file_n
            r['lua_inline'] = n
            r['lua_file'] = file_n
            r['lua_ops'] = len(MUT_TOK.findall(lua)) + len(REMOTE_VERB.findall(lua)) + \
                (len(HELPER_CALL.findall(exec_text)) if any(s.endswith('-do') for s in r['scripts']) else 0)
            r['lua_loop'] = bool(re.search(r'\bfor\b.*\bdo\b', lua, re.S))
            if lib_ref: r['src'] = 'lib-lua'
            elif tmp_ref or file_n: r['src'] = 'tmp-lua-file'
            else: r['src'] = 'inline-lua'
        libs = [s for k, s, _ in run_scripts if k == 'lib' and s not in PRIMS]
        tmps = [s for k, s, _ in run_scripts if k == 'tmp']
        if not r['src']:
            r['src'] = 'lib-script' if libs else 'tmp-wrapper' if (tmps or fallback) else 'verb-direct'
        elif libs and r['src'] != 'lib-lua':
            r['src'] += '+lib-script'
        return r
    wr_script = [p for p, _ in writes if not base(p).endswith('.md')]
    if r['sleep_static'] or re.search(r'ops-watch\.sh|inotifywait|tail\s+-f|\buntil\b.*\bdo\b', exec_text, re.S):
        r['cls'] = 'wait'
    elif r['md_write']:
        r['cls'] = 'doc-write'
    elif wr_script or re.search(r'sed\s+-i|\bchmod\b|\bcp\b|\bmv\b|tee\s', exec_text):
        r['cls'] = 'script-write'
    elif mds:
        r['cls'] = 'doc-read'
    elif re.search(r'python3?\b', exec_text):
        r['cls'] = 'compute'
    elif re.match(r'\s*(\w+=\S+;?\s*)*(cd\s+\S+\s*(;|&&)\s*)?(\w+=\S+;?\s*)*(cat|head|tail|grep|ls|sed|wc|find|jq|cut|awk|date|diff|stat|file)\b', exec_text):
        r['cls'] = 'file-read'
    elif re.search(r'\b(git|docker|pgrep|pkill|kill|ps|awm|systemctl|curl)\b', exec_text):
        r['cls'] = 'sysadmin'
    return r


def classify(name, inp):
    if name in ('Bash', 'bash'):
        r = classify_bash(inp.get('command', ''))
        r['bg'] = bool(inp.get('run_in_background'))
        r['cmd_len'] = len(inp.get('command', ''))
        return r
    r = dict(cls='harness', sub=name, verbs=[], n_inv=0, lua_len=None, lua_ops=0, src='', sleep_static=0.0,
             loop=False, md=[], md_write=False, scripts=[], bg=False, cmd_len=len(json.dumps(inp)))
    if name in ('Read', 'Grep', 'Glob'):
        p = inp.get('file_path') or inp.get('path') or ''
        r['cls'] = 'doc-read' if p.endswith('.md') else 'file-read'
        if p.endswith('.md'): r['md'] = [base(p)]
    elif name in ('Write', 'Edit', 'NotebookEdit'):
        p = inp.get('file_path') or ''
        r['cls'] = 'doc-write' if p.endswith('.md') else 'script-write'
        if p.endswith('.md'): r['md'] = [base(p)]; r['md_write'] = True
    elif name in ('Agent', 'Task'):
        r['cls'] = 'agent-spawn'
    elif name == 'SendMessage':
        r['cls'] = 'sendmessage'
    elif name == 'Monitor':
        r['cls'] = 'monitor'
    elif name == 'mcp__awm__rlm':
        v = (inp.get('verb') or '').replace('factorio_', '')
        r['cls'] = 'game'; r['verbs'] = [v]; r['n_inv'] = 1; r['src'] = 'mcp'
        r['sub'] = ('read' if v in READ_V else 'walk' if v in WALK_V else 'wait' if v in WAIT_V
                    else 'admin' if v in ADMIN_V else 'mutate')
        if v in EXEC_V:
            code = (inp.get('args') or {}).get('code', '')
            r['lua_len'] = len(code); r['sub'] = 'mutate' if MUT_TOK.search(code) else 'read'
    elif name == 'mcp__awm__reflection':
        r['cls'] = 'harness'; r['sub'] = 'reflection:' + str(inp.get('verb'))
    return r


def result_text(cont):
    if isinstance(cont, str):
        return cont
    if isinstance(cont, list):
        return '\n'.join(b.get('text', '') for b in cont if isinstance(b, dict) and b.get('type') == 'text')
    return ''


def parse(path, group, role, agent, desc):
    S = dict(group=group, role=role, agent=agent, desc=desc, path=path, models=collections.Counter(),
             first=None, last=None, gen=0.0, tool=0.0, idle=0.0, compact=0.0, n_compact=0, compact_ms=0,
             msgs={}, turns=0, human=0, notif=0, peer=0, first_all=None, last_all=None, naive_out=0)
    calls, order = {}, []
    pending = set()
    tp, pk, pid = None, None, None       # previous event time / kind / message id
    trigger = None                       # time of the event that triggered the current API call
    msg_end = {}                         # message id -> last line ts
    for line in open(path):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        t = d.get('timestamp')
        if not t:
            continue
        t = ts(t)
        S['first_all'] = S['first_all'] or t; S['last_all'] = t
        if t < W0 or t > W1:
            continue
        typ = d.get('type')
        m = d.get('message') or {}
        if typ == 'system':
            st = d.get('subtype')
            if st == 'compact_boundary':
                S['n_compact'] += 1
                S['compact_ms'] += (d.get('compactMetadata') or {}).get('durationMs', 0)
            elif st == 'turn_duration':
                S['turns'] += 1
            if st != 'scheduled_task_fire':
                continue
            kind = 'U'
        elif typ == 'assistant':
            if m.get('model') == '<synthetic>':
                continue
            kind = 'A'
        elif typ == 'user':
            cont = m.get('content')
            if isinstance(cont, list) and any(isinstance(b, dict) and b.get('type') == 'tool_result' for b in cont):
                kind = 'R'
            elif d.get('isCompactSummary'):
                kind = 'C'
            else:
                kind = 'U'
                o = (d.get('origin') or {}).get('kind')
                if o == 'human': S['human'] += 1
                elif o == 'task-notification': S['notif'] += 1
                elif o == 'peer': S['peer'] += 1
        else:
            continue
        S['first'] = S['first'] or t; S['last'] = t
        gap = max(0.0, t - tp) if tp is not None else 0.0
        if kind == 'A':
            mid = m.get('id')
            S['gen'] += gap
            u = m.get('usage') or {}
            S['naive_out'] += u.get('output_tokens', 0)
            rec = S['msgs'].get(mid)
            if rec is None:
                trig = tp if tp is not None else t
                rec = S['msgs'][mid] = dict(t0=t, t1=t, trig=trig, model=m.get('model'), usage=u,
                                            final=bool(m.get('stop_reason')), lines=0, max_out=0)
                S['models'][m.get('model')] += 1
            rec['t1'] = t; rec['lines'] += 1
            rec['max_out'] = max(rec['max_out'], u.get('output_tokens', 0))
            if m.get('stop_reason') or not rec['final']:
                rec['usage'] = u
                rec['final'] = rec['final'] or bool(m.get('stop_reason'))
            for b in m.get('content') or []:
                if isinstance(b, dict) and b.get('type') == 'tool_use':
                    c = classify(b['name'], b.get('input') or {})
                    c.update(id=b['id'], name=b['name'], t0=t, mid=mid, group=group, role=role, agent=agent)
                    calls[b['id']] = c; order.append(b['id']); pending.add(b['id'])
            pid = mid
        elif kind == 'R':
            S['tool'] += gap
            for b in m['content']:
                if isinstance(b, dict) and b.get('type') == 'tool_result' and b.get('tool_use_id') in calls:
                    c = calls[b['tool_use_id']]
                    if 't1' in c:
                        continue
                    c['t1'] = t
                    c['dur'] = t - c['t0']
                    c['excl'] = gap if pk in ('A', 'R') else max(0.0, t - c['t0'])
                    txt = result_text(b.get('content'))
                    c['res_size'] = len(txt)
                    c['is_error'] = bool(b.get('is_error'))
                    head = txt[:20000]
                    c['err_strict'] = c['is_error'] or bool(ERR_STRICT.search(head))
                    c['err_loose'] = c['is_error'] or bool(ERR_LOOSE.search(head))
                    pending.discard(b['tool_use_id'])
        elif kind == 'C':
            S['compact'] += gap
        else:
            if pending: S['tool'] += gap
            elif pk == 'R': S['gen'] += gap
            else: S['idle'] += gap
        tp, pk = t, kind
    S['calls'] = [calls[i] for i in order]
    return S


def main():
    files = []
    for group, sid in SESSIONS:
        top = f'{ROOT}/{sid}.jsonl'
        files.append((top, group, 'lead', sid[:8], group + ' lead'))
        for f in sorted(glob.glob(f'{ROOT}/{sid}/subagents/agent-*.jsonl')):
            try:
                meta = json.load(open(f.replace('.jsonl', '.meta.json')))
            except (OSError, ValueError):
                meta = {}
            files.append((f, group, 'sub', os.path.basename(f)[6:-6], meta.get('description', '')))
    discover([f[0] for f in files])
    out = []
    for f in files:
        s = parse(*f)
        if s['first'] is not None:
            out.append(s)
    pickle.dump(dict(sessions=out, W0=W0, W1=W1, wrappers=sorted(WRAPPERS), game_lib=sorted(GAME_LIB)),
                open(f'{OUT}/run4_{TAG}.pkl', 'wb'))
    print('files', len(files), 'in-window', len(out), 'wrappers', len(WRAPPERS), sorted(WRAPPERS)[:80])
    print('calls', sum(len(s['calls']) for s in out))


if __name__ == '__main__':
    main()
