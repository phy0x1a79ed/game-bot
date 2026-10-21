--- tool: check
--- kind: call
--- effect: read
--- summary: check a whole build list against stated intent before placing anything: directions, reach, pairing, fluid mixing, power, collisions
--- args: list (entries {name, position = {x, y}, intent, accept = {CODE}, direction}); surface (default nauvis); force (default player); accept (codes allowed on every entry)
--- returns: {ok, entries = {{i, ok, direction, dir, type, position, pick, drop, issues = {{code, msg}}}}, bom, counts, summary} or {error, hint}
--- uses: intent
-- Intents by type: inserter drop = {dx, dy} (+ item); mining-drill output; belt, splitter and loader flow;
-- underground-belt flow + role entry|exit; pipe-to-ground toward; assembler recipe. Build each entry at the
-- returned direction (and type, for an underground belt end).
local I = use("intent")
local a, err = I.prepare(...)
if not a then return err end
local ok, res = pcall(I.check, a.surface, a.force, a.list, {accept = a.accept})
if not ok then
  return {error = "the check failed on this list: " .. tostring(res):sub(1, 200), hint = "check each entry has a name and a position {x, y}"}
end
return res
