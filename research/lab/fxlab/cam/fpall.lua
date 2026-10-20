-- Whole-surface aggregate fingerprint: cheap sums that move with any simulation difference.
local s = game.surfaces.nauvis
local t = {tick = game.tick, n = 0, sx = 0, sy = 0, hp = 0, crafted = 0, belt = 0, inv = 0, chars = 0, units = 0, maxun = 0}
for _, e in pairs(s.find_entities_filtered{}) do
  t.n = t.n + 1
  t.sx = t.sx + e.position.x
  t.sy = t.sy + e.position.y
  if e.health then t.hp = t.hp + e.health end
  if e.unit_number and e.unit_number > t.maxun then t.maxun = e.unit_number end
  if e.type == "character" then t.chars = t.chars + 1 end
  if e.type == "unit" then t.units = t.units + 1 end
  if e.type == "assembling-machine" or e.type == "furnace" then t.crafted = t.crafted + e.products_finished end
  if e.type == "transport-belt" or e.type == "underground-belt" or e.type == "splitter" then
    for i = 1, e.get_max_transport_line_index() do
      local l = e.get_transport_line(i)
      t.belt = t.belt + #l
    end
  end
  if e.type == "container" or e.type == "logistic-container" then
    t.inv = t.inv + e.get_inventory(defines.inventory.chest).get_item_count()
  end
end
t.sx = math.floor(t.sx * 1000) t.sy = math.floor(t.sy * 1000) t.hp = math.floor(t.hp * 1000)
t.players = #game.players
t.connected = #game.connected_players
local st = game.forces.player.get_item_production_statistics(s)
local prod = 0
for _, v in pairs(st.input_counts) do prod = prod + v end
t.produced = prod
t.evo = game.forces.enemy.get_evolution_factor(s)
rcon.print(helpers.table_to_json(t))
