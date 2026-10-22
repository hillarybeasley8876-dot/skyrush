# Job: modes hygiene - NEW RECORD works, a finished pursuit stops the police, leaving a mode leaves no chase behind

Godot GDScript, unit `game/modes/` and the results screen `game/ui/menu/screens/results_screen.gd`. Read `briefs/improve/_godot-common.md` first.

## Goal
Three loose ends of the game modes:
1. **"NEW RECORD" is never shown.** `RaceSession._finish_racer` saves the player's time with `records.record_time(route_id, elapsed)` BEFORE the results are built; the results screen then compares the player's time with `payload["best_time"]` (`player_time < best_time`), which is now the saved time itself, so the comparison is never true.
2. **A pursuit that is won or times out keeps running.** `PursuitSession._finish(Result.SUCCESS / TIMEOUT)` toasts the result and emits `finished`, but the police pursuit (heat, units, the chase state) goes on in the background; a retry in pursuit mode calls `PolicePursuit.start_at`, which returns at once while the old chase is still active (`if not is_over(): return`), so the retry keeps the old heat.
3. **Leaving a mode leaves the chase behind.** `ModeDirector._stop_session` frees the session and stops the rivals but does not touch the police: start a race after a pursuit and the cops are still after you.

## Evidence (read the code)
- `game/modes/race_session.gd` `_finish_racer(racer)`: `records.record_time(route_id, elapsed)` (it returns true when the time is a new record) and later `build_results()`; `game/ui/menu/screens/results_screen.gd` `_build_race()` (around lines 150 to 170): `if player_time > 0.0 and (best_time < 0.0 or player_time < best_time): record_label.text = "新纪录  NEW RECORD"`.
- `game/modes/pursuit_session.gd` `_finish(new_result)` and `build_results()`; `game/modes/police_link.gd` (`PoliceLink`: `director(tree)`, `start_pursuit`, `set_heat`, `set_spawn_enabled`; the director has `remove_all_units()` and the `pursuit` object has `reset()`, `end(state)`, `is_over()`, `state`, `heat`).
- `game/modes/mode_director.gd` `_stop_session()` (around line 160).
- `game/ai/police/police_pursuit.gd` is read-only for you: `reset()` sets the state to `none` and the heat to 0.

## What to build
1. In `RaceSession`: before saving the time, remember whether it is a record (`var is_record: bool = records.record_time(...)`), keep it in a member `new_record` and put it into the results payload as `"new_record": bool`. The results screen shows "新纪录  NEW RECORD" when `payload.get("new_record", false)` is true (and no longer compares times). A race without records (`records == null`) has `new_record == false`.
2. `PoliceLink.stop_pursuit(police: Node)` (new, static): when the director exists, call `pursuit.reset()` on its `pursuit` object and `remove_all_units()`. `PursuitSession._finish` calls it for SUCCESS and TIMEOUT (for ESCAPED and BUSTED the police director has already ended the chase and shows its aftermath: do not call it there).
3. `ModeDirector._stop_session`: when the session that ends is a `PursuitSession`, call `PoliceLink.stop_pursuit` too, and make sure the spawning of police is on again (`PoliceLink.set_spawn_enabled(police, true)`) if the pursuit mode had switched it off (read how `PursuitSession` starts; do not change what free roam and race expect).
Nothing else changes.

## Files you own
`game/modes/` and `game/ui/menu/screens/results_screen.gd`. Existing tests are read-only. You add ONE new test file `game/modes/tests/test_hygiene.gd`.

## The test you write FIRST (`game/modes/tests/test_hygiene.gd`)
Copy the way `game/modes/tests/test_modes.gd` and `test_pursuit_mode.gd` build the world, the player, the rival director and the `ModeDirector` (the sandbox scene and `start_mode`). Checks (print `PASS ...` / `FAIL ...`; end with `MODE HYGIENE TESTS OK (0 failures)` and quit 0, or `MODE HYGIENE TESTS FAILED` and quit 1):
1. **New record**: a race session whose player finishes with a time that beats the stored record puts `new_record == true` in `build_results()`; one that does not beat it has `new_record == false`. Use a temporary records file (`GameRecords.new("user://test_records_hygiene.cfg")`, as `test_modes.gd` does) and set the session's `records`; call the session's finish path directly (`_finish_racer` of the player's racer after setting `elapsed`) or whatever the smallest honest way is. Delete the file at the end.
2. **Results screen**: instantiate the results screen with a race payload that has `"new_record": true` and a `best_time` equal to the player's time: its record label contains `NEW RECORD`; with `"new_record": false` it does not. (Look at `game/ui/menu/tests/test_results.gd` for how the screen is built.)
3. **Pursuit won**: start the pursuit mode with `{"goal": "takedowns", "count": 1}`, wait until the police pursuit is active (heat > 0), emit `Events.takedown.emit(Game.player, &"police")`: the session result is SUCCESS, and within a second the police director has `pursuit.heat == 0`, no units, and `pursuit.is_over()`.
4. **Leaving the pursuit**: start the pursuit mode, wait for the chase, then `start_mode(&"free", {})`: the police director has heat 0 and `spawn_enabled` is true.
Run it BEFORE you change anything: 1, 2, 3, 4 must fail for the right reason (print the values). Use `has_method` / `get` guards so that missing new members give a `FAIL` line, not a script error.

## Acceptance (the runner executes these itself)
1. `python tools/gd.py check --only=res://modes/` and `python tools/gd.py check --only=res://ui/menu/` print `CHECK N files, 0 failed, 0 engine errors`.
2. `python tools/gd.py test res://modes/tests/test_hygiene.gd` prints `MODE HYGIENE TESTS OK`.
3. `python tools/mutation_check.py --test res://modes/tests/test_hygiene.gd --files auto` prints `MUTATION_CHECK OK`.
4. `python tools/run_tests.py --filter res://modes/ --jobs 2 --out F:/dev/skyrush-out/tmp/modes-hygiene/tests` and `python tools/run_tests.py --filter res://ui/menu/ --jobs 2 --out F:/dev/skyrush-out/tmp/modes-hygiene/tests_menu` each end with `, 0 failed or timed out`.

## Pitfalls
- Resetting the police when the pursuit ended by BUSTED or ESCAPED: the police director shows its own aftermath (about 6 s) and resets by itself.
- Changing what `best_time` means in the payload: other code (the HUD, other screens) may read it.
- A test that passes because the police unit is not loaded (`PoliceLink.director` returns null): the sandbox of `test_pursuit_mode.gd` has a director, use the same.
