-- ops-audit-polelines: READ-ONLY. Pole rows (same y) and columns (same x) holding >= 8 poles, with extent, pole type and network id; plus electric-pole ghosts grouped the same way. Pairs of rows/columns running within 20 tiles of each other over overlapping extents are candidates for redundant power lines (check 1b).
local s = game.surfaces[1]
local rows, cols = {}, {}
local function add(t, key, e, g)
  local r = t[key]; if not r then r = {n=0, g=0, lo=1e9, hi=-1e9, names={}}; t[key] = r end
  r.n = r.n + 1; if g then r.g = r.g + 1 end
  r.names[g and ("ghost:"..e.ghost_name) or e.name] = true
end
local function ext(r, v) r.lo = math.min(r.lo, v); r.hi = math.max(r.hi, v) end
for _, e in pairs(s.find_entities_filtered{force="player", type={"electric-pole","entity-ghost"}}) do
  local g = e.type == "entity-ghost"
  if (not g) or e.ghost_type == "electric-pole" then
    local y, x = e.position.y, e.position.x
    add(rows, y, e, g); ext(rows[y], x)
    add(cols, x, e, g); ext(cols[x], y)
  end
end
local function dump(t, label)
  local l = {}
  for k, r in pairs(t) do if r.n >= 8 then
    local nm = {} for n in pairs(r.names) do nm[#nm+1] = n end
    l[#l+1] = string.format("%s=%.1f n=%d ghosts=%d %s..%s %s", label, k, r.n, r.g, r.lo, r.hi, table.concat(nm, "/"))
  end end
  table.sort(l); return l
end
rcon.print("TICK "..game.tick)
rcon.print(table.concat(dump(rows, "y"), "\n"))
rcon.print(table.concat(dump(cols, "x"), "\n"))
