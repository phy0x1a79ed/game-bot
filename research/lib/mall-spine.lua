-- mall-spine.lua: ghost layout of Spine A (M0) south of the annex (mall builder, run 4). Prepend MODE='check'|'place'.
-- Bus: x=-16.5 copper main (flows N, exists) | M x=-15.5 flows S: east lane iron (side-loaded at the head), west lane gears.
-- West cells: AM centre (-19.5,y), long-handed (-17.5,y) picks M, out inserter (-21.5,y) -> chest (-22.5,y). East cells: AM centre (-11.5,y).
-- Inserter direction = the side it picks from. The trunk splitter at (-19,-19.5) is placed by the seat (a ghost cannot replace a belt).
local s = game.surfaces[1]
local N, E, S, W = 0, 4, 8, 12
local L = {}
local function add(n, x, y, d, t, r) L[#L + 1] = {n, x, y, d or N, t, r} end
local function col(x, y1, y2, d) for y = y1, y2 do add('transport-belt', x, y, d) end end
-- iron branch: splitter output (-18.5,-18.5) south, east to x=-15.5, south under red belts and the copper main, to the spine head
col(-18.5, -18.5, -16.5, S); for x = -18.5, -16.5 do add('transport-belt', x, -15.5, E) end
col(-15.5, -15.5, -2.5, S)
add('underground-belt', -15.5, -1.5, S, 'input'); add('underground-belt', -15.5, 3.5, S, 'output')
add('underground-belt', -15.5, 4.5, S, 'input'); add('underground-belt', -15.5, 9.5, S, 'output')
add('transport-belt', -15.5, 10.5, S); add('transport-belt', -15.5, 11.5, E); add('transport-belt', -14.5, 11.5, E); add('transport-belt', -13.5, 11.5, S)
add('underground-belt', -13.5, 12.5, S, 'input'); add('underground-belt', -13.5, 17.5, S, 'output')
col(-13.5, 18.5, 27.5, S)
add('transport-belt', -13.5, 28.5, W); add('transport-belt', -14.5, 28.5, W)
col(-15.5, 27.5, 50.5, S)  -- M: (-15.5,27.5) is the dummy behind the head, so the iron side-loads onto the east lane
-- poles
for _, p in pairs({{-20.5, 32.5}, {-20.5, 40.5}, {-20.5, 48.5}, {-13.5, 32.5}}) do add('medium-electric-pole', p[1], p[2]) end
-- west cells
local function west(y, recipe)
  add('assembling-machine-1', -19.5, y, N, nil, recipe)
  add('long-handed-inserter', -17.5, y, E); add('inserter', -21.5, y, E); add('iron-chest', -22.5, y)
end
west(34.5, 'iron-chest'); west(38.5, 'transport-belt'); west(42.5, 'underground-belt'); west(46.5, 'pipe')
add('inserter', -18.5, 40.5, N)  -- belt AM -> UG AM
-- east cells: 2 gear AM1, iron in by long-handed from M, gears out by long-handed onto M's west lane
for _, y in pairs({30.5, 34.5}) do
  add('assembling-machine-1', -11.5, y, N, nil, 'iron-gear-wheel')
  add('long-handed-inserter', -13.5, y - 1, W); add('long-handed-inserter', -13.5, y + 1, E)
end
if ONLY then local K = {} for _, e in pairs(L) do if ONLY[e[1]] then K[#K + 1] = e end end L = K end
local poles = {}
for _, p in pairs(s.find_entities_filtered{type = 'electric-pole', area = {{-30, 20}, {10, 55}}}) do
  poles[#poles + 1] = {p.position.x, p.position.y, p.prototype.get_supply_area_distance(p.quality)}
end
for _, e in pairs(L) do if e[1] == 'medium-electric-pole' then poles[#poles + 1] = {e[2], e[3], 3.5} end end
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
rcon.print(string.format('spine %s: total %d ok %d placed %d bad %d unpowered %d | %s\nBAD %s\nUNPOWERED %s',
  MODE, #L, ok, placed, #bad, #unpowered, table.concat(c, ','), table.concat(bad, ' '), table.concat(unpowered, ' ')))
