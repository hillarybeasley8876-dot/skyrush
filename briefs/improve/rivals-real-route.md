# Job: the rivals race the real routes (no pile-up at the first corner, no rival stuck on the grid)

Godot job: read `briefs/improve/_godot-common.md` first, then **`status/improve/rivals-start.md`** (the previous job on this folder: what it fixed, every probe it made, the numbers). Your folder is `game/ai/rivals/`.
The previous job made the field leave the grid and race in the sandbox (`test_rival_driving`, `test_start_grid`, `test_race_flow` 13 of 14 checks). This job is about the REAL city and its five real routes.

## The defect (the lead ran `test_real_route.gd` on all four relevant routes; reproduce it first)
Command: `python tools/gd.py test res://ai/rivals/tests/test_real_route.gd -- --timeout=300 --stub=traffic,police,audio,fx,damage,hud,menu --route=<route> --limit=<s>` (about 3 minutes per run; it prints one line per check and
`CONTACT a x b impulse N at (x, y, z)` for every hit between two rivals over 800 N*s; the last line is `REAL ROUTE TESTS OK (<n> failures)` even when n > 0, read n).
 - `bund_sprint` (--limit=120): `FAIL every rival passed cp1 and cp2`: after 120 s three of the five rivals have passed 1 or 2 gates only (`龙柱猎手 2, 陆家嘴之刃 1, 浦江闪电 1`), the two others finished (7 gates). Seven hits of 5,000 to 26,000 N*s
   happen at (-145, 0..1, -388) to (-143, 0, -386): the racing line there runs straight south along the Bund (heading 174 degrees) 40 m before a 90 degree right turn onto Hankou Rd (the line turns from index ~413, z -352, heading 175 -> 262);
   the field arrives in a bunch at about 25 m/s and runs into each other in the braking zone.
 - `lujiazui_ring` (--limit=150): `FAIL every rival is rolling at GO+3 s`: two rivals (外滩幽灵 0.9 m/s, 龙柱猎手 0.8 m/s) have not moved three seconds after GO while the other two (14 m/s) have; plus 3 hits over 800 N*s in the first 10 s, one of 15,029 N*s at (785, 0, -604).
 - `river_loop` (--limit=150) and `elevated_sprint` (--limit=150): the checks pass, but there are hits of 25,000 and 32,000 N*s later in the race (at (1647, 1, 425) and (-1342, 10, 1019)): the test only counts the first 10 s.
Whatever you change must keep `river_loop` and `elevated_sprint` passing and must make `bund_sprint` and `lujiazui_ring` pass.

## What to do
1. Reproduce the four runs and put the numbers into `status/improve/rivals-real-route.md`.
2. Probe, do not guess (a temporary probe that you delete afterwards, like the previous job did): for the cars involved, print per tick their speed, throttle, brake, the target speed, the blocking car and its distance,
   the corner speed of the line ahead, the pass state, the lane offset. Find WHY the field arrives at the corner too fast / all in the same column, and WHY two rivals of the lujiazui_ring grid do not move
   (the grid slot may lie on a lane of another level, off the line, behind a wall; the brake of a car below 0.5 m/s is the reverse gear; the hold of the grid; the marshal).
3. Fix the causes in `game/ai/rivals/` (the speed plan before a corner has to count the cars in front that brake for it too; the personal columns; the start). Do not hide it: no tuning that makes the field slower than the test of
   the sandbox allows (`test_race_flow.gd`: the field is within 15 s, at least 6 passes, 60 % of the corners drifted), no deleting contacts by making the cars ghosts (the car layers stay as they are), no change of a test.
4. Write `tests/test_real_start.gd` (new): on the real world and the route `lujiazui_ring` (and `bund_sprint`), 4 s after GO every rival moves faster than 8 m/s and no rival is rescued by the marshal in the first 20 s.
   It must fail on the old code (run it first!). You may copy the setup of `test_real_route.gd` (it waits for the world with `await Game.world_ready()`).

## Files you own
`game/ai/rivals/` except the existing tests: `tests/test_layers.gd`, `test_performance.gd`, `test_race_flow.gd`, `test_real_route.gd`, `test_rival_driving.gd`, `test_rubber_band.gd`, `test_start_grid.gd` are read-only (the lead's judges).
`test_performance.gd` fails on the original code too (the AI costs 0.45 to 0.59 ms per tick against 0.35): it is not your job, but do not make it worse.

## Acceptance (the runner executes these itself, in order; the real route runs take about 3 minutes each)
1. `python tools/gd.py check --only=res://ai/rivals/` prints `CHECK n files, 0 failed, 0 engine errors`.
2. `bund_sprint`: the real route command above with `--route=bund_sprint --limit=120` prints `REAL ROUTE TESTS OK (0 failures)`.
3. `lujiazui_ring`: the same with `--route=lujiazui_ring --limit=150` prints `REAL ROUTE TESTS OK (0 failures)`.
4. `river_loop` and `elevated_sprint`: the same with `--limit=150` print `REAL ROUTE TESTS OK (0 failures)` (no regression).
5. `python tools/gd.py test res://ai/rivals/tests/test_real_start.gd` prints `REAL START TESTS OK (0 failures)` and `python tools/mutation_check.py --test res://ai/rivals/tests/test_real_start.gd --files auto` prints `MUTATION_CHECK OK`.
6. `python tools/gd.py test res://ai/rivals/tests/test_rival_driving.gd` prints `RIVAL DRIVING TESTS OK (0 failures)`, `test_start_grid.gd` prints `START GRID TESTS OK (0 failures)`.
7. `python tools/gd.py test res://ai/rivals/tests/test_race_flow.gd -- --timeout=300` keeps its 13 passing checks (the lead's judge `tools/fail_lines.py` accepts only the one known FAIL line `no rival hit a rival over 800`).
8. `python tools/run_tests.py --filter res://ai/rivals/ --jobs 2 --out F:/dev/skyrush-out/tmp/rivals-real-route/tests --allow-fail test_performance,test_race_flow,test_real_route` prints `RUN_TESTS_RATCHET OK`.

## Pitfalls
- Making the rivals slow or timid so that nobody ever touches anybody (steps 7 and the judge `test_race_flow` need 6 passes and a close field).
- A fix for the bund_sprint corner that is a special case of that corner (a position, a road id): the rule has to be general (the speed plan, the columns, the gap before a braking zone).
- The real route test is racy on a busy machine (other workers run too): run a failing check twice before you believe it.
