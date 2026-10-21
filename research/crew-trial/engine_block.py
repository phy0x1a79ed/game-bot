"""Build list (the `check` tool format) for an engine-unit block of N assembling-machine-2.

Inputs: iron plate on a belt entering from the north at x=-6, steel plate entering from the north at x=-1.
Output: engines leave east on the belt at y=6. Gears and steel share belt y=-1; pipes run on belt y=5.
"""
import json
import sys

N = int(sys.argv[1]) if len(sys.argv) > 1 else 7
L = []


def add(name, x, y, **intent):
    L.append({"name": name, "position": [x + 0.5, y + 0.5], "intent": intent})


def belt(x, y, dx, dy):
    add("transport-belt", x, y, flow=[dx, dy])


def asm(x, y, recipe):  # top-left tile
    L.append({"name": "assembling-machine-2", "position": [x + 1.5, y + 1.5], "intent": {"recipe": recipe}})


end = 3 * N - 1
# iron feed, north to south, x=-6, y=-5..8
for y in range(-5, 9):
    belt(-6, y, 0, 1)
# steel feed, x=-1, y=-5..-2, side-loads onto the north lane of the gear/steel belt
for y in range(-5, -1):
    belt(-1, y, 0, 1)
# gear/steel belt y=-1, x=-4..end
for x in range(-4, end + 1):
    belt(x, -1, 1, 0)
# pipe belt y=5, x=-4..end
for x in range(-4, end + 1):
    belt(x, 5, 1, 0)
# engine belt y=6, x=0..end, leaves east
for x in range(0, end + 1):
    belt(x, 6, 1, 0)
# gear assembler above, pipe assembler below
asm(-4, -5, "iron-gear-wheel")
add("fast-inserter", -5, -4, drop=[1, 0], item="iron-plate")
add("fast-inserter", -3, -2, drop=[0, 1], item="iron-gear-wheel")
asm(-4, 7, "pipe")
add("fast-inserter", -5, 8, drop=[1, 0], item="iron-plate")
add("fast-inserter", -3, 6, drop=[0, -1], item="pipe")
add("medium-electric-pole", -5, -2)
add("medium-electric-pole", -5, 6)
for i in range(N):
    x0 = 3 * i
    asm(x0, 1, "engine-unit")
    add("inserter", x0 + 1, 0, drop=[0, 1])
    add("inserter", x0, 4, drop=[0, -1], item="pipe")
    add("long-handed-inserter", x0 + 1, 4, drop=[0, 1], item="engine-unit")
    if i % 2 == 0:
        add("medium-electric-pole", x0 + 2, 0)
        add("medium-electric-pole", x0 + 2, 4)
print(json.dumps(L))
