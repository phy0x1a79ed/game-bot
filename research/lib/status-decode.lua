local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end
local rev = {}
for k, v in pairs(defines.entity_status) do rev[v] = k end
local names = {
  {'cable-asm','assembling-machine-1',{-34.5,-16.5}},
  {'circuit-asm','assembling-machine-1',{-30.5,-16.5}},
  {'link-inserter','inserter',{-32.5,-16.5}},
  {'output-inserter','inserter',{-28.5,-16.5}},
}
for _, n in pairs(names) do
  local e = surf.find_entity(n[2], n[3])
  if e then
    p(n[1]..' status='..tostring(rev[e.status])..' energy='..tostring(e.energy)..' network='..tostring(e.electric_network_id))
  end
end
local poles = surf.find_entities_filtered{name='small-electric-pole', area={{-37,-19},{-26,-13}}}
for _, e in pairs(poles) do p('pole @ '..string.format('%.1f,%.1f',e.position.x,e.position.y)..' network='..tostring(e.electric_network_id)) end
rcon.print(table.concat(out, '\n'))
