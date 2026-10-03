-- prod-30-b.lua: STAGE 1 raw feeds of the production-science block at full 30/min length: B1 iron|copper y=-9.5 (tail north to the stick belt y=-15.5), Q steel|stone y=-16.5 (then down x=224.5 and east on y=4.5), B2 copper|coal y=3.5, PG pipe y=4.5 and its column x=180.5.
-- Edge tiles at x=164.5 (belts) and (163.5,4.5) (PG pipe). B1 Fe lane carries EC iron 250 + stick iron 75, Cu lane 375; B2 Cu lane 200, coal lane 100; Q steel lane 250, stone lane 350. Q crosses AO_N, Ain1/Ain2 and AO_S by UG pairs on x=224.5.
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
local function pipes(x0, x1, y) for x = x0, x1 do add('pipe', x, y) end end
local function pipesy(x, y0, y1) for y = y0, y1 do add('pipe', x, y) end end
belts(164.5, 200.5, -9.5, E) add('transport-belt', 201.5, -9.5, N) beltsy(201.5, -10.5, -14.5, N) belts(201.5, 208.5, -15.5, E)
belts(164.5, 223.5, -16.5, E) add('transport-belt', 224.5, -16.5, S) beltsy(224.5, -15.5, -11.5, S)
ug(224.5, -10.5, S, 'input') ug(224.5, -8.5, S, 'output') beltsy(224.5, -7.5, -5.5, S)
ug(224.5, -4.5, S, 'input') ug(224.5, -1.5, S, 'output') beltsy(224.5, -0.5, 1.5, S)
ug(224.5, 2.5, S, 'input') ug(224.5, 4.5, S, 'output')
add('transport-belt', 224.5, 5.5, E) add('transport-belt', 225.5, 5.5, N) belts(225.5, 273.5, 4.5, E)
belts(164.5, 178.5, 3.5, E) ug(179.5, 3.5, E, 'input') ug(181.5, 3.5, E, 'output') belts(182.5, 183.5, 3.5, E)
pipes(164.5, 180.5, 4.5) pipesy(180.5, -0.5, 3.5)
-- RUNNER
