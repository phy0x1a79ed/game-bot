-- Read-only: enemy units within 300 of spawn, clustered, with unit_group
-- command info where present (forming/moving attack groups vs idle nest guards).
local surf = game.surfaces["nauvis"]
local out = {}
local function p(s) out[#out+1] = s end

local units = surf.find_entities_filtered{force="enemy", type="unit", position={0,-20}, radius=300}
p("total enemy units within 300 of (0,-20): " .. #units)

-- cluster
local clusters = {}
local function cluster(e)
  for _, c in pairs(clusters) do
    local dx, dy = e.position.x - c.cx, e.position.y - c.cy
    if (dx*dx+dy*dy)^0.5 <= 15 then
      table.insert(c.members, e)
      c.cx = (c.cx*(#c.members-1) + e.position.x)/#c.members
      c.cy = (c.cy*(#c.members-1) + e.position.y)/#c.members
      return
    end
  end
  table.insert(clusters, {cx=e.position.x, cy=e.position.y, members={e}})
end
for _, e in pairs(units) do cluster(e) end

p("=== CLUSTERS (" .. #clusters .. ") ===")
for _, c in pairs(clusters) do
  local grouped, has_cmd, cmd_types = 0, 0, {}
  for _, e in pairs(c.members) do
    local ok, grp = pcall(function() return e.unit_group end)
    if ok and grp then
      grouped = grouped + 1
      local ok2, cmd = pcall(function() return grp.command end)
      if ok2 and cmd then
        has_cmd = has_cmd + 1
        cmd_types[cmd.type] = (cmd_types[cmd.type] or 0) + 1
      end
    end
  end
  local ct = {}
  for k,v in pairs(cmd_types) do ct[#ct+1] = k..":"..v end
  local d = (c.cx^2 + c.cy^2)^0.5
  p(string.format("centre=(%.0f,%.0f) n=%d dist_spawn=%.0f in_group=%d with_command=%d cmds=%s",
    c.cx, c.cy, #c.members, d, grouped, has_cmd, #ct>0 and table.concat(ct,",") or "none"))
end

-- distinct unit_groups within 300, regardless of member position clustering
p("=== UNIT GROUPS (distinct) within 300 ===")
local seen = {}
for _, e in pairs(units) do
  local ok, grp = pcall(function() return e.unit_group end)
  if ok and grp and not seen[grp.group_number] then
    seen[grp.group_number] = true
    local ok2, cmd = pcall(function() return grp.command end)
    local cmdstr = "none"
    if ok2 and cmd then
      cmdstr = cmd.type
      if cmd.target then
        local ok3, tp = pcall(function() return cmd.target.position end)
        if ok3 and tp then cmdstr = cmdstr .. " target=(" .. math.floor(tp.x) .. "," .. math.floor(tp.y) .. ")" end
      end
      if cmd.destination then
        cmdstr = cmdstr .. " dest=(" .. math.floor(cmd.destination.x) .. "," .. math.floor(cmd.destination.y) .. ")"
      end
    end
    p(string.format("group#%d state=%s members=%d pos=(%.0f,%.0f) cmd=%s",
      grp.group_number, tostring(grp.state), #grp.members, grp.position.x, grp.position.y, cmdstr))
  end
end

rcon.print(table.concat(out, "\n"))
