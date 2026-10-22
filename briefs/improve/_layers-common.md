# The vertical layers of the map (read this for every `layers-*` job)

## The problem
The map is not flat. A street at y = 0 runs under the Yan'an elevated road (y about 10 to 31), under the inner ring (y = 10), the Nanpu bridge (y = 42.5) and the ramps; the tunnel runs at y down to -28 under the river; sky lanes fly above all of it.
Two things can lie at the same x/z and be 5 to 45 m apart in height. Most of the game code was written for a flat map and measures distances in the x/z plane (`Vector2(a.x - b.x, a.z - b.z)`), or with a 3D distance and a radius that is larger than the gap between two decks, and never asks which level a car is on.
The result is bugs you can see: a street car brakes for a car on the deck above it, a checkpoint under a deck is scored by a car driving over it, a cop under a deck busts the player above, the racing line of a rival runs on the street instead of the deck.

## The rule
Two positions are **on the same level** when their heights differ by at most `LEVEL := 3.0` m (use 4.0 m for AI that looks at a car). A check that finds a *neighbour* (car ahead, cop in reach, gate, lane under a point, hiding spot, ...) must ignore everything that is not on the same level, unless the thing is flying (`vehicle.is_airborne()` is true; sky lanes are real) and the check is about flying.
Do not use a bigger radius or a 3D distance as a substitute: a deck is 10 m above the street, a 3D radius of 12 m or 25 m still covers it.

If you need the constant in several files of your folder, put it in ONE place (a `const` in the file where it fits best or a tiny helper in your folder), not a copy in every file. Tuning numbers live in `tuning/` files when the unit has one.

## How you prove a fix (the three-part test)
For every defect you fix you write a test that
1. builds the smallest scene that shows it: two levels (a street at y = 0 and a deck at y = 10), one thing on each, no city (the helpers of your unit's tests show how: `core/stubs/stub_car.tscn` is a frozen-able car, `ai/traffic/tests/traffic_test_road.gd` builds lanes, ...);
2. checks the **wrong-level** case (nothing happens) AND the **same-level** case (the same thing happens as before): a fix that switches the feature off for everybody passes only the first half;
3. is written in a NEW test file named in your brief, `extends Node`, prints `PASS ...` / `FAIL ...` lines, ends with `quit(0)` / `quit(1)`.

The lead runs your test against the **old** code (`tools/mutation_check.py` puts the base version of your source files back for one run). If the test passes on the old code it proves nothing and the job fails. So write the test FIRST, run it, see it fail for the right reason (the wrong-level case), and only then fix.

## What not to do
- Do not change the unit's tuning to hide the problem, and do not delete or loosen an existing test.
- Do not touch folders that are not in "Files you own" (a change needed elsewhere goes under `## Requests` in your status file).
- Do not add a per-frame allocation, a per-frame sort or a per-frame `find_children` to a hot path (the AI ticks are timed by `test_performance`/`test_perf`).
