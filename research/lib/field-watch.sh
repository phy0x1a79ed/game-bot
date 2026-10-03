#!/usr/bin/env bash
# field-watch.sh SEAT [SECONDS=240] — poll every 10 s for enemy units within 80 tiles of the copper field, coal patch, stone drill or oil field; exit on the first sighting or at the deadline.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; secs=${2:-240}; end=$((SECONDS+secs))
while [ $SECONDS -lt $end ]; do
  r=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "
local s=game.surfaces[1] local o={}
for k,c in pairs({copper={15,60},coal={72,-45},stone={60,-30},oil={-56,177},pump={-63,32},swcorner={-40,12}}) do
  local n=#s.find_entities_filtered{force='enemy',type='unit',position=c,radius=80} if n>0 then o[#o+1]=k..'='..n end end
rcon.print(game.tick..' '..table.concat(o,' '))" 2>/dev/null | jq -r '.output // ""')
  case "$r" in *=*) echo "SIGHTING $r"; exit 0;; esac
  sleep 10
done
echo "quiet until deadline (last $r)"
