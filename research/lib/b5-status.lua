-- B5 (home column bank) status: furnace states, products_finished sum, key belt lanes. Run via act.sh exec_lua SEAT path=...
local s=game.surfaces[1]
local st={} for k,v in pairs(defines.entity_status) do st[v]=k end
local SRC=defines.inventory.crafter_input or defines.inventory.furnace_source
local o={'tick '..game.tick} local tot=0
for c=-36,-50,-2 do local f=s.find_entities_filtered{position={c,-44},radius=0.5,type='furnace'}[1]
 if f then tot=tot+f.products_finished o[#o+1]=c..' '..st[f.status]..' pf='..f.products_finished..' fuel='..f.get_fuel_inventory().get_item_count()..' src='..f.get_inventory(SRC).get_item_count()..' out='..f.get_output_inventory().get_item_count()
 else o[#o+1]=c..' NO FURNACE' end end
o[#o+1]='B5 pf sum '..tot
for _,p in pairs{{-33.5,-35.5},{-37.5,-41.5},{-50.5,-41.5},{-34.5,-44.5},{-22.5,-50.5},{-32.5,-46.5},{-19.5,-40.5}} do
 local b=s.find_entities_filtered{position=p,radius=0.3,type={'transport-belt','underground-belt'}}[1]
 if b then o[#o+1]=p[1]..','..p[2]..' '..b.get_transport_line(1).get_item_count()..'/'..b.get_transport_line(2).get_item_count() end end
rcon.print(table.concat(o,'\n'))
