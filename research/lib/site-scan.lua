local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end
-- entities in the candidate prototype box
local ents = surf.find_entities_filtered{area={{-50,-14},{-26,-4}}, force='player'}
p('entities in box (-50,-14)-(-26,-4): '..#ents)
for _, e in pairs(ents) do
  p('  '..e.name..' @ '..string.format('%.1f,%.1f',e.position.x,e.position.y)..' dir='..tostring(e.direction))
end
-- prototype geometry
local protos = {'assembling-machine-1','assembling-machine-2','inserter','fast-inserter'}
for _, n in pairs(protos) do
  local pr = prototypes.entity[n]
  if pr then
    local cb = pr.collision_box
    p(n..' collision_box: ('..cb.left_top.x..','..cb.left_top.y..')-('..cb.right_bottom.x..','..cb.right_bottom.y..')')
  end
end
-- automation-2 / assembling-machine-2 availability
local f = game.forces.player
p('automation-2 researched='..tostring(f.technologies['automation-2'] and f.technologies['automation-2'].researched))
p('assembling-machine-2 enabled='..tostring(prototypes.entity['assembling-machine-2'] and f.recipes['assembling-machine-2'] and f.recipes['assembling-machine-2'].enabled))
p('current_research='..tostring(f.current_research and f.current_research.name)..' '..string.format('%.1f%%', (f.research_progress or 0)*100))
-- nearby poles for power reach
local poles = surf.find_entities_filtered{area={{-52,-16},{-24,-2}}, name={'small-electric-pole','medium-electric-pole'}}
p('poles in wider area: '..#poles)
for _, e in pairs(poles) do p('  pole @ '..string.format('%.1f,%.1f',e.position.x,e.position.y)) end
rcon.print(table.concat(out, '\n'))
