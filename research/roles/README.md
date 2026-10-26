# Crew roles

## Purpose & Contents

This folder holds the brief for each crew role: the project lead, the research lead, the toolsmith and the builder. The chair gives each agent its role file plus a goal. This file states what every role shares: the request loop that connects the roles and the standing rules. Tool and verb details live in their sources, not here: `tool_list` on the target, `research/lab/CONTRACT.md` and `research/lab/fxlab.sh --help`.

## The request loop

1. A project lead owns a production goal, stated as a rate, such as 60 red science per minute with its full supply chain.
2. The project lead looks for a design: `fxlab.sh design-find --item <product> --min-rate <r>`. It stamps one that fits.
3. If nothing fits, the project lead asks a research lead for one. The request names the product, the rate, the space available, and the inputs the site can deliver.
4. The research lead develops the design in a sandbox, benches it and admits it to the library. Admission refuses a design without a trusted bench record, its ports and a render.
5. The project lead's builders stamp the admitted design and verify its measured rate at the consumer.

The chair adds research leads while requests wait and retires them as the library covers more needs.

## Standing rules

- Measure, then claim. A rate counts only when it is measured where the items are consumed.
- Call a tool before writing Lua. When no tool fits, tell the toolsmiths what you needed, then write the Lua.
- Standard play has no cheats. The realm refuses `cheat` tools, free blueprint stamps and teleports. God mode exists only in lab sandboxes.
- Your body on the realm is a drone seat. It walks over anything and reaches 128 tiles, and every other game rule holds. Your Lua on the realm, `exec_lua` and tools alike, reads anything and changes the world only through `act`, your drone's verbs. A script gets your body as `drone`. It has no `player`.
- Decide inside your own scope. Escalate to the chair only a change to a standing rule, work another team must do, or a goal that is too big.
- After a failure, fix the mechanism that caused it, then resume. Report it as information.
- The game never pauses. Keep your thinking short, and act through batched calls.
