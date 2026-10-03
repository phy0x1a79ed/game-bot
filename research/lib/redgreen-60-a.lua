-- redgreen-60-a.lua: STAGE 0 of the red+green 60/min block (council/builder2/redgreen-60.md): 8 loaded gun turrets around the site, ghosts with ammo insert plans.
-- MODE='check'|'place'|'recipes' as in blue-60-a.lua. Ammo comes from the net-6 storage chests (122.5,-2.5) (129.5,-2.5): stock 160 yellow first.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
local function belts(x0, x1, y, dir) local st = x0 <= x1 and 1 or -1 for x = x0, x1, st do add('transport-belt', x, y, dir) end end
local function beltsy(x, y0, y1, dir) local st = y0 <= y1 and 1 or -1 for y = y0, y1, st do add('transport-belt', x, y, dir) end end
local function ug(x, y, dir, t) add('underground-belt', x, y, dir, {type = t}) end
local function am(x, y, recipe) add('assembling-machine-2', x, y, N, {recipe = recipe}) end
local function poles(list) for _, p in pairs(list) do add('medium-electric-pole', p[1], p[2]) end end
local AREA = {{95, -45}, {160, 30}}
-- north edge faces the attack band x 100..125, y -70..-110; west pair guards the iron feed; east pair the line end
for _, t in pairs({{112, -38}, {124, -38}, {136, -38}, {148, -38}, {104, -26}, {104, -12}, {154, -32}, {154, -18}}) do
  add('gun-turret', t[1], t[2], N, {ammo = 'firearm-magazine', n = 20})
end
-- RUNNER
