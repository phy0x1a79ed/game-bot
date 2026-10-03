local surf = game.surfaces[1]
local S = defines.entity_status
local out = {}
local function add(k) out[#out+1] = k end
local function at(e) return e.name .. '@' .. math.floor(e.position.x) .. ',' .. math.floor(e.position.y) end

-- Engine script time is budgeted per seat (50 ms/s): reading status on every belt, pipe and pole cost ~50 ms a run.
-- Part A (machines and turrets). Part B (alerts-b.lua): walls, poles, remnants, enemies.
-- So status is read on machines and turrets only, health on those plus walls and poles; lost belts show as remnants.
local MACHINES = {'assembling-machine', 'furnace', 'lab', 'mining-drill', 'boiler', 'generator', 'offshore-pump', 'radar', 'roboport', 'ammo-turret', 'electric-turret', 'fluid-turret', 'rocket-silo', 'reactor'}
local BASE = {{-450, -550}, {650, 450}}

for _, e in pairs(surf.find_entities_filtered{force = 'player', type = MACHINES}) do
  local st = e.status
  if st == S.no_fuel then add('NOFUEL ' .. at(e))
  elseif st == S.no_power then add('NOPOWER ' .. at(e))
  elseif (st == S.no_ingredients or st == S.missing_science_packs) and (e.type == 'assembling-machine' or e.type == 'lab') then add('STARVED ' .. at(e))
  end
  if e.health < e.max_health then add('DAMAGED ' .. at(e)) end
  if e.name == 'gun-turret' and e.get_inventory(defines.inventory.turret_ammo).get_item_count() < 10 then add('LOWAMMO ' .. at(e) .. ' ammo<10') end
end

table.sort(out)
rcon.print(table.concat(out, '\n'))
