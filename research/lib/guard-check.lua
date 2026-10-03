-- guard-check.lua: outer-field turrets (copper, coal patch, stone drill, oil) vs the expected list: missing, low ammo, damaged; plus enemies near each field.
local s=game.surfaces[1]
local exp={
 copper={{11,49},{16,49},{21,49},{9,57},{9,62},{9,67},{21,71},{23,71},{25,71},{27,71}},
 coal={{66,-50},{66,-54},{70,-55},{72,-55},{74,-50},{75,-55},{76,-43},{77,-55},{80,-55},{83,-48}},
 stone={{57,-30},{63,-30}},
 oil={{-60,174},{-52,177},{-57,182}},
 pump={{-62,34},{-59,34},{-56,34},{-62,37},{-59,37},{-56,37}},
}
local centre={copper={15,60},coal={72,-45},stone={60,-30},oil={-56,177},pump={-60,35}}
local out={'tick '..game.tick}
for field,list in pairs(exp) do
  local miss,low,dmg={},{},{}
  for _,p in ipairs(list) do
    local e=s.find_entities_filtered{name='gun-turret',force='player',position=p,radius=0.6}[1]
    if not e then miss[#miss+1]=string.format('(%d,%d)',p[1],p[2])
    else
      local n=e.get_inventory(defines.inventory.turret_ammo).get_item_count()
      if n<30 then low[#low+1]=string.format('(%d,%d)=%d',p[1],p[2],n) end
      if e.health<e.max_health then dmg[#dmg+1]=string.format('(%d,%d) %.0f',p[1],p[2],e.health) end
    end
  end
  local c=centre[field]
  local en=#s.find_entities_filtered{force='enemy',type={'unit','unit-spawner'},position=c,radius=60}
  out[#out+1]=string.format('%s: missing[%s] low[%s] damaged[%s] enemies60=%d',field,table.concat(miss,' '),table.concat(low,' '),table.concat(dmg,' '),en)
end
local hurt={}
for _,e in ipairs(s.find_entities_filtered{force='player',area={{-2,44},{36,76}}}) do
  if e.type~='character' and e.health and e.health<e.max_health then hurt[#hurt+1]=string.format('%s(%g,%g) %.0f',e.name,e.position.x,e.position.y,e.health) end
end
local drills=#s.find_entities_filtered{name='electric-mining-drill',area={{12,54},{25,67}}}
out[#out+1]='copper field: drills '..drills..'/8 damaged: '..table.concat(hurt,' ')
rcon.print(table.concat(out,'\n'))
