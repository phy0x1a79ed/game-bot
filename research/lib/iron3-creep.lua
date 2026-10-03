-- iron3-creep.lua: robot creep test readout around roboport (-6,-63): turrets/ghosts/proxies near the test spots, storage, robots
local s=game.surfaces[1] rcon.print('tick '..game.tick)
for _,t in pairs(s.find_entities_filtered{area={{-4,-70},{5,-64}},name={'gun-turret','entity-ghost','item-request-proxy'}}) do
 local x=t.name..' '..t.position.x..','..t.position.y
 if t.name=='gun-turret' then x=x..' ammo '..t.get_inventory(defines.inventory.turret_ammo).get_item_count('piercing-rounds-magazine')..' proxy '..tostring(t.item_request_proxy~=nil)..' decon '..tostring(t.to_be_deconstructed()) end
 rcon.print(x) end
local n=s.find_entity('roboport',{-6,-63}).logistic_network
rcon.print('robots all '..n.all_construction_robots..' avail '..n.available_construction_robots..' storage '..serpent.line(n.get_contents()))
