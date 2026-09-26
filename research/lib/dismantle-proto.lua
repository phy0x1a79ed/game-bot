local seat = player.name
local out = {}
local function p(s) out[#out+1] = s end
local spots = {
  {-34.5,-16.5}, {-32.5,-16.5}, {-30.5,-16.5}, {-28.5,-16.5}, {-27.5,-16.5},
  {-33.5,-18.5}, {-29.5,-18.5},
}
for _, pos in pairs(spots) do
  local ok, res = pcall(remote.call, 'game_bot', 'mine', {seat=seat, x=pos[1], y=pos[2]})
  p('mine @ '..pos[1]..','..pos[2]..': ok='..tostring(ok)..' res='..tostring(res and (res.mining or res)))
end
rcon.print(table.concat(out, '\n'))
