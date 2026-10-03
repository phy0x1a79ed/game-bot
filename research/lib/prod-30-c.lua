-- prod-30-c.lua: STAGE 1 spine belts at full length: Ain1 y=-3.5 (cable lane N, EC lane S), Ain2 y=-2.5 (plastic lane N, module lane S), AO_N y=-9.5 (adv lane N, rail lane S), AO_S y=3.5 (adv for the EF row), EB y=-3.5 flowing west (electric furnaces, lane N).
-- Lanes follow the rule 'an inserter drops on the far lane': north-side producers fill a belt's south lane, south-side producers its north lane.
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
belts(165.5, 236.5, -3.5, E) belts(165.5, 254.5, -2.5, E)
belts(202.5, 254.5, -9.5, E) belts(202.5, 268.5, 3.5, E) belts(275.5, 239.5, -3.5, W)
-- RUNNER
