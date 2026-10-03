-- patches.lua: ore totals per 96-tile cell within R tiles of the origin, largest first per resource.
local s=game.surfaces[1] local R=450 local C=96
local cells={}
for _,o in pairs(s.find_entities_filtered{type="resource",area={{-R,-R},{R,R}}}) do
  local k=o.name.."@"..math.floor(o.position.x/C)..","..math.floor(o.position.y/C)
  local c=cells[k] if not c then c={n=o.name,a=0,sx=0,sy=0,t=0} cells[k]=c end
  c.a=c.a+o.amount c.t=c.t+1 c.sx=c.sx+o.position.x c.sy=c.sy+o.position.y
end
local l={} for k,c in pairs(cells) do if c.a>100000 or c.n=="crude-oil" then l[#l+1]=c end end
table.sort(l,function(a,b) if a.n~=b.n then return a.n<b.n end return a.a>b.a end)
local out={}
for _,c in ipairs(l) do
  local x,y=c.sx/c.t,c.sy/c.t
  local nests=s.count_entities_filtered{force="enemy",type="unit-spawner",position={x,y},radius=80}
  local mine=s.count_entities_filtered{force="player",type="mining-drill",position={x,y},radius=60}
  out[#out+1]=string.format("%-11s %6.2fM tiles %4d centre (%4d,%4d) dist %3d nests80 %d drills60 %d",c.n,c.a/1e6,c.t,x,y,math.sqrt(x*x+y*y),nests,mine)
end
rcon.print(table.concat(out,"\n"))
