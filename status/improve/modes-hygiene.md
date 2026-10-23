# modes-hygiene — NEW RECORD, a finished pursuit stops the police, leaving a mode leaves no chase

## Plan
1. Read SPEC/CONTRACTS, the modes unit, the police unit and the results screen. [done]
2. Write `game/modes/tests/test_hygiene.gd` (4 checks) and run it on the OLD code: every check
   must FAIL (with a FAIL line, no crash) — `python tools/gd.py test res://modes/tests/test_hygiene.gd`.
3. `game/modes/race_session.gd`: the member `new_record` (set from `records.record_time`),
   the public `is_new_record()`, the flag handed to the results helper.
4. `game/modes/race_results.gd`: the row of the player carries `new_record`.
5. `game/ui/menu/screens/results_screen.gd`: the label uses the flag (the payload key first, the
   row of the player second) and no longer compares the times.
6. `game/modes/police_link.gd`: `stop_pursuit(police)` (reset the pursuit, remove the units).
7. `game/modes/pursuit_session.gd`: `_finish` stops the police on SUCCESS and TIMEOUT.
8. `game/modes/mode_director.gd`: `_stop_session` stops the police when a pursuit session ends
   and switches the spawning of the police on again.
9. Run the test, the two folders, the two checks and the mutation check. [done]

## Done
- `race_session.gd`: `new_record` (the return value of `records.record_time`, written before
  the results are built), `is_new_record()`, the flag handed to `RaceResults`.
- `race_results.gd`: the row of the player carries `"new_record"` (the rivals do not).
- `results_screen.gd`: the label shows "新纪录  NEW RECORD" when the flag is set; the times are
  not compared any more (`best_time` of the payload is the time of the player itself, because
  the record is written before the results are built).
- `police_link.gd`: `stop_pursuit(police)` — `pursuit.reset()` + `remove_all_units()`.
- `pursuit_session.gd`: `_finish` stops the police on SUCCESS and TIMEOUT (a bust and an escape
  are left to the police unit, which shows its own aftermath and resets itself).
- `mode_director.gd`: `_stop_session` stops the police when the session that ends is a pursuit
  and switches the spawning of the police on again (a race still switches it off right after).
- `game/modes/tests/test_hygiene.gd` (new): 19 checks — the record of a race (the flag, the row
  of the player), the results screen (the label with and without the flag), a pursuit that is
  won (the result, the heat, the pursuit is over, the units are gone, the chase does not go on)
  and a mode that is left (the heat, the pursuit is over, the units are gone, the police can
  spawn again). The test file of the records (`user://test_records_hygiene.cfg`) is deleted.

## In progress / next
- nothing. The job is done; the lead commits.

## How to test (exact commands)
- `python tools/gd.py test res://modes/tests/test_hygiene.gd`
- `python tools/gd.py check --only=res://modes/`
- `python tools/gd.py check --only=res://ui/menu/`
- `python tools/run_tests.py --filter res://modes/ --jobs 2 --out F:/dev/skyrush-out/tmp/modes-hygiene/tests`
- `python tools/run_tests.py --filter res://ui/menu/ --jobs 2 --out F:/dev/skyrush-out/tmp/modes-hygiene/tests_menu`
- `python tools/mutation_check.py --test res://modes/tests/test_hygiene.gd --files auto`

## Evidence (key output lines)
- Test on the OLD code (before the fix): 7 FAIL lines
  (`FAIL a time that beats the record is a new record`, `FAIL the heat is gone after the win (3)`,
  `FAIL the heat is gone after leaving the mode (3)`, ...) — `MODE HYGIENE TESTS FAILED (7 failures)`.
- Test on the NEW code: 19 PASS lines, `MODE HYGIENE TESTS OK (0 failures)` (run 6 times, stable).
- `python tools/gd.py check --only=res://modes/` → `CHECK 22 files, 0 failed, 0 engine errors, 0 warnings`
- `python tools/gd.py check --only=res://ui/menu/` → `CHECK 52 files, 0 failed, 0 engine errors, 0 warnings`
- `python tools/run_tests.py --filter res://modes/ ...` → `5 tests, 5 passed, 0 failed or timed out`
- `python tools/run_tests.py --filter res://ui/menu/ ...` → `6 tests, 6 passed, 0 failed or timed out`
- `python tools/mutation_check.py --test res://modes/tests/test_hygiene.gd --files auto` →
  `MUTATION_CHECK OK: the test fails on the old code of 209bbc7406 (11 FAIL lines, first: FAIL a time that beats the record is a new record)`

## Known issues
- The number of police units on the road is counted in the frame of the win: the police put
  their patrols on the road again in the next tick (that is the free roam, not the chase), so
  the count is only 0 right after the units are removed. The test counts it synchronously.
- A bust and an escape are not touched: the police unit shows its own aftermath (6 s) and resets
  itself (the aftermath never kills a chase that has just begun).
- The results payload of the menu (built by `game/ui/menu/results_router.gd`, the file of the
  menu unit) does not carry the flag at the top level. The screen reads `payload["new_record"]`
  first and falls back to the row of the player in the standings, which carries the flag, so the
  game shows NEW RECORD. See the request below.

## Requests
- `game/ui/menu/results_router.gd` (menu unit, not mine): the race payload could carry the flag
  at the top level (`"new_record": <session.is_new_record()>`), so the results screen does not
  have to look into the row of the player. The screen already prefers the top-level key.
- The voice line `new_record` of the audio unit (`game/audio/voice/voice_lines.gd`) is never
  played: the modes unit could announce it when the time of the player is a record
  (`audio.play_voice(&"new_record")`). Out of scope for this job.
- `game/world/tests/probe_path_blockers.gd.uid` (world unit) is untracked in this worktree: Godot
  generated it during the import. It is not mine; the lead may ignore it or commit it.
- `game/modes/tests/test_hygiene.gd.uid` is new and belongs with the new test (the other test
  files have their `.uid` in the repository).
