-- steel-belt.lua: infra-b steel belt from NE steel cell 1 (belt y=-78.5, reversed east) to builder2's B2-4 edge (164.5,-16.5), steel on the NORTH lane arriving east. Route: y=-78.5 east (UG under 78.5,88.5,95.5/96.5) -> x=97.5 south (UG under band belts y=-66.5,-54.5) -> y=-40.5 east -> x=158.5 south -> y=-16.5 east.
-- Part PART_ARG: 1 = x<=98 section (net 5), 2 = the rest (net 26).
local MODE = MODE_ARG
local PART = PART_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{76, -80}, {166, -15}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
local function ug(x, y, dir, t) add('underground-belt', x, y, dir, {type = t}) end
if PART == 1 then
  ug(77.5, -78.5, E, 'input'); ug(79.5, -78.5, E, 'output')
  for x = 80.5, 86.5 do add('transport-belt', x, -78.5, E) end
  ug(87.5, -78.5, E, 'input'); ug(89.5, -78.5, E, 'output')
  for x = 90.5, 93.5 do add('transport-belt', x, -78.5, E) end
  ug(94.5, -78.5, E, 'input'); ug(97.5, -78.5, E, 'output')
  add('transport-belt', 98.5, -78.5, S)
  for y = -77.5, -68.5 do add('transport-belt', 98.5, y, S) end
  ug(98.5, -67.5, S, 'input'); ug(98.5, -65.5, S, 'output')
  for y = -64.5, -56.5 do add('transport-belt', 98.5, y, S) end
  ug(98.5, -55.5, S, 'input'); ug(98.5, -53.5, S, 'output')
  for y = -52.5, -41.5 do add('transport-belt', 98.5, y, S) end
  add('transport-belt', 98.5, -40.5, E)
  for x = 99.5, 124.5 do add('transport-belt', x, -40.5, E) end
else
  for x = 125.5, 157.5 do add('transport-belt', x, -40.5, E) end
  add('transport-belt', 158.5, -40.5, S)
  for y = -39.5, -17.5 do add('transport-belt', 158.5, y, S) end
  add('transport-belt', 158.5, -16.5, E)
  for x = 159.5, 164.5 do add('transport-belt', x, -16.5, E) end
end
-- RUNNER
