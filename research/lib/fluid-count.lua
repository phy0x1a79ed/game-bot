-- fluid-count.lua: approximate size of the fluid system around a seed entity (geometric flood: touching fluid entities
-- holding the same fluid, PTG to its partner up to 10 tiles along its axis; pumps are counted but not crossed).
-- Substitute SX SY FLUID. The engine's own fluid segment API is not exposed to exec_lua.
local s=game.surfaces[1] local FL='FLUID'
local T={'pipe','pipe-to-ground','storage-tank','pump','pumpjack','oil-refinery','flamethrower-turret','chemical-plant','fluid-wagon','offshore-pump','boiler','generator'}
local function holds(e) if e.type=='pumpjack' or e.type=='flamethrower-turret' then return true end local c=e.get_fluid_contents() return c[FL]~=nil end
local seed=s.find_entities_filtered{position={SX,SY},radius=0.6,type=T}[1]
local seen,q,cnt={},{seed},{} seen[seed.unit_number]=true local total=0
local dv={[0]={0,-1},[4]={1,0},[8]={0,1},[12]={-1,0}}
while #q>0 do local e=table.remove(q) total=total+1 cnt[e.type]=(cnt[e.type] or 0)+1
  if e.type~='pump' or e==seed then
    local b=e.bounding_box local a={{b.left_top.x-0.6,b.left_top.y-0.6},{b.right_bottom.x+0.6,b.right_bottom.y+0.6}}
    local nb=s.find_entities_filtered{area=a,type=T}
    if e.type=='pipe-to-ground' then local v=dv[e.direction] for k=1,11 do for _,f in pairs(s.find_entities_filtered{position={e.position.x-v[1]*k,e.position.y-v[2]*k},radius=0.3,type='pipe-to-ground'}) do nb[#nb+1]=f end for _,f in pairs(s.find_entities_filtered{position={e.position.x+v[1]*k,e.position.y+v[2]*k},radius=0.3,type='pipe-to-ground'}) do nb[#nb+1]=f end end end
    for _,f in pairs(nb) do local bx=f.bounding_box local ox=math.min(b.right_bottom.x,bx.right_bottom.x)-math.max(b.left_top.x,bx.left_top.x) local oy=math.min(b.right_bottom.y,bx.right_bottom.y)-math.max(b.left_top.y,bx.left_top.y)
      local side=(ox>0.1 and oy>-0.6) or (oy>0.1 and ox>-0.6) or f.type=='pipe-to-ground'
      if side and f.unit_number and not seen[f.unit_number] and holds(f) then seen[f.unit_number]=true q[#q+1]=f end end
  end end
local o={} for k,v in pairs(cnt) do o[#o+1]=k..'='..v end
rcon.print('system '..total..': '..table.concat(o,' '))
