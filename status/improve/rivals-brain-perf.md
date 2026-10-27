# rivals-brain-perf — the brains of the rivals cost half of what they cost now

Goal: `RivalDirector.brain_total_usec` under 0.35 ms per tick (aim 0.28) with the sandbox race
unchanged (4 passes, 2 hard contacts, 17 gates, 0 rescues, 12.4 s spread).

**Result: 0.603 ms → 0.308 ms per tick (-49 %).** The sandbox race drives exactly as before.

## Plan

1. Measure the breakdown of `RivalBrain.tick` (timers around every part) and, inside the three
   biggest parts, the sub-costs. Write both tables into this file.
2. Remove the duplicated work the tables point at (the same line frame / the same relation
   computed several times per tick), keeping every formula bit-identical.
3. Repeat step 2 until the perf test is under 0.35 ms (twice in a row, quiet machine).
4. Remove every timer and print, run the whole acceptance list.

## Done

- The breakdown of the tick (5 rivals, 240 ticks, `Time.get_ticks_usec()` around every part;
  a region costs ~1 us, so the numbers are the raw region times):

| part of `tick` | before (us/tick/rival) | after |
|---|---|---|
| `avoid.update_blocker` | 26 % | 11 |
| `speed_helper.update` | 22 % | 11 |
| `avoid.update` | 12 % | 5 |
| `_steering` | 11 % | 7 |
| `_update_drift` | 10 % | 6 |
| `_update_position` (`line.project`) | 8 % | 6 |
| `_update_road` (the road frame) | part of the 11 % | 3 |
| the rest of the tick (the calls, the frame, the gate) | 11 % | 9 |

  Inside `avoid.update_blocker` (5 cars: 4 rivals + the player) the costs were: the level
  test 0.5, the cast 0.3, the offset of the other car 0.5, **the side of the other car 1.2**,
  the forward distance 0.2, the calls and the checks 1.0.
- What was changed (every change keeps the arithmetic bit-identical):
  - the frame of the line at the place of the car is measured **once per tick** (`RivalFrame`)
    and the helpers read it instead of measuring it again for every car they looked at;
  - the side of a car on the line is the same for every rival of the field: the brain of a
    rival measures it from the frame of its own place (the context keeps the frame of the
    player), and it is only measured for the cars that are in front of the rival;
  - the speed profile of the route is built once per rival and not twice per tick (the profile
    of the line is keyed by a string: 1.9 us per lookup);
  - the highest curvature of the next 30 m is a table lookup and not a scan of 16 samples;
  - the segments of the line are precomputed for the projection;
  - the near list of the rival is read once per tick and not once per helper;
  - the level tests and the wake test are inline (the call costs more than the test);
  - the road frame reuses the places the search of the nearest lane measured, and the middle of
    the road is only computed for the roads of the city (the lanes that know their own offset);
  - the forward axis of the car is read once per tick.
- **The trap**: `Vector2` (and `Vector3`) are single precision in Godot 4. The relation of a car
  is a `Vector2` in the original code, and a rewrite that kept the two numbers in float64
  variables changed the race (4 passes → 2, 12.4 s → 9.6 s). The relation is a `Vector2` again.
  The same trap applies to every value that leaves a `Vector2`/`Vector3`.
- The helpers (`RivalAvoid`, `RivalSpeed`) still work on their own: they measure the frame of
  the line and read the near list themselves when the brain did not give them (the unit tests
  use them directly).

## In progress / next

- nothing (the job is finished)

## How to test (exact commands)

```
python tools/gd.py check --only=res://ai/rivals/
python tools/gd.py test res://ai/rivals/tests/test_performance.gd
python tools/gd.py test res://ai/rivals/tests/test_race_flow.gd -- --timeout=420
python tools/gd.py test res://ai/rivals/tests/test_rival_driving.gd
python tools/gd.py test res://ai/rivals/tests/test_rubber_band.gd
python tools/gd.py test res://ai/rivals/tests/test_start_grid.gd
python tools/gd.py test res://ai/rivals/tests/test_layers.gd
python tools/gd.py test res://ai/rivals/tests/test_real_start.gd -- --timeout=420
python tools/gd.py test res://ai/rivals/tests/test_real_route.gd -- --timeout=420
```

## Evidence (key output lines)

- Before: `PERF the AI of the five rivals costs 0.603 ms per tick` (fails the 0.35 budget).
- After: `PERF the AI of the five rivals costs 0.308 ms per tick` /
  `PASS the AI of the rivals costs less than 0.35 ms per tick (0.308 ms)` (the runs of the
  acceptance measured 0.307, 0.308, 0.309, 0.320, 0.329 ms — the machine runs other jobs and
  the physics without the rivals moves between 0.53 and 0.64 ms).
- `CHECK 24 files, 0 failed, 0 engine errors, 0 warnings`.
- The race is the race of before: `PASS the field is within 15 s (12.4 s)`,
  `the field made at least 6 passes (4)`, `no rival hit a rival over 800 N*s (2)`,
  `PASS every racer counted the gates ([17, 17, 17, 17, 17])`, `PASS no rival needed the marshal (0)`,
  `PASS 60 % of the corners are drifts (126 % of 50)`.
- `RIVAL DRIVING TESTS OK (0 failures)`, `RUBBER BAND TESTS OK (0 failures)`,
  `START GRID TESTS OK (0 failures)`, `RIVAL LAYER TESTS OK (0 failures)`,
  `REAL START TESTS OK (0 failures)`, `REAL ROUTE TESTS OK (0 failures)`.

## Known issues

- `rival_avoid.gd` (527 lines before, 637 now) and `rival_brain.gd` (512 before, 536 now) are
  over the 400 lines of the code rules; they were over before the job. The pass logic of the
  avoid could move into a file of its own (`rival_pass.gd`) in a later job.
- The helpers of the unit keep a reference to the frame of the brain and to the near list of
  the tick; a helper that is used on its own (the unit tests) measures them itself.

## Requests

- none
