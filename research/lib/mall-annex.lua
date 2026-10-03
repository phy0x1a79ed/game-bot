-- mall-annex.lua: ghost layout of the mall annex south of belt F (infra-a, run 4).
-- Prepend MODE='check'|'place', PHASE=1|2, optional ONLY={name=true}. check = can_place + power coverage (a read); place = entity ghosts (a Lua order). PHASE 2 = LHI + chem-plant cells south of H, iron onto H's north lane.
-- Section y: F 14.5 (iron N lane, copper S lane) | inserters 15.5 | machines 16.5-18.5 | inserters 19.5 | G 20.5 (EC|gears, W) | H 21.5 (steel, W).
-- Outputs: long-handed at y=15.5 lifts over F into chests at y=13.5. G = right output of splitter (17.5,9) on F_gc, under F at x=19.5.
-- Inserter direction = the side it picks from.
local s = game.surfaces[1]
local N, E, S, W = 0, 4, 8, 12
local L = {}
local function add(n, x, y, d, t, r, f) L[#L + 1] = {n, x, y, d or N, t, r, f} end
local function belts(x1, x2, y, d) for x = math.min(x1, x2), math.max(x1, x2) do add('transport-belt', x, y, d) end end
if PHASE == 1 then
  -- G: splitter output (18.5,9.5) -> x=19.5 south under F -> west along y=20.5, under turret (10,21)
  add('splitter', 17.5, 9.0, E)  -- fast-replaces the F_gc belt (17.5,8.5)
  add('transport-belt', 18.5, 9.5, E); add('transport-belt', 19.5, 9.5, S)
  add('underground-belt', 19.5, 10.5, S, 'input'); add('underground-belt', 19.5, 15.5, S, 'output')
  for y = 16.5, 19.5 do add('transport-belt', 19.5, y, S) end
  add('transport-belt', 19.5, 20.5, W); belts(12.5, 18.5, 20.5, W)
  add('underground-belt', 11.5, 20.5, W, 'input'); add('underground-belt', 8.5, 20.5, W, 'output')
  belts(-3.5, 7.5, 20.5, W)
  -- H: steel from the two furnaces, west along y=21.5, under turret (10,21)
  belts(12.5, 25.5, 21.5, W)
  add('underground-belt', 11.5, 21.5, W, 'input'); add('underground-belt', 8.5, 21.5, W, 'output')
  belts(-4.5, 7.5, 21.5, W)
  -- machines (recipe in field 6)
  add('assembling-machine-1', -4.5, 17.5, N, nil, 'assembling-machine-2')
  add('assembling-machine-1', -0.5, 17.5, N, nil, 'assembling-machine-1')
  add('assembling-machine-1', 2.5, 17.5, N, nil, 'iron-stick')
  add('assembling-machine-1', 6.5, 17.5, N, nil, 'medium-electric-pole')
  add('assembling-machine-1', 10.5, 17.5, N, nil, 'copper-cable')
  add('assembling-machine-1', 13.5, 17.5, N, nil, 'fast-inserter')
  add('electric-furnace', 17.5, 17.5); add('electric-furnace', 21.5, 17.5); add('electric-furnace', 24.5, 17.5)
  -- F -> machine
  for _, x in pairs({-0.5, 2.5, 10.5, 14.5, 17.5, 21.5, 24.5}) do add('inserter', x, 15.5, N) end
  -- outputs over F into chests
  for _, x in pairs({-5.5, 5.5, 13.5}) do add('long-handed-inserter', x, 15.5, S); add('passive-provider-chest', x, 13.5) end
  -- mall inserter chest (12.5,11.5) -> buffer (12.5,13.5) -> FI
  add('inserter', 12.5, 12.5, N); add('iron-chest', 12.5, 13.5); add('long-handed-inserter', 12.5, 15.5, N)
  -- G -> machine
  for _, x in pairs({-3.5, -0.5, 13.5}) do add('inserter', x, 19.5, S) end
  -- H -> machine (steel), furnace -> H
  add('long-handed-inserter', -4.5, 19.5, S); add('long-handed-inserter', 6.5, 19.5, S)
  add('long-handed-inserter', 17.5, 19.5, N); add('long-handed-inserter', 21.5, 19.5, N); add('long-handed-inserter', 24.5, 19.5, N)
  -- side chains: AM1-maker -> AM2, stick -> pole <- cable
  add('inserter', -2.5, 17.5, E); add('inserter', 4.5, 17.5, W); add('inserter', 8.5, 17.5, E)
  -- poles: medium (hand-crafted), positions chosen so every powered entity is covered
  POLES = POLES or {{-2.5,15.5},{-2.5,19.5},{4.5,15.5},{7.5,19.5},{11.5,15.5},{14.5,19.5},{22.5,15.5},{22.5,19.5}}
  for _, p in pairs(POLES or {}) do add(p[3] or 'medium-electric-pole', p[1], p[2]) end
end
if PHASE == 2 then
  -- row y=23.5-25.5 south of H. H north lane = iron, put there by a filter inserter off F's south branch (26.5,18.5).
  add('inserter', 26.5, 19.5, N, nil, nil, 'iron-plate'); add('transport-belt', 26.5, 20.5, S); add('transport-belt', 26.5, 21.5, W)
  -- LHI cell: inserter-maker (0.5) -> side inserter (2.5) -> LHI-maker (4.5); out (4.5,26.5) -> chest (4.5,27.5)
  add('assembling-machine-1', 0.5, 24.5, N, nil, 'inserter'); add('assembling-machine-1', 4.5, 24.5, N, nil, 'long-handed-inserter')
  add('inserter', 0.5, 22.5, N); add('long-handed-inserter', 1.5, 22.5, N); add('inserter', 4.5, 22.5, N); add('long-handed-inserter', 5.5, 22.5, N)
  add('inserter', 2.5, 24.5, W); add('inserter', 4.5, 26.5, N); add('iron-chest', 4.5, 27.5)
  -- chem plant cell: pipe-maker (18.5) -> side inserter (16.5) -> chem-plant-maker (14.5); out (14.5,26.5) -> chest (14.5,27.5)
  add('assembling-machine-1', 14.5, 24.5, N, nil, 'chemical-plant'); add('assembling-machine-1', 18.5, 24.5, N, nil, 'pipe')
  add('long-handed-inserter', 13.5, 22.5, N); add('inserter', 14.5, 22.5, N); add('inserter', 18.5, 22.5, N)
  add('inserter', 16.5, 24.5, E); add('inserter', 14.5, 26.5, N); add('iron-chest', 14.5, 27.5)
  local POLES2 = {{2.5,22.5},{2.5,26.5},{16.5,22.5},{16.5,26.5},{27.5,20.5}}
  for _, p in pairs(POLES2) do add(p[3] or 'medium-electric-pole', p[1], p[2]) end
end
-- ONLY (optional set of names) limits a place run to the parts the network can supply
if ONLY then local K = {} for _, e in pairs(L) do if ONLY[e[1]] then K[#K + 1] = e end end if MODE == 'place' then L = K end end
-- power coverage: every planned entity that uses electricity must sit in some pole's supply area
local poles = {}
for _, p in pairs(s.find_entities_filtered{type = 'electric-pole', area = {{-20, 0}, {40, 35}}}) do
  local r = p.prototype.get_supply_area_distance(p.quality)
  poles[#poles + 1] = {p.position.x, p.position.y, r}
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
      if gh then placed = placed + 1; if e[6] then pcall(function() gh.set_recipe(e[6]) end) end
        if e[7] then pcall(function() gh.use_filters = true; gh.set_filter(1, e[7]) end) end end
    end
  end
end
local c = {} for k, v in pairs(cnt) do c[#c + 1] = k .. '=' .. v end
rcon.print(string.format('phase %d %s: total %d ok %d placed %d bad %d unpowered %d | %s\nBAD %s\nUNPOWERED %s',
  PHASE, MODE, #L, ok, placed, #bad, #unpowered, table.concat(c, ','), table.concat(bad, ' '), table.concat(unpowered, ' ')))
