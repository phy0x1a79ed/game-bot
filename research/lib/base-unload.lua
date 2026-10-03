-- base-unload.lua = rail-yard.lua layout (infra-b) + MODE='build' with a window, WX=15. Prepend MODE='check'|'build', WX, SEAT, BX0,BX1,BY0,BY1.
-- rail-yard.lua original header: base stop 'Unload Stone Base' platform (south of the trunk y=-161). Prepend MODE='check'|'ghost' and WX (x of the westbound front, RAIL.md sec 3: 15).
-- Wagon i (0..2 stone, 3 coal) spans x WX+7+7i .. +6. Stone: wagon -> fast inserter y-159.5 -> chest y-158.5 -> inserter y-157.5 -> steel furnace (centre y-156), 2 chains per furnace.
-- Fuel: inserter y-154.5 from the coal belt y-153.5. Bricks: long-handed y-154.5 over the belt into chest y-152.5. Coal: wagon 3 -> belt y-158.5 east -> x+52.5 south -> y-153.5 west
-- past the furnaces -> splitter: one side north to the west loco inserter, the other (20.5,-152.5) south to the boiler fuel belt. Direction = side an inserter picks from, belts = flow.
local s = game.surfaces[1]
local N, E, S, W = 0, 4, 8, 12
local L = {}
local NM = {[0]='north', [4]='east', [8]='south', [12]='west'}
local function add(n, x, y, d) L[#L + 1] = {n, x, y, NM[d or 0]} end
for i = 0, 2 do
  local xs = WX + 7 + 7 * i
  for k = 0, 5 do
    local t = xs + k + 0.5
    add('fast-inserter', t, -159.5, N); add('iron-chest', t, -158.5); add('inserter', t, -157.5, N)
  end
  for j = 0, 2 do
    local xa = xs + 2 * j + 0.5
    add('steel-furnace', xa + 0.5, -156)
    add('inserter', xa, -154.5, S); add('long-handed-inserter', xa + 1, -154.5, N); add('iron-chest', xa + 1, -152.5)
  end
end
local cx = WX + 28
for k = 0, 3 do add('fast-inserter', cx + k + 0.5, -159.5, N) end
for x = cx + 0.5, cx + 8.5 do add('transport-belt', x, -158.5, E) end
for y = -158.5, -154.5 do add('transport-belt', cx + 9.5, y, S) end
add('transport-belt', cx + 9.5, -153.5, W)
for x = cx + 8.5, WX + 7.5, -1 do add('transport-belt', x, -153.5, W) end
add('splitter', WX + 6.5, -153, W)
for y = -153.5, -157.5, -1 do add('transport-belt', WX + 5.5, y, N) end
for x = WX + 5.5, WX + 3.5, -1 do add('transport-belt', x, -158.5, W) end
add('transport-belt', WX + 5.5, -152.5, S)
add('inserter', WX + 3.5, -159.5, S); add('inserter', WX + 36.5, -159.5, S)
for _, p in pairs{{WX - 0.5, -157.5}, {WX + 6.5, -156.5}, {WX + 13.5, -156.5}, {WX + 20.5, -156.5}, {WX + 27.5, -156.5}, {WX + 34.5, -156.5}} do add('medium-electric-pole', p[1], p[2]) end
local PP = SEAT and game.get_player(SEAT).position or {x = 0, y = 0}
local DV = {north = 0, east = 4, south = 8, west = 12}
local bad, ok, built, cnt = {}, 0, 0, {}
for _, e in ipairs(L) do
  local n, x, y, d = e[1], e[2], e[3], e[4]
  if (not BX0 and MODE ~= 'build') or (BX0 and x >= BX0 and x <= BX1 and y >= BY0 and y <= BY1) or (MODE == 'build' and not BX0 and (x - PP.x) ^ 2 + (y - PP.y) ^ 2 < 100) then
    cnt[n] = (cnt[n] or 0) + 1
    local ex = s.find_entities_filtered{position = {x, y}, radius = 0.3, name = n}[1]
    if ex then ok = ok + 1
    else
      local can = s.can_place_entity{name = n, position = {x, y}, direction = DV[d], force = 'player'}
      if not can then bad[#bad + 1] = n:sub(1, 4) .. '@' .. x .. ',' .. y
      elseif MODE == 'check' then bad[#bad + 1] = 'MISS ' .. n:sub(1, 6) .. '@' .. x .. ',' .. y
      elseif MODE == 'build' then
        local k, r = pcall(remote.call, 'game_bot', 'build', {seat = SEAT, name = n, x = x, y = y, direction = d})
        if k and type(r) == 'table' and r.built then built = built + 1 else bad[#bad + 1] = 'ERR' .. n:sub(1, 4) .. '@' .. x .. ',' .. y .. ':' .. (k and serpent.line(r) or tostring(r)):sub(1, 50) end
      end
    end
  end
end
rcon.print(MODE .. ' total ' .. #L .. ' built-already ' .. ok .. ' built-now ' .. built .. ' bad[' .. #bad .. '] ' .. table.concat(bad, ' '):sub(1, 1200) .. ' | ' .. serpent.line(cnt))
