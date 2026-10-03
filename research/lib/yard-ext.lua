-- yard-ext.lua: infra-b NE yard north-row extension +8 steel furnaces (x123..137, y=-138). PART 0: new loco-coal tap (120.5,-141.5) + pole. PART 1: everything else; ore belt y=-135.5 UG hop (116.5->120.5) under x=117.5/119.5, coal from band feed x=119.5 by inserter (120.5,-134.5) onto belt y=-134.5 E, plates y=-140.5 W through UG (121.5->116.5) into (112.5,-140.5). Needs the old loco tap (120.5,-140.5)+(121.5,-140.5) removed first for the UG entrance.
-- Inserter dir = PICKUP side.
local MODE = MODE_ARG
local PART = PART_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{112, -143}, {140, -132}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
local function ug(x, y, dir, t) add('underground-belt', x, y, dir, {type = t}) end
if PART == 0 then
  add('fast-inserter', 120.5, -141.5, W)
else
  add('transport-belt', 115.5, -135.5, E); ug(116.5, -135.5, E, 'input'); ug(120.5, -135.5, E, 'output')
  for x = 121.5, 137.5 do add('transport-belt', x, -135.5, E) end
  add('fast-inserter', 120.5, -134.5, W)
  for x = 121.5, 137.5 do add('transport-belt', x, -134.5, E) end
  add('medium-electric-pole', 121.5, -133.5)
  for fx = 123, 137, 2 do
    add('steel-furnace', fx, -138)
    add('fast-inserter', fx - 0.5, -136.5, S); add('long-handed-inserter', fx + 0.5, -136.5, S)
    add('fast-inserter', fx - 0.5, -139.5, S)
  end
  for _, fx in pairs({123, 127, 131, 135}) do add('medium-electric-pole', fx + 0.5, -139.5) end
  for x = 136.5, 122.5, -1 do add('transport-belt', x, -140.5, W) end
  ug(121.5, -140.5, W, 'input'); ug(116.5, -140.5, W, 'output')
  for x = 115.5, 113.5, -1 do add('transport-belt', x, -140.5, W) end
end
-- RUNNER
