-- fixture-mini-factory.lua: a small honest factory on its own surface "fx", for the balance gate's fixtures.
-- Setup creates entities and items freely. Only the window after setup is judged.
-- Lines: electric drill on iron ore into a stone furnace fuelled by a burner drill on coal, furnace to chest,
-- chest to a gear assembler, a lab researching on red packs, and a roboport building belt ghosts from storage.
if game.surfaces.fx then game.delete_surface("fx") rcon.print("deleted; run again") return end
local s = game.create_surface("fx", {width = 128, height = 128, peaceful_mode = true, no_enemies_mode = true})
s.request_to_generate_chunks({0, 0}, 2)
s.force_generate_chunk_requests()
local tiles = {}
for x = -40, 39 do for y = -40, 39 do tiles[#tiles + 1] = {name = "refined-concrete", position = {x, y}} end end
s.set_tiles(tiles)
for _, e in pairs(s.find_entities_filtered{}) do e.destroy() end
s.always_day = true
local D = defines.direction
local function mk(t) t.force = t.force or "player" local e = s.create_entity(t) assert(e, "create failed: " .. t.name) return e end

-- ore under the drills
for x = -12, -7 do for y = -12, -8 do mk{name = "iron-ore", position = {x + 0.5, y + 0.5}, amount = 5000, force = "neutral"} end end
for x = -10, -9 do for y = -6, -5 do mk{name = "coal", position = {x + 0.5, y + 0.5}, amount = 5000, force = "neutral"} end end

local eei = mk{name = "electric-energy-interface", position = {20, 20}}
eei.power_production = 1e8 eei.electric_buffer_size = 1e9 eei.energy = 1e9
s.create_global_electric_network()

-- iron: an electric drill drops south into a stone furnace, and a burner drill on coal drops north into it
mk{name = "electric-mining-drill", position = {-9.5, -9.5}, direction = D.south}
local furnace = mk{name = "stone-furnace", position = {-9, -7}}
furnace.insert{name = "coal", count = 10}
mk{name = "burner-mining-drill", position = {-9, -5}, direction = D.north}.insert{name = "coal", count = 50}
-- plates out of the furnace east into a chest, then into a gear assembler
mk{name = "inserter", position = {-7.5, -6.5}, direction = D.west}
local plates = mk{name = "iron-chest", position = {-6.5, -6.5}}
mk{name = "inserter", position = {-5.5, -6.5}, direction = D.west}
local asm = mk{name = "assembling-machine-2", position = {-3.5, -6.5}}
asm.set_recipe("iron-gear-wheel")
mk{name = "inserter", position = {-1.5, -6.5}, direction = D.west}
local gears = mk{name = "iron-chest", position = {-0.5, -6.5}}

-- research: a chest of red packs feeds a lab
local packs = mk{name = "iron-chest", position = {6.5, 6.5}}
packs.insert{name = "automation-science-pack", count = 200}
mk{name = "inserter", position = {7.5, 6.5}, direction = D.west}
mk{name = "lab", position = {9.5, 6.5}}
local f = game.forces.player
-- trigger techs (crafted or mined, never lab-researched) gate the first lab techs: mark them done at setup
for _, t in pairs{"automation", "logistics", "electronics", "turrets"} do
  local tech = f.technologies[t]
  if tech and not tech.researched then
    for _, pre in pairs(tech.prerequisites) do if pre.prototype.research_trigger then pre.researched = true end end
    f.add_research(t)
  end
end
assert(f.current_research, "no research queued")

-- robots: a roboport with 10 construction robots, a storage chest of belts, and a row of belt ghosts
local rp = mk{name = "roboport", position = {10, -10}}
rp.insert{name = "construction-robot", count = 10}
mk{name = "storage-chest", position = {13.5, -12.5}}.insert{name = "transport-belt", count = 30}
for x = 0, 19 do mk{name = "entity-ghost", inner_name = "transport-belt", position = {x + 0.5, -20.5}, direction = D.east} end
local out = {}
for _, e in pairs(s.find_entities_filtered{type = {"inserter", "mining-drill"}}) do
  local drop = e.drop_position
  local tgt = s.find_entities_filtered{position = drop, limit = 1}[1]
  out[#out + 1] = string.format("%s (%.1f,%.1f) drop (%.1f,%.1f)->%s", e.name, e.position.x, e.position.y, drop.x, drop.y, tgt and tgt.name or "-")
  if e.type == "inserter" then
    local pk = s.find_entities_filtered{position = e.pickup_position, limit = 1}[1]
    out[#out] = out[#out] .. " pick<-" .. (pk and pk.name or "-")
  end
end
rcon.print("fixture mini-factory ready\n" .. table.concat(out, "\n"))
