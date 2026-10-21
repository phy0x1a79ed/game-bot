"""Build list (the `check` tool format) for a steel-furnace iron smelting column, N furnaces per side.

Iron ore enters from the north at x=2, coal at x=8; they side-load onto the two lanes of the fast main belt
at x=5. Plates leave south at x=5, the left column on one lane and the right column on the other.
"""
import json
import sys

N = int(sys.argv[1]) if len(sys.argv) > 1 else 6
L = []


def add(name, x, y, **intent):
    L.append({"name": name, "position": [x + 0.5, y + 0.5], "intent": intent})


def furnace(x, y):
    L.append({"name": "steel-furnace", "position": [x + 1, y + 1], "intent": {}})


H = 2 * N
add("fast-transport-belt", 2, -3, flow=[0, 1])
add("fast-transport-belt", 2, -2, flow=[0, 1])
for x in (2, 3, 4):
    add("fast-transport-belt", x, -1, flow=[1, 0])
add("transport-belt", 8, -3, flow=[0, 1])
add("transport-belt", 8, -2, flow=[0, 1])
for x in (6, 7, 8):
    add("transport-belt", x, -1, flow=[-1, 0])
for y in range(-1, H):
    add("fast-transport-belt", 5, y, flow=[0, 1])
for k in range(N):
    y = 2 * k
    furnace(2, y)
    furnace(7, y)
    add("fast-inserter", 4, y, drop=[-1, 0])
    add("fast-inserter", 6, y, drop=[1, 0])
    add("fast-inserter", 1, y, drop=[-1, 0], item="iron-plate")
    add("fast-inserter", 9, y, drop=[1, 0], item="iron-plate")
for y in range(1, H, 4):
    add("medium-electric-pole", 4, y)
    add("medium-electric-pole", 6, y)
for y in range(0, H + 2):
    add("transport-belt", 0, y, flow=[0, 1])
    add("transport-belt", 10, y, flow=[0, 1])
L[-2]["intent"]["flow"] = [1, 0]   # (0, H + 1) turns east
L[-1]["intent"]["flow"] = [-1, 0]  # (10, H + 1) turns west
for x in range(1, 5):
    add("transport-belt", x, H + 1, flow=[1, 0])
for x in range(6, 10):
    add("transport-belt", x, H + 1, flow=[-1, 0])
add("transport-belt", 5, H + 1, flow=[0, 1])
add("transport-belt", 5, H + 2, flow=[0, 1])
print(json.dumps(L))
