-- util-30-a.lua: STAGE 0: 12 loaded gun turrets around the utility-science site and the pole tie to the grid.
-- Site x 164..290, y 14..78 south of the production block. Turrets carry 20 firearm-magazine each (net 71 storage first). The tie poles (166.5,25.5) (172.5,32.5) (172.5,38.5) join the medium pole at (160.5,25.5) to the site grid.
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
poles({{166.5, 25.5}, {172.5, 32.5}, {172.5, 38.5}})
for _, t in pairs({{180, 52}, {212, 52}, {236, 52}, {256, 40}, {276, 40}, {180, 67}, {212, 67}, {240, 67}, {266, 67}, {291, 30}, {291, 52}, {291, 70}}) do add('gun-turret', t[1], t[2], N, {ammo = 'firearm-magazine', n = 20}) end
-- RUNNER
