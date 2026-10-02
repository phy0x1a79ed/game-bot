-- slot-check.lua: can_place_entity check of the west iron column (6 drill/furnace/inserter modules, 3 poles, the output belt). Blocked=0 before building, 55 after.
local s=game.surfaces[1]
local f='player'
local bad={}
local n=0
local function cp(name,x,y,dir)
  n=n+1
  local ok=s.can_place_entity{name=name,position={x,y},direction=dir,force=f}
  if not ok then bad[#bad+1]=string.format('%s (%.1f,%.1f)',name,x,y) end
end
for _,y in ipairs{-63,-60,-57,-54,-51,-48} do
  cp('electric-mining-drill',-36.5,y-0.5,4)
  cp('stone-furnace',-34,y)
  cp('inserter',-32.5,y+0.5,12)
end
for _,y in ipairs{-61.5,-55.5,-49.5} do cp('small-electric-pole',-34.5,y) end
-- belt x=-31.5 flowing north from y=-47.5 to -65.5 then corner at -66.5
for y=-47.5,-65.5,-1 do cp('transport-belt',-31.5,y,0) end
cp('transport-belt',-31.5,-66.5,4)
for x=-30.5,-20.5,1 do cp('transport-belt',x,-66.5,4) end
for y=-66.5,-64.5,1 do cp('transport-belt',-19.5,y,8) end
-- existing head of iron A
local out={'checked='..n..' blocked='..#bad}
for _,b in ipairs(bad) do out[#out+1]='BLOCKED '..b end
local h=s.find_entities_filtered{area={{-20,-67},{-19,-62}},type='transport-belt'}
for _,b in ipairs(h) do out[#out+1]=string.format('existing belt (%.1f,%.1f) dir=%d',b.position.x,b.position.y,b.direction) end
rcon.print(table.concat(out,'\n'))
