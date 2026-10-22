# layers-rivals — rivals must not react to cars on another level

## Plan

1. Probe the current behaviour of `RivalAvoid._consider`, `RivalAvoid._avoid_offset` and
   `RivalSpeed._in_wake` with a stub car on the deck and on the street below.
   Proof: `python tools/gd.py test res://ai/rivals/tests/test_layers.gd` prints the probed values.
2. Write the three-part test `game/ai/rivals/tests/test_layers.gd` (same level = the old
   behaviour, other level = nothing happens) and run it BEFORE the fix: the wrong-level cases
   must FAIL.
   Proof: `python tools/gd.py test res://ai/rivals/tests/test_layers.gd` prints FAIL lines.
3. Add the shared level rule (one place, `RivalContext.LEVEL` + `RivalContext.on_my_level` /
   `RivalContext.same_level`) and use it in `RivalAvoid._consider`, the loop of
   `RivalAvoid._avoid_offset` and `RivalSpeed._in_wake`.
   Proof: `python tools/gd.py test res://ai/rivals/tests/test_layers.gd` prints
   `RIVAL LAYER TESTS OK (0 failures)`.
4. Check the folder: `python tools/gd.py check --only=res://ai/rivals/` prints
   `CHECK N files, 0 failed, 0 engine errors`.
5. The test must fail on the old code:
   `python tools/mutation_check.py --test res://ai/rivals/tests/test_layers.gd --files auto`
   prints `MUTATION_CHECK OK`.
6. The rivals test folder must not get worse:
   `python tools/run_tests.py --filter res://ai/rivals/ --jobs 3 --out
   F:/dev/skyrush-out/tmp/layers-rivals/tests --allow-fail
   test_performance,test_race_flow,test_real_route,test_rival_driving` ends with
   `RUN_TESTS_RATCHET OK`.

## Done

- `game/ai/rivals/rival_context.gd`: the shared rule in ONE place —
  `const LEVEL := 4.0`, `static func same_level(y, other_y) -> bool` and
  `static func on_my_level(a: Node3D, b: Node3D) -> bool`.
- `game/ai/rivals/rival_avoid.gd`: `_consider` ignores every car that is not on the level of
  the rival; the loop of `_avoid_offset` does the same.
- `game/ai/rivals/rival_speed.gd`: `_in_wake` gives no wake to a car on another level, so
  `_slipstream` gives no 4 % bonus for a car on the street under the deck.
- `game/ai/rivals/tests/test_layers.gd` (new): the three-part test, 14 checks.
- No tuning changed, no new allocation in the per-tick loops (three `absf` comparisons).

## In progress / next

- Nothing. The job is done; the points under "Requests" are for the lead to decide.

## How to test (exact commands)

- `python tools/gd.py test res://ai/rivals/tests/test_layers.gd`
- `python tools/gd.py check --only=res://ai/rivals/`
- `python tools/mutation_check.py --test res://ai/rivals/tests/test_layers.gd --files auto`
- `python tools/run_tests.py --filter res://ai/rivals/ --jobs 3 --out F:/dev/skyrush-out/tmp/layers-rivals/tests --allow-fail test_performance,test_race_flow,test_real_route,test_rival_driving`

## Evidence (key output lines)

Test BEFORE the fix (the wrong-level halves fail, the same-level halves pass):

```
PASS a car on the same level blocks the rival
PASS the blocker stands 30 m ahead (30.00 in 27.00..33.00)
FAIL a car on the street below is not a blocker
FAIL a car on the street below has no distance
FAIL the player on the street below is not a blocker
PASS the player on the deck is a blocker
PASS the player stands 50 m ahead (50.00 in 47.00..53.00)
avoid: same level 0.000, street below 0.000
PASS a car 15 m ahead on the same level is in the wake
FAIL a car 10 m below is not in the wake
PASS the car on the same level gives the slipstream
FAIL the car on the street below gives no slipstream
RIVAL LAYER TESTS FAILED
```

Test AFTER the fix:

```
CHECK 21 files, 0 failed, 0 engine errors, 0 warnings
RIVAL LAYER TESTS OK (0 failures)
mutating: game/ai/rivals/rival_avoid.gd game/ai/rivals/rival_context.gd game/ai/rivals/rival_speed.gd
MUTATION_CHECK OK: the test fails on the old code of cf2e11125b (5 FAIL lines, first: FAIL a car on the street below is not a blocker)
ok   ai/rivals/tests/test_layers.gd                                 checks=0   fail=0      17s
FAIL ai/rivals/tests/test_performance.gd   (0.35 ms budget, pre-existing: 0.458 ms before the fix, 0.443 ms after it)
FAIL ai/rivals/tests/test_race_flow.gd    (pre-existing, allow list)
FAIL ai/rivals/tests/test_real_route.gd   (pre-existing, no race session, allow list)
FAIL ai/rivals/tests/test_rival_driving.gd (pre-existing, rivals stuck on the real map, allow list)
ok   ai/rivals/tests/test_rubber_band.gd
RUN_TESTS_RATCHET OK (4 failing, all of them on the allow list)
```

## Known issues

- **The distance of check 1 of the brief cannot be used for a traffic car.** `_consider` only
  sees a car of the traffic within `AVOID_DISTANCE` (40 m); the `FOLLOW_DISTANCE` (80 m) is
  for the cars on the racing line. A stub 50 m ahead is ignored by the old code as well, so
  the "below" half of the check would pass for the wrong reason (out of range). The test uses
  30 m for the traffic (inside the 40 m) and 50 m for the player (inside the 80 m), and it
  checks the distance of the blocker in both cases.
- **The sideways avoidance of `RivalAvoid` shifts nothing today, for any geometry.** A car
  that counts for the avoidance stands at most `AVOID_BAND` (2.2 m) beside the rival, and the
  clearance it needs (`AVOID_CLEARANCE`, 2.5 m) is bigger than that, so the free space on the
  blocked side is negative and the shift is clamped to 0. Measured: `avoid: same level 0.000,
  street below 0.000` (before the fix as well). The level filter is in the loop as the brief
  asks, but the test cannot see a difference in the shift; the test asserts the current
  behaviour (exactly 0.0 for the car on the street below) and says so in a comment.
- The four tests that fail in the folder fail for the same reasons as before the change
  (millisecond budget, missing race session, rivals stuck on the real map); the AI of the
  rivals costs 0.443 ms per tick with the fix and 0.458 ms without it (budget 0.35 ms).

## Requests

- **`RivalAvoid._is_slower_ahead` has the same defect and is not one of the three places of
  the brief.** The pass blocker (the other rivals and the player) is measured in the frame of
  the racing line, without a level test: a rival on the Yan'an deck can start a pass for a
  slower car on the Yan'an street under it (the player under the deck is the worst case). The
  brief says "nothing else changes", so I did not touch it — a follow-up job should add the
  level test there (and to `_pass_fits`).
- **`RivalAvoid._avoid_offset` never shifts the rival** (see above): the branch that picks the
  side to move to is inverted, so the rivals do not swerve for the traffic at all. Fixing it
  changes the driving model of the field and is out of the scope of this job.
