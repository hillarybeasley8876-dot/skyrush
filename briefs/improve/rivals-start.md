# Job: the rivals must drive away from the start grid (three of the five get "stuck" at the start of every race)

Godot GDScript, unit `game/ai/rivals/`. Read `briefs/improve/_godot-common.md` first.

## Goal
In every race three of the five rivals - the ones on the back rows of the grid - are picked up by the marshal as "stuck" within the first seconds, and a race can fail to finish at all. Find the cause and fix it, so that every rival leaves the grid by itself and the race runs through. Two existing tests are the judges and you may not change them: `game/ai/rivals/tests/test_rival_driving.gd` and `game/ai/rivals/tests/test_race_flow.gd`.

## Evidence (run it yourself first)
`python tools/gd.py test res://ai/rivals/tests/test_rival_driving.gd` prints

    step 0: 浦江闪电 18m/24m/s 外滩幽灵 13m/24m/s 龙柱猎手 -28m/10m/s 霓虹小燕 -32m/11m/s 陆家嘴之刃 -36m/11m/s
    WARNING: [rivals] 龙柱猎手 was rescued (stuck): v=16.2 blk=inf@inf round=false road=false travel=10.8
    WARNING: [rivals] 霓虹小燕 was rescued (stuck): v=15.7 blk=inf@inf round=false road=false travel=10.1
    WARNING: [rivals] 陆家嘴之刃 was rescued (stuck): v=0.0 blk=inf@inf round=false road=false travel=0.0
    FAIL rival 龙柱猎手 is stuck at -40.4 m (speed 8.0)
    ...

(the progress of a rival is a distance along its racing line; the back rows of the grid stand BEHIND the start of the line, at negative distances: -28, -32, -36 m).
`python tools/gd.py test res://ai/rivals/tests/test_race_flow.gd` prints `TEST TIMEOUT after 120 s`: the race never finishes, with `rescued (stuck): v=6.7 ... travel=11.1` and one rival `v=0.0 travel=0.1` rescued again and again.
Both are in the sandbox city (the small test route), so it is not a problem of the real map.

## What the marshal does (read `game/ai/rivals/rival_marshal.gd`)
`check(brain, delta, car, ctx)`: every `WATCHDOG_TIME := 4.0` s it compares `brain.distance - _watch_start` with `WATCHDOG_TRAVEL := 15.0`; a rival that covered less is "stuck" and `rescue(...)` puts it back on the line 6 m ahead at 8 m/s. `brain.distance` comes from the projection of the car on the racing line (`rival_brain.gd`, `rival_line.gd`).

## Hypotheses to verify with probes (do not assume; print numbers into your status file)
1. **The projection saturates behind the start of the line.** A car that stands 36 m behind the first point of the line has `brain.distance == 0` (or a clamped value) however it moves, so a rival that really drives 16 m/s for 4 s has "travelled" 0 m and is rescued. If this is the cause, extend the line backwards (extrapolate the first segment: negative distances), or measure the watchdog travel with the car's real path length, or do not run the watchdog while `brain.distance <= 0` and the car moves. Choose the fix that is right for the other uses of `distance` (rubber band, positions, standings): read `rival_brain.gd`, `rival_line.gd`, `rival_director.gd` (`travelled`).
2. **A rival that has `v = 0.0` and `travel = 0.1` is not driving at all**: its throttle is 0 or it is held. Find out why (the grid release flag `on_grid`, the target speed behind the start of the line - a corner speed table that returns 0 for a negative offset, the avoid logic, the start-line speed limit). That one is a real bug whatever happens to the watchdog.
3. A rescue puts the car "never behind a gate it has already passed"; a rival rescued from -36 m is put at +6 m: it skips the first 40 m of the race. That is a visible cheat; after the fix a rival on the back row must not be rescued at all in a normal start.

## What to build
The smallest honest fix of the causes you find, in `game/ai/rivals/`. Keep the watchdog for cars that really are stuck (the other rivals tests, `test_rubber_band.gd`, prove that the marshal still works). No change of the tuning to make the tests pass (`WATCHDOG_TRAVEL`, the time window), no change of the grid slots.

## Files you own
`game/ai/rivals/` (the tests in it are read-only). You may add ONE new test file `game/ai/rivals/tests/test_start_grid.gd` that checks the cause you found in isolation (for instance: a rival behind the start of the line with a speed of 16 m/s has a growing distance, and the marshal does not rescue it in 6 s); it must fail on the old code.

## Acceptance (the runner executes these itself)
1. `python tools/gd.py check --only=res://ai/rivals/` prints `CHECK N files, 0 failed, 0 engine errors`.
2. `python tools/gd.py test res://ai/rivals/tests/test_rival_driving.gd` prints `RIVAL DRIVING TESTS OK`.
3. `python tools/gd.py test res://ai/rivals/tests/test_race_flow.gd` prints `RACE FLOW TESTS OK`.
4. `python tools/run_tests.py --filter res://ai/rivals/ --jobs 2 --out F:/dev/skyrush-out/tmp/rivals-start/tests --allow-fail test_performance,test_real_route` ends with `RUN_TESTS_RATCHET OK` (`test_performance` checks a millisecond budget that a busy machine fails; `test_real_route` runs the real city and is another problem).

## Pitfalls
- Raising `WATCHDOG_TRAVEL`/`WATCHDOG_TIME` or switching the watchdog off for the first 10 seconds: that hides the symptom.
- Editing the two judge tests.
- A fix that makes the back rows start faster than the front rows (rubber band is handled elsewhere).
