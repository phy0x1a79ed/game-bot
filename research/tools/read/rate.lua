--- tool: rate
--- kind: call
--- effect: read
--- summary: items (or fluids) made and used per minute, averaged over the last 1, 10 and 60 minutes, for a force on a surface
--- args: items (a name or a list of up to 100 item or fluid names); surface (default nauvis), force (default player)
--- returns: {windows = {1, 10, 60}, rates = {name = {made = {m1, m10, m60}, used = {m1, m10, m60}}}}, per minute; {error, hint} on an unknown name
--- uses: rd
local rd = use("rd")
local a = ...
local c, err = rd.ctx(a, {bare = true, extra = {"items"}})
if not c then return err end

local names = a.items
if type(names) == "string" then names = {names} end
if type(names) ~= "table" or #names == 0 then
  return rd.fail("items must be an item name or a list of names", "for example items = {\"iron-plate\", \"copper-plate\"}")
end
if #names > 100 then return rd.fail("at most 100 items per call", "split the list") end
for _, n in ipairs(names) do
  if type(n) ~= "string" or not (prototypes.item[n] or prototypes.fluid[n]) then
    local _, e = rd.nameset({tostring(n)}, "item", "items")
    return e
  end
end

local P = defines.flow_precision_index
local WINDOWS = {P.one_minute, P.ten_minutes, P.one_hour}
local items, fluids = c.f.get_item_production_statistics(c.s), c.f.get_fluid_production_statistics(c.s)

local rates = {}
for _, n in ipairs(names) do
  local st = prototypes.item[n] and items or fluids
  local made, used = {}, {}
  for i, p in ipairs(WINDOWS) do
    made[i] = rd.r2(st.get_flow_count{name = n, category = "input", precision_index = p, count = false})
    used[i] = rd.r2(st.get_flow_count{name = n, category = "output", precision_index = p, count = false})
  end
  rates[n] = {made = made, used = used}
end
return {windows = {1, 10, 60}, rates = rates}
