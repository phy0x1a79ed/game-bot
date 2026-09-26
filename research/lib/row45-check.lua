local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end
local f = surf.find_entities_filtered{position={-22,-45}, radius=1, name='stone-furnace'}[1]
if f then
  p('furnace(-22,-45): status='..tostring(f.status)..' result='..tostring(f.get_output_inventory().get_item_count('iron-plate')))
else p('furnace not found') end
local i = surf.find_entities_filtered{position={-20.5,-45}, radius=0.6, name='burner-inserter'}[1]
if i then
  local fuel = i.get_fuel_inventory() and i.get_fuel_inventory().get_item_count('coal') or -1
  p('inserter(-20.5,-45): status='..tostring(i.status)..' fuel_coal='..fuel..' pickup='..i.pickup_position.x..','..i.pickup_position.y..' drop='..i.drop_position.x..','..i.drop_position.y)
else p('inserter not found near -20.5,-45') end
local b = surf.find_entities_filtered{position={-19.5,-45.5}, radius=0.6, name='transport-belt'}[1]
if b then
  local line1 = b.get_transport_line(1).get_contents()
  local line2 = b.get_transport_line(2).get_contents()
  local c1,c2={},{}
  for _,it in pairs(line1) do c1[#c1+1]=it.name..':'..it.count end
  for _,it in pairs(line2) do c2[#c2+1]=it.name..':'..it.count end
  p('belt(-19.5,-45.5): line1='..table.concat(c1,',')..' line2='..table.concat(c2,','))
else p('belt not found near -19.5,-45.5') end
rcon.print(table.concat(out, '\n'))
