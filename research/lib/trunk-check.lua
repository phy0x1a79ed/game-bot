-- trunk-check.lua: north line phase-2 trunk (OUT2 (54.5,-30.5) -> x=55.5 N -> y=-72.5 W -> chest (-31.5,-70.5)): items on the trunk, west-most item, chest + OUT2 counts.
local s=game.surfaces[1] local n,west,tiles=0,999,0
local function scan(a) for _,e in pairs(s.find_entities_filtered{area=a,type={'transport-belt','underground-belt'}}) do tiles=tiles+1 local c=0 for l=1,e.get_max_transport_line_index() do c=c+e.get_transport_line(l).get_item_count('piercing-rounds-magazine') end n=n+c if c>0 and e.position.y<-72 and e.position.y>-73 and e.position.x<west then west=e.position.x end end end
scan({{54,-29},{56,-28}}) scan({{55,-72},{56,-29}}) scan({{-32,-73},{56,-72}})
local function cnt(x,y) local c=s.find_entity('iron-chest',{x,y}) return c and c.get_item_count('piercing-rounds-magazine') or -1 end
local i1=s.find_entity('inserter',{54.5,-29.5}) local i2=s.find_entity('inserter',{-31.5,-71.5})
rcon.print(string.format('tick %d trunk tiles %d items %d westmost %s | OUT2 %d chest %d | src %s dst %s',game.tick,tiles,n,west,cnt(54.5,-30.5),cnt(-31.5,-70.5),i1 and i1.status or '-',i2 and i2.status or '-'))
