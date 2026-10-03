-- Copper redesign per-machine snapshot: products_finished + status for the 16 drills and 14 bank furnaces, tick, 1-min copper-plate made/used. Diff two runs for utilisation.
local s=game.surfaces[1] local st={} for k,v in pairs(defines.entity_status) do st[v]=k end
local o={'tick '..game.tick}
local function pf(e) local ok,v=pcall(function() return e.products_finished end) return ok and v or -1 end
for _,x in pairs{13.5,17.5,21.5,25.5} do local l='D'..x..':' for _,y in pairs{55.5,58.5,61.5,64.5} do local d=s.find_entity('electric-mining-drill',{x,y}) l=l..' '..(d and (pf(d)..'/'..(st[d.status] or '?'):sub(1,10)..'/d'..d.direction) or 'NONE') end o[#o+1]=l end
for _,x in pairs{37,42} do local l='F'..x..':' for yc=55,67,2 do local f=s.find_entity('steel-furnace',{x,yc}) l=l..' '..(f and (pf(f)..'/'..(st[f.status] or '?'):sub(1,10)) or 'NONE') end o[#o+1]=l end
local ps=game.forces.player.get_item_production_statistics(s)
local function fl(n,c) return math.floor(ps.get_flow_count{name=n,category=c,precision_index=defines.flow_precision_index.one_minute,count=true}) end
o[#o+1]='copper-plate made1m '..fl('copper-plate','input')..' used1m '..fl('copper-plate','output')..' | ore made1m '..fl('copper-ore','input')
rcon.print(table.concat(o,'\n'))
