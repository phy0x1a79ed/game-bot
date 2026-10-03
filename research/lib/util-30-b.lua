-- util-30-b.lua: Fluid backbone: PG column x=167.5 (tee off the production PG trunk at (164.5,14.5)), water row y=19.5, heavy row y=21.5, acid and lube trunks, PU acid stubs.
-- Every pipe and pipe-to-ground of the block at full length. Pipe-to-ground direction = open side. Edge tiles: PG (164.5,14.5), water (164.5,19.5), heavy oil (164.5,21.5).
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
pipes(164.5, 167.5, 14.5)
pipes(167.5, 179.5, 17.5)
pipes(164.5, 165.5, 19.5)
pipes(169.5, 181.5, 19.5)
pipes(164.5, 165.5, 21.5)
pipes(181.5, 240.5, 32.5)
pipes(169.5, 206.5, 34.5)
pipes(240.5, 258.5, 52.5)
pipes(167.5, 169.5, 53.5)
pipes(167.5, 173.5, 69.5)
pipesy(167.5, 15.5, 16.5)
pipesy(167.5, 18.5, 27.5)
pipesy(167.5, 31.5, 34.5)
pipesy(167.5, 38.5, 47.5)
pipesy(167.5, 52.5, 52.5)
pipesy(167.5, 54.5, 56.5)
pipesy(167.5, 60.5, 63.5)
pipesy(167.5, 67.5, 68.5)
pipesy(169.5, 21.5, 21.5)
pipesy(240.5, 33.5, 47.5)
pipesy(240.5, 51.5, 51.5)
pipesy(242.5, 53.5, 53.5)
pipesy(246.5, 53.5, 53.5)
pipesy(250.5, 53.5, 53.5)
pipesy(254.5, 53.5, 53.5)
pipesy(258.5, 53.5, 53.5)
ptgs({{166.5, 19.5, W}, {166.5, 21.5, W}, {167.5, 28.5, N}, {167.5, 30.5, S}, {167.5, 35.5, N}, {167.5, 37.5, S}, {167.5, 48.5, N}, {167.5, 51.5, S}, {167.5, 57.5, N}, {167.5, 59.5, S}, {167.5, 64.5, N}, {167.5, 66.5, S}, {168.5, 19.5, E}, {168.5, 21.5, E}, {169.5, 22.5, N}, {169.5, 24.5, S}, {169.5, 28.5, N}, {169.5, 33.5, S}, {177.5, 20.5, N}, {177.5, 24.5, S}, {179.5, 18.5, N}, {179.5, 24.5, S}, {181.5, 20.5, N}, {181.5, 24.5, S}, {181.5, 28.5, N}, {181.5, 31.5, S}, {198.5, 35.5, N}, {198.5, 37.5, S}, {202.5, 35.5, N}, {202.5, 37.5, S}, {206.5, 35.5, N}, {206.5, 37.5, S}, {209.5, 33.5, N}, {209.5, 37.5, S}, {213.5, 33.5, N}, {213.5, 37.5, S}, {217.5, 33.5, N}, {217.5, 37.5, S}, {240.5, 48.5, N}, {240.5, 50.5, S}})
-- RUNNER
