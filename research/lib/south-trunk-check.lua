-- south-trunk-check.lua: yellow-block south trunk. Source inserter (18.5,-11.5) off AM W -> leg A (x=18.5, y=1.5, x=30.5)
-- -> copper S row belt y=73.5 (4 turret inserters) -> leg B y=73.5 W, x=-46.5 S -> oil field S row y=183.5 (6 inserters).
-- Prints magazines per section and turret ammo of both fed groups.
local s=game.surfaces[1] local m={} for k,v in pairs(defines.entity_status) do m[v]=k end
local function cnt(a) local y,p=0,0 for _,e in pairs(s.find_entities_filtered{area=a,type={'transport-belt','underground-belt'}}) do for l=1,e.get_max_transport_line_index() do local t=e.get_transport_line(l) y=y+t.get_item_count('firearm-magazine') p=p+t.get_item_count('piercing-rounds-magazine') end end return 'y'..y..'/p'..p end
local function tur(a) local o={} for _,e in pairs(s.find_entities_filtered{area=a,name='gun-turret'}) do local i=e.get_inventory(defines.inventory.turret_ammo) o[#o+1]=string.format('(%g,%g)%s%d',e.position.x,e.position.y,i.get_item_count('firearm-magazine')>0 and 'y' or 'p',i.get_item_count()) end return table.concat(o,' ') end
local i=s.find_entity('inserter',{18.5,-11.5})
rcon.print(table.concat({'tick '..game.tick..' src '..tostring(i and m[i.status]),
 'legA x18.5 '..cnt({{18,-11},{19,2}})..' y1.5 '..cnt({{19,1},{31,2}})..' x30.5 '..cnt({{30,2},{31,73}}),
 'copperrow '..cnt({{21,73},{31,74}})..' | '..tur({{19,69},{30,72}}),
 'legB y73.5 '..cnt({{-47,73},{21,74}})..' x-46.5 '..cnt({{-47,74},{-46,183}}),
 'oilrow '..cnt({{-62,183},{-46,184}})..' | '..tur({{-63,185},{-44,188}})},'\n'))
