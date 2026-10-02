-- Follow the coal belt from the chain-1 tap to its end; prints tile count, undergrounds hopped, and the entity where the flow stops.
local s=game.surfaces[1]
local vec={[0]={0,-1},[4]={1,0},[8]={0,1},[12]={-1,0}}
local function belt_at(x,y) return s.find_entities_filtered{area={{x-0.4,y-0.4},{x+0.4,y+0.4}},type={'transport-belt','underground-belt','splitter'}}[1] end
local x,y=79.5,-46.5
local n,hops,coal,seen=0,0,0,{}
local msg
while true do
  local e=belt_at(x,y)
  if not e then msg='NO BELT at '..x..','..y..' after '..n..' tiles' break end
  local k=x..','..y
  if seen[k] then msg='LOOP at '..k break end
  seen[k]=true
  n=n+1
  for i=1,e.get_max_transport_line_index() do coal=coal+e.get_transport_line(i).get_item_count('coal') end
  local d=e.direction
  if e.type=='underground-belt' then
    if e.belt_to_ground_type=='input' then
      local v=vec[d]
      local found
      for step=1,6 do
        local o=belt_at(x+v[1]*step,y+v[2]*step)
        if o and o.type=='underground-belt' and o.belt_to_ground_type=='output' then found=step x=x+v[1]*step y=y+v[2]*step hops=hops+1 break end
      end
      if not found then msg='UNDERGROUND input at '..k..' has no exit' break end
      local o=belt_at(x,y) n=n+1
      for i=1,o.get_max_transport_line_index() do coal=coal+o.get_transport_line(i).get_item_count('coal') end
      local ov=vec[o.direction]
      x=x+ov[1] y=y+ov[2]
    else
      local ov=vec[d]
      x=x+ov[1] y=y+ov[2]
    end
  else
    local v=vec[d]
    x=x+v[1] y=y+v[2]
  end
end
rcon.print(msg..' | tiles='..n..' undergrounds='..hops..' coal_on_belt='..coal)
