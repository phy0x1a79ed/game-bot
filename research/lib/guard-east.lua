-- guard-east.lua: north/east zones — every gun turret (ammo kind+count, hp), turret remnants, enemies near each zone.
local s=game.surfaces[1]
local BRIEF=(BRIEF_FLAG or false) -- set true to list only turrets under 15 ammo or damaged
local Z={
 coal={60,-62,90,-40}, nwall={-36,-76,0,-58}, steel={0,-56,45,-35}, blk5={76,-30,95,-4},
 oil={25,25,56,50}, eblue={60,20,110,52}, nwpatch={-155,-160,-125,-130}, pipe={-75,-115,-10,-76},
}
local out={'tick '..game.tick..' evo '..string.format('%.3f',game.forces.enemy.get_evolution_factor(1))}
for name,b in pairs(Z) do
  local area={{b[1],b[2]},{b[3],b[4]}}
  local t={} local cnt=0
  for _,e in ipairs(s.find_entities_filtered{name='gun-turret',force='player',area=area}) do
    local inv=e.get_inventory(defines.inventory.turret_ammo)
    local k,n='-',0
    for _,it in pairs(inv.get_contents()) do k=it.name:sub(1,1) n=n+it.count end
    local flag=''
    if n<15 then flag='!' end
    if e.health<e.max_health then flag=flag..string.format('h%d',e.health) end
    if not BRIEF or flag~='' then t[#t+1]=string.format('(%g,%g)%s%d%s',e.position.x,e.position.y,k,n,flag) end
    cnt=cnt+1
  end
  local rem={}
  for _,c in ipairs(s.find_entities_filtered{name='gun-turret-remnants',area=area}) do rem[#rem+1]=string.format('(%g,%g)',c.position.x,c.position.y) end
  local big={{b[1]-30,b[2]-30},{b[3]+30,b[4]+30}}
  local en=s.find_entities_filtered{force='enemy',type='unit',area=big}
  local sp=#s.find_entities_filtered{force='enemy',type={'unit-spawner','turret'},area=big}
  out[#out+1]=string.format('%s[%d]: %s | rem %s | enemies30 %d spawn %d',name,cnt,table.concat(t,' '),table.concat(rem,' '),#en,sp)
end
rcon.print(table.concat(out,'\n'))
