-- ops-audit-belts: READ-ONLY. Dead-end belt tiles (no output belt, no inserter/loader pickup on the tile) that carry items, and orphan runs (dead end AND start with no input belt / inserter / drill feeding it). Walks back along inputs to the run start. Prints one line per dead end, sorted by run length.
local s = game.surfaces[1]
local function K(x,y) return math.floor(x)..","..math.floor(y) end
local pick, feed = {}, {}
for _, i in pairs(s.find_entities_filtered{force="player", type={"inserter","loader","loader-1x1"}}) do
  if i.type == "inserter" then
    pick[K(i.pickup_position.x, i.pickup_position.y)] = true
    feed[K(i.drop_position.x, i.drop_position.y)] = true
  else pick[K(i.position.x,i.position.y)] = true; feed[K(i.position.x,i.position.y)] = true end
end
for _, d in pairs(s.find_entities_filtered{force="player", type="mining-drill"}) do
  local ok, dp = pcall(function() return d.drop_position end)
  if ok and dp then feed[K(dp.x,dp.y)] = true end
end
local belts = s.find_entities_filtered{force="player", type={"transport-belt","underground-belt","splitter"}}
local UGX = {[0]={0,-1},[4]={1,0},[8]={0,1},[12]={-1,0}}
local ugidx = {}
for _, u in pairs(s.find_entities_filtered{force="player", type="underground-belt"}) do ugidx[K(u.position.x,u.position.y)] = u end
local function ug(b)
  local v = UGX[b.direction]; local sgn = (b.belt_to_ground_type == "input") and 1 or -1
  for d = 1, 12 do
    local o = ugidx[K(b.position.x + v[1]*d*sgn, b.position.y + v[2]*d*sgn)]
    if o and o.name == b.name and o.direction == b.direction and o.belt_to_ground_type ~= b.belt_to_ground_type then return o end
  end
  return nil
end
local function nitems(b)
  local n, names = 0, {}
  for i=1,b.get_max_transport_line_index() do
    local c = b.get_transport_line(i).get_contents()
    for _, it in pairs(c) do n = n + it.count; names[it.name] = true end
  end
  local l = {} for k in pairs(names) do l[#l+1]=k end
  return n, table.concat(l,"/")
end
local ends, total = {}, #belts
for _, b in pairs(belts) do
  local nb = b.belt_neighbours
  local hasout = nb.outputs and #nb.outputs > 0
  if not hasout and b.type == "underground-belt" and b.belt_to_ground_type == "input" and ug(b) then hasout = true end
  if not hasout and not pick[K(b.position.x,b.position.y)] then
    if b.type == "splitter" then
      -- splitter covers two tiles; treat as non-dead if either half has a picker
    end
    ends[#ends+1] = b
  end
end
local rows = {}
for _, b in ipairs(ends) do
  local n, names = nitems(b)
  local cur, len, srcfeed, seen, tailpick = b, 1, false, {}, false
  while len < 500 do
    local k = cur.unit_number
    if seen[k] then break end seen[k] = true
    if len <= 14 and pick[K(cur.position.x,cur.position.y)] then tailpick = true end
    if feed[K(cur.position.x,cur.position.y)] then srcfeed = true end
    local ins = cur.belt_neighbours.inputs
    if (not ins or #ins == 0) and cur.type == "underground-belt" and cur.belt_to_ground_type == "output" and ug(cur) then
      cur = ug(cur); len = len + 1
    elseif not ins or #ins == 0 then break
    else cur = ins[1]; len = len + 1 end
  end
  local startfeed = srcfeed
  rows[#rows+1] = {len=len, n=n, line=string.format("%s end=(%.1f,%.1f) start=(%.1f,%.1f) len=%d items=%d [%s] %s", (n>0) and (tailpick and "END-STUB(picker within 14 tiles, fine)" or "DEADEND-NO-CONSUMER") or "EMPTY", b.position.x,b.position.y,cur.position.x,cur.position.y,len,n,names, startfeed and "fed" or "ORPHAN-NOFEED")}
end
table.sort(rows, function(a,b) return a.len > b.len end)
rcon.print("TICK "..game.tick.." belts "..total.." deadends "..#rows)
for i, r in ipairs(rows) do if i<=150 and (r.n>0 or r.len>=4) and not r.line:find('END%-STUB') then rcon.print(r.line) end end
