-- downstream BFS over belts from START; lists per-run tiles, items, inserters picking from them and what they feed
local s=game.surfaces[1]
local START=START_XY
local MAXN=MAXN_V
local dv={[0]={0,-1},[4]={1,0},[8]={0,1},[12]={-1,0}}
local DN={[0]='N',[4]='E',[8]='S',[12]='W'}
local function at(x,y) return s.find_entities_filtered{area={{x-0.45,y-0.45},{x+0.45,y+0.45}},type={'transport-belt','underground-belt','splitter'}}[1] end
local q={START} local seen={} local out={} local n=0
local picks={}
while #q>0 and n<MAXN do
  local p=table.remove(q,1) local e=at(p[1],p[2])
  if e then
    local k=e.unit_number
    if not seen[k] then seen[k]=true n=n+1
      local items={}
      for i=1,math.min(2,e.get_max_transport_line_index()) do for _,c in pairs(e.get_transport_line(i).get_contents()) do local k=c.name:sub(1,4).."@"..i items[k]=(items[k] or 0)+c.count end end
      local is='' for nm,c in pairs(items) do is=is..nm:sub(1,6)..c..' ' end
      out[#out+1]=string.format('%s %.1f,%.1f %s %s',e.type:sub(1,5),e.position.x,e.position.y,DN[e.direction] or e.direction,is)
      local v=dv[e.direction]
      for _,o in pairs(e.belt_neighbours.outputs) do q[#q+1]={o.position.x,o.position.y} end
      if e.type=='underground-belt' and e.belt_to_ground_type=='input' and e.underground_belt_neighbour then local nb=e.underground_belt_neighbour q[#q+1]={nb.position.x,nb.position.y} end
      if e.type=='splitter' then out[#out]=out[#out]..' filt='..tostring(e.splitter_filter and e.splitter_filter.name)..' outprio='..e.splitter_output_priority end
      for _,ins in pairs(s.find_entities_filtered{type='inserter',area={{e.position.x-3,e.position.y-3},{e.position.x+3,e.position.y+3}}}) do
        local pp=ins.pickup_position
        local hit=false
        if e.type=='splitter' then hit=math.abs(pp.x-e.position.x)<1 and math.abs(pp.y-e.position.y)<1 else hit=math.abs(pp.x-e.position.x)<0.5 and math.abs(pp.y-e.position.y)<0.5 end
        if hit and not picks[ins.unit_number] then picks[ins.unit_number]=true
          local d=ins.drop_target local dn=d and d.name or '-'
          if d and d.type=='assembling-machine' and d.get_recipe() then dn=dn..'['..d.get_recipe().name..']' end
          local f='' if ins.filter_slot_count>0 and ins.get_filter(1) then f=' F='..ins.get_filter(1).name end
          out[#out+1]=string.format('   <- %s %.1f,%.1f -> %s %.1f,%.1f%s',ins.name,ins.position.x,ins.position.y,dn,d and d.position.x or 0,d and d.position.y or 0,f)
        end
      end
    end
  end
end
out[#out+1]='tiles='..n..' queue='..#q
rcon.print(table.concat(out,'\n'))
