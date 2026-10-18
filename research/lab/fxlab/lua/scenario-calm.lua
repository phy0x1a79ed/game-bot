-- scenario-calm.lua: take enemies out of a lab world so one run's outcome follows its build, not its battles.
-- Removes every enemy entity, then stops new ones: peaceful mode, no expansion, no evolution.
local n = 0
for _, s in pairs(game.surfaces) do
  s.peaceful_mode = true
  for _, e in pairs(s.find_entities_filtered{force = "enemy"}) do e.destroy() n = n + 1 end
end
game.map_settings.enemy_expansion.enabled = false
game.map_settings.enemy_evolution.enabled = false
game.forces.enemy.reset_evolution()
rcon.print(n)
