-- prod-30-d.lua: STAGE 1 pack route and lab feed: PO y=-10.5 west from the pack row, UG under Q (x=224.5), north on x=216.5 (UG under Q y=-16.5), west on y=-18.5 to x=160.5, south to a splitter at (161,-3.5).
-- Branch A: y=-0.5 west along the campus north edge; branch B: x=161.5 south, y=13.5 west (UG under the turret (118,14)). 15 long-handed inserters drop packs into the labs (north row from y=-0.5 via y=1.5; south row from y=13.5 via y=11.5): the 5th/6th pack belt.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
-- Inserter dirs name the side items GO TO; the game's direction names the pickup side, so add() turns inserters 180.
local function add(name, x, y, dir, extra) dir = dir or N if name:find('inserter') then dir = (dir + 8) % 16 end L[#L + 1] = {name = name, x = x, y = y, dir = dir, extra = extra} end
local function belts(x0, x1, y, dir) local st = x0 <= x1 and 1 or -1 for x = x0, x1, st do add('transport-belt', x, y, dir) end end
local function beltsy(x, y0, y1, dir) local st = y0 <= y1 and 1 or -1 for y = y0, y1, st do add('transport-belt', x, y, dir) end end
local function ug(x, y, dir, t) add('underground-belt', x, y, dir, {type = t}) end
local function am(x, y, recipe) add('assembling-machine-2', x, y, N, {recipe = recipe}) end
local function poles(list) for _, p in pairs(list) do add('medium-electric-pole', p[1], p[2]) end end
local AREA = {{158, -30}, {280, 16}}
belts(254.5, 226.5, -10.5, W) ug(225.5, -10.5, W, 'input') ug(223.5, -10.5, W, 'output') belts(222.5, 217.5, -10.5, W)
add('transport-belt', 216.5, -10.5, N) beltsy(216.5, -11.5, -14.5, N) ug(216.5, -15.5, N, 'input') ug(216.5, -17.5, N, 'output')
add('transport-belt', 216.5, -18.5, W) belts(215.5, 161.5, -18.5, W) add('transport-belt', 160.5, -18.5, S) beltsy(160.5, -17.5, -4.5, S)
add('splitter', 161.0, -3.5, S) beltsy(160.5, -2.5, -1.5, S) belts(160.5, 111.5, -0.5, W)
beltsy(161.5, -2.5, 12.5, S) belts(161.5, 120.5, 13.5, W)
ug(119.5, 13.5, W, 'input') ug(116.5, 13.5, W, 'output') belts(115.5, 111.5, 13.5, W)
for x = 112.5, 133.5, 3 do add('long-handed-inserter', x - 1, 1.5, S) end
for x = 112.5, 130.5, 3 do add('long-handed-inserter', x - 1, 11.5, N) end
-- RUNNER
