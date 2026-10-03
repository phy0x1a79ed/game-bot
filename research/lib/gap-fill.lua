-- gap-fill.lua: infra-b re-lay belt tiles left missing by the copper-ore purge (B1 y=58.5, column x=162.5, builder2 y=-9.5).
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{70, -12}, {190, 60}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
for _, x in pairs({74.5, 80.5, 90.5, 104.5, 117.5, 121.5, 127.5, 130.5, 133.5, 139.5, 148.5}) do add('transport-belt', x, 58.5, E) end
for _, y in pairs({-8.5, -7.5, -6.5, -4.5, 0.5, 10.5, 16.5, 19.5, 22.5, 25.5, 52.5}) do add('transport-belt', 162.5, y, N) end
for _, x in pairs({163.5, 167.5, 168.5, 172.5}) do add('transport-belt', x, -9.5, E) end
-- RUNNER
