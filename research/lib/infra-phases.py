import math, collections
from infra_calc import expand, machines, R, SPEED, KW
def phase(t,label,labs_unit_s=60):
    need=expand(t); rows=machines(need)
    m=collections.Counter(); el=0; furn=0
    for it,rate,mach,per,n,u in rows:
        m[mach]+=n
        if mach=='furn': furn+=n
        else: el+=n*KW[mach]
    drills={k:math.ceil(need[k]/33) for k in ('ironore','copperore','stone')}
    coal_ing=need['coal']
    crude=(need['pg']+0.5*need['heavy'])/0.975
    refineries=math.ceil(crude/1200)
    pumpjack_note=crude/60
    crackers=math.ceil(refineries*1.3)  # approx heavy+light cracking plants per refinery
    pack=max(t.values()); labs=math.ceil(pack/(1.5*60/labs_unit_s))
    eldrill=sum(drills.values())*90
    el_total=(el+eldrill+refineries*420+crackers*210+labs*60+refineries*90*2)*1.15  # pumpjacks ~2/ref, inserters/belts +15%
    furn_coal=furn*90/4000*60   # steel furnace 90kW, coal 4MJ
    boiler_coal=el_total/4000*60
    print(f"== {label}")
    print(f"  ore/min iron {need['ironore']:.0f} copper {need['copperore']:.0f} stone {need['stone']:.0f} | coal ingredient {coal_ing:.0f} | PG {need['pg']:.0f} heavy(lube) {need['heavy']:.0f} -> crude {crude:.0f}/min ({crude/60:.0f}/s), refineries {refineries}")
    print(f"  plates/min iron {need['iron']:.0f} copper {need['copper']:.0f} steel {need['steel']:.0f} brick {need['brick']:.0f} | EC {need['ec']:.0f} adv {need['adv']:.0f} plastic {need['plastic']:.0f} gear {need['gear']:.0f}")
    print(f"  machines AM2 {m['am2']} chem {m['chem']} furnaces {furn} | drills {drills} | labs {labs} ({labs_unit_s}s units)")
    print(f"  electric {el_total/1000:.1f} MW (steam coal {boiler_coal:.0f}/min) | furnace fuel {furn_coal:.0f} coal/min | coal total {coal_ing+boiler_coal+furn_coal:.0f}/min | water {need['water']:.0f}/min + refinery water")
    return need
P4={'red':1,'green':1,'blue':1,'military':1}
phase({k:15 for k in P4},'NOW-equiv 15/min x4 (reference)')
phase({k:30 for k in P4},'PHASE 1: 30/min red green blue military')
phase({k:60 for k in P4},'PHASE 2: 60/min red green blue military')
t=dict({k:60 for k in P4}); t.update({'production':30,'utility':30})
phase(t,'PHASE 3: + production, utility 30/min')
t.update({'production':60,'utility':60})
phase(t,'PHASE 4: all six 60/min')
for p in ['red','green','blue','military','production','utility']:
    n=expand({p:60}); print(f"  per-pack 60/min {p:10s} iron-ore {n['ironore']:6.0f} copper-ore {n['copperore']:6.0f} stone {n['stone']:5.0f} coal {n['coal']:4.0f} PG {n['pg']:6.0f} steel {n['steel']:5.0f}")
