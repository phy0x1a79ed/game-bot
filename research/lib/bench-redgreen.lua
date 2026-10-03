-- bench-redgreen.lua: rate the run 4 red/green block (lib/redgreen-60.bp) on an empty surface with free inputs.
-- Builds surface "bench", revives the blueprint, feeds iron (lane 1) and copper (lane 2) into the block's one
-- input belt through loaders on infinity chests, and voids both pack outputs. A second run deletes the bench.
-- Editor-style: it creates entities and items, so it belongs on a scratch copy of a save, never the live run.
-- Then: game.tick_paused=false game.speed=64, wait, and read with lib/bench-read.lua twice.
local BP = "0eNq1nduS4jgWRf+FZ+iwji626lcqKjpIypNFDAk5QE5PR0X9+xjIC1UNeK/TzVvaCduydLZ0bC2J75OH1Uv/vF2u95NP3yfLxWa9m3z6/H2yWz6u56vDufX8qZ98muy38/XuebPdzx761X7yYzpZrr/2/5t8Cj+mFz4+3+36p4fVcv04e5ovvi3X/czOvmQ/vkwn/Xq/3C/70wWPB3/+vn55eui3g+r0ptJ08rzZDV/erA/XHARnZr/l6eTP4a/mtzxcaNsvls+H7y82z8/9draYP6z6ydv53//zMl8N1xv+v95sn4aiH+7ilzLY9MrNX7h6eLt6yMfLf10OFzp9Il2Qji7p5lfpYBe0E6669yu0P1fdcrtZzx77+Xb2x7e+X7Hay+/FeOq/Ll+eZv1qKPZ2uZg9b44tcb0Yhyq8oFg8lZaU5mgdylVqjA4oNyyGqktai6HQvIuvNkP4fJsPvv06W653/XY/fODWJa60Xgie8krNF8wjHSXpD6f+a77bazUQtDpODmmx+bKjQrSADsCFobKIDq1LW6yTTq7uD+2/FLu7pFw9xZYi2xqPtBTZFhzSWowY8GPoWIxYdGlrMWJ47Py4xD85dlr23KQWUcUjrUVUSweNjwvY5UHDOn+D/JIHntKPzXpIQBbL7eJluYdtUmlC816UcPnmYuNoCs2BkZi7hbmrubQ1B8aIY6gdSTxi8pRXMlPMHmnJTLE4pMXgIMNsgcHRubTF4Kj6EF7QEJ4aT7GlGEnBIy3FSDJHfYgPkdFRai38EvFjZuGXsktbrJOCB6N8j+wgtXgkyiN9ZOo89abFf/VIS/GfGz3+80imkQMeePLt4T2b48a1+44OZc2cmZgzMXPm7NLWzJkLbr80YorcesormSJ3HmktOCrupdKVlPms8kD3VBrHvUm3VoJDWYv7QswaWdyX6NLW4r58GPZWrEeUDpXsKbEU+aV4pLXw4M+fcWRUKJ1b8sqoUKrj/qXbbxuHsuaOlhjPmDtac2lr7mij5I532aq4o+VviexKHjh/2W+e5oePznaLZb9e9LPn+eLfrMNts6cGtYmR4pHWwpVnsXbbWm3nKKxW1upQFieIPlz7+LKe7V+22/6y7Gvgx0u33hGDwrnKzlzamkG7iKMgnJv1kmTCfXZAo2OXPRUi+a0rHmkphrtW6grDyIjYdY4SagWsDmXNZJUMjXQaNri0NXtUkxqtQfFbo6fEUvzW5JGWwqNmPOo2V55r/lI0MNjWor9zaG6PV7V1VJZJddU5lLVWqA5lcWa5AS6lM8tN8GirsITk0oqSzNBEGu/1nklmaBIdqesYEdJkR6NoREhTHNIaEdLgx8w6MqaGpuOlNa2wlStr1RAcbhU7AoIKQXwgEFaI4gMh4NnLjpEmITlKrzmGMEOMCwiEGepQeBNiqGPh3Sl9+ptmusa8VV4+0SQEDYIz/IGwQXSGP5g0WrbMGAQLaiFcmBzSWpAZhmTb2yllIHhPi6xmLVcWawFDPm/65edEZ7V5XO72Q+X9jTTnDPMRorO70gzRYU7R9wTtgfBGIGgPhTdClN7FFpYlR/wuttw1SyZEEONIAiGCCoScWy6t9RqEByqo1ziDgcRcq4wM1mcQkNgbl5FuIDm8KnYDCVgVQjSBwD8UogkJP0fmkRe+4Yz6EUMhs+wiFUeFaK5OrUNacwiBejJyNWF6ENkSzpAeofmuOTkHXj7Rd4TqgXxMIFwP5WNClkCBxIxBkB5GyIRcHNJikLVcWjMG4XoSMwbGetL9kuTSkFi6NjoSnCfBRUrApZDmCQTnoTRP0HCeyJLkgqdO4l2T5DMGSEwB4tir5NI6GkXriErnkNZMTWCgiDoiAgMhyii0GJSNI6N16zCr2A+0ZKE1XayYPNpiP9DilNbYyE3IHsYMhbZ1SIvB13Fp0TCVK2tl7qTB0kZMQggfRiAFBPhAk3TRo62u6NXYV2YMRPcwYyC6hxmj4zTdyJtkBPogqyHQB1ntjPNRGZH7JclnYJAQndeS5Oowp+h7wgFBKCoQEAhvTnGGAt2o2YYlyRWv7mrumiQTOghul0HwILhdBuGDENJkhA5CSJM1OKNtbg/WdgYEib1xc7sbsMbhVXGzhjOw5xaB3Nzijw2gPLArMYDy0J7EGjpsNiPvoq2hK0YYu2kA6GG9ggGgp4E7jQSsrPUJAOZhXUJQ5irHegEA60DLAlYHJuwGWB2ar1tQEHSWrlvoeHlFP1SurEUXQHdQZm2A20GJtZ0xO1pydL+82iyCKLo2ngKoJ8C9j3RvwjdOBuAe+sLJTPEmWydnGOy56zI5wzv42MhbZwOYD3uHZoDyYa/QDDA+6A2axYiFxRLTBV0j79IscouK5geMTqT7nrUOadH8kSatbDm5xcrLrvkEbNzD5mYMsDtoasYAuYNmZiwpA+PIZIyB3XnYXIyBvXkgOGGAz0l4S0BlYGTYhAEyJ0E/VK6sRVemdFy6/YLZAKSDIAwDiA5iMCzTJVn3QzBMwnlGCAzL3JKi2QG9A+lEA/QOhRMtK6s+MsuCMbmT75oFF+rjsb3DDHA8Ge5ValxZszKAeBAaaSVhYbHElAgYgSQNUzh5pDcp3JhibwIQHLjkwQp9KCxjb4Bbunc626rSwGY8bIWBARCnwJ2BI1bW7AYgHLS8wFpljnFkRYEByIbh/wYYG7j4zwBj07K2qlhYa6uOTvvfb/2Ydcqs/8jyMQNEDls9ZoDHoRuzdwlLa3EDiJyOxQ3dM3Jkua91LS6p2m66KSttt4qltXYDu+6grQdMImvqSFsBsAb++gHgauhmQ1bp6qmxTWisZl5asf0LVxYDoKXTUc39evyqPDOGMcADgDNwX50IyBm6N1wE++oENJcZG+PK2s76Dd2l410/XfshB+zKkfnJCHgauBdaPONpbvE+tzccjI0+1NEdQSPYDicYC6rKlbWgCgrlHUZmpiIgZeA+kxGwMnSD4xjoLo5ju+RGwM4ENP0SCTsTWQhQgvRd/58flaLG2sSRbojQNRHGI7Bior9Q03BtLXoIYYMmF+IZYiOOSmmkMwF74tDf2YiEn6E/IQMIGv7bReLg172+gb9csS0RuaLREY0rg7ABD8HH+QjYFvo7f5HQLQ3VNqliD0Y+qoaLNXsGsygql5snJiJyRSMTjWt3U5DI5e4EACj453DBNjF2I5vsLmpXj3aStAF+cqYdNe3g0TZN2zzaQdOOHu1G004O7apJZ4d0p0kXh3SrSbcO6aJJezypWTJ5LKk5MnscqRkyewyp+TG7/KhJe+youTE73CgqO8woVofDi2IbOqwoBp7DiaJbHEbULF4cPtT6peKwodaZFocLu7/mN1+mkz+G493k0+fPeZqnQ5aev0yPfw7d9eHPw5lpe/r7cGp62F37/eD1H+3xH8PD0OGgi2efOh2k08Hx5PvnXo9KOR0dzk4PG9udHXUn+ePZ6WGp4unop+8dj+y14MezH987Hh0worOj5vV/h898aJ6O8umTx7NTe73C8RvvV3g9Kq9Hx+p5u8Lr0ZtKPpa6pvOjN83y0/9OR2+ax3LG1wo8fubXozDU6peh7Zb7/mmIgIfVS/+8Xa4Pjb+aD1EwnNu+rNNs23993Pb9ejj/3367OzZ6LlZzslRLrcMTyI8f/weOw3Jf"
local out = {}
local function p(x) out[#out + 1] = tostring(x) end
if game.surfaces.bench then game.delete_surface("bench") rcon.print("old bench deleted; run again to rebuild") return end
local b = game.create_surface("bench")
b.request_to_generate_chunks({0, 0}, 4)
b.force_generate_chunk_requests()
local tiles = {}
for x = -64, 63 do for y = -64, 63 do tiles[#tiles + 1] = {name = "refined-concrete", position = {x, y}} end end
b.set_tiles(tiles)
for _, e in pairs(b.find_entities_filtered{area = {{-64, -64}, {64, 64}}}) do if e.type ~= "character" then e.destroy() end end
b.always_day = true
local inv = game.create_inventory(1)
p("import " .. inv[1].import_stack(BP))
local ghosts = inv[1].build_blueprint{surface = b, force = "player", position = {0, 0}, build_mode = defines.build_mode.forced}
local revived = 0
for _, g in pairs(ghosts) do if g.valid then local _, e = g.revive() if e then revived = revived + 1 end end end
inv.destroy()
p("ghosts " .. #ghosts .. " revived " .. revived)
-- Bench coordinates = captured-world coordinates + (dx, dy). The capture was x 115..158, y -42..-10.
local dx, dy = -136, 25
local D = defines.direction
local function mk(t) t.force = "player" local e = b.create_entity(t) if not e then p("FAILED " .. t.name) end return e end
local function chest(x, y, item)
  local c = mk{name = "infinity-chest", position = {x, y}}
  if item then c.infinity_container_filters = {{name = item, count = 400, mode = "exactly", index = 1}} else c.remove_unfiltered_items = true end
end
-- Input tee one tile west of the input belt (115.5,-29.5). A belt side-loaded from both sides stays straight,
-- so the north loader fills lane 1 and the south loader fills lane 2.
local tx, ty = 114.5 + dx, -29.5 + dy
mk{name = "transport-belt", position = {tx, ty}, direction = D.east}
chest(tx, ty - 3, "iron-plate")
chest(tx, ty + 3, "copper-plate")
mk{name = "loader", position = {tx, ty - 1.5}, direction = D.south, type = "output"}
mk{name = "loader", position = {tx, ty + 1.5}, direction = D.north, type = "output"}
-- Pack sinks: red leaves west at (115.5,-35.5), green at (115.5,-15.5).
chest(112.5 + dx, -35.5 + dy, nil)
chest(112.5 + dx, -15.5 + dy, nil)
mk{name = "loader", position = {114.0 + dx, -35.5 + dy}, direction = D.west, type = "input"}
mk{name = "loader", position = {114.0 + dx, -15.5 + dy}, direction = D.west, type = "input"}
-- The capture rectangle cut off the cable assembler's own feeder, so give it copper directly.
chest(-24.5, -0.5, "copper-plate")
mk{name = "fast-inserter", position = {-23.5, -0.5}, direction = D.west}
b.create_global_electric_network()
local eei = mk{name = "electric-energy-interface", position = {40.5, 40.5}}
eei.power_production = 1e9
eei.electric_buffer_size = 1e10
eei.energy = 1e10
rcon.print(table.concat(out, "\n"))
