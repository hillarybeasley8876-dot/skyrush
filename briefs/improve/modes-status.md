# Job: the modes tell the HUD what is going on (Events.mode_status)

Godot GDScript, unit `game/modes/`. Read `briefs/improve/_godot-common.md` first.

## Goal
The HUD does not know the state of the running mode: it shows no score in free roam, no goal and no timer in a pursuit, takes the lap count of a race from "the first route of the city" (a race of 3 laps shows 2) and ranks the racers by checkpoints. The contract between the modes and the HUD is now on the event bus (`game/core/events.gd`, read the comment above it):

    signal mode_status(kind: StringName, data: Dictionary)
      &"free"    {"score": int}
      &"race"    {"lap": int (1 based), "laps": int, "position": int (1 = first), "racers": int}
      &"pursuit" {"takedowns": int, "target": int (0 = no goal), "time_left": float (s, -1.0 = no limit)}
      &"none"    {}   (no mode: nothing to show)

The HUD side is another job (`hud-readouts`). Yours is the emitting side: each session emits its status on every change and at least every 0.5 s while it runs.

## Evidence (read the code)
- `game/modes/free_session.gd` keeps `score`, `stunts`, `near_misses`, `takedowns`, `streak` and adds points in `_add_score`.
- `game/modes/race_session.gd` keeps `laps`, `racers`, `elapsed`, `state` and the positions (`_update_positions`, `_results`, `standings()` of the director); the player is `player` / the racer with `is_player`.
- `game/modes/pursuit_session.gd` keeps `takedowns`, `target_takedowns`, `goal`, `elapsed`, `time_limit` (read the file for the exact names) and `result`.
- `game/modes/mode_director.gd` `_stop_session()` ends a session.

## What to build
1. A small helper `game/modes/mode_status.gd` (`class_name ModeStatus`, `extends RefCounted`) with a throttle: `func push(kind: StringName, data: Dictionary, delta: float) -> void` emits `Events.mode_status` when `data` differs from the last pushed data of the same kind OR 0.5 s have passed since the last emission. (A `static`-free class; each session owns an instance.)
2. `FreeSession`: in `_physics_process`/`_process` (use the one the file has, or the `delta` of its tick) push `(&"free", {"score": score})`. Also push once right when the session starts (score 0) and on every `_add_score`.
3. `RaceSession`: push `(&"race", {...})` while the state is COUNTDOWN or RUNNING: `lap` = the lap the player is on (1 for the first lap; at most `laps`), `laps` = the number of laps of THIS race (the chosen one: `laps` of the session), `position` = the place of the player now (1 = first; the live order the session already computes), `racers` = the number of racers.
4. `PursuitSession`: push `(&"pursuit", {"takedowns": takedowns, "target": target_takedowns if the goal is TAKEDOWNS else 0, "time_left": seconds left or -1.0 when there is no limit})` while running (`result == RUNNING`); after the result keep pushing the last values once.
5. `ModeDirector._stop_session()`: emit `Events.mode_status.emit(&"none", {})` after the session is freed.
Nothing else changes: no scoring, no result, no timing.

## Files you own
`game/modes/`. Existing tests are read-only. You add ONE new test file `game/modes/tests/test_status.gd`.

## The test you write FIRST (`game/modes/tests/test_status.gd`)
Copy how `game/modes/tests/test_modes.gd` builds the sandbox world, the player, the rival director and the `ModeDirector`. Connect to `Events.mode_status` and collect `[kind, data]` records. Checks (`PASS ...` / `FAIL ...`; end with `MODE STATUS TESTS OK (0 failures)` and quit 0, or `MODE STATUS TESTS FAILED` and quit 1):
1. **Free**: `start_mode(&"free", {})`; after 0.2 s at least one record `&"free"` with `score == 0`; then `Events.stunt.emit(&"test", 500, "t")` and within 0.2 s a record with `score == 500`; over 1.3 s at least 3 records arrive (the 0.5 s heartbeat).
2. **Race**: `start_mode(&"race", {"route": "sandbox_loop", "laps": 3})`: within 1 s a record `&"race"` with `laps == 3`, `lap == 1`, `racers == 6` and `position` between 1 and 6.
3. **Pursuit**: `start_mode(&"pursuit", {"goal": "takedowns", "count": 3, "time": 60})`: a record `&"pursuit"` with `target == 3`, `takedowns == 0` and `time_left` between 55 and 60; 1.2 s later `time_left` is smaller; after `Events.takedown.emit(Game.player, &"police")` a record with `takedowns == 1` within 0.2 s. A pursuit without `time` has `time_left == -1.0`.
4. **None**: `start_mode(&"free", {})` after a race: a record `&"none"` arrived (the old session ended).
Run it BEFORE you change anything: every check must fail (no record at all).
Use `has_signal("mode_status")` guards if you want, but the signal exists in this checkout.

## Acceptance (the runner executes these itself)
1. `python tools/gd.py check --only=res://modes/` prints `CHECK N files, 0 failed, 0 engine errors`.
2. `python tools/gd.py test res://modes/tests/test_status.gd` prints `MODE STATUS TESTS OK`.
3. `python tools/mutation_check.py --test res://modes/tests/test_status.gd --files auto` prints `MUTATION_CHECK OK`.
4. `python tools/run_tests.py --filter res://modes/ --jobs 2 --out F:/dev/skyrush-out/tmp/modes-status/tests` ends with `, 0 failed or timed out`.

## Pitfalls
- Emitting every frame (the rate is on change plus a 0.5 s heartbeat; a status every tick costs the HUD).
- `laps` from the route instead of the session (the whole point is the chosen number).
- `position` computed from checkpoint counts only: use what the session already uses for the live order (`standings()` of the director sorts by it).
- Changing the results payload or the scoring: not in this job.
