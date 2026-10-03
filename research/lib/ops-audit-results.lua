-- ops-audit-results: READ-ONLY. Verification reads for audited RESULT lines and previous-audit items (audit-0350 target list). Prints: east coal field census (drills, poles, belts, turrets with ammo, ghosts), named turrets, named poles, products_finished of the piercing and steel machines (rate = delta over >=120 s between two runs), lab statuses and the current research. Run twice >=120 s apart for rates.
local ST = {} for k,v in pairs(defines.entity_status) do ST[v]=k end
local s = game.surfaces[1]
local f = game.forces.player
rcon.print("TICK "..game.tick)
local box = {{338,-170},{374,-128}}
local cnt, st = {}, {}
for _, e in pairs(s.find_entities_filtered{force="player", area=box}) do
  local k = e.name
  cnt[k] = (cnt[k] or 0) + 1
  if e.type=="mining-drill" then local n=ST[e.status] or "?"; st[n]=(st[n] or 0)+1 end
end
local l = {} for k,v in pairs(cnt) do l[#l+1]=k.."="..v end table.sort(l)
rcon.print("COALFIELD "..table.concat(l,","))
l = {} for k,v in pairs(st) do l[#l+1]=k.."="..v end table.sort(l)
rcon.print("COALFIELD drills "..table.concat(l,","))
for _, e in pairs(s.find_entities_filtered{force="player", type="ammo-turret", area=box}) do
  rcon.print(string.format("TURRET (%.1f,%.1f) ammo=%d hp=%d", e.position.x, e.position.y, e.get_inventory(defines.inventory.turret_ammo).get_item_count(), e.health))
end
for _, e in pairs(s.find_entities_filtered{force="player", type="electric-pole", area=box}) do
  rcon.print(string.format("POLE (%.1f,%.1f) %s net=%s", e.position.x, e.position.y, e.name, tostring(e.electric_network_id)))
end
local g = {} for _, e in pairs(s.find_entities_filtered{force="player", name="entity-ghost", area=box}) do g[e.ghost_name]=(g[e.ghost_name] or 0)+1 end
l = {} for k,v in pairs(g) do l[#l+1]=k.."="..v end table.sort(l)
rcon.print("COALFIELD ghosts "..table.concat(l,","))
