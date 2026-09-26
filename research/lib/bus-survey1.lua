local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end

local function resource_stats(name, x1,y1,x2,y2)
  local ents = surf.find_entities_filtered{name=name, area={{x1,y1},{x2,y2}}}
  local total, minv, maxv = 0, 1e18, 0
  local minx,maxx,miny,maxy = 1e18,-1e18,1e18,-1e18
  for _,e in pairs(ents) do
    total = total + e.amount
    if e.amount < minv then minv = e.amount end
    if e.amount > maxv then maxv = e.amount end
    if e.position.x < minx then minx = e.position.x end
    if e.position.x > maxx then maxx = e.position.x end
    if e.position.y < miny then miny = e.position.y end
    if e.position.y > maxy then maxy = e.position.y end
  end
  p(string.format('%s box(%d,%d)-(%d,%d): tiles=%d total=%d min=%d max=%d bbox=(%.0f,%.0f)-(%.0f,%.0f)',
    name, x1,y1,x2,y2, #ents, total, (#ents>0 and minv or 0), maxv, minx,miny,maxx,maxy))
end

p('=== RESOURCES ===')
resource_stats('iron-ore', -40,-80, -8,-25)
resource_stats('iron-ore', -40,-30, -8,10)
resource_stats('iron-ore', -20,-10, -8,15)
resource_stats('copper-ore', 0,45, 35,78)
resource_stats('coal', 55,-80, 95,-20)
resource_stats('coal', 190,-80, 220,-55)
resource_stats('stone', 45,-42, 72,-18)

p('=== WATER (tiles) ===')
local function water_area(x1,y1,x2,y2,label)
  local tiles = surf.find_tiles_filtered{area={{x1,y1},{x2,y2}}, name={'water','deepwater','water-green','deepwater-green','water-mud','water-shallow'}}
  if #tiles > 0 then
    local minx,maxx,miny,maxy = 1e18,-1e18,1e18,-1e18
    for _,t in pairs(tiles) do
      if t.position.x < minx then minx=t.position.x end
      if t.position.x > maxx then maxx=t.position.x end
      if t.position.y < miny then miny=t.position.y end
      if t.position.y > maxy then maxy=t.position.y end
    end
    p(label..': '..#tiles..' tiles bbox=('..minx..','..miny..')-('..maxx..','..maxy..')')
  else
    p(label..': none')
  end
end
water_area(-70,-30,-30,10,'near power block')
water_area(-20,-90,60,-10,'east of iron col / near coal-1')
water_area(150,-100,250,-30,'near coal-2')
water_area(-10,20,60,90,'near copper field')
water_area(-150,-150,150,150,'wide 300-box scan (any missed)')

p('=== EXISTING PUMPS/BOILERS/ENGINES ===')
for _, tname in pairs({'offshore-pump','boiler','steam-engine'}) do
  for _, e in pairs(surf.find_entities_filtered{name=tname}) do
    p(tname..' @ ('..e.position.x..','..e.position.y..') dir='..e.direction)
  end
end

p('=== CLIFFS near candidate bus corridor (-60,-25)-(30,10) ===')
local cliffs = surf.find_entities_filtered{type='cliff', area={{-60,-25},{30,10}}}
for _, c in pairs(cliffs) do
  p('cliff @ ('..string.format('%.1f',c.position.x)..','..string.format('%.1f',c.position.y)..') orientation='..tostring(c.cliff_orientation))
end
p('cliff count in corridor box = '..#cliffs)

p('=== WRECK FIELD (-30,-5)-(-5,5) ===')
local wrecks = surf.find_entities_filtered{area={{-30,-5},{-5,5}}}
local wcounts = {}
for _, e in pairs(wrecks) do
  wcounts[e.name] = (wcounts[e.name] or 0) + 1
end
local wl = {}
for k,v in pairs(wcounts) do wl[#wl+1] = k..'='..v end
table.sort(wl)
p(table.concat(wl, ' '))

rcon.print(table.concat(out, '\n'))
