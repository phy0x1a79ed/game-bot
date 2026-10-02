-- green-lab-rate.lua: tick, products_finished of the green asms, lab statuses, current research and its progress. Run twice and diff.
local s=game.surfaces[1]
local out={'tick='..game.tick}
for _,e in pairs(s.find_entities_filtered{type='assembling-machine',force='player'}) do
  local r=e.get_recipe()
  if r and r.name=='logistic-science-pack' then
    out[#out+1]=string.format('green (%.1f,%.1f) finished=%d st=%s',e.position.x,e.position.y,e.products_finished,tostring(e.status))
  end
end
local st={}
for _,e in pairs(s.find_entities_filtered{type='lab',force='player'}) do
  st[#st+1]=string.format('(%.1f,%.1f)=%s',e.position.x,e.position.y,tostring(e.status))
end
out[#out+1]='labs '..table.concat(st,' ')
local f=game.forces.player
out[#out+1]='research '..tostring(f.current_research and f.current_research.name)..' '..string.format('%.4f',f.research_progress)
rcon.print(table.concat(out,'\n'))
