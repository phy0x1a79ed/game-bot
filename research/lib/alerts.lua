local surf = game.surfaces[1]
local S = defines.entity_status
local out = {}
local function add(k) out[#out+1] = k end
local function at(e) return e.name .. '@' .. math.floor(e.position.x) .. ',' .. math.floor(e.position.y) end

for _, e in pairs(surf.find_entities_filtered{force = 'player'}) do
  if e.type ~= 'character' then
    local ok, st = pcall(function() return e.status end)
    if ok and st then
      if st == S.no_fuel then add('NOFUEL ' .. at(e))
      elseif st == S.no_power then add('NOPOWER ' .. at(e))
      elseif (st == S.no_ingredients or st == S.missing_science_packs) and (e.type == 'assembling-machine' or e.type == 'lab') then add('STARVED ' .. at(e))
      end
    end
    if e.health and e.max_health and e.health < e.max_health then add('DAMAGED ' .. at(e)) end
    if e.name == 'gun-turret' then
      local n = e.get_inventory(defines.inventory.turret_ammo).get_item_count()
      if n < 10 then add('LOWAMMO ' .. at(e) .. ' ammo<10') end
    end
  end
end

for _, c in pairs(surf.find_entities_filtered{type = 'corpse'}) do
  if c.name:find('remnants', 1, true) then add('DESTROYED ' .. c.name:gsub('%-remnants', '') .. '@' .. math.floor(c.position.x) .. ',' .. math.floor(c.position.y)) end
end

local cells = {}
for _, u in pairs(surf.find_entities_filtered{force = 'enemy', type = 'unit', position = {0, -20}, radius = 250}) do
  if surf.count_entities_filtered{force = 'player', position = u.position, radius = 40, limit = 1} > 0 then
    local k = math.floor(u.position.x / 20) * 20 .. ',' .. math.floor(u.position.y / 20) * 20
    cells[k] = true
  end
end
for k in pairs(cells) do add('ENEMY near base, cell ' .. k) end

table.sort(out)
rcon.print(table.concat(out, '\n'))
