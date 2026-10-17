-- capture-ports.lua: what crosses the boundary of a live rectangle. Expects CAP = {surface, x0, y0, x1, y1}.
-- Prints JSON {origin = {x, y}, ports = [...]}. Port positions are relative to origin, the smallest position of
-- any belt in the rectangle (belt ghosts included: the bench revives them), so the bench can place the ports.
--   belt-in: a belt inside fed by a belt outside; lanes = the items on each lane now (a starved lane reads empty)
--   belt-out: a belt inside that feeds a belt outside
--   inserter-in: an inserter inside picking from outside; items = what its pickup target holds
--   inserter-out: an inserter inside dropping outside
local C = CAP
local s = game.surfaces[C.surface]
local A = {{C.x0, C.y0}, {C.x1, C.y1}}
local function inside(p) return p.x >= C.x0 and p.x <= C.x1 and p.y >= C.y0 and p.y <= C.y1 end
local ox, oy = math.huge, math.huge
-- even- and odd-sized entities snap to different grids when a blueprint is built, so only belts anchor it
local function is_belt(e) return e.type == "transport-belt" or (e.type == "entity-ghost" and e.ghost_type == "transport-belt") end
for _, e in pairs(s.find_entities_filtered{area = A, force = "player"}) do
  if inside(e.position) and is_belt(e) then ox = math.min(ox, e.position.x) oy = math.min(oy, e.position.y) end
end
local function lane_items(b, i)
  local names = {}
  for _, it in pairs(b.get_transport_line(i).get_contents()) do names[#names + 1] = it.name end
  return names
end
local ports = {}
local function rel(p) return p.x - ox, p.y - oy end
for _, b in pairs(s.find_entities_filtered{area = A, type = {"transport-belt", "underground-belt", "splitter"}}) do
  if not inside(b.position) then goto next_belt end
  local x, y = rel(b.position)
  for _, i in pairs(b.belt_neighbours.inputs) do
    if not inside(i.position) then
      ports[#ports + 1] = {kind = "belt-in", x = x, y = y, name = b.name, direction = b.direction,
        lanes = {lane_items(i, 1), lane_items(i, 2)}}
    end
  end
  for _, o in pairs(b.belt_neighbours.outputs) do
    if not inside(o.position) then ports[#ports + 1] = {kind = "belt-out", x = x, y = y, name = b.name, direction = b.direction} end
  end
  ::next_belt::
end
for _, ins in pairs(s.find_entities_filtered{area = A, type = "inserter"}) do
  if not inside(ins.position) then goto next_inserter end
  local pick, drop = ins.pickup_target, ins.drop_target
  if not inside(ins.pickup_position) then
    local items = {}
    if pick then
      local inv = pick.get_output_inventory and pick.get_output_inventory() or nil
      if pick.type == "transport-belt" or pick.type == "underground-belt" or pick.type == "splitter" then
        for i = 1, 2 do for _, n in pairs(lane_items(pick, i)) do items[#items + 1] = n end end
      elseif inv then
        for _, it in pairs(inv.get_contents()) do items[#items + 1] = it.name end
      end
    end
    if ins.held_stack.valid_for_read then items[#items + 1] = ins.held_stack.name end
    local px, py = rel(ins.pickup_position)
    ports[#ports + 1] = {kind = "inserter-in", x = px, y = py, items = items}
  end
  if not inside(ins.drop_position) then
    local dx, dy = rel(ins.drop_position)
    ports[#ports + 1] = {kind = "inserter-out", x = dx, y = dy}
  end
  ::next_inserter::
end
rcon.print(helpers.table_to_json{origin = {x = ox, y = oy}, ports = ports})
