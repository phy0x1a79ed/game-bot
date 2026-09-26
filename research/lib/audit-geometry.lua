-- Read-only: exact bounding boxes for the entity types involved in the
-- fuel-feed inserter bug, at each of the four directions, plus the
-- pickup/drop offset a burner-inserter actually produces at each direction.
local surf = game.surfaces["nauvis"]
local out = {}
local function p(s) out[#out+1] = s end

local function bb(e)
  local b = e.bounding_box
  return string.format("bbox=(%.2f,%.2f)-(%.2f,%.2f)", b.left_top.x, b.left_top.y, b.right_bottom.x, b.right_bottom.y)
end

p("=== sample bounding boxes (first of each, any direction) ===")
for _, name in ipairs({"burner-mining-drill","stone-furnace","iron-chest","burner-inserter"}) do
  local ents = surf.find_entities_filtered{force="player", name=name}
  for i, e in pairs(ents) do
    p(name .. " dir=" .. e.direction .. " pos=(" .. e.position.x .. "," .. e.position.y .. ") " .. bb(e))
    if i >= 2 then break end
  end
end

p("=== inserter pickup/drop offset from own center, by direction (measured) ===")
for _, e in pairs(surf.find_entities_filtered{force="player", name="burner-inserter"}) do
  local pox = e.pickup_position.x - e.position.x
  local poy = e.pickup_position.y - e.position.y
  local dox = e.drop_position.x - e.position.x
  local doy = e.drop_position.y - e.position.y
  p(string.format("dir=%-2d pickup_off=(%.2f,%.2f) drop_off=(%.2f,%.2f)", e.direction, pox, poy, dox, doy))
end

rcon.print(table.concat(out, "\n"))
