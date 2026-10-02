-- research-avail.lua: techs ready to research (prereqs done) that need only red/green packs, with unit count and time.
local f=game.forces.player
local out={}
for n,t in pairs(f.technologies) do
  if t.enabled and not t.researched then
    local ready=true
    for _,p in pairs(t.prerequisites) do if not p.researched then ready=false end end
    local only=true
    for _,ing in pairs(t.research_unit_ingredients) do if ing.name~='automation-science-pack' and ing.name~='logistic-science-pack' then only=false end end
    if ready and only then out[#out+1]=string.format('%s units=%s t=%s',n,tostring(t.research_unit_count),tostring(t.research_unit_energy/60)) end
  end
end
table.sort(out)
rcon.print(table.concat(out,'\n'))
