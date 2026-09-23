#!/usr/bin/env bash
# Read-only status of every burner-mining-drill / furnace on nauvis: position,
# status code, fuel level, and (for furnaces) ore/plate counts. Works from
# anywhere -- no reach requirement, it's exec-lua inspection, not an action.
#
# Usage: ./lib/smelting-status.sh
set -euo pipefail
cd "$(dirname "$0")/.."

read -r -d '' LUA <<'EOF' || true
local surf = game.surfaces["nauvis"]
local out = {}
for _, d in pairs(surf.find_entities_filtered{type = "mining-drill"}) do
  local fuel = d.burner and d.burner.inventory and d.burner.inventory.get_item_count("coal") or -1
  out[#out+1] = string.format("drill   (%.0f,%.0f) dir=%d status=%-3d fuel=%d target=%s",
    d.position.x, d.position.y, d.direction, d.status, fuel,
    d.mining_target and d.mining_target.name or "none")
end
for _, f in pairs(surf.find_entities_filtered{type = "furnace"}) do
  local fuel = f.get_item_count("coal")
  local plate = f.get_item_count("iron-plate") + f.get_item_count("copper-plate")
  local ore = f.get_item_count("iron-ore") + f.get_item_count("copper-ore")
  out[#out+1] = string.format("furnace (%.0f,%.0f) status=%-3d fuel=%d ore_in=%d plate_out=%d",
    f.position.x, f.position.y, f.status, fuel, ore, plate)
end
for _, c in pairs(surf.find_entities_filtered{name = "iron-chest"}) do
  out[#out+1] = string.format("chest   (%.1f,%.1f) coal=%d", c.position.x, c.position.y, c.get_item_count("coal"))
end
rcon.print(table.concat(out, "\n"))
EOF

./rlm.sh exec-lua --code "$LUA"
