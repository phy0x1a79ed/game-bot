-- iron3-r4.lua: R3/R4/gear status and finished counts, east red belt contents
local s=game.surfaces[1]
local st={} for k,v in pairs(defines.entity_status) do st[v]=k end
local function am(n,x,y) local e=s.find_entity(n,{x,y}) if not e then return n..' missing' end return string.format('%s(%g,%g) %s fin=%d', e.get_recipe() and e.get_recipe().name or 'nil',x,y,st[e.status] or e.status,e.products_finished) end
rcon.print('tick '..game.tick)
rcon.print(am('assembling-machine-2',-25.5,4.5)) rcon.print(am('assembling-machine-2',-19.5,16.5)) rcon.print(am('assembling-machine-1',-21.5,12.5))
local function lane(x,y) local b=s.find_entities_filtered{position={x,y},radius=0.3,type='transport-belt'}[1] if not b then return 'nobelt' end local o='' for i=1,2 do for _,c in pairs(b.get_transport_line(i).get_contents()) do o=o..' L'..i..':'..c.name..'x'..c.count end end return x..','..y..o end
for _,p in pairs({{-21.5,4.5},{-22.5,4.5},{-22.5,2.5},{-23.5,10.5}}) do rcon.print(lane(p[1],p[2])) end
