# Assault tactics

## Purpose & Contents

This file states the interface of a tactic: the Lua file that `fxlab.assault` drives against a nest. It holds the contract only. Each tactic's own header comment lists its parameters.

## Interface

A tactic is `research/lab/tactics/<name>.lua`. It is a Lua chunk that starts with `local ctx = ...` and returns a table:

- `setup()`: called once, at the start tick `ctx.tick0`.
- `step(tick)`: called every 5 ticks after that, with the absolute tick. A truthy return means the tactic gives up.
- `report()` (optional): returns a plain table that lands in the trial record as `extra`.

The driver ends a trial when no spawner and no worm stands within 40 tiles of the nest, when `max_ticks` have passed, or when `step` returns true.

## ctx

- `box`, `surface`, `force`: the sandbox name, the surface and the name of the force the tactic plays. Create every entity with `force = ctx.force`.
- `nest = {x, y}`, `params`, `tick0`, `clear_radius` (40), `scan_radius` (70).
- `statics(radius)`: live enemy spawners and worms around the nest.
- `give(entity, name, count)`: items into an entity. A character goes through the god `items` verb, which also fills its gun, ammo and armor slots; a turret takes a plain insert, because the verb cannot address it. Returns how many fitted.
- `place(name, position, direction)`: `create_entity` for `ctx.force`.
- `body(at, {invulnerable, reach})`: a character with no client, from the god `body` verb. It is destructible unless `invulnerable` is true.
- `book(name, count)`: record items that came from nowhere else, such as grid equipment or fluid.

## Rules

- Take every item through `give` or `book`. The bench computes spend as items booked minus items still held by entities the tactic touched, so an item created by other means counts as free.
- Keep all inputs on the 5-tick step. Use no `math.random`. A trial must repeat exactly when it starts on the same tick.
- Register no event handlers. The driver owns them.
- A body without a client walks (`walking_state`), shoots (`shooting_state`), drives (`set_driver` and `riding_state`) and throws capsules (`create_entity` of the capsule projectile with `source`, `target` and `speed`). It has no cursor, so `use_from_cursor` does not exist.
