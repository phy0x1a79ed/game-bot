-- brick-rate.lua: industry brick line status. Run: lib/act.sh exec_lua SEAT path=$PWD/lib/brick-rate.lua (absolute path)
local s=game.surfaces[1]
local function st(e) for k,v in pairs(defines.entity_status) do if v==e.status then return k end end return tostring(e.status) end
local o={'tick '..game.tick}
for _,p in ipairs({{55.5,-34.5},{58.5,-34.5},{61.5,-34.5},{59.5,-30.5},{64.5,-39.5}}) do local e=s.find_entities_filtered{name='electric-mining-drill',position=p,radius=0.3}[1] o[#o+1]='drill'..p[1]..','..p[2]..'='..(e and st(e) or 'MISSING') end
local done=0
for _,x in ipairs({45,47,49,51}) do local e=s.find_entities_filtered{name='steel-furnace',position={x,-43},radius=0.3}[1]
 if e then local f=e.get_fuel_inventory().get_item_count('coal') local i=e.get_item_count('stone') done=done+e.products_finished o[#o+1]='F'..x..'='..st(e)..' fuel'..f..' stone'..i..' made'..e.products_finished else o[#o+1]='F'..x..' MISSING' end end
local c=s.find_entities_filtered{name='iron-chest',position={43.5,-43.5},radius=0.3}[1]
o[#o+1]='brickchest='..(c and c.get_item_count('stone-brick') or -1)..' furnace_made_total='..done
local k=s.find_entities_filtered{name='iron-chest',position={42.5,-45.5},radius=0.3}[1] o[#o+1]='coalsink='..(k and k.get_item_count('coal') or -1)
local function belt(a,b) local t={} for _,e in ipairs(s.find_entities_filtered{type={'transport-belt','underground-belt'},area={a,b}}) do for l=1,2 do for _,it in ipairs(e.get_transport_line(l).get_contents()) do t[it.name]=(t[it.name] or 0)+it.count end end end local q={} for n,v in pairs(t) do q[#q+1]=n..'='..v end return table.concat(q,',') end
o[#o+1]='S['..belt({53,-33},{62,-32})..'|'..belt({52,-46},{53,-33})..'|'..belt({44,-46},{52,-45})..'] C['..belt({44,-40},{52,-39})..'+'..belt({53,-40},{63,-39})..'] O['..belt({43,-42},{52,-40})..']'
rcon.print(table.concat(o,' '))
