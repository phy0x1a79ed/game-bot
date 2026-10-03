import math, collections
# recipe: (energy, {ing:amt}, out_amt, machine)
R={
 'red':(5,{'copper':1,'gear':1},1,'am2'),
 'green':(6,{'belt':1,'inserter':1},1,'am2'),
 'blue':(24,{'sulfur':1,'adv':3,'engine':2},2,'am2'),
 'military':(10,{'piercing':1,'grenade':1,'wall':2},2,'am2'),
 'production':(21,{'rail':30,'efurnace':1,'prodmod':1},3,'am2'),
 'utility':(21,{'pu':2,'frame':1,'lds':3},3,'am2'),
 'gear':(0.5,{'iron':2},1,'am2'),
 'ec':(0.5,{'iron':1,'cable':3},1,'am2'),
 'cable':(0.5,{'copper':1},2,'am2'),
 'adv':(6,{'plastic':2,'cable':4,'ec':2},1,'am2'),
 'engine':(10,{'steel':1,'gear':1,'pipe':2},1,'am2'),
 'eeu':(10,{'ec':2,'engine':1,'lube':15},1,'am2'),
 'battery':(4,{'iron':1,'copper':1,'acid':20},1,'chem'),
 'plastic':(1,{'coal':1,'pg':20},2,'chem'),
 'sulfur':(1,{'water':30,'pg':30},2,'chem'),
 'acid':(1,{'iron':1,'sulfur':5,'water':100},50,'chem'),
 'steel':(16,{'iron':5},1,'furn'),
 'brick':(3.2,{'stone':2},1,'furn'),
 'iron':(3.2,{'ironore':1},1,'furn'),
 'copper':(3.2,{'copperore':1},1,'furn'),
 'piercing':(6,{'copper':2,'steel':1,'mag':2},2,'am2'),
 'mag':(1,{'iron':4},1,'am2'),
 'grenade':(8,{'coal':10,'iron':5},1,'am2'),
 'wall':(0.5,{'brick':5},1,'am2'),
 'belt':(0.5,{'iron':1,'gear':1},2,'am2'),
 'inserter':(0.5,{'iron':1,'gear':1,'ec':1},1,'am2'),
 'rail':(0.5,{'stone':1,'steel':1,'stick':1},2,'am2'),
 'stick':(0.5,{'iron':1},2,'am2'),
 'efurnace':(5,{'steel':10,'adv':5,'brick':10},1,'am2'),
 'prodmod':(15,{'ec':5,'adv':5},1,'am2'),
 'pu':(10,{'ec':20,'adv':2,'acid':5},1,'am2'),
 'lds':(15,{'copper':20,'steel':2,'plastic':5},1,'am2'),
 'frame':(20,{'steel':1,'battery':2,'ec':3,'eeu':1},1,'am2'),
 'pipe':(0.5,{'iron':1},1,'am2'),
 'lube':(1,{'heavy':10},10,'chem'),
}
SPEED={'am2':0.75,'chem':1,'furn':2}
KW={'am2':150,'chem':210,'furn':90}
RAW={'ironore','copperore','stone','coal','pg','heavy','water'}
def expand(targets):
    need=collections.Counter()
    def add(item,rate):
        need[item]+=rate
        if item in RAW or item not in R: return
        e,ing,out,m=R[item]
        for k,a in ing.items(): add(k,rate*a/out)
    for k,v in targets.items(): add(k,v)
    return need
def machines(need):
    rows=[]
    for item,rate in need.items():
        if item in R:
            e,ing,out,m=R[item]
            per=60*SPEED[m]/e*out
            n=math.ceil(rate/per-1e-9)
            rows.append((item,rate,m,per,n,rate/(n*per) if n else 0))
    return rows
import sys
packs=['red','green','blue','military','production','utility']
def report(targets,label):
    need=expand(targets)
    rows=machines(need)
    print('==',label)
    tot=collections.Counter(); kw=0
    for it,rate,m,per,n,u in sorted(rows,key=lambda r:r[0]):
        print(f"{it:10s} {rate:8.1f}/min  {m:5s} cap/mach {per:7.1f}  n={n:4d} util={u*100:5.1f}%")
        tot[m]+=n; kw+=n*KW[m]
    for r in sorted(RAW): print(f"RAW {r:10s} {need[r]:9.1f}/min")
    print('machines',dict(tot),'kW (crafting only)',kw)
    return need,rows,kw
if __name__=='__main__':
    for p in packs: report({p:60},p)
    report({p:60 for p in packs},'ALL')
