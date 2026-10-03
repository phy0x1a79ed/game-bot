-- Copper field crafts: sum products_finished of every furnace in the old field (x 14..23, y 54..67) and the new bank (x 35..44, y 53..68), plus 1-min copper-plate made/used. Run via act.sh exec_lua SEAT path=...
local s=game.surfaces[1] local st={} for k,v in pairs(defines.entity_status) do st[v]=k end
local function sum(area) local t,n,l=0,0,{} for _,f in pairs(s.find_entities_filtered{area=area,type='furnace'}) do t=t+f.products_finished n=n+1 l[#l+1]=f.position.x..','..f.position.y..'='..(st[f.status] or '?') end return t,n,table.concat(l,' ') end
local a,an,al=sum{{14,53},{23,68}} local b,bn,bl=sum{{35,53},{44,69}}
local ps=game.forces.player.get_item_production_statistics(s)
local function f(cat) return math.floor(ps.get_flow_count{name='copper-plate',category=cat,precision_index=defines.flow_precision_index.one_minute,count=true}) end
rcon.print('tick '..game.tick..' old '..an..' pf='..a..' | bank '..bn..' pf='..b..' | made1m '..f('input')..' used1m '..f('output')..'\nold: '..al..'\nbank: '..bl)
