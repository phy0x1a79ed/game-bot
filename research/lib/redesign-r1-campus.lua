-- redesign-r1-campus.lua: ghost layout of the 20-lab science campus at S2 (audit-ratios.md R1).
-- MODE='check' only tests can_place (a read). MODE='place' creates entity ghosts (a Lua order; robots build them).
-- Idempotent: a tile that already holds the same entity or ghost is skipped.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local function add(name, x, y, dir) L[#L + 1] = {name, x, y, dir or N} end
-- RG belt (lane 1 red, lane 2 green): east along y=0.5, south down x=142.5, back west along y=12.5
for x = 109.5, 141.5 do add('transport-belt', x, 0.5, E) end
add('transport-belt', 142.5, 0.5, S)
for y = 1.5, 11.5 do add('transport-belt', 142.5, y, S) end
add('transport-belt', 142.5, 12.5, W)
for x = 110.5, 141.5 do add('transport-belt', x, 12.5, W) end
-- BM belt (lane 1 blue from the north feeder, lane 2 military from the south feeder); (108.5,6.5) keeps the head straight
for x = 108.5, 140.5 do add('transport-belt', x, 6.5, E) end
-- labs, inserters, poles
for k = 0, 9 do
  local c = 112.5 + 3 * k
  add('lab', c, 3.5); add('lab', c, 9.5)
  add('inserter', c, 1.5, N)   -- RG -> row 1
  add('inserter', c, 5.5, S)   -- BM -> row 1
  add('inserter', c, 7.5, N)   -- BM -> row 2
  add('inserter', c, 11.5, S)  -- RG2 -> row 2
  if k % 2 == 0 then
    add('medium-electric-pole', c + 1, 1.5); add('medium-electric-pole', c + 1, 5.5); add('medium-electric-pole', c + 1, 11.5)
  end
end
-- power line from the robot cell pole (88.5,12.5)
add('medium-electric-pole', 96.5, 8.5); add('medium-electric-pole', 104.5, 4.5); add('medium-electric-pole', 110.5, -0.5)
local ok, bad, skip, placed = 0, {}, 0, 0
local cnt = {}
for _, e in pairs(L) do
  local name, x, y, dir = e[1], e[2], e[3], e[4]
  cnt[name] = (cnt[name] or 0) + 1
  local have = s.find_entities_filtered{position = {x, y}, radius = 0.3, name = name}[1]
    or s.find_entities_filtered{position = {x, y}, radius = 0.3, ghost_name = name}[1]
  if have then skip = skip + 1
  elseif s.can_place_entity{name = name, position = {x, y}, direction = dir, force = 'player', build_check_type = defines.build_check_type.manual_ghost} then
    ok = ok + 1
    if MODE == 'place' then
      if s.create_entity{name = 'entity-ghost', inner_name = name, position = {x, y}, direction = dir, force = 'player'} then placed = placed + 1 end
    end
  else bad[#bad + 1] = string.format('%s(%.1f,%.1f)', name, x, y) end
end
local c = {} for k, v in pairs(cnt) do c[#c + 1] = k .. '=' .. v end
rcon.print(string.format('mode=%s total=%d ok=%d skip=%d placed=%d bad=%d %s | %s', MODE, #L, ok, skip, placed, #bad, table.concat(bad, ' '), table.concat(c, ',')))
