local seat = SEAT_ID
local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end

-- 1. mine the test-furnace endpoint (recovers materials to the seat)
local furn = surf.find_entities_filtered{name='stone-furnace', position={80,-46}, radius=1.5}[1]
local player
for _, pl in pairs(game.connected_players) do if pl.name == seat then player = pl end end
if not player then
  for _, force in pairs(game.forces) do end
end
-- fall back: find character by name match on seat string via remote? We just use game_bot remote for legality.
local ok1, err1 = pcall(function()
  if furn then
    local inv = player and player.get_main_inventory()
    if furn.get_fuel_inventory() then furn.get_fuel_inventory().clear() end
    local res = furn.mine{inventory = inv, force=false}
    p('mined furnace: ' .. tostring(res))
  else
    p('furnace not found (already gone?)')
  end
end)
if not ok1 then p('mine error: ' .. tostring(err1)) end

rcon.print(table.concat(out, '\n'))
