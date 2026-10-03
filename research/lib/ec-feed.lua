-- ec-feed.lua: feed for the green circuit block without a splitter. Prepend MODE='check'|'place'.
-- IRON: 3 fast inserters lift off the full branch belt y=-7.5 (x20.5..22.5) onto belt y=-5.5 -> x=22.5 S -> y=-0.5 E -> x=27.5 S (UG under y=1.5) -> x=28.5 S (UG under y=18.5) -> branch x=28.5 -> sideloads the N lane of y=38.5.
-- COPPER: 4 fast inserters lift off y=50.5 (x23.5..26.5) onto belt y=52.5 E -> x=29.5 N (UG under y=50.5..48.5) -> (29.5,38.5) W, straight-behind belt so the iron sideloads one lane and copper sideloads the other.
-- Inserter direction = the side it picks from.
local s = game.surfaces[1]
local N, E, S, W = 0, 4, 8, 12
local L = {}
local function add(n, x, y, d, t) L[#L + 1] = {n, x, y, d or N, t} end
local function belts(x1, x2, y, d) for x = math.min(x1, x2), math.max(x1, x2) do add('transport-belt', x, y, d) end end
local function vbelts(x, y1, y2, d) for y = math.min(y1, y2), math.max(y1, y2) do add('transport-belt', x, y, d) end end
-- iron
for x = 20.5, 22.5 do add('fast-inserter', x, -6.5, N) end
belts(20.5, 21.5, -5.5, E); add('transport-belt', 22.5, -5.5, S)
vbelts(22.5, -4.5, -1.5, S); add('transport-belt', 22.5, -0.5, E); belts(23.5, 26.5, -0.5, E)
add('transport-belt', 27.5, -0.5, S)
add('underground-belt', 27.5, 0.5, S, 'input'); add('underground-belt', 27.5, 2.5, S, 'output')
vbelts(27.5, 3.5, 12.5, S); add('transport-belt', 27.5, 13.5, E); add('transport-belt', 28.5, 13.5, S)
add('underground-belt', 28.5, 14.5, S, 'input')
if MODE ~= 'noug2' then add('underground-belt', 28.5, 19.5, S, 'output') end
add('medium-electric-pole', 21.5, -4.5)
-- copper
for x = 23.5, 26.5 do add('fast-inserter', x, 51.5, N) end
belts(23.5, 28.5, 52.5, E); add('transport-belt', 29.5, 52.5, N)
add('underground-belt', 29.5, 51.5, N, 'input'); add('underground-belt', 29.5, 47.5, N, 'output')
vbelts(29.5, 39.5, 46.5, N); belts(29.5, 30.5, 38.5, W)
add('medium-electric-pole', 27.5, 51.5)
local bad, ok, placed = {}, 0, 0
for _, e in pairs(L) do
  local spec = {name = e[1], position = {e[2], e[3]}, direction = e[4], force = 'player', build_check_type = defines.build_check_type.manual_ghost}
  if e[5] then spec.type = e[5] end
  local have = s.find_entities_filtered{position = {e[2], e[3]}, radius = 0.3, name = e[1]}[1] or s.find_entities_filtered{position = {e[2], e[3]}, radius = 0.3, ghost_name = e[1]}[1]
  if have then ok = ok + 1
  elseif not s.can_place_entity(spec) then
    local nm = {} for _, x in pairs(s.find_entities_filtered{position = {e[2], e[3]}, radius = 0.45}) do nm[#nm + 1] = x.name end
    bad[#bad + 1] = string.format('%s@%.1f,%.1f[%s]', e[1], e[2], e[3], table.concat(nm, '/'))
  else
    ok = ok + 1
    if MODE == 'place' then
      local g = {name = 'entity-ghost', inner_name = e[1], position = {e[2], e[3]}, direction = e[4], force = 'player'}
      if e[5] then g.type = e[5] end
      if s.create_entity(g) then placed = placed + 1 end
    end
  end
end
rcon.print(string.format('ec-feed %s: total %d ok %d placed %d bad %d\nBAD %s', MODE, #L, ok, placed, #bad, table.concat(bad, ' ')))
