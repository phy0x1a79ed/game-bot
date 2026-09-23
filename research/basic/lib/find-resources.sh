#!/usr/bin/env bash
# Nearest iron-ore/copper-ore/coal/stone patch tile + nearest water tile,
# relative to the body's current position. Read-only (exec-lua), no mutation.
# Works around observe's 50-entity nearby cap, which a big ore field fills
# with just one resource type before reaching the others.
#
# Usage: ./lib/find-resources.sh [radius]   (default 200)
set -euo pipefail
cd "$(dirname "$0")/.."
RADIUS="${1:-200}"

read -r -d '' LUA <<EOF || true
local surf = game.surfaces["nauvis"]
local body = surf.find_entities_filtered{type="character"}[1]
if not body then rcon.print("no character body on nauvis") return end
local p = body.position
local function dist(a,b) local dx,dy=a.x-b.x,a.y-b.y return math.sqrt(dx*dx+dy*dy) end
local out = {}
for _, rn in ipairs({"iron-ore","copper-ore","coal","stone"}) do
  local ents = surf.find_entities_filtered{position=p, radius=$RADIUS, name=rn, type="resource"}
  local best, bestd, total = nil, nil, 0
  for _, e in pairs(ents) do
    total = total + e.amount
    local d = dist(p, e.position)
    if not bestd or d < bestd then best, bestd = e, d end
  end
  if best then
    out[#out+1] = string.format("%s: nearest(%.1f,%.1f) d=%.1f amount=%d tiles=%d total=%d",
      rn, best.position.x, best.position.y, bestd, best.amount, #ents, total)
  else
    out[#out+1] = rn..": none within $RADIUS"
  end
end
local wtiles = surf.find_tiles_filtered{position=p, radius=$RADIUS, name={"water","deepwater"}}
if #wtiles > 0 then
  local best, bestd
  for _, t in pairs(wtiles) do
    local c = {x=t.position.x+0.5, y=t.position.y+0.5}
    local d = dist(p, c)
    if not bestd or d < bestd then best, bestd = c, d end
  end
  out[#out+1] = string.format("water: nearest(%.1f,%.1f) d=%.1f tiles=%d", best.x, best.y, bestd, #wtiles)
else
  out[#out+1] = "water: none within $RADIUS"
end
rcon.print(table.concat(out, "\\n"))
EOF

./rlm.sh exec-lua --code "$LUA"
