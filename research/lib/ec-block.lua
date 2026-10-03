-- ec-block.lua: green circuit block (builder1, run 4). Prepend MODE='check'|'place'. check = can_place + power coverage (a read); place = ghosts (a Lua order).
-- Target 220 EC/min = 4 EC AM1 + 6 cable AM1 (two C-E-C-E-C rows, cable direct-inserted), 330 Cu + 220 Fe /min.
-- Feed: splitter on the F->blue mixed belt y=18.5 at x=27.5, branch S on x=28.5, mixed belt y=38.5 W between the rows.
-- Output: row belts y=32.5 / y=44.5 E -> collector x=26.5 S (UG under y=38.5) -> y=48.5 E (UG under x=30,31) -> x=106.5 N to y=30.5.
-- Inserter direction = the side it picks from.
local s = game.surfaces[1]
local N, E, S, W = 0, 4, 8, 12
local L = {}
local function add(n, x, y, d, t, r) L[#L + 1] = {n, x, y, d or N, t, r} end
local function belts(x1, x2, y, d) for x = math.min(x1, x2), math.max(x1, x2) do add('transport-belt', x, y, d) end end
local function vbelts(x, y1, y2, d) for y = math.min(y1, y2), math.max(y1, y2) do add('transport-belt', x, y, d) end end
-- feed
add('splitter', 27.5, 19.0, E)
vbelts(28.5, 19.5, 37.5, S); belts(5.5, 28.5, 38.5, W)
-- rows: north (machines y 35.5, belt inserters 37.5 pick S, gaps 34.5/35.5, poles 36.5, out inserters 33.5, belt 32.5)
--       south (machines y 41.5, belt inserters 39.5 pick N, gaps 40.5/41.5, poles 42.5, out inserters 43.5, belt 44.5)
local rows = {{35.5, 37.5, S, 34.5, 35.5, 36.5, 33.5, S, 32.5}, {41.5, 39.5, N, 40.5, 41.5, 42.5, 43.5, N, 44.5}}
for _, r in pairs(rows) do
  for _, x in pairs({5.5, 13.5, 21.5}) do add('assembling-machine-1', x, r[1], N, nil, 'copper-cable'); add('fast-inserter', x, r[2], r[3]) end
  for _, x in pairs({9.5, 17.5}) do
    add('assembling-machine-1', x, r[1], N, nil, 'electronic-circuit'); add('fast-inserter', x, r[2], r[3])
  end
  for _, g in pairs({{7.5, W}, {11.5, E}, {15.5, W}, {19.5, E}}) do
    add('fast-inserter', g[1], r[4], g[2]); add('fast-inserter', g[1], r[5], g[2])
  end
  for _, x in pairs({7.5, 11.5, 15.5, 19.5}) do add('medium-electric-pole', x, r[6]) end
  for _, x in pairs({9.5, 17.5}) do add('fast-inserter', x, r[7], r[8]) end
  belts(9.5, 25.5, r[9], E)
end
-- collector, UG under the mixed belt, then east
vbelts(26.5, 32.5, 36.5, S); add('underground-belt', 26.5, 37.5, S, 'input'); add('underground-belt', 26.5, 39.5, S, 'output')
vbelts(26.5, 40.5, 47.5, S)
belts(26.5, 28.5, 48.5, E); add('underground-belt', 29.5, 48.5, E, 'input'); add('underground-belt', 32.5, 48.5, E, 'output')
belts(33.5, 105.5, 48.5, E); add('transport-belt', 106.5, 48.5, N); vbelts(106.5, 30.5, 47.5, N)
-- buffer chest on the collector
add('fast-inserter', 25.5, 46.5, E); add('iron-chest', 24.5, 46.5); add('medium-electric-pole', 24.5, 47.5)
if ONLY then local K = {} for _, e in pairs(L) do if ONLY[e[1]] then K[#K + 1] = e end end if MODE == 'place' then L = K end end
local poles = {}
for _, p in pairs(s.find_entities_filtered{type = 'electric-pole', area = {{0, 28}, {34, 52}}}) do
  poles[#poles + 1] = {p.position.x, p.position.y, p.prototype.get_supply_area_distance(p.quality), p.electric_network_id}
end
for _, e in pairs(L) do if prototypes.entity[e[1]].type == 'electric-pole' then poles[#poles + 1] = {e[2], e[3], prototypes.entity[e[1]].get_supply_area_distance()} end end
local function covered(e)
  local proto = prototypes.entity[e[1]]
  if not proto.electric_energy_source_prototype then return true end
  local cb = proto.collision_box
  local x1, y1, x2, y2 = e[2] + cb.left_top.x, e[3] + cb.left_top.y, e[2] + cb.right_bottom.x, e[3] + cb.right_bottom.y
  for _, p in pairs(poles) do
    if x2 > p[1] - p[3] and x1 < p[1] + p[3] and y2 > p[2] - p[3] and y1 < p[2] + p[3] then return true end
  end
  return false
end
local bad, unpowered, ok, placed, cnt = {}, {}, 0, 0, {}
for _, e in pairs(L) do
  cnt[e[1]] = (cnt[e[1]] or 0) + 1
  local spec = {name = e[1], position = {e[2], e[3]}, direction = e[4], force = 'player', build_check_type = defines.build_check_type.manual_ghost}
  if e[5] then spec.type = e[5] end
  local have = s.find_entities_filtered{position = {e[2], e[3]}, radius = 0.3, name = e[1]}[1]
    or s.find_entities_filtered{position = {e[2], e[3]}, radius = 0.3, ghost_name = e[1]}[1]
  if not covered(e) then unpowered[#unpowered + 1] = string.format('%s(%.1f,%.1f)', e[1], e[2], e[3]) end
  if have then ok = ok + 1
  elseif not s.can_place_entity(spec) then
    local nm = {} for _, x in pairs(s.find_entities_filtered{position = {e[2], e[3]}, radius = 0.45}) do nm[#nm + 1] = x.name end
    bad[#bad + 1] = string.format('%s@%.1f,%.1f[%s]', e[1], e[2], e[3], table.concat(nm, '/'))
  else
    ok = ok + 1
    if MODE == 'place' then
      local g = {name = 'entity-ghost', inner_name = e[1], position = {e[2], e[3]}, direction = e[4], force = 'player'}
      if e[5] then g.type = e[5] end
      local gh = s.create_entity(g)
      if gh then placed = placed + 1; if e[6] then pcall(function() gh.set_recipe(e[6]) end) end end
    end
  end
end
local c = {} for k, v in pairs(cnt) do c[#c + 1] = k .. '=' .. v end
local nets = {} for _, p in pairs(poles) do if p[4] then nets[#nets + 1] = p[4] end end
rcon.print(string.format('ec-block %s: total %d ok %d placed %d bad %d unpowered %d | %s | existing pole nets %s\nBAD %s\nUNPOWERED %s',
  MODE, #L, ok, placed, #bad, #unpowered, table.concat(c, ','), table.concat(nets, ','), table.concat(bad, ' '), table.concat(unpowered, ' ')))
