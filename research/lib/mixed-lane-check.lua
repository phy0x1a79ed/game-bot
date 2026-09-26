local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end

-- ore richness at the candidate new row (y=-66, south end of the now-powered pole line)
local ore = surf.find_entities_filtered{type='resource', name='iron-ore', area={{-30,-68},{-15,-63}}}
local tot, n = 0, 0
for _, e in pairs(ore) do tot = tot + e.amount; n = n + 1 end
p('iron-ore near (-24.5,-65.5): n=' .. n .. ' avg=' .. (n>0 and string.format('%.0f', tot/n) or 0))

-- turret cover check
local turrets = surf.find_entities_filtered{name='gun-turret', position={-24.5,-65.5}, radius=20}
p('turrets within 20 of (-24.5,-65.5): ' .. #turrets)
for _, t in pairs(turrets) do p('  turret @ ' .. string.format('%.1f,%.1f', t.position.x, t.position.y)) end

-- power: nearest pole
local poles = surf.find_entities_filtered{name='small-electric-pole', position={-24.5,-65.5}, radius=10}
p('poles within 10 of (-24.5,-65.5): ' .. #poles)
for _, pl in pairs(poles) do p('  pole @ ' .. string.format('%.1f,%.1f', pl.position.x, pl.position.y) .. ' dist=' .. string.format('%.2f', ((pl.position.x+24.5)^2+(pl.position.y+65.5)^2)^0.5)) end

-- can_place checks for the mixed-lane prototype layout:
-- drill(-24.5,-65.5)E -> ore-belt(-22.5,-65.5)S (a short 2-tile ore-lane stub) -> ore-belt(-22.5,-64.5)S
-- furnace at (-20,-65) fed by: ore-inserter(-21.5,-65.5? ) hmm compute reach: furnace 2x2 centred (-20,-65), inserter needs to sit adjacent
local checks = {
  {name='electric-mining-drill', pos={-24.5,-65.5}, dir=defines.direction.east, label='new ore drill'},
  {name='transport-belt', pos={-22.5,-65.5}, dir=defines.direction.south, label='ore-lane tile 1'},
  {name='transport-belt', pos={-22.5,-64.5}, dir=defines.direction.south, label='ore-lane tile 2'},
  {name='stone-furnace', pos={-20,-65}, dir=defines.direction.north, label='furnace'},
  {name='inserter', pos={-21.5,-65}, dir=defines.direction.west, label='ore-inserter (belt->furnace)'},
  {name='transport-belt', pos={-20,-62.5}, dir=defines.direction.west, label='coal-lane stub'},
  {name='inserter', pos={-20,-63.5}, dir=defines.direction.south, label='coal-inserter (belt->furnace)'},
  {name='inserter', pos={-18.5,-65}, dir=defines.direction.east, label='output inserter (furnace->plate belt)'},
  {name='transport-belt', pos={-17.5,-65}, dir=defines.direction.west, label='plate-lane tile'},
}
for _, c in pairs(checks) do
  local ok = surf.can_place_entity{name=c.name, position=c.pos, direction=c.dir, force='player'}
  p(string.format('can_place %-40s %s @ %.1f,%.1f = %s', c.label, c.name, c.pos[1], c.pos[2], tostring(ok)))
end

rcon.print(table.concat(out, '\n'))
