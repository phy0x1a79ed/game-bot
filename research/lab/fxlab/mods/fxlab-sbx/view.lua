-- The camera booth and screenshots. Built in T6 (scope fxlab-cam); see CONTRACT.md § sbx.
local M = {remote = {}}

M.on_init = function() storage.view = {} end
M.on_configuration_changed = function() storage.view = storage.view or {} end

return M
