-- greedy new-drill candidates on the home iron patch that drop onto an ore belt (x=-34.5,-27.5,-22.5,-15.5). MODE='check'|'place'
local s=game.surfaces[1]
local A={{-60,-80},{0,-36}}
local ore={} 
for _,o in pairs(s.find_entities_filtered{type="resource",name="iron-ore",area=A}) do ore[math.floor(o.position.x)..","..math.floor(o.position.y)]=o.amount end
local function cover(d) local r=2.49 return d end
for _,d in pairs(s.find_entities_filtered{type="mining-drill",force="player",area={{-64,-84},{4,-32}}}) do
  local p=d.position
  for x=math.floor(p.x-2.49),math.floor(p.x+2.49) do for y=math.floor(p.y-2.49),math.floor(p.y+2.49) do ore[x..","..y]=nil end end
end
-- ghosts count as occupied by can_place with manual_ghost? use normal check
local belts={}
for _,b in pairs(s.find_entities_filtered{type="transport-belt",area=A}) do belts[b.position.x..","..b.position.y]=b.direction end
local belt_xs={[-34.5]=true,[-27.5]=true,[-22.5]=true,[-15.5]=true}
local chosen={} local occ={}
local dirs={{4,1,0},{12,-1,0}} -- east drops at +2, west at -2 (drill center +/-2)
local tot=0
for iter=1,12 do
  local best,bs
  for cx=-48.5,-4.5 do for cy=-70.5,-38.5 do
    for _,dd in ipairs(dirs) do
      local bx=cx+dd[2]*2
      if belt_xs[bx] and belts[bx..","..cy] then
        local sc=0
        for x=math.floor(cx-2.49),math.floor(cx+2.49) do for y=math.floor(cy-2.49),math.floor(cy+2.49) do sc=sc+(ore[x..","..y] or 0) end end
        local clash=false for x=math.floor(cx-1.5),math.floor(cx+1.5) do for y=math.floor(cy-1.5),math.floor(cy+1.5) do if occ[x..","..y] then clash=true end end end
        if not clash and (not bs or sc>bs) and sc>=1500 and s.can_place_entity{name='electric-mining-drill',position={cx,cy},direction=dd[1],force='player'} then best={cx,cy,dd[1],bx} bs=sc end
      end
    end
  end end
  if not best then break end
  chosen[#chosen+1]={best[1],best[2],best[3],bs}
  tot=tot+bs
  for x=math.floor(best[1]-2.49),math.floor(best[1]+2.49) do for y=math.floor(best[2]-2.49),math.floor(best[2]+2.49) do ore[x..","..y]=nil end end
  for x=math.floor(best[1]-1.5),math.floor(best[1]+1.5) do for y=math.floor(best[2]-1.5),math.floor(best[2]+1.5) do occ[x..","..y]=true end end
  if MODE=='place' then s.create_entity{name='entity-ghost',inner_name='electric-mining-drill',position={best[1],best[2]},direction=best[3],force='player'} end
end
local o={} for _,c in ipairs(chosen) do o[#o+1]=string.format("%.1f,%.1f d%d ore%d",c[1],c[2],c[3],c[4]) end
rcon.print(MODE.." n="..#chosen.." ore="..tot.."\n"..table.concat(o,"\n"))
