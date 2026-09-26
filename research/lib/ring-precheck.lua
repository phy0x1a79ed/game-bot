local surf = game.surfaces["nauvis"]
local out = {}
local function p(s) out[#out+1] = s end
local pts = {{73,-48},{75,-48},{75,-46},{73,-46},{78,-48},{80,-48}}
for _, pt in pairs(pts) do
  local e = surf.find_entities_filtered{position=pt, radius=0.6, name="burner-mining-drill"}[1]
  if e then
    local dp = e.drop_position
    local okt, target = pcall(function() return e.drop_target end)
    local tname = "nil"
    if okt and target then tname = target.name .. "@(" .. target.position.x .. "," .. target.position.y .. ")" end
    p(string.format("(%.0f,%.0f) dir=%d drop=(%.4f,%.4f) drop_target=%s", e.position.x, e.position.y, e.direction, dp.x, dp.y, tname))
  else
    p(string.format("(%.0f,%.0f): NOT FOUND", pt[1], pt[2]))
  end
end
rcon.print(table.concat(out, "\n"))
