# Job: the brains of the rivals cost half of what they cost now, and they drive exactly as well

Godot unit `game/ai/rivals/` (typed GDScript). Read `briefs/improve/_godot-common.md` first. This is a performance job: the
behaviour of the rivals must not change.

## Goal
`res://ai/rivals/tests/test_performance.gd` runs the sandbox race with five rivals and measures the time the brains of the five
rivals take per physics tick (`RivalDirector.brain_total_usec`, summed over 240 ticks). The budget is 0.35 ms per tick. Today it is
**0.56-0.70 ms** (0.557 in a suite run, 0.631 and 0.700 alone on a busy machine). Bring it under 0.35 ms with a margin (aim for
0.28 ms on a quiet machine: the machine runs other jobs while your acceptance runs) **without changing how the rivals drive**.

## Evidence: where the time goes (measured, 5 rivals, the sandbox race of test_performance)
The lead timed the parts of `RivalBrain.tick` (`rival_brain.gd`) with `Time.get_ticks_usec()` around each call:

| part of `tick` | share |
|---|---|
| `avoid.update_blocker(...)` (`rival_avoid.gd`: `_consider` -> `_relation` for every near car and the player) | 26 % |
| `speed_helper.update(...)` (`rival_speed.gd`) | 22 % |
| `avoid.update(...)` (the pass logic) | 12 % |
| `_steering` / `road.steering` | 11 % |
| `_update_drift` | 10 % |
| `_update_position` (`line.project`) | 8 % |
| `_update_road`, `road.update`, lanes, mistakes, nitro, gates | 11 % together |

Reproduce this table yourself first (step 1 of the plan): put timers around the same calls, run the test, write the numbers into
your status file. Then go one level deeper inside the three biggest parts before you change anything.

## What usually costs time in GDScript (look for these, measure, do not guess)
- The same expensive query made several times per tick: projecting a car onto the racing line (`line.project`,
  `curve.get_closest_offset`, `sample_baked`, `point_at`, `right_at`), the relation of the same car to the rival (`_relation`) computed in
  `update_blocker` and again in `update`, the curvature ahead (`max_curvature_ahead`) recomputed by several helpers. Compute it once per
  tick and pass it on, or cache it on the rival for the tick.
- Work for cars that cannot matter: a near car far behind or far to the side can be rejected with a cheap distance check before any
  projection.
- Allocations in the tick: new Arrays, Dictionaries, PackedArrays, string building, `get_nodes_in_group`, `find_children`.
- Untyped code: `Variant` locals and untyped arrays are slower than typed ones.

## What you must NOT do
- Do not think less often: no change of `FAR_HZ`, `FAR_DISTANCE`, of how often a rival thinks, or of the near/traffic refresh
  rates of `rival_director.gd` (`NEAR_REFRESH`, `TRAFFIC_REFRESH`). The comment at the top of `rival_director.gd` says why: at 60 Hz the
  field of the sandbox race overtook once instead of five times.
- Do not change a tuning constant, a gain, a distance or a threshold of the driving.
- Do not change a test (`game/ai/rivals/tests/` is read-only for you) or the way the brain time is counted (`brain_usec`,
  `brain_total_usec`): moving work out of the counted part does not make it cheaper.
- Leave no timer or print in the code when you finish.

## The behaviour does not change (this is checked)
The sandbox race of `test_race_flow.gd` is deterministic: three runs on the current code gave the same numbers every time —
`the field made at least 6 passes (4)`, `no rival hit a rival over 800 N*s (2)`, `the field is within 15 s (12.4 s)`, 17 gates for every
racer, 0 marshal rescues. A change that only makes the same computation cheaper gives the same numbers. If your numbers move, find out
why before you go on (a cached value that is one tick old, a projection with a different window): the acceptance allows no fewer
passes and no more hard contacts than today.

## Files you own
`game/ai/rivals/*.gd` (not the tests). Everything else is read-only, `game/ai/rivals/tests/` included.

## Plan
1. Measure the breakdown above (timers around the parts of `tick`), then inside the three biggest parts; write both tables into
   `status/improve/rivals-brain-perf.md`.
2. Fix the biggest cost, re-run `test_performance.gd` and `test_race_flow.gd`; write the numbers into the status file after every step.
3. Repeat until the brains cost under 0.35 ms per tick with a margin.
4. Remove your timers, run every acceptance command below.

## Acceptance (the runner executes these itself, in order)
1. `python tools/gd.py check --only=res://ai/rivals/` prints `CHECK n files, 0 failed, 0 engine errors`.
2. `python tools/gd.py test res://ai/rivals/tests/test_performance.gd` prints `PASS the AI of the rivals costs less than 0.35 ms per tick`.
3. `python tools/gd.py test res://ai/rivals/tests/test_race_flow.gd -- --timeout=420` prints `PASS the race started`,
   `PASS the results hold 6 racers (6)`, `PASS every racer counted the gates`, `PASS no rival needed the marshal (0)`,
   `PASS the field is within 15 s`, and neither `at least 6 passes (0..3)` nor more than 2 hard contacts (`over 800 N*s (3)` or more).
4. `test_rival_driving.gd`, `test_rubber_band.gd`, `test_start_grid.gd`, `test_layers.gd` each print `... TESTS OK (0 failures)`.
5. `test_real_start.gd` and `test_real_route.gd` (`-- --timeout=420`, the real city, about 90 s each) each print `... TESTS OK (0 failures)`.

## Pitfalls
- The tests print `... TESTS OK (n failures)` even when n > 0: read the number.
- A timing measured once on a busy machine can be 30 % off: run `test_performance.gd` twice before you trust a number.
- `rival_line.gd` serves the whole field (one racing line): a cache in it must not mix up the cars.
