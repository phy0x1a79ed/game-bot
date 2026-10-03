-- ammo-belt-check.lua: status of every inserter in AREA_BOX, ammo in each gun turret there, belt item count and feed chest contents.
local s=game.surfaces[1] local A=AREA_BOX
local st={} for k,v in pairs(defines.entity_status) do st[v]=k end
local o={'tick '..game.tick}
local ins={} for _,e in ipairs(s.find_entities_filtered{type='inserter',area=A}) do ins[#ins+1]=string.format('(%g,%g)%s',e.position.x,e.position.y,(st[e.status] or '?'):sub(1,12)) end
o[#o+1]='ins: '..table.concat(ins,' ')
local t={} for _,e in ipairs(s.find_entities_filtered{name='gun-turret',area=A}) do local n,k=0,'-' for _,it in pairs(e.get_inventory(defines.inventory.turret_ammo).get_contents()) do n=n+it.count k=it.name:sub(1,1) end t[#t+1]=string.format('(%g,%g)%s%d h%d',e.position.x,e.position.y,k,n,e.health) end
o[#o+1]='turrets: '..table.concat(t,' ')
local n=0 for _,b in ipairs(s.find_entities_filtered{type='transport-belt',area=A}) do for l=1,2 do local tl=b.get_transport_line(l) n=n+tl.get_item_count('piercing-rounds-magazine')+tl.get_item_count('firearm-magazine') end end
local c={} for _,e in ipairs(s.find_entities_filtered{type='container',area=A}) do c[#c+1]=string.format('(%g,%g)%d',e.position.x,e.position.y,e.get_inventory(defines.inventory.chest).get_item_count()) end
o[#o+1]='belt ammo '..n..' chests '..table.concat(c,' ')
rcon.print(table.concat(o,'\n'))
