local surf = game.surfaces[1]
local n = surf.find_entities_filtered{force="enemy", type="unit", position={-42,-16}, radius=40}
rcon.print("enemies within 40 of (-42,-16): "..#n)
