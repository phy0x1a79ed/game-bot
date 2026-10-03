local surf = game.surfaces[1]
local S = defines.entity_status
local out = {}
local function add(k) out[#out+1] = k end
local function at(e) return e.name .. '@' .. math.floor(e.position.x) .. ',' .. math.floor(e.position.y) end

-- Engine script time is budgeted per seat (50 ms/s): reading status on every belt, pipe and pole cost ~50 ms a run.
-- Part B (walls, poles, remnants, enemies); part A is alerts.lua.
-- So status is read on machines and turrets only, health on those plus walls and poles; lost belts show as remnants.
local MACHINES = {'assembling-machine', 'furnace', 'lab', 'mining-drill', 'boiler', 'generator', 'offshore-pump', 'radar', 'roboport', 'ammo-turret', 'electric-turret', 'fluid-turret', 'rocket-silo', 'reactor'}
local BASE = {{-450, -550}, {650, 450}}

for _, e in pairs(surf.find_entities_filtered{force = 'player', type = {'wall', 'gate', 'electric-pole'}, area = BASE}) do
  if e.health < e.max_health then add('DAMAGED ' .. at(e)) end
end

for _, c in pairs(surf.find_entities_filtered{type = 'corpse', area = BASE}) do
  if c.name:find('remnants', 1, true) then add('DESTROYED ' .. c.name:gsub('%-remnants', '') .. '@' .. math.floor(c.position.x) .. ',' .. math.floor(c.position.y)) end
end

for _, c in pairs(surf.find_entities_filtered{type = 'character-corpse'}) do
  local p = game.get_player(c.character_corpse_player_index)
  add('SEATDEAD ' .. (p and p.name or '?') .. '@' .. math.floor(c.position.x) .. ',' .. math.floor(c.position.y) .. ' tick ' .. c.character_corpse_tick_of_death)
end

local cells = {}
for _, u in pairs(surf.find_entities_filtered{force = 'enemy', type = 'unit', position = {0, -20}, radius = 250}) do
  if surf.count_entities_filtered{force = 'player', position = u.position, radius = 40, limit = 1} > 0 then
    cells[math.floor(u.position.x / 20) * 20 .. ',' .. math.floor(u.position.y / 20) * 20] = true
  end
end
for k in pairs(cells) do add('ENEMY near base, cell ' .. k) end

table.sort(out)
rcon.print(table.concat(out, '\n'))
