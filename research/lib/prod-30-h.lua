-- prod-30-h.lua: STAGE 2 final machines (to 30 packs/min): rail AM2 2, 2 more module AM2, brick furnaces 2 and EF AM2 2, 3 more pack AM2, inserters, poles. Same grid as prod-30-g.lua.
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
local function rail(x) am(x, -12.5, 'rail') add('long-handed-inserter', x - 1, -14.5, S) add('long-handed-inserter', x + 1, -14.5, S) add('fast-inserter', x, -10.5, S) end
local function mod(j) local x = 227.5 + 3 * j am(x, -6.5, 'productivity-module') add('inserter', x, -8.5, S) add('inserter', x - 1, -4.5, N) add('long-handed-inserter', x + 1, -4.5, S) poles({{x, -4.5}}) if j % 2 == 0 then poles({{x + 1, -8.5}}) end end
local function furn(x) add('electric-furnace', x, 0.5, N) add('long-handed-inserter', x, 2.5, N) end
local function ef(x) am(x, 0.5, 'electric-furnace') add('inserter', x - 1, 2.5, N) add('long-handed-inserter', x + 1, 2.5, N) add('long-handed-inserter', x, -1.5, N) end
local function pk(j) local x = 241.5 + 3 * j am(x, -6.5, 'production-science-pack') add('fast-inserter', x - 1, -8.5, S) add('long-handed-inserter', x + 1, -8.5, N) add('inserter', x - 1, -4.5, N) add('long-handed-inserter', x + 1, -4.5, N) poles({{x, -8.5}, {x, -4.5}}) end
local function gap(x, d) add('inserter', x, 0.5, d) poles({{x, 1.5}}) end
rail(211.5) add('fast-inserter', 209.5, -12.5, E) poles({{209.5, -13.5}})
for j = 2, 3 do mod(j) end
gap(262.5, W) furn(264.5) ef(268.5) gap(266.5, E) furn(272.5) gap(270.5, W)
for j = 2, 4 do pk(j) end
-- RUNNER
