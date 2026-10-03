#!/usr/bin/env bash
# wall-line.sh SEAT NAME AXIS FIXED FROM TO — build NAME (default use: stone-wall) along a row or column at half-tile steps of 1.
#   AXIS=x: row y=FIXED, x from FROM to TO.  AXIS=y: column x=FIXED, y from FROM to TO.
# Prints how many were built and the first few failures (trimmed). Stand within reach (10.5) of the whole run.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; name=$2; axis=$3; fixed=$4; from=$5; to=$6
RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "
local o={} local n=0
local step=$from<=$to and 1 or -1
for v=$from,$to,step do
  local x,y if '$axis'=='x' then x,y=v,$fixed else x,y=$fixed,v end
  local ok,r=pcall(function() return remote.call('game_bot','build',{seat='$seat',name='$name',x=x,y=y}) end)
  if ok and r and r.ok then n=n+1 elseif #o<4 then o[#o+1]=string.format('(%g,%g) %s',x,y,(ok and serpent.line(r) or tostring(r)):sub(1,140):gsub('\n',' ')) end
end
rcon.print('built '..n..(#o>0 and '\n'..table.concat(o,'\n') or ''))" | jq -r .output
