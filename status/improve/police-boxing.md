# police-boxing — the rolling box must really bust a slow player twice as fast

## Plan
1. Baseline: run the oracle and the police folder. `python tools/gd.py test res://ai/police/tests/test_box.gd`
   → 6 PASS, 1 FAIL (the busted meter 0.00 in 1 s).
2. Probe: a temporary `game/ai/police/tests/test_box_probe.gd` prints the numbers of the pursuit
   (state, speed, meter, box_time, the units in the frame of the player) every 0.5 s.
3. Fix the cause in `game/ai/police/` (no change to BUST_FILL / BUST_RANGE / the oracle).
4. Verify: the oracle, the folder, `gd.py check --only=res://ai/police/`.
5. A new test `game/ai/police/tests/test_box_rules.gd`: a boxed player at 60 km/h is not doubled,
   a box that breaks up fades (the time does not reset) and forms again from the time that is left.
6. Report.

## Done
- The cause is found and fixed; the oracle and the new test pass; the folder passes.
- Files changed: `police_tactics.gd`, `police_driver.gd`, `police_car.gd`, `police_car_roles.gd`,
  `police_pursuit.gd`; new test `tests/test_box_rules.gd`.

## The cause (the numbers of the probe)
The probe prints `state/speed/busted/box_time` and per unit `state/rel.x/rel.z/speed`
(rel.x = to the right of the player, rel.z = behind him).

* The units are in `PoliceCar.State.BOX` (4) almost all the time → hypothesis 1 of the brief is FALSE.
* The pursuit is in `chase` and `update_busted` runs every tick → hypothesis 3 is FALSE.
* In the last second the oracle measures, **every unit is 12-20 m away**:
```
meter busted=0.000 box_time=1.74 front=4/-1.3/-14.6/5.2 left=4/-11.7/-11.4/13.7 right=4/1.2/-20.0/13.7
```
  → `close` (the units within BUST_RANGE = 12 m) is 0 → the meter DRAINS at 1/s → **hypothesis 4 is TRUE**.

Why the units leave the player when he brakes (the player brakes at ~16 m/s², the test presses the
brake key):

1. A police car may only use 0.6 of its brake (`PoliceDriver.BRAKE_MAX` = 9.6 m/s²), so a unit
   that matches the speed of the player sails past him when he brakes hard.
2. The speed of a side unit was the length of the error to its slot: a unit **in front** of its slot
   got "speed of the player + 8 m/s" and drove even further away. Its target (the slot) was then
   behind it, the pure pursuit turned it around and it swerved away (rel.x -2.4 → -11.7).
3. The front unit merged onto the line of the player only 4 m in front of him: the pure pursuit
   swung it across the player, it hit him (11 contacts) and it left the road.
   The box hit its own front unit.

## The fix
* `police_tactics.gd`
  * The speed of a side unit follows the **signed** error to its slot: behind the slot it catches
    up, in front of the slot it slows down and lets the player catch him up.
  * The target of a side unit never falls behind the unit (`BOX_TARGET_CLEARANCE`): a unit that
    overshot the player keeps driving forward instead of turning around.
  * The slot of the side units is 1 m behind the player (`BOX_BACK` = 1.0, the dossier: 0-2 m).
  * The front unit merges on the way to the gap it holds (`BOX_MERGE_START` = 5.5 m instead of
    4 m) and in a lane of 3.5 m (`BOX_OVERTAKE_OFFSET`), so it does not swing across the player.
* `police_driver.gd` / `police_car.gd` / `police_car_roles.gd`
  * The units of the box may use the whole brake (`PoliceDriver.BRAKE_FULL`): they have to follow
    a player who brakes hard, or the box breaks up when he slows down. The other roles keep the
    gentle brake (a police car that brakes hard in front of the player is a wall).
  * The front unit gets the cross-track term of the steering while it merges (`box_line_steer`): the
    pure pursuit alone swings across the player.
  * `steer_bias` is cleared when a unit changes its state (it belongs to the state that uses it).
* `police_pursuit.gd`
  * The doubled rate needs the box **and** a player under 40 km/h: before, the meter filled at
    2/3 per second for a player who had sped up to 60 km/h (found by the new test).

## In progress / next
- Nothing open. The report is the last step.

## How to test (exact commands)
- `python tools/gd.py test res://ai/police/tests/test_box.gd` (the oracle, read-only)
- `python tools/gd.py test res://ai/police/tests/test_box_rules.gd` (the new test)
- `python tools/gd.py check --only=res://ai/police/`
- `python tools/run_tests.py --filter res://ai/police/ --jobs 3 --out F:/dev/skyrush-out/tmp/police-boxing/tests`

## Evidence (key output lines)
- The oracle (after the fix): 7 PASS, `POLICE TESTS OK (7 checks, 0 failures, 0 engine errors of the police code)`,
  the last one `PASS the busted meter fills twice as fast when the player is boxed (0.67 in 1 s)`.
- The new test (after the fix): 6 PASS, `POLICE TESTS OK (6 checks, 0 failures, 0 engine errors of the police code)`.
- The new test on the **unfixed** code (the files of HEAD): 3 FAIL
  (`FAIL the busted meter fills twice as fast (0.00 in 1 s)`, `FAIL the box holds while the player is slow (1.16 s)`,
  `FAIL a boxed player at 60 km/h is not busted (0.33)`) → the test can fail, and it fails for the bug.
- `python tools/gd.py check --only=res://ai/police/` → `CHECK 62 files, 0 failed, 0 engine errors, 0 warnings`.
- The folder: `17 tests, 17 passed, 0 failed or timed out` (a clean run; see Known issues for the
  exit code 4294967295 that hits a random test now and then).

## Known issues
- `tools/gd.py` / `tools/run_tests.py`: a test now and then ends with the exit code 4294967295 (-1)
  although its log says `POLICE TESTS OK` (the Godot process dies while it shuts down). It hits
  random tests (1-3 of 17 per run) and it happens on the untouched baseline as well
  (the baseline run failed `test_brake_probe.gd` the same way), so it is not caused by this job.
  It can make the third acceptance command flaky.
- The player cannot accelerate away from the box: he rear-ends the front unit of the box, which
  drives slower than him. This is the same before and after the fix (the probe shows it in both).

## Requests
- (none)
