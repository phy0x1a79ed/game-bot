#!/usr/bin/env bash
# feed-ammo.sh SEAT — stand by the ammo assembler, move iron into its input chest
# (-40.5,-4.5) from the science gear chest (-38.5,-8.5) and the iron belts y=-2.5/-7.5,
# then pick up the finished magazines from (-34.5,-4.5). Prints iron moved and mags held.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1
"$LIB/walk.sh" "$seat" -36.6 -6.5 2 >/dev/null
RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "
local S='$seat' local tot=0
local function take(x,y,n,t) local ok,r=pcall(function() return remote.call('game_bot','take',{seat=S,x=x,y=y,name=n,target=t}) end) if ok and r and r.taken then return r.taken end return 0 end
tot=tot+take(-38.5,-8.5,'iron-plate','iron-chest')
for x=-44.5,-26.5 do for _,y in pairs({-2.5,-7.5}) do tot=tot+take(x,y,'iron-plate','transport-belt') end end
local ok,r=pcall(function() return remote.call('game_bot','insert',{seat=S,x=-40.5,y=-4.5,name='iron-plate',count=tot,target='iron-chest'}) end)
local m=take(-34.5,-4.5,'firearm-magazine','iron-chest')
rcon.print('iron taken '..tot..' inserted '..tostring(ok and r and r.inserted)..' mags collected '..m)
" 2>/dev/null | jq -r '.output // .'
