# Job: after the first bust or escape in free roam the police must come back and the HUD must clear

Godot GDScript, units `game/ai/police/` and `game/ui/hud/`. Read `briefs/improve/_godot-common.md` first (how to run things, how tests are written, the loop that gets a job accepted).

## Goal
In free roam the first time the player is BUSTED or ESCAPES, the pursuit state stays `busted` / `escaped` for ever. Consequences the player sees: the screen stays dimmed (60 % black) after a bust, the pursuit panel stays on screen, no patrol or unit ever spawns again, and no second chase can ever start (only the toll plaza can still start a chase).
Make the aftermath last a few seconds and then reset the pursuit to `none`, so the game goes on.

## Evidence (read the code, then reproduce it with the test below)
- `game/ai/police/police_director.gd` `_update_spawning`: `if pursuit.state == &"escaped" or pursuit.state == &"busted": return` - no spawning while in the aftermath state.
- `game/ai/police/police_pursuit.gd` `end(new_state)`: sets the state and zeroes the heat, but nothing ever sets the state back to `none`; `reset()` (state `none`) is called only from the test hook `police_test_hooks.gd` `clear_pursuit()`.
- `PoliceSpawner.end_pursuit()` says "the patrols fill the road again" and `update()` spawns `PATROL_COUNT := 2` patrols at heat 0, but the dispatcher never gets there.
- `game/ui/hud/hud.gd` keeps a 60 % black dim while the state is `busted` (around line 184) and its pursuit-state handler (around lines 318-332) never hides the pursuit panel again.
- `PolicePursuit.start()` returns at once when the pursuit is not over (`if not is_over(): return`): a retry in pursuit mode keeps the old heat.

## What to build
1. An aftermath timer in the dispatcher (`police_director.gd`): when the pursuit state is `busted` or `escaped`, a timer runs; after `AFTERMATH_SECONDS := 6.0` (a `const` with a doc comment, or in the unit's tuning file if it has one) the dispatcher calls `pursuit.reset()` (state `none`, heat 0) so that `_update_spawning` runs again and the patrols come back (`spawner.end_pursuit()` was already called by `_end_pursuit`). The timer restarts for every new end state and is cleared by `reset()`.
   Do not clear the state earlier than 6 s: the pursuit mode (`game/modes/pursuit_session.gd`, read-only for you) reads the end state to finish and to show the results.
2. The HUD: when the pursuit state becomes `none` (signal `Events.pursuit_state_changed`), the busted dim goes away and the pursuit panel hides. While the state is `busted` / `escaped` the dim and the panel behave as they do today (the toast "BUSTED" / "ESCAPED" stays).
3. Nothing else changes: the heat table, the toasts, the rewards, the pursuit mode, the box rules.

## Files you own
`game/ai/police/` and `game/ui/hud/`. Tests that already exist in them are read-only (do not edit, do not delete); you add ONE new test file `game/ai/police/tests/test_pursuit_end.gd`.

## The test you write FIRST (`game/ai/police/tests/test_pursuit_end.gd`)
Copy the setup of an existing police test that starts a pursuit and has a HUD or a director (look at `game/ai/police/tests/test_busted.gd`, `police_test.gd`, `test_toll.gd`; for the HUD see how `game/ui/hud/tests/` builds the HUD). The test must check, with `PASS`/`FAIL` lines, in this order:
1. `start_pursuit(1)` -> the state is `chase`.
2. End it: call `_end_pursuit(&"busted")` on the dispatcher. Right after: the state is `busted`, the heat is 0, and (if you built a HUD) the dim is visible.
3. After 3 s (physics frames) the state is STILL `busted` (the aftermath has not ended).
4. After 7 s the state is `none`; the HUD dim is not visible and the pursuit panel is not visible.
5. Within 40 s more the dispatcher has at least one unit again (the patrols are back) - the test world must allow spawning (`spawn_enabled` true, a player on a lane).
6. The same for `&"escaped"` (steps 2 to 4 are enough).
7. A second chase can start: `start_pursuit(1)` after the reset gives state `chase` again.
The test prints `PURSUIT END TESTS OK (0 failures)` and quits with 0 when everything passed, otherwise it prints `PURSUIT END TESTS FAILED` and quits with 1. Run it BEFORE you change anything and read the failure: it must fail at step 4 (state still `busted`).

## Acceptance (the runner executes these itself)
1. `python tools/gd.py check --only=res://ai/police/` and `python tools/gd.py check --only=res://ui/hud/` print `CHECK N files, 0 failed, 0 engine errors`.
2. `python tools/gd.py test res://ai/police/tests/test_pursuit_end.gd` prints `PURSUIT END TESTS OK`.
3. `python tools/mutation_check.py --test res://ai/police/tests/test_pursuit_end.gd --files auto` prints `MUTATION_CHECK OK` (the runner puts the OLD version of every source file you changed back for one run and your test must FAIL on it).
4. `python tools/run_tests.py --filter res://ai/police/ --jobs 3 --out F:/dev/skyrush-out/tmp/police-lifecycle/tests_police` and `python tools/run_tests.py --filter res://ui/hud/ --jobs 2 --out F:/dev/skyrush-out/tmp/police-lifecycle/tests_hud` each end with `, 0 failed or timed out`.

## Pitfalls
- Resetting the state at once in `end()`: the toasts, the reward and the pursuit mode need the end state for a few seconds.
- A test that only checks the state name: also check the HUD and the units (a state reset that leaves the dim on is the bug).
- Resetting while a NEW pursuit started inside the aftermath (a new `start()` must cancel the timer).
- Making the police spawn during the aftermath.
- Touching `game/modes/` (read-only for you): if the pursuit session needs a change, write it under `## Requests` in your status file.
