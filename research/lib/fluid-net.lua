-- geometric flood of one fluid system from START (x,y), box index 1; pumps are boundaries
local s=game.surfaces[1]
local START=START_XY
local DV={[0]={0,-1},[4]={1,0},[8]={0,1},[12]={-1,0}}
local function fl(v) return math.floor(v) end
local function conns(e,i)
  local fb=e.prototype.fluidbox_prototypes[i] local r={}
  if not fb then return r end
  local k=fl((e.direction or 0)/4)
  for _,c in pairs(fb.pipe_connections) do
    if c.connection_type~='linked' then
      local p=c.positions[k+1] local d=(c.direction+(e.direction or 0))%16
      local ix,iy=fl(e.position.x+p.x),fl(e.position.y+p.y)
      r[#r+1]={ix=ix,iy=iy,d=d,ug=(c.connection_type=='underground'),max=c.max_underground_distance or 0}
    end
  end
  return r
end
local function fents(x,y) local r={} for _,e in pairs(s.find_entities_filtered{area={{x+0.1,y+0.1},{x+0.9,y+0.9}}}) do if e.prototype.fluidbox_prototypes and #e.prototype.fluidbox_prototypes>0 and e.type~='character' then r[#r+1]=e end end return r end
local st=s.find_entities_filtered{position=START,radius=0.3}[1]
local q={{st,1}} local seen={} local ents={} local n=0 local pumps={} local names={}
seen[st.unit_number..':1']=true
while #q>0 do
  local e,i=q[#q][1],q[#q][2] q[#q]=nil
  if not ents[e.unit_number] then ents[e.unit_number]=true n=n+1 names[e.name]=(names[e.name] or 0)+1 end
  for _,c in pairs(conns(e,i)) do
    local v=DV[c.d] local tx,ty=c.ix+v[1],c.iy+v[2]
    local cands={}
    if c.ug then
      for dd=1,c.max do local x,y=c.ix+v[1]*dd,c.iy+v[2]*dd local hit=false
        for _,e2 in pairs(fents(x,y)) do if e2.name==e.name then cands[#cands+1]={e2,x,y,true} hit=true end end
        if hit then break end end
    else for _,e2 in pairs(fents(tx,ty)) do cands[#cands+1]={e2,tx,ty,false} end end
    for _,cd in pairs(cands) do local e2=cd[1]
      if e2.type=='pump' then pumps[e2.unit_number]=string.format('%.1f,%.1f',e2.position.x,e2.position.y)
      else
        for j=1,#e2.prototype.fluidbox_prototypes do
          for _,c2 in pairs(conns(e2,j)) do
            local ok
            if cd[4] then ok=c2.ug and c2.ix==cd[2] and c2.iy==cd[3] and c2.d==(c.d+8)%16
            else local v2=DV[c2.d] ok=(not c2.ug) and c2.ix==tx and c2.iy==ty and c2.ix+v2[1]==c.ix and c2.iy+v2[2]==c.iy end
            if ok then local key=e2.unit_number..':'..j if not seen[key] then seen[key]=true q[#q+1]={e2,j} end end
          end
        end
      end
    end
  end
end
local t={} for k,v in pairs(names) do t[#t+1]=k..'='..v end
local pp={} for _,v in pairs(pumps) do pp[#pp+1]=v end
rcon.print('entities='..n..' '..table.concat(t,' ')..' | boundary pumps: '..table.concat(pp,' '))
