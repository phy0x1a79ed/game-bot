local surf = game.surfaces["nauvis"]
local out = {}
local function p(s) out[#out+1] = s end
local pts = {{73,-48},{75,-48},{75,-46},{73,-46},{78,-48},{80,-48}}
p("tick=" .. game.tick)
for _, pt in pairs(pts) do
  local e = surf.find_entities_filtered{position=pt, radius=0.6, name="burner-mining-drill"}[1]
  if e then
    local fuel = e.get_fuel_inventory().get_item_count()
    p(string.format("(%.0f,%.0f) status=%d fuel=%d", e.position.x, e.position.y, e.status, fuel))
  end
end
local ground = surf.find_entities_filtered{type="item-entity", position={76,-47}, radius=10}
local gc = 0
for _, it in pairs(ground) do if it.stack.name == "coal" then gc = gc + it.stack.count end end
p("coal-on-ground within 10 of (76,-47): " .. gc .. " (" .. #ground .. " piles)")
rcon.print(table.concat(out, "\n"))
