-- ops-audit-ratio: READ-ONLY. One line per assembling-machine: x|y|name|recipe|status|crafting_speed|products_finished|feeders. feeders = per inserter dropping into it: source kind (AM recipe:status, belt, chest, furnace, other). Run twice >=120 s apart; rate/min = delta products_finished / delta ticks * 3600 (join in shell).
local ST = {} for k,v in pairs(defines.entity_status) do ST[v]=k end
local s = game.surfaces[1]
local out = {}
for _, a in pairs(s.find_entities_filtered{force="player", type="assembling-machine"}) do
  local r = a.get_recipe()
  local fe = {}
  local p = a.position
  for _, i in pairs(s.find_entities_filtered{area={{p.x-3.5,p.y-3.5},{p.x+3.5,p.y+3.5}}, type="inserter", force="player"}) do
    if i.drop_target == a then
      local src = i.pickup_target
      local k = "none"
      if src then
        if src.type == "assembling-machine" then
          local sr = src.get_recipe()
          k = "AM:"..(sr and sr.name or "norecipe")..":"..(ST[src.status] or "?")
        elseif src.type == "container" then
          local inv = src.get_inventory(defines.inventory.chest)
          k = "chest"..((inv and inv.is_full()) and "(full)" or "")
        elseif src.type == "furnace" then k = "furnace:"..(ST[src.status] or "?")
        elseif src.type:find("belt") or src.type == "splitter" then k = "belt"
        else k = src.type end
      else
        local b = s.find_entities_filtered{position=i.pickup_position, radius=0.3, type={"transport-belt","underground-belt","splitter"}}
        if #b > 0 then k = "belt" end
      end
      fe[#fe+1] = k
    end
  end
  out[#out+1] = string.format("%.1f|%.1f|%s|%s|%s|%.2f|%d|%s", p.x, p.y, a.name, r and r.name or "-", ST[a.status] or "?", a.crafting_speed, a.products_finished, table.concat(fe, ","))
end
rcon.print("TICK "..game.tick.." N "..#out)
rcon.print(table.concat(out, "\n"))
