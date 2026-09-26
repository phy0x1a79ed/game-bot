local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end

p('=== WRECK ENTITIES (exact) ===')
for _, e in pairs(surf.find_entities_filtered{area={{-35,-8},{-5,8}}}) do
  if e.name:find('crash') or e.name == 'assembling-machine-1' then
    p(e.name..' @ ('..string.format('%.1f',e.position.x)..','..string.format('%.1f',e.position.y)..')')
  end
end

p('=== EXISTING BELTS (transport-belt), grouped by rounded x or y line ===')
local belts = surf.find_entities_filtered{name='transport-belt'}
local minx,maxx,miny,maxy = 1e18,-1e18,1e18,-1e18
for _,e in pairs(belts) do
  if e.position.x<minx then minx=e.position.x end
  if e.position.x>maxx then maxx=e.position.x end
  if e.position.y<miny then miny=e.position.y end
  if e.position.y>maxy then maxy=e.position.y end
end
p('belt count='..#belts..' bbox=('..minx..','..miny..')-('..maxx..','..maxy..')')

p('=== POWER BLOCK / SCIENCE LINE AREA (-56,-20)-(-16,0) entities ===')
local zone = surf.find_entities_filtered{area={{-56,-20},{-16,0}}}
local zc = {}
for _, e in pairs(zone) do
  if e.type ~= 'character' then
    local k = e.name
    zc[k] = (zc[k] or 0)+1
  end
end
local zl = {}
for k,v in pairs(zc) do zl[#zl+1]=k..'='..v end
table.sort(zl)
p(table.concat(zl,' '))

p('--- key entity positions in that zone ---')
for _, tname in pairs({'lab','assembling-machine-1','gun-turret','small-electric-pole','iron-chest','pump','boiler','steam-engine'}) do
  for _, e in pairs(surf.find_entities_filtered{name=tname, area={{-56,-20},{-16,0}}}) do
    local extra = ''
    if e.type == 'assembling-machine' then extra = ' recipe='..(e.get_recipe() and e.get_recipe().name or 'none') end
    p(tname..' @ ('..e.position.x..','..e.position.y..')'..extra)
  end
end

p('=== ALL GUN TURRETS (whole base) ===')
for _, e in pairs(surf.find_entities_filtered{name='gun-turret'}) do
  p('turret @ ('..e.position.x..','..e.position.y..') ammo='..e.get_inventory(defines.inventory.turret_ammo).get_item_count())
end

p('=== DEPOT / MALL AREA (-5,-25)-(10,-15) ===')
for _, e in pairs(surf.find_entities_filtered{area={{-5,-25},{10,-15}}}) do
  if e.type ~= 'character' then
    p(e.name..' @ ('..string.format('%.1f',e.position.x)..','..string.format('%.1f',e.position.y)..')')
  end
end

p('=== NESTS (unit-spawner) within 400 of (0,-20), with bearing ===')
for _, s in pairs(surf.find_entities_filtered{type='unit-spawner', position={0,-20}, radius=400}) do
  local dx,dy = s.position.x-0, s.position.y-(-20)
  local dist = (dx*dx+dy*dy)^0.5
  local bearing = math.deg(math.atan(dx,-dy)) -- 0=N,90=E
  if bearing < 0 then bearing = bearing + 360 end
  p(string.format('spawner @ (%.0f,%.0f) dist=%.0f bearing=%.0f', s.position.x, s.position.y, dist, bearing))
end

p('=== WORMS within 400 of (0,-20) ===')
local wc = 0
for _, s in pairs(surf.find_entities_filtered{type='turret', force='enemy', position={0,-20}, radius=400}) do
  wc = wc + 1
end
p('worm count = '..wc)

rcon.print(table.concat(out, '\n'))
