-- chunk-pollution.lua: the most polluted chunks near the base with their polluter and turret counts (attack targets are chosen by chunk pollution).
local s=game.surfaces[1]
local rows={}
local tur=s.find_entities_filtered{type='ammo-turret',force='player'}
for cx=-6,6 do for cy=-6,4 do
  local x,y=cx*32+16,cy*32+16
  local p=s.get_pollution({x,y})
  if p>1 then
    local ents=s.count_entities_filtered{area={{cx*32,cy*32},{cx*32+32,cy*32+32}},force='player',type={'mining-drill','furnace','boiler','assembling-machine'}}
    local nt=0 for _,t in ipairs(tur) do if math.abs(t.position.x-x)<=34 and math.abs(t.position.y-y)<=34 then nt=nt+1 end end
    rows[#rows+1]={x=x,y=y,p=p,e=ents,t=nt}
  end
end end
table.sort(rows,function(a,b) return a.p>b.p end)
local out={'tick='..game.tick..' chunk centres with pollution>1 (cx,cy: pollution, polluter entities, turrets within 34 of centre)'}
for i,r in ipairs(rows) do if i<=16 then out[#out+1]=string.format('(%d,%d) pol=%.0f polluters=%d turrets34=%d',r.x,r.y,r.p,r.e,r.t) end end
rcon.print(table.concat(out,'\n'))
