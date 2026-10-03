-- util-30-c.lua: Belts of the chem hub, robot-frame block and processing-unit block at full length (stage 1 and 2).
-- Raw edge tiles (x=164.5): CH iron y=29.5; FB nb y=36.5 (iron|copper), d1 y=49.5 (copper|iron), d2 y=50.5 (steel); PUM coal y=58.5, r1 y=65.5 (red, copper|iron). Red belts (fast-transport-belt): PUM c2 y=59.5 and r1 y=65.5.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
-- Inserter dirs name the side items GO TO; the game's direction names the pickup side, so add() turns inserters 180 (the prod-30 convention).
local function add(name, x, y, dir, extra) dir = dir or N if name:find('inserter') then dir = (dir + 8) % 16 end L[#L + 1] = {name = name, x = x, y = y, dir = dir, extra = extra} end
local function belts(x0, x1, y, dir, nm) local st = x0 <= x1 and 1 or -1 for x = x0, x1, st do add(nm or 'transport-belt', x, y, dir) end end
local function beltsy(x, y0, y1, dir, nm) local st = y0 <= y1 and 1 or -1 for y = y0, y1, st do add(nm or 'transport-belt', x, y, dir) end end
local function ug(x, y, dir, t) add('underground-belt', x, y, dir, {type = t}) end
local function ams(y, recipe, xs) for _, x in pairs(xs) do add('assembling-machine-2', x, y, N, {recipe = recipe}) end end
local function chems(y, recipe, xs, dir) for _, x in pairs(xs) do add('chemical-plant', x, y, dir, {recipe = recipe}) end end
local function ins(nm, list) for _, p in pairs(list) do add(nm, p[1], p[2], p[3]) end end
local function poles(list) for _, p in pairs(list) do add('medium-electric-pole', p[1], p[2]) end end
local function pipes(x0, x1, y) for x = x0, x1 do add('pipe', x, y) end end
local function pipesy(x, y0, y1) for y = y0, y1 do add('pipe', x, y) end end
local function ptgs(list) for _, p in pairs(list) do add('pipe-to-ground', p[1], p[2], p[3]) end end
local AREA = {{158, -14}, {292, 90}}
belts(164.5, 184.5, 29.5, E)
belts(164.5, 219.5, 36.5, E)
belts(173.5, 232.5, 42.5, E)
belts(185.5, 232.5, 43.5, E)
belts(164.5, 207.5, 49.5, E)
belts(210.5, 278.5, 49.5, E)
belts(164.5, 232.5, 50.5, E)
belts(164.5, 172.5, 58.5, E)
belts(276.5, 240.5, 58.5, W)
beltsy(279.5, 49.5, 73.5, S)
belts(169.5, 275.5, 59.5, E, 'fast-transport-belt')
belts(164.5, 276.5, 65.5, E, 'fast-transport-belt')
-- RUNNER
