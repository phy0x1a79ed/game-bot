-- prod-30-f.lua: STAGE 2 circuit machines (to 30 packs/min): 2 more EC cells, 2 more cable AM2, plastic plant 2, 9 more adv AM2 (4 north, 5 south), inserters and poles, the link pole (188.5,-5.5) between EC cells.
-- Same grid as prod-30-e.lua; adding this file takes the circuit block from 10 to 30 packs/min worth of adv, EC, cable and plastic.
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
local function cell(k0) local xe = 166.5 + 4 * (k0 + 1)
  for i = 0, 2 do local x = 166.5 + 4 * (k0 + i)
    if i == 1 then am(x, -6.5, 'electronic-circuit') add('fast-inserter', x, -8.5, S) add('fast-inserter', x, -4.5, S)
    else am(x, -6.5, 'copper-cable') add('inserter', x, -8.5, S) end
  end
  add('fast-inserter', xe - 2, -6.5, E) add('fast-inserter', xe + 2, -6.5, W) poles({{xe - 2, -5.5}, {xe + 2, -5.5}})
end
local function cable(j) local x = 166.5 + 3 * j am(x, 0.5, 'copper-cable') add('inserter', x, 2.5, N) add('long-handed-inserter', x - 1, -1.5, N) add('long-handed-inserter', x + 1, -1.5, N) poles({{x, -1.5}, {x + 1, 2.5}}) end
local function plant(x, d) add('chemical-plant', x, 0.5, d, {recipe = 'plastic-bar'}) add('fast-inserter', x, -1.5, N) add('inserter', x, 2.5, N) end
local function advn(j) local x = 203.5 + 3 * j am(x, -6.5, 'advanced-circuit') add('inserter', x - 1, -4.5, N) add('long-handed-inserter', x + 1, -4.5, N) add('inserter', x, -8.5, N) poles({{x, -4.5}}) if j % 2 == 0 then poles({{x + 1, -8.5}}) end end
local function advs(j) local x = 203.5 + 3 * j am(x, 0.5, 'advanced-circuit') add('inserter', x - 1, -1.5, S) add('long-handed-inserter', x + 1, -1.5, S) add('inserter', x, 2.5, S) poles({{x, -1.5}}) if j % 2 == 0 then poles({{x + 1, 2.5}}) end end
cell(3) cell(6) cable(1) cable(2) plant(182.5, W) poles({{188.5, -5.5}})
for j = 3, 6 do advn(j) end
for j = 2, 6 do advs(j) end
-- RUNNER
