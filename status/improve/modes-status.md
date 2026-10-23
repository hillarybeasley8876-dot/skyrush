# modes-status — the modes tell the HUD what is going on (Events.mode_status)

## Plan
1. Read SPEC/CONTRACTS, `briefs/improve/_godot-common.md`, the brief and the modes unit
   (`free_session.gd`, `race_session.gd`, `pursuit_session.gd`, `mode_director.gd`,
   `race_results.gd`, `police_link.gd`) and the existing tests. [done]
2. Write `game/modes/tests/test_status.gd` (4 groups: free, race, pursuit, none) and run it on
   the OLD code: every check must FAIL with a FAIL line (no crash) —
   `python tools/gd.py test res://modes/tests/test_status.gd`. [done]
3. `game/modes/mode_status.gd` (new): `class_name ModeStatus extends RefCounted`, the throttle
   `push(kind, data, delta)` — emits on a change of the data of the kind or every 0.5 s. [done]
4. `game/modes/free_session.gd`: the status `&"free" {"score": score}` at the start of the
   session, on every score change (`_add_score`, the wreck penalty) and the heartbeat. [done]
5. `game/modes/race_session.gd`: the status `&"race" {"lap", "laps", "position", "racers"}` while
   the state is COUNTDOWN or RUNNING (the lap and the place of the player, the laps of THIS race). [done]
6. `game/modes/pursuit_session.gd`: the status `&"pursuit" {"takedowns", "target", "time_left"}`
   while the pursuit runs and once more with the last values after the result. [done]
7. `game/modes/mode_director.gd`: `Events.mode_status.emit(&"none", {})` when the session ends. [done]
8. Run the test, the check of the folder, the test folder and the mutation check. [done]

## Done
- `game/modes/mode_status.gd` (new, 40 lines): the throttle. `push(kind, data, delta)` emits
  `Events.mode_status` when the data of the kind changed or when 0.5 s (`HEARTBEAT`) are over.
  The helper knows its owner (the session): a session that is queued for deletion says nothing
  any more, so the old mode cannot report after the `&"none"` of the new one.
- `free_session.gd`: `&"free" {"score": score}` at the start of the session, on every score
  change (`_add_score`, the wreck penalty) and every frame (the throttle makes it the heartbeat).
- `race_session.gd`: `&"race"` while the state is COUNTDOWN or RUNNING. `lap` = the lap the
  player is on (1 based, at most `laps`), `laps` = the laps of THIS race (the session's own
  number), `position` = the place of the player in the live order, `racers` = the size of the
  field.
- `race_results.gd`: the new `live_status(laps)` builds that data from the live order of the
  race (the same `assign_positions()` the results use) — it lives here so that
  `race_session.gd` stays under 400 lines (399).
- `pursuit_session.gd`: `&"pursuit" {"takedowns", "target", "time_left"}` while the pursuit runs
  (also right after a takedown) and once more with the last values after the result. The clock
  is counted in whole seconds, so the status changes once a second and not once a frame.
  `target` is 0 when the goal is to escape. `time_left` is -1.0 when the mode was given no time.
- `mode_director.gd`: `Events.mode_status.emit(&"none", {})` at the end of `_stop_session()`.
- `game/modes/tests/test_status.gd` (new, 163 lines): 16 checks — free roam (the score of 0, the
  score of a stunt, the heartbeat), the race (the 3 laps of the race, the first lap, the 6 racers,
  the place of the player), the pursuit (the goal of 3 takedowns, the clock, the clock running
  down, the takedown, no clock without a time) and the end of a mode (the `&"none"`, nothing of
  the old mode after it).

## In progress / next
- nothing. The job is done; the lead commits.

## How to test (exact commands)
- `python tools/gd.py test res://modes/tests/test_status.gd`
- `python tools/gd.py check --only=res://modes/`
- `python tools/run_tests.py --filter res://modes/ --jobs 2 --out F:/dev/skyrush-out/tmp/modes-status/tests`
- `python tools/mutation_check.py --test res://modes/tests/test_status.gd --files auto`

## Evidence (key output lines)
- Test on the OLD code (before the fix): 15 FAIL lines (`FAIL the free roam reports a score of
  0`, `FAIL the race reports the 3 laps of this race ({  })`, ...) — `MODE STATUS TESTS FAILED
  (15 failures)`.
- Test on the NEW code: 16 PASS lines, `MODE STATUS TESTS OK (0 failures)` (run 3 times, stable).
- `python tools/gd.py check --only=res://modes/` → `CHECK 24 files, 0 failed, 0 engine errors, 0 warnings`
- `python tools/run_tests.py --filter res://modes/ ...` → `6 tests, 6 passed, 0 failed or timed out`
- `python tools/mutation_check.py --test res://modes/tests/test_status.gd --files auto` →
  `MUTATION_CHECK OK: the test fails on the old code of b649a54f45 (15 FAIL lines, first: FAIL the free roam reports a score of 0)`

## Known issues
- The clock of a pursuit is counted in whole seconds (the status changes once a second). A
  pursuit without a time has no clock (`time_left` = -1.0), but the session still ends after its
  own fallback of 180 s: the HUD shows no clock for such a pursuit (see the request below).

## Requests
- The pursuit setup of the menu (`game/ui/menu/screens/pursuit_setup.gd`, not my file) starts a
  pursuit without a `time`, so the HUD shows no countdown for a menu pursuit while the session
  still times out after its 180 s fallback. Either the menu should pass a time (then the HUD
  shows the clock) or the session's default should become a real limit that the status reports.
  I did not change either: the brief says the timing does not change and a pursuit without a
  time has `time_left` = -1.0.
