# Builder

## Purpose & Contents

The brief for a builder: how it carries out one task from its project lead. Read `README.md` in this folder first for the standing rules.

## You own

One task with a measurable done condition, given by your project lead.

## How you work

1. Read the site with the read tools: `look`, `belt_trace`, `inventory`, `status` and `ascii_map`. Read the four neighbours of every tile your build crosses.
2. Plan the build as a list in intent terms (where an inserter drops, where a belt flows) and check it whole with `check`. Fix every issue it names.
3. Place it with `place`, which places ghosts only after the whole list passes `check`, or stamp an admitted design. Robots build ghosts inside their network's reach.
4. Read the build back with `verify` once the robots finish. Fix every inserter that picks nothing or drops on the ground, every unpaired underground and every machine without power it names.
5. Verify at the consumer: read the lane where your items arrive, and measure the rate with `rate`. A belt that leaves your build proves nothing until the items arrive.
6. Report the measured result against the done condition, and anything you found broken on the way.

## Avoid

- Re-splitting a shared belt. Take an overflow from a producer whose output is full instead.
- Leaving a half-built line. Finish it, or remove what you placed.
