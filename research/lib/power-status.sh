#!/usr/bin/env bash
# Read-only status of the steam-power chain: offshore-pump, boiler,
# steam-engine, burner-inserter (boiler auto-feed), the coal chest, and every
# small-electric-pole (+ which electric_network_id they're on -- same id
# across pump->engine->poles confirms one continuous network). Works from
# anywhere -- no reach requirement, it's exec-lua inspection, not an action.
#
# Usage: ./lib/power-status.sh
set -euo pipefail
cd "$(dirname "$0")/.."

read -r -d '' LUA <<'EOF' || true
local surf = game.surfaces["nauvis"]
local function fc(e)
  local t = e.get_fluid_contents()
  local out = {}
  for k, v in pairs(t) do out[#out+1] = string.format("%s:%.0f", k, v) end
  return #out > 0 and table.concat(out, ",") or "empty"
end
local out = {}
for _, p in pairs(surf.find_entities_filtered{name = "offshore-pump"}) do
  out[#out+1] = string.format("pump    (%.1f,%.1f) dir=%-2d status=%-3d fluid=%s",
    p.position.x, p.position.y, p.direction, p.status, fc(p))
end
for _, b in pairs(surf.find_entities_filtered{name = "boiler"}) do
  out[#out+1] = string.format("boiler  (%.1f,%.1f) status=%-3d fuel=%-3d fluid=%s",
    b.position.x, b.position.y, b.status, b.get_item_count("coal"), fc(b))
end
for _, e in pairs(surf.find_entities_filtered{name = "steam-engine"}) do
  out[#out+1] = string.format("engine  (%.1f,%.1f) status=%-3d energy_last_tick=%.1f network=%s fluid=%s",
    e.position.x, e.position.y, e.status, e.energy_generated_last_tick,
    tostring(e.electric_network_id), fc(e))
end
for _, bi in pairs(surf.find_entities_filtered{name = "burner-inserter"}) do
  out[#out+1] = string.format("bi-fuel (%.1f,%.1f) status=%-3d own_fuel=%d",
    bi.position.x, bi.position.y, bi.status, bi.get_item_count("coal"))
end
for _, i in pairs(surf.find_entities_filtered{name = "inserter"}) do
  out[#out+1] = string.format("inserter(%.1f,%.1f) status=%-3d energy=%.0f",
    i.position.x, i.position.y, i.status, i.energy)
end
for _, c in pairs(surf.find_entities_filtered{name = "iron-chest"}) do
  local coal = c.get_item_count("coal")
  if coal > 0 then
    out[#out+1] = string.format("chest   (%.1f,%.1f) coal=%d", c.position.x, c.position.y, coal)
  end
end
for _, pole in pairs(surf.find_entities_filtered{name = "small-electric-pole"}) do
  out[#out+1] = string.format("pole    (%.1f,%.1f) network=%s",
    pole.position.x, pole.position.y, tostring(pole.electric_network_id))
end
rcon.print(table.concat(out, "\n"))
EOF

./rlm.sh exec-lua --code "$LUA"
