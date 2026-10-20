-- Slicing and reset. Built in T4 (scope fxlab-slice); see CONTRACT.md § sbx for the verbs it exports.
local sbx = require("sbx")
local M = {remote = {}}

M.on_init = function() storage.slice = {} end
M.on_configuration_changed = function() storage.slice = storage.slice or {} end

return M
