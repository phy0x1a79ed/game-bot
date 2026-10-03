-- rail-trunk.lua: east trunk (RAIL.md sec 2, 4, 10). Prepend MODE='check'|'ghost' and PART='yard'|'east'.
-- Straight rails on the y=-161 line, centres at odd x (grid read from a snapped ghost); big poles at y=-165 every 28;
-- stops 'Unload Stone Base' (x=15, north side, west-facing), 'Load Coal E' (343) and 'Load Stone E' (459) (south side, east-facing).
-- yard = x 9..109 + the feed poles from the workshop poles; east = x 111..461. Rock (85,-161) and tree (399,-161) get deconstruction marks.
local s = game.surfaces[1]
local Y, PY = -161, -165
local X0, X1 = 9, 109
if PART == 'east' then X0, X1 = 111, 461 end
local bad, rails, poles, stops, corridor, placed, marks = {}, 0, 0, 0, {}, 0, 0
local function chk(name, x, y, d)
  return s.can_place_entity{name = name, position = {x, y}, direction = d or 0, force = 'player', build_check_type = defines.build_check_type.manual_ghost}
end
local function ghost(name, x, y, d, station)
  if MODE ~= 'ghost' then return end
  if s.find_entities_filtered{position = {x, y}, radius = 0.3, ghost_name = name}[1] or s.find_entities_filtered{position = {x, y}, radius = 0.3, name = name}[1] then return end
  local g = {name = 'entity-ghost', inner_name = name, position = {x, y}, direction = d or 0, force = 'player'}
  if station then g.station = station end
  if s.create_entity(g) then placed = placed + 1 end
end
for x = X0, X1, 2 do
  rails = rails + 1
  if not chk('straight-rail', x, Y, 4) then
    local b = s.find_entities_filtered{area = {{x - 1, Y - 1}, {x + 1, Y + 1}}, type = {'tree', 'simple-entity', 'cliff'}}[1]
    bad[#bad + 1] = x .. ':' .. (b and (b.name .. '@' .. b.position.x .. ',' .. b.position.y) or '?')
  end
  ghost('straight-rail', x, Y, 4)
end
local px = {}  -- trunk pole line dropped (lead 02:0x): rails need no power
px = {}
if PART == 'yard' then
  for _, p in pairs{{12, -108}, {12, -136}} do
    poles = poles + 1
    if not chk('big-electric-pole', p[1], p[2]) then bad[#bad + 1] = 'pole@' .. p[1] .. ',' .. p[2] end
    ghost('big-electric-pole', p[1], p[2])
  end
end
for _, x in pairs(px) do
  poles = poles + 1
  if not chk('big-electric-pole', x, PY) then bad[#bad + 1] = 'pole@' .. x .. ',' .. PY end
  ghost('big-electric-pole', x, PY)
end
local STOPS = PART == 'yard' and {{'Unload Stone Base', 15, -163, 12}} or {{'Load Coal E', 343, -159, 4}, {'Load Stone E', 459, -159, 4}}
for _, st in pairs(STOPS) do
  stops = stops + 1
  ghost('train-stop', st[2], st[3], st[4], st[1])
end
-- corridor scan: anything that is not rail, ghost-rail or a decorative blocks the second track and the platforms
local c = {}
for _, e in pairs(s.find_entities_filtered{area = {{X0 - 2, -166}, {X1 + 2, -154}}}) do
  if e.type ~= 'straight-rail' and e.type ~= 'curved-rail-a' and e.type ~= 'curved-rail-b' and e.type ~= 'resource' and not (e.type == 'entity-ghost' and (e.ghost_name == 'straight-rail' or e.ghost_name == 'big-electric-pole' or e.ghost_name == 'train-stop')) and e.name ~= 'big-electric-pole' then
    c[#c + 1] = e.name .. '@' .. e.position.x .. ',' .. e.position.y
  end
end
if MODE == 'ghost' then
  for _, e in pairs(s.find_entities_filtered{area = {{80, -163}, {90, -159}}, name = 'big-sand-rock'}) do if e.order_deconstruction('player') then marks = marks + 1 end end
  for _, e in pairs(s.find_entities_filtered{area = {{397, -163}, {401, -159}}, type = 'tree'}) do if e.order_deconstruction('player') then marks = marks + 1 end end
end
rcon.print(string.format('%s %s rails %d poles %d stops %d placed %d marks %d bad[%d] %s corridor[%d] %s', MODE, PART, rails, poles, stops, placed, marks, #bad, table.concat(bad, ' '), #c, table.concat(c, ' ')))
