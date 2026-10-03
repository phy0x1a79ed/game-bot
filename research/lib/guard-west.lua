-- guard-west.lua: west zones — every gun turret (ammo kind+count, hp), turret remnants, damaged walls/pipes, enemies near each zone; plus the seat's position and ammo.
local s=game.surfaces[1]
local BRIEF=(BRIEF_FLAG or false) -- true lists only turrets under 15 ammo or damaged
local Z={
 blk4={-80,-36,-55,-15}, pumpw={-70,28,-48,46}, sw={-50,4,-28,22}, oil={-72,165,-40,192},
 copper={-2,44,36,76}, nwflank={-50,-68,-36,-48},
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
  for _,c in ipairs(s.find_entities_filtered{type='corpse',area=area}) do if c.name:find('remnants') and not c.name:find('wall') then rem[#rem+1]=string.format('%s(%g,%g)',c.name:gsub('%-remnants',''),c.position.x,c.position.y) end end
  local hurt={}
  for _,e in ipairs(s.find_entities_filtered{force='player',area=area}) do
    if e.type~='character' and e.type~='ammo-turret' and e.health and e.health<e.max_health then hurt[#hurt+1]=string.format('%s(%g,%g)%d',e.name,e.position.x,e.position.y,e.health) end
  end
  local big={{b[1]-30,b[2]-30},{b[3]+30,b[4]+30}}
  local en=s.find_entities_filtered{force='enemy',type='unit',area=big}
  local sp=#s.find_entities_filtered{force='enemy',type={'unit-spawner','turret'},area=big}
  out[#out+1]=string.format('%s[%d]: %s | rem %s | hurt %s | enemies30 %d spawn %d',name,cnt,table.concat(t,' '),table.concat(rem,' '),table.concat(hurt,' '),#en,sp)
end
if player and player.valid then
  local inv=player.get_main_inventory()
  local function c(n) return inv.get_item_count(n) end
  out[#out+1]=string.format('seat (%.1f,%.1f) pierce %d yellow %d steel %d copper %d iron %d stone %d brick %d wall %d turret %d repair %d coal %d',player.position.x,player.position.y,c('piercing-rounds-magazine'),c('firearm-magazine'),c('steel-plate'),c('copper-plate'),c('iron-plate'),c('stone'),c('stone-brick'),c('stone-wall'),c('gun-turret'),c('repair-pack'),c('coal'))
end
rcon.print(table.concat(out,'\n'))
