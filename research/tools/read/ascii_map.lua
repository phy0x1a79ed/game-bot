--- tool: ascii_map
--- kind: call
--- effect: read
--- summary: an area of at most 64 x 64 tiles as rows of characters, one per tile, with a legend; belts and inserters show their direction
--- args: x0, y0, x1, y1 (numbers: tiles x0 <= x < x1, y0 <= y < y1); scenery (bool, default true: trees, rocks and cliffs); surface
--- returns: {x0, y0, w, h, rows = {"...", ...}, legend = {char = meaning}}; row i, column j is tile (x0 + j - 1, y0 + i - 1); ^ > v < belts by flow direction, U u underground entrance and exit, Y splitter, N E S W inserter by the side it drops to; {error, hint} on bad args
--- uses: rd
local rd = use("rd")
local a = ...
local c, err = rd.ctx(a, {area = true, extra = {"scenery"}})
if not c then return err end

local X0, Y0 = math.floor(c.x0), math.floor(c.y0)
local W, H = math.max(1, math.ceil(c.x1) - X0), math.max(1, math.ceil(c.y1) - Y0)
if W > 64 or H > 64 then
  return rd.fail(string.format("the area is %d x %d tiles; at most 64 x 64", W, H), "map it in parts, or use look with count = true")
end
local scenery = a.scenery ~= false

local grid = {}
for j = 1, H do
  grid[j] = {}
  for i = 1, W do grid[j][i] = "." end
end
local legend = {["."] = "empty ground"}

local function put(x, y, ch) local row = grid[y - Y0 + 1] if row and row[x - X0 + 1] then row[x - X0 + 1] = ch end end
local function get(x, y) local row = grid[y - Y0 + 1] return row and row[x - X0 + 1] end

for _, t in pairs(c.s.find_tiles_filtered{area = {{X0, Y0}, {X0 + W, Y0 + H}}, collision_mask = "water_tile"}) do
  put(math.floor(t.position.x), math.floor(t.position.y), "~")
  legend["~"] = "water"
end

local TYPE_CHAR = {
  ["splitter"] = "Y", ["pipe"] = "=", ["pipe-to-ground"] = "p", ["pump"] = "M", ["offshore-pump"] = "O",
  ["storage-tank"] = "K", ["electric-pole"] = "P", ["wall"] = "#", ["gate"] = "#", ["assembling-machine"] = "A",
  ["furnace"] = "F", ["lab"] = "L", ["mining-drill"] = "D", ["boiler"] = "B", ["generator"] = "G",
  ["container"] = "C", ["logistic-container"] = "H", ["roboport"] = "R", ["radar"] = "Q", ["ammo-turret"] = "T",
  ["electric-turret"] = "T", ["fluid-turret"] = "T", ["straight-rail"] = "%", ["curved-rail-a"] = "%",
  ["curved-rail-b"] = "%", ["half-diagonal-rail"] = "%", ["rail-signal"] = "%", ["rail-chain-signal"] = "%",
  ["train-stop"] = "Z", ["locomotive"] = "$", ["cargo-wagon"] = "$", ["fluid-wagon"] = "$", ["tree"] = "t",
  ["simple-entity"] = "X", ["cliff"] = "X", ["simple-entity-with-owner"] = "X", ["beacon"] = "b",
  ["accumulator"] = "a", ["solar-panel"] = "z", ["reactor"] = "V", ["heat-pipe"] = "h", ["lamp"] = "*",
}
local ORE = {["iron-ore"] = "i", ["copper-ore"] = "c", ["coal"] = "k", ["stone"] = "s", ["crude-oil"] = "o"}
local ARROW = {[0] = "^", [4] = ">", [8] = "v", [12] = "<"}
local ARROW_NAME = {[0] = "north", [4] = "east", [8] = "south", [12] = "west"}
local SKIP = {character = true, corpse = true, ["item-entity"] = true, ["construction-robot"] = true,
  ["logistic-robot"] = true, ["combat-robot"] = true, fish = true, unit = true, ["item-request-proxy"] = true}
local POOL = "dfghjlmnrwxy0123456789"
local used = {}
for ch in pairs(legend) do used[ch] = true end
for _, ch in pairs(TYPE_CHAR) do used[ch] = true end
for _, ch in pairs(ORE) do used[ch] = true end
for _, ch in ipairs{"^", ">", "v", "<", "U", "u", "N", "E", "S", "W", "+", "~", "."} do used[ch] = true end
local assigned = {}

-- a character for an entity name that has none of its own
local function spare(name)
  if assigned[name] then return assigned[name] end
  for i = 1, #POOL do
    local ch = POOL:sub(i, i)
    if not used[ch] then used[ch] = true assigned[name] = ch return ch end
  end
  assigned[name] = "?"
  return "?"
end

local function symbol(e)
  local t = e.type
  if t == "entity-ghost" then return "+", "ghost (planned entity)" end
  if t == "resource" then
    local ch = ORE[e.name] or spare(e.name)
    return ch, e.name
  end
  if t == "transport-belt" then
    local d = e.direction
    return ARROW[d] or "?", "belt flowing " .. (ARROW_NAME[d] or "?")
  end
  if t == "underground-belt" then
    return e.belt_to_ground_type == "input" and "U" or "u", "underground belt " .. e.belt_to_ground_type
  end
  if t == "inserter" then
    local p, d = e.position, e.drop_position
    local dx, dy = d.x - p.x, d.y - p.y
    local ch, side
    if math.abs(dy) >= math.abs(dx) then
      if dy < 0 then ch, side = "N", "north" else ch, side = "S", "south" end
    elseif dx > 0 then
      ch, side = "E", "east"
    else
      ch, side = "W", "west"
    end
    return ch, "inserter dropping " .. side
  end
  local ch = TYPE_CHAR[t]
  if ch then return ch, t end
  return spare(e.name), e.name
end

-- later layers overwrite earlier ones
local RANK = {resource = 1, tree = 2, ["simple-entity"] = 2, cliff = 2, ["simple-entity-with-owner"] = 2}
local ents = {}
for _, e in pairs(c.s.find_entities_filtered{area = {{X0, Y0}, {X0 + W, Y0 + H}}}) do
  if not SKIP[e.type] then
    local rank = RANK[e.type] or 3
    if e.type == "entity-ghost" then rank = 4 end
    if scenery or rank ~= 2 then ents[#ents + 1] = {e = e, rank = rank} end
  end
end
table.sort(ents, function(p, q)
  if p.rank ~= q.rank then return p.rank < q.rank end
  local pa, pb = p.e.position, q.e.position
  if pa.y ~= pb.y then return pa.y < pb.y end
  return pa.x < pb.x
end)

for _, item in ipairs(ents) do
  local e = item.e
  local ch, meaning = symbol(e)
  legend[ch] = legend[ch] or meaning
  if legend[ch] ~= meaning and not legend[ch]:find(meaning, 1, true) and #legend[ch] < 60 then
    legend[ch] = legend[ch] .. ", " .. meaning
  end
  if e.type == "resource" then
    local x, y = math.floor(e.position.x), math.floor(e.position.y)
    local here = get(x, y)
    if here == "." or here == "~" then put(x, y, ch) end
  elseif item.rank == 4 then
    local bb = e.bounding_box
    for y = math.floor(bb.left_top.y + 0.01), math.ceil(bb.right_bottom.y - 0.01) - 1 do
      for x = math.floor(bb.left_top.x + 0.01), math.ceil(bb.right_bottom.x - 0.01) - 1 do
        if get(x, y) == "." then put(x, y, ch) end
      end
    end
  else
    local bb = e.bounding_box
    for y = math.floor(bb.left_top.y + 0.01), math.ceil(bb.right_bottom.y - 0.01) - 1 do
      for x = math.floor(bb.left_top.x + 0.01), math.ceil(bb.right_bottom.x - 0.01) - 1 do put(x, y, ch) end
    end
  end
end

local rows, seen = {}, {}
for j = 1, H do
  rows[j] = table.concat(grid[j])
  for i = 1, W do seen[grid[j][i]] = true end
end
local shown = {}
for ch, meaning in pairs(legend) do
  if seen[ch] then shown[ch] = meaning end
end
return {x0 = X0, y0 = Y0, w = W, h = H, rows = rows, legend = shown}
