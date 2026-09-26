local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end

p('tick=' .. game.tick)

-- (2) boiler/engine/feed-chest baseline snapshot
local function find1(name, pos)
  local e = surf.find_entities_filtered{name=name, position=pos, radius=1.5}[1]
  return e
end
local boiler = find1('boiler', {-50.5,-9})
local engine = find1('steam-engine', {-50.5,-13.5})
local feedchest = find1('iron-chest', {-47.5,-8.5})
local burnerins = find1('burner-inserter', {-48.5,-8.5})
if boiler then
  local bf = boiler.get_fuel_inventory()
  p(string.format('boiler@%.1f,%.1f status=%d fuel_coal=%d', boiler.position.x, boiler.position.y, boiler.status, bf and bf.get_item_count('coal') or -1))
else p('boiler NOT FOUND near -50.5,-9') end
if engine then
  p(string.format('engine@%.1f,%.1f status=%d energy_generated_last_tick=%d', engine.position.x, engine.position.y, engine.status, engine.energy_generated_last_tick))
else p('engine NOT FOUND near -50.5,-13.5') end
if feedchest then
  p(string.format('feedchest@%.1f,%.1f coal=%d', feedchest.position.x, feedchest.position.y, feedchest.get_inventory(defines.inventory.chest).get_item_count('coal')))
else p('feedchest NOT FOUND near -47.5,-8.5') end
if burnerins then
  local bf = burnerins.burner
  p(string.format('boiler_feed_inserter@%.1f,%.1f status=%d fuel_coal=%d', burnerins.position.x, burnerins.position.y, burnerins.status, bf and bf.inventory.get_item_count('coal') or -1))
end

-- (3) existing coal-patch entities: drills/furnaces/chests/inserters near ring1 + research's chains
local box = {{58,-58},{95,-35}}
local ents = surf.find_entities_filtered{area=box, force='player'}
p('=== existing player entities in coal-patch box (58,-58)-(95,-35): ' .. #ents .. ' ===')
for _, e in pairs(ents) do
  local extra = ''
  if e.type == 'mining-drill' or e.type == 'furnace' then
    local b = e.burner
    extra = ' fuel=' .. (b and b.inventory.get_item_count('coal') or -1)
  elseif e.type == 'ammo-turret' then
    extra = ' ammo=' .. e.get_inventory(defines.inventory.turret_ammo).get_item_count()
  end
  p(string.format('  %s @ %.2f,%.2f dir=%s%s', e.name, e.position.x, e.position.y, tostring(e.direction), extra))
end

-- (5) turret positions in the wider region (for cover-radius reasoning)
local turret_proto = prototypes.entity['gun-turret']
p('gun-turret range=' .. tostring(turret_proto and turret_proto.attack_parameters and turret_proto.attack_parameters.range))

rcon.print(table.concat(out, '\n'))
