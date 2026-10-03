-- coverage.lua: for each local patch, ore tiles vs tiles inside some drill's mining area, and drill output blocking.
local s=game.surfaces[1]
local st={} for k,v in pairs(defines.entity_status) do st[v]=k end
local P={{"iron home","iron-ore",{{-70,-100},{10,-10}}},{"iron NW","iron-ore",{{-180,-190},{-95,-100}}},{"copper","copper-ore",{{-20,30},{60,100}}},{"coal","coal",{{40,-70},{110,-10}}},{"stone","stone",{{45,-45},{75,-15}}}}
local out={}
for _,p in ipairs(P) do
  local cov={}
  local drills={n=0}
  for _,d in pairs(s.find_entities_filtered{type="mining-drill",force="player",area={{p[3][1][1]-3,p[3][1][2]-3},{p[3][2][1]+3,p[3][2][2]+3}}}) do
    local r=d.prototype.mining_drill_radius
    for x=math.floor(d.position.x-r),math.ceil(d.position.x+r)-1 do for y=math.floor(d.position.y-r),math.ceil(d.position.y+r)-1 do cov[x..","..y]=true end end
    drills.n=drills.n+1 local k=d.name..":"..(st[d.status] or "?") drills[k]=(drills[k] or 0)+1
  end
  local tiles,covered,amt,camt=0,0,0,0
  for _,o in pairs(s.find_entities_filtered{type="resource",name=p[2],area=p[3]}) do
    tiles=tiles+1 amt=amt+o.amount
    if cov[math.floor(o.position.x)..","..math.floor(o.position.y)] then covered=covered+1 camt=camt+o.amount end
  end
  local dl={} for k,v in pairs(drills) do if k~="n" then dl[#dl+1]=k.."="..v end end
  out[#out+1]=string.format("%-10s ore tiles %4d covered %4d (%d%%) ore %.2fM (covered %.2fM) | drills %d: %s",p[1],tiles,covered,tiles>0 and math.floor(100*covered/tiles) or 0,amt/1e6,camt/1e6,drills.n,table.concat(dl," "))
end
local t=game.forces.player.technologies
local m={} for _,n in pairs({"military","military-2","military-3","military-4","military-science-pack","stronger-explosives-1","physical-projectile-damage-1","physical-projectile-damage-2","physical-projectile-damage-3","weapon-shooting-speed-1","weapon-shooting-speed-2","weapon-shooting-speed-3","explosives","land-mines","flamethrower","heavy-armor","modular-armor"}) do m[#m+1]=n.."="..(t[n] and (t[n].researched and "Y" or "n") or "?") end
out[#out+1]=table.concat(m," ")
local r=game.forces.player.recipes
out[#out+1]="recipes enabled: grenade="..tostring(r["grenade"].enabled).." poison-capsule="..tostring(r["poison-capsule"].enabled).." military-science-pack="..tostring(r["military-science-pack"].enabled)
rcon.print(table.concat(out,"\n"))
