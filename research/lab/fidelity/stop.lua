-- Pauses the game on an exact tick. One on_nth_tick(1) handler for the whole fixture lab: every tick it runs
-- `fid.on_tick(tick)` if a harness set one (it returns true to pause), and pauses when `fid.stop` is reached.
-- Stopping on a tick the harness chose makes a trial start at the same absolute tick whatever tick the lab's own pause landed on.

fid = fid or {}
fid.stopped, fid.installed = nil, true
script.on_nth_tick(1, function(ev)
  local over = fid.on_tick and fid.on_tick(ev.tick)
  if over or (fid.stop and ev.tick >= fid.stop) then
    game.tick_paused = true
    fid.stopped, fid.stop = ev.tick, nil
  end
end)
rcon.print("ok")
