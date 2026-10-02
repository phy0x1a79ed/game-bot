-- spawner-absorb.lua: spawners whose chunk holds pollution (those that absorb), map settings for groups, evolution and expansion.
local s=game.surfaces[1]
local sp=s.find_entities_filtered{type='unit-spawner'}
local out={'tick='..game.tick..' spawners='..#sp}
local rows={}
for _,e in ipairs(sp) do
  local p=e.position
  local pol=s.get_pollution(p)
  rows[#rows+1]={x=p.x,y=p.y,pol=pol,n=e.name}
end
table.sort(rows,function(a,b) return a.pol>b.pol end)
for i,r in ipairs(rows) do
  if r.pol>0.01 or i<=5 then out[#out+1]=string.format('%s (%.0f,%.0f) pol=%.2f dist=%.0f',r.n,r.x,r.y,r.pol,math.sqrt((r.x+20)^2+(r.y+45)^2)) end
end
local ms=game.map_settings
out[#out+1]='unit_group: min_gather='..ms.unit_group.min_group_gathering_time..' max_gather='..ms.unit_group.max_group_gathering_time..' max_late='..ms.unit_group.max_wait_time_for_late_members..' min_size='..ms.unit_group.min_group_radius..'..'..ms.unit_group.max_group_radius
local ac=ms.enemy_evolution
out[#out+1]='evo time='..ac.time_factor..' destroy='..ac.destroy_factor..' pollution='..ac.pollution_factor
local ex=ms.enemy_expansion
out[#out+1]=string.format('expansion enabled=%s max_dist=%d min_cd=%d max_cd=%d',tostring(ex.enabled),ex.max_expansion_distance,ex.min_expansion_cooldown,ex.max_expansion_cooldown)
out[#out+1]='max_unit_group_size='..ms.unit_group.max_unit_group_size
out[#out+1]='pollution diffusion_ratio='..ms.pollution.diffusion_ratio..' min_to_diffuse='..ms.pollution.min_to_diffuse..' ageing='..ms.pollution.ageing..' enemy_attack_pollution_consumption_modifier='..ms.pollution.enemy_attack_pollution_consumption_modifier
rcon.print(table.concat(out,'\n'))
