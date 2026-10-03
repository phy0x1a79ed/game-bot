#!/usr/bin/env python3
"""bld.py SPEC [--stands x,y;x,y;...] [--dry]
SPEC lines: name x y [dir]   (dir: north|east|south|west or N/E/S/W; default north)
Each entity is built from the nearest stand point (<=9.8 tiles). Walks between stands."""
import sys, subprocess, math, json, re
LIB="/home/tony/agentic_workspace/projects/game-bot/factorio/research/lib"
import os
SEAT=os.environ.get("RLM_SEAT") or sys.exit("build-list.py: set RLM_SEAT to your own seat id")
D={'N':'north','E':'east','S':'south','W':'west','north':'north','east':'east','south':'south','west':'west'}
def sh(*a):
    return subprocess.run(a,capture_output=True,text=True).stdout
def main():
    spec=sys.argv[1]; stands=[]; dry=False
    for i,a in enumerate(sys.argv):
        if a=='--stands': stands=[tuple(map(float,s.split(','))) for s in sys.argv[i+1].split(';')]
        if a=='--dry': dry=True
    ents=[]
    for ln in open(spec):
        ln=ln.split('#')[0].strip()
        if not ln: continue
        p=ln.split(); n=p[0]; x=float(p[1]); y=float(p[2]); d=D[p[3]] if len(p)>3 else 'north'
        ents.append((n,x,y,d))
    groups={s:[] for s in stands}
    for e in ents:
        best=min(stands,key=lambda s:math.hypot(s[0]-e[1],s[1]-e[2]))
        if math.hypot(best[0]-e[1],best[1]-e[2])>10.0: print("TOO FAR",e); continue
        groups[best].append(e)
    # order stands by nearest-neighbour from first
    order=[]; cur=stands[0]; rem=[s for s in stands if groups[s]]
    while rem:
        nxt=min(rem,key=lambda s:math.hypot(s[0]-cur[0],s[1]-cur[1])); order.append(nxt); rem.remove(nxt); cur=nxt
    for s in order:
        es=groups[s]
        print("stand",s,len(es),"entities")
        if dry: continue
        out=sh(LIB+"/walk.sh",SEAT,str(s[0]),str(s[1]),"1.5"); print(" ",out.strip())
        lua="local seat='%s' local function B(n,x,y,d) local ok,e=pcall(remote.call,'game_bot','build',{seat=seat,name=n,x=x,y=y,direction=d}) if not ok then rcon.print('FAIL '..n..' '..x..','..y..' '..tostring(e):sub(1,160)) elseif type(e)=='table' and e.ok==false then rcon.print('FAIL '..n..' '..x..','..y..' '..serpent.line(e)) end end "%SEAT
        for (n,x,y,d) in es: lua+="B('%s',%s,%s,'%s') "%(n,x,y,d)
        lua+="rcon.print('done')"
        r=sh(LIB+"/act.sh","exec_lua",SEAT,"code="+lua)
        try: print(" ",json.loads(r).get('output',r).strip())
        except Exception: print(" ",r.strip()[:600])
main()
