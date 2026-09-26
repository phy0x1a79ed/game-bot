local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end

p('=== IDLE ASSEMBLERS @ y=0.5 -- full surroundings (-50,-3)-(-26,4) ===')
for _, e in pairs(surf.find_entities_filtered{area={{-50,-3},{-26,4}}}) do
  if e.type ~= 'character' then
    local extra = ''
    if e.type == 'assembling-machine' then
      extra = ' recipe='..(e.get_recipe() and e.get_recipe().name or 'none')..' powered='..tostring(e.energy > 0 or e.status ~= defines.entity_status.no_power)
    end
    if e.type == 'electric-pole' then extra = ' net='..tostring(e.electric_network_id) end
    p(e.name..' @ ('..string.format('%.1f',e.position.x)..','..string.format('%.1f',e.position.y)..')'..extra)
  end
end

p('=== SOUTH OF WAIST: mall/green-science candidate area (-20,0)-(20,20) ===')
local cnt=0
for _, e in pairs(surf.find_entities_filtered{area={{-20,0},{20,20}}}) do
  if e.type ~= 'character' and e.type ~= 'resource' then
    cnt = cnt + 1
    p(e.name..' @ ('..string.format('%.1f',e.position.x)..','..string.format('%.1f',e.position.y)..')')
  end
end
p('total obstacles in mall candidate box = '..cnt)

p('=== COAL SPUR CROSSING ZONE (y=-30 to -24, x=-25 to -10) ===')
local c2 = 0
for _, e in pairs(surf.find_entities_filtered{area={{-25,-30},{-10,-24}}}) do
  if e.type ~= 'character' and e.type ~= 'resource' then c2 = c2 + 1; p(e.name..' @ ('..string.format('%.1f',e.position.x)..','..string.format('%.1f',e.position.y)..')') end
end
p('obstacles in coal-spur crossing zone = '..c2)

p('=== ELECTRIC NETWORK CHECK: pole @ (-27.5,-13.5) and (-30.5,-13.5) network ids ===')
for _, e in pairs(surf.find_entities_filtered{name='small-electric-pole', area={{-32,-15},{-25,-12}}}) do
  p(string.format('pole @ (%.1f,%.1f) net=%s', e.position.x, e.position.y, tostring(e.electric_network_id)))
end

rcon.print(table.concat(out, '\n'))
