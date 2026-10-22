# Job: the rolling box must really bust a slow player twice as fast (police pursuit)

Read `briefs/improve/_godot-common.md` first (how to run tests, rules, the loop). The unit is `police` (`game/ai/police/`).

## Goal
The design (`ref/gameplay/DOSSIER.md` section 6.3, summarised in `game/ai/police/tests/test_box.gd`): the front unit overtakes the player and holds 9 m in front, the two side units squeeze from both sides.
A player who is **boxed and slower than 40 km/h** is busted **twice as fast** (the busted meter fills at 2/3 per second instead of 1/3).
Today the box forms but the meter does not move at all.

## Evidence
`python tools/gd.py test res://ai/police/tests/test_box.gd`: six checks pass (units on the road, box forms and holds, front unit ahead, side units on both sides), then
`FAIL the busted meter fills twice as fast when the player is boxed (0.00 in 1 s)` (needs more than 0.5). The test is your oracle: it is **read-only** for you.
Read it from `_check_busted`: the player drives at 30 km/h inside the box for 4 s, the test sets `pursuit.busted = 0.0`, drives 1 s more and expects the meter above 0.5.

## Where the rule lives
`game/ai/police/police_pursuit.gd`, function `update_busted(delta, player, units)` (read it fully, about 40 lines) and its caller in `police_director.gd` (around line 169). Constants at the top:
`BUST_SPEED` 15 km/h, `BUST_RANGE` 12 m, `BUST_FILL` 1/3 per s, `BUST_BOX_SPEED` 40 km/h, `BUST_BOX_TIME` 2 s.
The logic: units within `BUST_RANGE` count (`close`); `boxing` is true when one of them has `unit.state == PoliceCar.State.BOX`; `box_time` grows while `boxing` and the player is slower than 40 km/h;
`rate` is `BUST_FILL` below 15 km/h, `2 * BUST_FILL` once `box_time >= 2`, else 0; with `close < 1` or `rate <= 0` the meter **drains**.
Other candidates in the same path: `is_over()` (the meter drains and returns when the pursuit state is none/escaped/busted), `player_flying or player.is_airborne()`.

## Hypotheses to test (print values, do not guess)
1. The units that form the box are in a different `PoliceCar.State` than `BOX` (the geometry the test measures is not the state the rule reads), so `boxing` stays false and `rate` is 0 at 30 km/h.
2. `box_time` never reaches 2 s because `boxing` flickers (the side units change places), and the fade (`box_time - delta * BUST_DRAIN`) eats it.
3. The pursuit is not in a state where `update_busted` runs at all in this test setup (`is_over()`), or the director does not call it in this phase.
4. A unit counts as `close` only within 12 m of the player: check the actual distances in the test.
Find which one is true with a probe (temporary `print`s, or a small new test), write the numbers into your status file, then fix the cause: the state assignment of the boxing units, the way the box is recognised, or the bookkeeping.
Do not change `BUST_FILL`, `BUST_RANGE` or the test.

## Files you own
`game/ai/police/` (everything in it) **except** the read-only oracle `game/ai/police/tests/test_box.gd` and the other existing files under `game/ai/police/tests/` (you may add NEW test files there named `test_box_*.gd`).

## Plan
1. Run the oracle and the whole police test folder to see the baseline (only `test_box.gd` fails today).
2. Probe, find the cause, write it down. 3. Fix. 4. Run the oracle, then the folder, then `gd.py check --only=res://ai/police/`. 5. Add one new test case file of your own for a boxed player at 60 km/h (not doubled: below 40 only) and for a box that breaks up and re-forms (the time fades, it does not reset). 6. Report.

## Acceptance (the runner executes these itself, in order)
1. `python tools/gd.py check --only=res://ai/police/` prints `CHECK ... 0 failed, 0 engine errors`.
2. `python tools/gd.py test res://ai/police/tests/test_box.gd` prints `PASS the busted meter fills twice as fast` and exits 0.
3. `python tools/run_tests.py --filter res://ai/police/ --jobs 3 --out F:/dev/skyrush-out/tmp/police-boxing/tests` ends with `, 0 failed or timed out`.

## Pitfalls
- Making the meter fill unconditionally while any unit is near: the rule is "boxed AND slower than 40 km/h"; the doubling must not apply to a free player at 60 km/h.
- Setting `box_time` high artificially or forcing the units' state in the director to satisfy this one test.
- Touching `police_test_hooks.gd` semantics the other tests rely on (run the whole folder).
