-- Dispatcher. Factorio keeps one handler per event per mod, so only this file registers handlers.
-- Each module exports hooks (on_init, on_configuration_changed, on_load, on_tick, nth = {[n] = fn},
-- events = {[defines.events.x] = fn}) and remote verbs (remote = {verb = fn}). See CONTRACT.md § sbx.
local modules = {require("sbx"), require("slice"), require("god"), require("view")}
local sbx = modules[1]
for _, m in ipairs(modules) do
  if m.on_drop then sbx.drop_hooks[#sbx.drop_hooks + 1] = m.on_drop end
end

local function each(hook, ...)
  for _, m in ipairs(modules) do
    if m[hook] then m[hook](...) end
  end
end

script.on_init(function() each("on_init") end)
script.on_configuration_changed(function(data) each("on_configuration_changed", data) end)
script.on_load(function() each("on_load") end)

local ticked = {}
for _, m in ipairs(modules) do
  if m.on_tick then ticked[#ticked + 1] = m.on_tick end
end
if #ticked > 0 then
  script.on_event(defines.events.on_tick, function(ev)
    for i = 1, #ticked do ticked[i](ev) end
  end)
end

local nth = {}
for _, m in ipairs(modules) do
  for n, fn in pairs(m.nth or {}) do
    nth[n] = nth[n] or {}
    table.insert(nth[n], fn)
  end
end
for n, fns in pairs(nth) do
  script.on_nth_tick(n, function(ev)
    for i = 1, #fns do fns[i](ev) end
  end)
end

local handlers = {}
for _, m in ipairs(modules) do
  for id, fn in pairs(m.events or {}) do
    if id == defines.events.on_tick then error("use the on_tick export, not events[on_tick]") end
    handlers[id] = handlers[id] or {}
    table.insert(handlers[id], fn)
  end
end
for id, fns in pairs(handlers) do
  script.on_event(id, function(ev)
    for i = 1, #fns do fns[i](ev) end
  end)
end

-- Every verb takes one args table and returns a table with ok. A raised error becomes
-- {ok = false, error = "lua_error", detail = message}; a verb signals its own failure with sbx.fail.
local verbs = {}
for _, m in ipairs(modules) do
  for name, fn in pairs(m.remote or {}) do
    if verbs[name] then error("sbx verb defined twice: " .. name) end
    verbs[name] = function(args)
      local ok, r = pcall(fn, args or {})
      if not ok then
        if type(r) == "table" and r.sbx_error then return {ok = false, error = r.sbx_error, detail = r.detail} end
        return {ok = false, error = "lua_error", detail = tostring(r)}
      end
      if type(r) ~= "table" then r = {value = r} end
      if r.ok == nil then r.ok = true end
      return r
    end
  end
end
verbs.verbs = function()
  local names = {}
  for name in pairs(verbs) do names[#names + 1] = name end
  table.sort(names)
  return {ok = true, verbs = names}
end
remote.add_interface("sbx", verbs)
