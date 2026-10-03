"""Theoretical science yields: raw demand per pack line and the max pack rate a given raw supply allows.

Run: mamba run -n game-bot python research/lib/science_yield.py
Recipes come from infra_calc.R (live 2.1 recipes); supply scenarios are edited below from live reads.
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from infra_calc import expand, machines

PACKS = ['red', 'green', 'military', 'blue']
# Raw-ish inputs the lines draw. Plates rather than ore, because smelting is builder 1's.
RAWKEYS = ['iron', 'copper', 'steel', 'stone', 'coal', 'pg']

# Supply available to science, per minute. 'now' = live capacity at tick ~2.86M; 'p2' = after builder 1's planned projects.
SUPPLY = {
    'now': {'iron': 1350, 'copper': 524, 'steel': 135, 'stone': 200, 'coal': 330, 'pg': 2340},
    'p2':  {'iron': 2700, 'copper': 1050, 'steel': 240, 'stone': 860, 'coal': 1250, 'pg': 3510},
}


def raw_per_pack(pack):
    """Raw draw (per minute) for 1 pack/min, with steel kept as its own input (not expanded to iron)."""
    need = expand({pack: 1})
    out = {k: 0.0 for k in RAWKEYS}
    for item, rate in need.items():
        if item in ('iron', 'copper', 'stone', 'coal', 'pg', 'steel'):
            out[item] += rate
    # expand() also expanded steel into iron; remove that double count
    out['iron'] -= 5 * need.get('steel', 0)
    return out


def main():
    per = {p: raw_per_pack(p) for p in PACKS}
    print('Raw draw per 60 packs/min:')
    print('pack      ' + ''.join(f'{k:>9}' for k in RAWKEYS))
    for p in PACKS:
        print(f'{p:<10}' + ''.join(f'{60 * per[p][k]:>9.0f}' for k in RAWKEYS))
    tot = {k: sum(60 * per[p][k] for p in PACKS) for k in RAWKEYS}
    print(f'{"all four":<10}' + ''.join(f'{tot[k]:>9.0f}' for k in RAWKEYS))
    for name, sup in SUPPLY.items():
        print(f'\nScenario {name}: supply ' + ', '.join(f'{k} {v}' for k, v in sup.items()))
        for p in PACKS:
            lim = min((sup[k] / per[p][k], k) for k in RAWKEYS if per[p][k] > 0)
            print(f'  {p:<9} alone: max {lim[0]:6.0f}/min, bound by {lim[1]}')
        lim = min((sup[k] / sum(per[p][k] for p in PACKS), k) for k in RAWKEYS if sum(per[p][k] for p in PACKS) > 0)
        print(f'  all four together at one rate: max {lim[0]:5.1f}/min each, bound by {lim[1]}')
    print('\nMachines at 60/min of all four (AM2 0.75, chem 1, steel furnace 2):')
    rows = machines(expand({p: 60 for p in PACKS}))
    for item, rate, m, cap, n, util in sorted(rows, key=lambda r: r[0]):
        if item in ('iron', 'copper'):
            continue
        print(f'  {item:<10} {rate:8.1f}/min  {n:3d} x {m:<5} util {util:5.0%}')


if __name__ == '__main__':
    main()
