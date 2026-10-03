-- steel-cell.lua: redesign-c steel cell (council/builder2): Join 2 plates -> iron corridor x=99.5 -> side-load onto the extended loop column x=101.5 (iron lane 1 | coal lane 2) -> furnace row y=22 -> steel on the south lane of the y=24.5 belt into (106.5,24.5).
-- MODE='check'|'place' via lib/redesign-ghosts.sh. Inserter dir = PICKUP side (S picks south, drops north). FURN may be swapped to 'steel-furnace' (4 of them give 30/min).
-- Needs first: order_deconstruction of the old loop-end inserter (101.5,26.5) and chest (101.5,25.5).
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local FURN = 'stone-furnace'
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
local function belts(x0, x1, y, dir) local st = x0 <= x1 and 1 or -1 for x = x0, x1, st do add('transport-belt', x, y, dir) end end
local function beltsy(x, y0, y1, dir) local st = y0 <= y1 and 1 or -1 for y = y0, y1, st do add('transport-belt', x, y, dir) end end
local function ug(x, y, dir, t) add('underground-belt', x, y, dir, {type = t}) end
local AREA = {{97, -37}, {120, 30}}
-- tap: 3 fast inserters pull plates off Join 2 (x=101.5) onto the corridor x=99.5 (no splitter in stock)
for y = -34.5, -32.5 do add('fast-inserter', 100.5, y, E) end
add('medium-electric-pole', 100.5, -31.5); add('medium-electric-pole', 105.5, -27.5)
beltsy(99.5, -35.5, -31.5, S); ug(99.5, -30.5, S, 'input'); ug(99.5, -28.5, S, 'output'); beltsy(99.5, -27.5, 4.5, S)
ug(99.5, 5.5, S, 'input'); ug(99.5, 10.5, S, 'output'); beltsy(99.5, 11.5, 21.5, S); belts(99.5, 100.5, 22.5, E)
-- loop column x=101.5 extended north from its dead end (101.5,27.5); corridor side-loads the iron lane at (101.5,22.5); UG under pack column x=104.5
beltsy(101.5, 26.5, 20.5, N); add('transport-belt', 101.5, 19.5, E); add('transport-belt', 102.5, 19.5, E)
ug(103.5, 19.5, E, 'input'); ug(105.5, 19.5, E, 'output'); belts(106.5, 116.5, 19.5, E)
for _, fx in pairs({106, 108, 110, 112, 114, 116}) do
  add(FURN, fx, 22.0, N); add('inserter', fx - 0.5, 20.5, N); add('inserter', fx - 0.5, 23.5, N)
end
add('medium-electric-pole', 106.5, 20.5); add('medium-electric-pole', 112.5, 20.5)
-- north pair: fed from the same row (inserters y=18.5), steel on belt y=14.5 west, side-loads the old pack column x=104.5 from the east (west lane, ends on the south lane of y=24.5)
for _, fx in pairs({107, 109}) do
  add(FURN, fx, 17.0, N); add('inserter', fx - 0.5, 18.5, S); add('inserter', fx - 0.5, 15.5, S)
end
belts(108.5, 105.5, 14.5, W); add('medium-electric-pole', 107.5, 15.5)
-- RUNNER
