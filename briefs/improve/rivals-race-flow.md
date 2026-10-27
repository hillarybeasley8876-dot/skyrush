# Job: the rivals pass each other in a race, and do not crash into each other (test_race_flow)

Rival AI (`game/ai/rivals/`). One Godot test drives a whole race on the sandbox loop (about 3 minutes, deterministic: the same
numbers every run at the fixed 120 Hz of the test host). Read `briefs/improve/_godot-common.md` first.

## Goal
    python tools/gd.py test res://ai/rivals/tests/test_race_flow.gd -- --timeout=900

prints today

    FAIL the field made at least 6 passes (4)
    PASS 60 % of the corners are drifts (126 % of 50)
    FAIL no rival hit a rival over 800 N*s (2)
    RACE FLOW TESTS OK (2 failures)

Make it `RACE FLOW TESTS OK (0 failures)` with real racing: a rival that comes up behind a slower car goes by it when there is
room, and two cars side by side keep the space of a car between them.

## How the test counts (read `game/ai/rivals/tests/test_race_flow.gd`, do not change it)
- A pass: two cars swap places in the race order, the swap still holds 3 s later (`SWAP_HOLD`), and the lateral offset of the
  passer changed by at least 2 m (`LATERAL_SWAP`): it went by on the side, it did not just win a drag race on the line.
- A crash: a contact between two rivals with an impulse over 800 N*s (`CONTACT_LIMIT`).
- The other checks (6 racers, the gates, the field within 15 s, the drifts, no marshal rescue) pass today and must stay so.

## Where the passes are decided
`rival_avoid.gd` (dossier 6.2: the target moves to the side, in the frame of the racing line): `_pass_shift`, `_pass_blocker`,
`_is_slower_ahead`, `_pass_side_of`, `_pass_target_of`, with the constants at the top (`PASS_MIN_GAP` 20 m, `PASS_DISTANCE`
60 m, `PASS_CLOSING` 1.5 m/s, `PASS_SHIFT` 6 m, `CORNER_LOOKAHEAD` 40 m, `CORNER_SPEED_LIMIT` 30 m/s, `PASS_MAX_TIME` 10 s,
`PASS_SIDE_BAND` 8 m, ...). The speed of a rival is `rival_speed.gd`, the brain that ties them together `rival_brain.gd`.

## Plan
1. Run the test; then measure, with temporary prints (remove them at the end): every time a rival is within `PASS_DISTANCE`
   of a slower car ahead, which condition refuses the pass (the gap, the closing speed, a corner ahead, no room on the side, the
   time limit) and how often; for every hit over 800 N*s: the two cars, the time, their speeds, their lateral offsets, and
   whether a pass or an avoidance was under way. Write the counts into `status/improve/rivals-race-flow.md`.
2. Change what the measurement shows (a condition that refuses passes that have room; a pass that cuts back in too early; two
   cars that steer into the same spot); re-run; repeat.
3. Run every acceptance command; numbers before / after into the status file.

## Files you own
`game/ai/rivals/rival_avoid.gd`, `game/ai/rivals/rival_brain.gd`, `game/ai/rivals/rival_speed.gd`, and
`game/ai/rivals/rival_pass.gd` (a new file, if you need one: preload it, no `class_name`). Everything else is read-only (the
tests, `rival_line.gd`, `rival_context.gd`, the vehicle, the modes, the sandbox).

`rival_avoid.gd` has 637 lines today: do not shorten its comments or docstrings to meet the 400-line rule; put new code into
`rival_pass.gd` and keep the text of the existing files.

## Acceptance (the runner executes these itself, in order)
1. `python tools/gd.py test res://ai/rivals/tests/test_race_flow.gd -- --timeout=900` prints `RACE FLOW TESTS OK (0 failures)`.
2. `python tools/gd.py test res://ai/rivals/tests/test_rival_driving.gd -- --timeout=900` prints `RIVAL DRIVING TESTS OK (0 failures)`.
3. `python tools/gd.py test res://ai/rivals/tests/test_start_grid.gd -- --timeout=900` prints `START GRID TESTS OK (0 failures)`.
4. `python tools/gd.py test res://ai/rivals/tests/test_rubber_band.gd -- --timeout=900` prints `RUBBER BAND TESTS OK (0 failures)`.
5. `python tools/gd.py test res://ai/rivals/tests/test_real_route.gd -- --timeout=900` prints `REAL ROUTE TESTS OK (0 failures)` (a race on the
   real map: the passes must not make the rivals crash there).

## Pitfalls
- Do not make the rivals weave to collect lateral changes, and do not slow the leaders down to be passed: the lead looks at the
  race (the order over time, the lateral offsets) and rejects passes that are not overtakes.
- The race is deterministic: if a change gives 6 passes in one run, it gives 6 in every run. A change of a constant that only
  moves the numbers by one is luck on this loop; find the reason a pass does not happen.
- Keep the cost of the brain: `game/ai/rivals/tests/test_performance.gd` measures it (it is noisy on a busy machine; print its
  numbers before and after into the status file; the lead re-measures on a quiet machine).
- Temporary prints out before you finish; static types everywhere (GDScript), tabs, LF.
