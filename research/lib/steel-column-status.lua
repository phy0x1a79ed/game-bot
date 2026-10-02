-- Status of the 13 electric-drill column furnaces and their drills, plus products_finished totals.
local s=game.surfaces[1]
local st={} for k,v in pairs(defines.entity_status) do st[v]=k end
local SRC=defines.inventory.crafter_input or defines.inventory.furnace_source
local r={"tick "..game.tick}
local tot=0
local pos={}
for _,y in pairs{-63,-60,-57,-54,-51,-48} do pos[#pos+1]={-34,y} end
for _,y in pairs{-63,-60,-57,-54,-51,-48,-45} do pos[#pos+1]={-22,y} end
for _,p in pairs(pos) do
  local f=s.find_entities_filtered{position=p,radius=0.5,type='furnace'}[1]
  if f then
    tot=tot+f.products_finished
    local d=s.find_entities_filtered{area={{p[1]-3,p[2]-1},{p[1]+3,p[2]+1}},type='mining-drill'}[1]
    r[#r+1]=string.format('(%d,%d) %s %s pf=%d fuel=%d src=%d out=%d | drill %s',p[1],p[2],f.name,st[f.status],f.products_finished,
      f.get_fuel_inventory().get_item_count(),f.get_inventory(SRC).get_item_count(),f.get_output_inventory().get_item_count(),
      d and (d.name..'@'..d.position.x..','..d.position.y..' '..st[d.status]) or 'none')
  else r[#r+1]='('..p[1]..','..p[2]..') NO FURNACE' end
end
r[#r+1]='sum products_finished '..tot
rcon.print(table.concat(r,'\n'))
