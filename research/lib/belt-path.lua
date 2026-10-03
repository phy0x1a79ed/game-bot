-- belt-path.lua: Dijkstra belt router with underground jumps. Run via belt-path.sh, which substitutes the PARAMS line.
-- A belt tile is usable when a belt can be placed there, no existing belt/UG exit/splitter outputs into it, and no inserter
-- picks from or drops onto it. Turns cost +3, an underground pair (2..5 apart, not across a parallel UG) costs 4+gap.
-- Output: compressed segments and a build list "name x y dir" (UG exits are listed with their FLOW direction; build them facing opposite).
local s=game.surfaces[1]
PARAMS
local X0,Y0,X1,Y1=P.box[1],P.box[2],P.box[3],P.box[4]
local W=X1-X0+1
local function id(x,y) return (y-Y0)*W+(x-X0) end
local inb=function(x,y) return x>=X0 and x<=X1 and y>=Y0 and y<=Y1 end
local D={[0]={0,-1},[1]={1,0},[2]={0,1},[3]={-1,0}} local DN={[0]='north',[1]='east',[2]='south',[3]='west'}
local open,bad,ugaxis={}, {}, {}
local function key(px,py) return id(math.floor(px),math.floor(py)) end
for y=Y0,Y1 do for x=X0,X1 do open[id(x,y)]=s.can_place_entity{name='transport-belt',position={x+0.5,y+0.5},direction=defines.direction.north,force='player'} end end
local area={{X0-1,Y0-1},{X1+2,Y1+2}}
local dv={[0]={0,-1},[4]={1,0},[8]={0,1},[12]={-1,0}}
for _,e in pairs(s.find_entities_filtered{area=area,type={'transport-belt','underground-belt','splitter'}}) do
  local v=dv[e.direction] if v then
    if e.type=='transport-belt' or (e.type=='underground-belt' and e.belt_to_ground_type=='output') then bad[key(e.position.x+v[1],e.position.y+v[2])]=true end
    if e.type=='splitter' then local px,py=-v[2]*0.5,v[1]*0.5 bad[key(e.position.x+px+v[1],e.position.y+py+v[2])]=true bad[key(e.position.x-px+v[1],e.position.y-py+v[2])]=true end
    if e.type=='underground-belt' then ugaxis[key(e.position.x,e.position.y)]=(e.direction%8) end
  end end
for _,e in pairs(s.find_entities_filtered{area=area,type='inserter'}) do bad[key(e.pickup_position.x,e.pickup_position.y)]=true bad[key(e.drop_position.x,e.drop_position.y)]=true end
for _,t in pairs(P.open or {}) do open[id(t[1],t[2])]=true bad[id(t[1],t[2])]=nil end
for _,t in pairs(P.block or {}) do for x=t[1],t[3] do for y=t[2],t[4] do if inb(x,y) then open[id(x,y)]=false end end end end
local function ok(x,y) return inb(x,y) and open[id(x,y)] and not bad[id(x,y)] end
-- heap
local H={} local function push(c,st) H[#H+1]={c,st} local i=#H while i>1 do local p=math.floor(i/2) if H[p][1]<=H[i][1] then break end H[p],H[i]=H[i],H[p] i=p end end
local function pop() local r=H[1] H[1]=H[#H] H[#H]=nil local i=1 while true do local l,rr,m=2*i,2*i+1,i if l<=#H and H[l][1]<H[m][1] then m=l end if rr<=#H and H[rr][1]<H[m][1] then m=rr end if m==i then break end H[m],H[i]=H[i],H[m] i=m end return r end
local dist,prev={},{}
local function sk(x,y,d) return id(x,y)*4+d end
for _,d in ipairs(P.sdirs) do local k=sk(P.s[1],P.s[2],d) dist[k]=0 push(0,{P.s[1],P.s[2],d}) end
local goal
while #H>0 do local it=pop() local c,st=it[1],it[2] local x,y,d=st[1],st[2],st[3] local k=sk(x,y,d)
  if c<=dist[k] then
    if x==P.g[1] and y==P.g[2] and d==P.g[3] then goal=k break end
    local v=D[d] local nx,ny=x+v[1],y+v[2]
    if ok(nx,ny) or (nx==P.g[1] and ny==P.g[2]) then for _,dd in ipairs({d,(d+1)%4,(d+3)%4}) do local nc=c+1+(dd~=d and 3 or 0) local nk=sk(nx,ny,dd) if not dist[nk] or nc<dist[nk] then dist[nk]=nc prev[nk]={k,'b'} push(nc,{nx,ny,dd}) end end end
    if ok(nx,ny) then for L=2,5 do local ex,ey=nx+v[1]*L,ny+v[2]*L local fx,fy=ex+v[1],ey+v[2]
      local clash=false for j=1,L-1 do local a=ugaxis[id(nx+v[1]*j,ny+v[2]*j)] if a and a==((d*4)%8) then clash=true end end
      if not clash and ok(ex,ey) and (ok(fx,fy) or (fx==P.g[1] and fy==P.g[2])) then local nc=c+5+L local nk=sk(fx,fy,d) if not dist[nk] or nc<dist[nk] then dist[nk]=nc prev[nk]={k,'u',L} push(nc,{fx,fy,d}) end end end end
  end end
if not goal then rcon.print('NO PATH') return end
local seq={} local k=goal
while k do local d=k%4 local i=(k-d)/4 local y=math.floor(i/W)+Y0 local x=i%W+X0 table.insert(seq,1,{x,y,d,prev[k]}) k=prev[k] and prev[k][1] end
local build={} local belts,ugs=0,0
for i,t in ipairs(seq) do local p=t[4]
  if p and p[2]=='u' then local v=D[t[3]] local L=p[3] local ex,ey=t[1]-v[1],t[2]-v[2] local nx,ny=ex-v[1]*L,ey-v[2]*L
    build[#build+1]=string.format('UGIN %.1f %.1f %s',nx+0.5,ny+0.5,DN[t[3]]) build[#build+1]=string.format('UGOUT %.1f %.1f %s',ex+0.5,ey+0.5,DN[t[3]]) ugs=ugs+1 end
  build[#build+1]=string.format('BELT %.1f %.1f %s',t[1]+0.5,t[2]+0.5,DN[t[3]]) belts=belts+1 end
rcon.print('cost '..dist[goal]..' belts '..belts..' ugpairs '..ugs..'\n'..table.concat(build,'\n'))
