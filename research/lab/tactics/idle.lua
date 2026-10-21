-- idle: no assault. Samples the nest's units every 600 ticks, to rate the other tactics against doing nothing.
local ctx = ...
local series = {}
return {
  setup = function() end,
  step = function(tick)
    if (tick - ctx.tick0) % 600 == 0 then
      series[#series + 1] = ctx.surface.count_entities_filtered{force = "enemy", type = "unit", position = ctx.nest,
                                                                radius = ctx.scan_radius}
    end
  end,
  report = function() return {units = series} end,
}
