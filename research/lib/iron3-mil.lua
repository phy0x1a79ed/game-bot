-- iron3-mil.lua: military/ammo block survey (x 36..58, y -50..-12): recipe, speed, ingredients, feeding inserters
local s=game.surfaces[1] local st={} for k,v in pairs(defines.entity_status) do st[v]=k end
rcon.print('tick '..game.tick)
for _,e in pairs(s.find_entities_filtered{area={{36,-50},{58,-12}},type={'assembling-machine'}}) do
  local r=e.get_recipe() if r then
    local ing={} for _,x in pairs(r.ingredients) do ing[#ing+1]=x.name..':'..x.amount end
    local pr={} for _,x in pairs(r.products) do pr[#pr+1]=x.name..':'..(x.amount or '?') end
    rcon.print(string.format('== %s (%g,%g) spd=%g e=%g [%s] -> [%s] %s fin=%d',r.name,e.position.x,e.position.y,e.crafting_speed,r.energy,table.concat(ing,' '),table.concat(pr,' '),st[e.status],e.products_finished))
    local bb=e.bounding_box
    for _,i in pairs(s.find_entities_filtered{type='inserter',area={{bb.left_top.x-3,bb.left_top.y-3},{bb.right_bottom.x+3,bb.right_bottom.y+3}}}) do
      local p,d=i.pickup_target,i.drop_target
      if p==e or d==e then rcon.print(string.format('   %s (%g,%g) %s -> %s',i.name,i.position.x,i.position.y,p and (p.name..'@'..p.position.x..','..p.position.y) or ('pos '..i.pickup_position.x..','..i.pickup_position.y),d and (d.name..'@'..d.position.x..','..d.position.y) or ('pos '..i.drop_position.x..','..i.drop_position.y))) end
    end
  end
end
