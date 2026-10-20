-- Per-entity rolling hash over nauvis: name, position, health, and the unit's command state where it has one.
local s = game.surfaces.nauvis
local h1, h2, M = 0, 0, 2147483629
local function mix(v) v = math.floor(v) % M h1 = (h1 * 31 + v) % M h2 = (h2 * 131 + v + 7) % M end
local rows = s.find_entities_filtered{}
for _, e in pairs(rows) do
  mix(e.position.x * 256) mix(e.position.y * 256)
  if e.health then mix(e.health * 1000) end
  mix(#e.name)
  if e.unit_number then mix(e.unit_number) end
end
rcon.print(helpers.table_to_json({tick = game.tick, n = #rows, h1 = h1, h2 = h2}))
