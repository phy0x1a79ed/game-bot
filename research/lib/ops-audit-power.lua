-- ops-audit-power: READ-ONLY. Groups electric poles by electric_network_id; reports networks without a producer, other networks with producers, bbox, pole count, nearest pole of the main (largest) network + distance.
local s = game.surfaces[1]
local poles = s.find_entities_filtered{force="player", type="electric-pole"}
local nets = {}
for _, p in pairs(poles) do
  local id = p.electric_network_id
  local n = nets[id]
  if not n then n = {id=id, poles={}, prod=0, x1=1e9,y1=1e9,x2=-1e9,y2=-1e9, kinds={}} nets[id]=n end
  n.poles[#n.poles+1] = p
  local x,y = p.position.x, p.position.y
  if x<n.x1 then n.x1=x end if y<n.y1 then n.y1=y end if x>n.x2 then n.x2=x end if y>n.y2 then n.y2=y end
end
local PT = {"generator","solar-panel","accumulator","burner-generator","electric-energy-interface","fusion-generator","fusion-reactor","reactor"}
for _, e in pairs(s.find_entities_filtered{force="player", type=PT}) do
  local ok, id = pcall(function() return e.electric_network_id end)
  if ok and id and nets[id] then nets[id].prod = nets[id].prod + 1; nets[id].kinds[e.type]=(nets[id].kinds[e.type] or 0)+1 end
end
local arr = {}
for _, n in pairs(nets) do arr[#arr+1] = n end
table.sort(arr, function(a,b) return #a.poles > #b.poles end)
local main = arr[1]
rcon.print("TICK "..game.tick.." poles "..#poles.." networks "..#arr)
for i, n in ipairs(arr) do
  local nd, np = 1e9, nil
  if i > 1 then
    local cx, cy = (n.x1+n.x2)/2, (n.y1+n.y2)/2
    for _, mp in pairs(main.poles) do
      for _, q in pairs(n.poles) do
        local d = math.sqrt((mp.position.x-q.position.x)^2 + (mp.position.y-q.position.y)^2)
        if d < nd then nd = d; np = {mp.position, q.position} end
      end
    end
  end
  local kinds = {} for k,v in pairs(n.kinds) do kinds[#kinds+1]=k..":"..v end
  rcon.print(string.format("net %d poles=%d producers=%d [%s] bbox=(%.0f,%.0f)-(%.0f,%.0f)%s%s", n.id, #n.poles, n.prod, table.concat(kinds,","), n.x1,n.y1,n.x2,n.y2,
    i==1 and " MAIN" or "", np and string.format(" nearest_main_pole=(%.1f,%.1f) own_pole=(%.1f,%.1f) dist=%.1f", np[1].x,np[1].y,np[2].x,np[2].y,nd) or ""))
end
