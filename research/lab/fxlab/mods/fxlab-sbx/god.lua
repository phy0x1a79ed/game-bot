-- God-mode calls and the mode switch. Built in T5 (scope fxlab-god); see CONTRACT.md § sbx.
local sbx = require("sbx")
local M = {remote = {}}

M.on_init = function() storage.god = {} end
M.on_configuration_changed = function() storage.god = storage.god or {} end

return M
