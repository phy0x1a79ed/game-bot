-- blue-rate.lua: pack assembler crafts (modules 1,2,4,3 + A/E of 4 and 3), packs on the column x=52.5, lab statuses. Run: lib/act.sh exec_lua SEAT path=lib/blue-rate.lua
local s=game.surfaces[1]
local o={'tick '..game.tick}
for _,p in ipairs({{38.5,8.5},{38.5,28.5},{74.5,36.5},{70.5,36.5},{78.5,36.5},{94.5,36.5},{90.5,36.5},{98.5,36.5}}) do local e=s.find_entities_filtered{name='assembling-machine-2',position=p,radius=0.5}[1] o[#o+1]=p[1]..','..p[2]..'='..(e and e.products_finished or -1) end
local packs=0 for _,b in ipairs(s.find_entities_filtered{name='transport-belt',area={{52,4},{53,34}}}) do for l=1,2 do packs=packs+b.get_transport_line(l).get_item_count('chemical-science-pack') end end
o[#o+1]='colpacks='..packs
local ls={} for _,l in ipairs(s.find_entities_filtered{type='lab',force='player'}) do local st=l.status for k,v in pairs(defines.entity_status) do if v==st then ls[k]=(ls[k] or 0)+1 end end end
for k,v in pairs(ls) do o[#o+1]=k..'='..v end
rcon.print(table.concat(o,' '))
