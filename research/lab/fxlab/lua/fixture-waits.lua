-- fixture-waits.lua: a red-science cell on surface "wc" fed by infinity chests, for the wait census.
-- Iron plates make gears, gears and copper plates make red packs, and the packs go to a voiding chest.
-- WC_CUT names an input to cut; without it the cell is built.
local D = defines.direction
if WC_CUT then
  local s = game.surfaces.wc
  local c = s.find_entities_filtered{name = "infinity-chest", position = WC_CUT == "copper-plate" and {0.5, -2.5} or {-6.5, 0.5}}[1]
  c.set_infinity_container_filter(1, nil)
  c.clear_items_inside()
  rcon.print("cut " .. WC_CUT)
  return
end
if game.surfaces.wc then game.delete_surface("wc") rcon.print("deleted; run again") return end
local s = game.create_surface("wc", {width = 64, height = 64, peaceful_mode = true, no_enemies_mode = true})
s.request_to_generate_chunks({0, 0}, 1)
s.force_generate_chunk_requests()
local tiles = {}
for x = -20, 19 do for y = -20, 19 do tiles[#tiles + 1] = {name = "refined-concrete", position = {x, y}} end end
s.set_tiles(tiles)
for _, e in pairs(s.find_entities_filtered{}) do e.destroy() end
local function mk(t) t.force = "player" local e = s.create_entity(t) assert(e, "create failed: " .. t.name) return e end
local function source(pos, item)
  local c = mk{name = "infinity-chest", position = pos}
  c.set_infinity_container_filter(1, {name = item, count = 100, mode = "exactly"})
  return c
end
local eei = mk{name = "electric-energy-interface", position = {10, 10}}
eei.power_production = 1e8 eei.electric_buffer_size = 1e9 eei.energy = 1e9
s.create_global_electric_network()
for _, r in pairs{"iron-gear-wheel", "automation-science-pack"} do game.forces.player.recipes[r].enabled = true end

source({-6.5, 0.5}, "iron-plate")
mk{name = "inserter", position = {-5.5, 0.5}, direction = D.west}
mk{name = "assembling-machine-2", position = {-3.5, 0.5}}.set_recipe("iron-gear-wheel")
mk{name = "inserter", position = {-1.5, 0.5}, direction = D.west}
mk{name = "assembling-machine-2", position = {0.5, 0.5}}.set_recipe("automation-science-pack")
source({0.5, -2.5}, "copper-plate")
mk{name = "inserter", position = {0.5, -1.5}, direction = D.north}
mk{name = "inserter", position = {2.5, 0.5}, direction = D.west}
mk{name = "infinity-chest", position = {3.5, 0.5}}.remove_unfiltered_items = true
rcon.print("fixture waits ready")
