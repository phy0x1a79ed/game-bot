-- Read-only: pollution on a chunk grid (32-tile cells) around the base, plus
-- turret coverage (turret range ~18 tiles) and polluting-entity sites with
-- no turret within range.
local surf = game.surfaces["nauvis"]
local out = {}
local function p(s) out[#out+1] = s end

local CELL = 32
local RADIUS = 320 -- tiles from origin
local cells = {}
for gx = -RADIUS, RADIUS, CELL do
  for gy = -RADIUS, RADIUS, CELL do
    local pol = surf.get_pollution({gx, gy})
    if pol and pol > 8 then
      cells[#cells+1] = {x=gx, y=gy, pol=pol}
    end
  end
end
table.sort(cells, function(a,b) return a.pol > b.pol end)
p("=== POLLUTION CELLS (>50, top 40 of " .. #cells .. ") ===")
for i, c in pairs(cells) do
  if i > 40 then break end
  p(string.format("(%d,%d) pollution=%.0f", c.x, c.y, c.pol))
end

-- Polluting entity sites (boilers, burner drills, furnaces) and nearest turret
local turrets = surf.find_entities_filtered{force="player", name="gun-turret"}
local function nearest_turret(x, y)
  local best, bd = nil, nil
  for _, t in pairs(turrets) do
    local d = ((t.position.x-x)^2 + (t.position.y-y)^2)^0.5
    if not bd or d < bd then best, bd = t, d end
  end
  return best, bd
end

p("=== POLLUTER SITES vs TURRET COVERAGE (turret range ~18) ===")
local polluters = {}
for _, name in ipairs({"boiler","burner-mining-drill","stone-furnace"}) do
  for _, e in pairs(surf.find_entities_filtered{force="player", name=name}) do
    polluters[#polluters+1] = e
  end
end
-- cluster polluters into sites (32-tile buckets) to avoid one line per drill
local sites = {}
for _, e in pairs(polluters) do
  local key = math.floor(e.position.x/24)*24 .. "," .. math.floor(e.position.y/24)*24
  sites[key] = sites[key] or {x=0,y=0,n=0}
  sites[key].x = sites[key].x + e.position.x
  sites[key].y = sites[key].y + e.position.y
  sites[key].n = sites[key].n + 1
end
for key, s in pairs(sites) do
  local cx, cy = s.x/s.n, s.y/s.n
  local t, d = nearest_turret(cx, cy)
  local cover = (d and d <= 20) and string.format("covered by (%.0f,%.0f) d=%.1f", t.position.x, t.position.y, d) or "NO COVER within 20"
  p(string.format("site ~(%.0f,%.0f) polluters=%d -- %s", cx, cy, s.n, cover))
end

rcon.print(table.concat(out, "\n"))
