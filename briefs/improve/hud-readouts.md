# Job: the HUD shows the state of the mode (score, laps and place, takedowns and time)

Godot GDScript, unit `game/ui/hud/`. Read `briefs/improve/_godot-common.md` first.

## Goal
The HUD knows nothing about the running mode: free roam shows no score at all (it appears only after the pause menu is left), a pursuit shows neither the goal ("3 takedowns") nor a time limit, and a race takes its lap count from "the first route of the city" (`Hud._route_laps()`), so a race of 3 laps shows 2, and ranks the racers by checkpoints.
The modes now say what is going on on the event bus (`game/core/events.gd`, read the comment above the signal; another job, `modes-status`, makes the modes emit it):

    signal mode_status(kind: StringName, data: Dictionary)
      &"free"    {"score": int}
      &"race"    {"lap": int (1 based), "laps": int, "position": int (1 = first), "racers": int}
      &"pursuit" {"takedowns": int, "target": int (0 = no goal), "time_left": float (s, -1.0 = no limit)}
      &"none"    {}   (no mode: show nothing of it)

Your job is the drawing side: the HUD listens and shows it.

## Evidence (read the code)
- `game/ui/hud/hud.gd`: the widget tree (`race_panel`, `pursuit_panel`, `timer_panel`, `minimap`, `toasts`, ...), `_update_timer_layout()` sets `events.laps = _route_laps()`, `_route_laps()` reads the first route of the world; `DEFAULT_LAPS := 2`. `hud_events.gd` (`HudEvents`) keeps the bus state of the HUD (`laps`, `lap`, `race_running`, `progress`, `race_total`, ...). `race_panel.gd` shows the place; `timer_panel.gd` the clock and the lap counter (`update_values(race_time, best_lap, lap, laps, ...)`).
- Nothing in the HUD draws a score, a takedown goal or a countdown of a pursuit.

## What to build
1. `HudEvents` (or a new small script next to it) connects `Events.mode_status` and keeps the last status: `status_kind: StringName`, `status: Dictionary`.
2. **Free roam**: a score readout `SCORE  1250` (a label with the HUD's own font and colours, see `skyrush_theme.gd`/`UI`; place it where it does not collide with the existing clusters: the layout test `test_hud_layout.gd` checks the boxes of the HUD, look at it and keep it green) visible only while the status kind is `&"free"`; the number is `data.score`.
3. **Pursuit**: while the kind is `&"pursuit"`: a goal line `TAKEDOWNS  1 / 3` (hidden when `target == 0`) and a countdown `TIME  01:23` (hidden when `time_left < 0`, otherwise `mm:ss` of the seconds left, never negative). Put them under the pursuit panel or next to it.
4. **Race**: while the kind is `&"race"`: `events.laps = data.laps` (so the lap counter says `lap / laps` of the race that is running, not of the first route) and `events.lap = data.lap`; the place shown by the race panel is `data.position` of `data.racers`. If `_route_laps()` is still used as a fallback when no status arrived, keep it as that fallback only.
5. **None**: the kind `&"none"` (or no status) hides the score, goal and countdown labels.
Do not change the speedometer, the N2 cluster, the minimap, the toasts, the flight gauges, the busted dim, the pursuit panel logic.

## Files you own
`game/ui/hud/`. Existing tests are read-only. You add ONE new test file `game/ui/hud/tests/test_mode_status.gd`.

## The test you write FIRST (`game/ui/hud/tests/test_mode_status.gd`)
Build the HUD as `game/ui/hud/tests/test_hud.gd` does (the scene `res://ui/hud/hud.tscn`, `telemetry_override`), then drive it through the bus (`Events.mode_status.emit(...)`) and read the labels (find them by node name or by the member you add: give the nodes clear names, e.g. `ScoreLabel`, `GoalLabel`, `TimeLabel`). Checks (`PASS ...` / `FAIL ...`; end with `HUD STATUS TESTS OK (0 failures)` and quit 0, or `HUD STATUS TESTS FAILED` and quit 1):
1. free `{"score": 1250}`: the score label is visible and its text contains `1250`; a later `{"score": 3000}` updates it.
2. none: the score label is hidden.
3. pursuit `{"takedowns": 1, "target": 3, "time_left": 83.2}`: the goal label contains `1` and `3`, the time label contains `01:23`; `time_left` -1.0 hides the time label, `target` 0 hides the goal label; `time_left` -5.0 never shows a negative time.
4. race `{"lap": 2, "laps": 3, "position": 4, "racers": 6}`: `hud.events.laps == 3` and `hud.events.lap == 2` after two frames, and the place text of the race panel shows `4`.
5. switching kinds hides what belongs to the other kind (free then pursuit: the score label is hidden).
Run it BEFORE you change anything: every check must fail (nothing is drawn). Find the nodes with `get("name")` / `find_child` guards so that a missing node prints a `FAIL` line, not a script error.

## Acceptance (the runner executes these itself)
1. `python tools/gd.py check --only=res://ui/hud/` prints `CHECK N files, 0 failed, 0 engine errors`.
2. `python tools/gd.py test res://ui/hud/tests/test_mode_status.gd` prints `HUD STATUS TESTS OK`.
3. `python tools/mutation_check.py --test res://ui/hud/tests/test_mode_status.gd --files auto` prints `MUTATION_CHECK OK`.
4. `python tools/run_tests.py --filter res://ui/hud/ --jobs 2 --out F:/dev/skyrush-out/tmp/hud-readouts/tests --allow-fail test_hud_perf` ends with `RUN_TESTS_RATCHET OK` (`test_hud_perf` checks millisecond budgets that a busy machine fails; every other HUD test, `test_hud_layout` included, must pass).

## Pitfalls
- A label that overlaps another cluster (the layout test) or that is created every frame.
- Per-frame string formatting without a change check (the HUD has a perf test): update the text only when the data changed.
- Reading the session of the modes directly: the contract is the signal, nothing else.
