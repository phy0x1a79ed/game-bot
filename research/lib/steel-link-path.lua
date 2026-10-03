-- BFS with underground hops (basic UG, max gap 4) from (SX,SY) to (TX,TY); prints tiles with E/X = UG entrance/exit
local s=game.surfaces[1] local D={{1,0},{-1,0},{0,1},{0,-1}}
local cache={} local function fr(x,y) local k=x..','..y local v=cache[k] if v==nil then v=s.can_place_entity{name='transport-belt',position={x,y},force='player'} cache[k]=v end return v end
local SX,SY,TX,TY=39.5,-36.5,15.5,-23.5
local q={{SX,SY,0,'b'}} local prev={} local function key(n) return n[1]..','..n[2]..','..n[3]..n[4] end prev[key(q[1])]=false
local i=1 local goal
local function push(c,n) local k=key(n) if prev[k]==nil then prev[k]=c n.from=c q[#q+1]=n end end
while q[i] do local c=q[i] i=i+1
 if c[1]==TX and c[2]==TY then goal=c break end
 for di,d in ipairs(D) do
  local nx,ny=c[1]+d[1],c[2]+d[2]
  if c[4]~='x' or c[3]==di then
   if fr(nx,ny) and nx>=8 and nx<=70 and ny>=-60 and ny<=-5 then push(c,{nx,ny,di,'b'}) end
   if (c[3]==di or c[3]==0) and c[4]=='b' then
    for k=2,5 do local ex,ey=c[1]+d[1]*k,c[2]+d[2]*k
     if fr(ex,ey) and ex>=8 and ex<=70 and ey>=-60 and ey<=-5 and fr(c[1],c[2]) then local n={ex,ey,di,'x'} local kk=key(n) if prev[kk]==nil then prev[kk]=c n.from=c n.hop=true q[#q+1]=n end end end
   end
  end
 end
end
local reach={} for k,_ in pairs(prev) do local x,y=k:match("^([%d.-]+),([%d.-]+)") reach[x..","..y]=true end local o={} for _,p in pairs{{39.5,-30.5},{16.5,-29.5},{30.5,-25.5},{22.5,-23.5},{15.5,-23.5},{38.5,-27.5},{20.5,-22.5},{15.5,-20.5}} do o[#o+1]=p[1]..","..p[2]..(reach[p[1]..","..p[2]] and "Y" or "n") end rcon.print(table.concat(o," "))
if not goal then return end
local p={} local n=goal while n do p[#p+1]=(n.hop and 'X' or '')..n[1]..','..n[2]..'d'..n[3] n=n.from end
rcon.print(#p..' '..table.concat(p,' '))
