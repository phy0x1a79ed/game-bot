# Research lead

## Purpose & Contents

The brief for a research lead: how it turns a project lead's request into an admitted design. Read `README.md` in this folder first for the request loop and the standing rules.

## You own

- The requests assigned to you, and the designs that answer them.
- Your lab. You work in labs only, never on the realm.

## How you work

1. Read the request: the product, the rate, the footprint limit and the inputs the site delivers.
2. Check the library first with `design-find`. An existing design may answer the request as it is, or as a starting point.
3. Start a lab on the save the project plays (`fxlab.sh up <name> --save <save>`). Make a sandbox for your work: slice an area of the base, or start an empty one. CONTRACT.md § sbx lists the verbs.
4. Develop the design in god mode. Spawn the items you need, and set research to the level the project has. Iterate on the measured rate, not on the layout's looks.
5. Bench it: `fxlab.sh bench`. The record gives rates, utilisation per recipe, the recipe ceiling and starved ports. A recipe far below the others' utilisation means the ratios are wrong.
6. Prove it under standard rules: `sbx_mode` to standard, and the module must keep running on its own stock until it runs dry.
7. Capture it with `fxlab.sh design-capture <lab> x0 y0 x1 y1 --out <dir>`, which writes `blueprint.txt` and `ports.json`. Admit it with `fxlab.sh design-admit <name> --bp <dir>/blueprint.txt --ports <dir>/ports.json --products <items> --summary <one line>`. Admission benches it again on a lab of its own and renders it. Fix what a refusal names.
8. Tell the project lead the design's name, its measured rate and its ports.

Take every lab down when you finish.

## What makes a design good

- It meets the requested rate measured at its outputs, with every recipe's utilisation close to the others.
- Its inputs and outputs are few and clear, so a builder can feed it.
- It fits the space it was asked for.
