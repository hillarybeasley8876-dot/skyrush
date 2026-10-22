# layers-traffic — the street traffic must not react to the player on the deck above

## Plan
1. Baseline: `python tools/gd.py check --only=res://ai/traffic/` → `CHECK 35 files, 0 failed, 0 engine errors`.
2. New test `game/ai/traffic/tests/test_layers.gd` (written FIRST): the traffic test road
   (3 lanes), a `TrafficCar` (sedan_ev, lane 0, s = 50), the stub player
   (`res://core/stubs/stub_car.tscn`, a `VehicleBase`).
   Checks: (1) near miss same level → `near_misses == 1`; (2) near miss on a deck (+10.6 m) →
   `near_misses == 0` and `horns == 0`; (3) horn same level (gap 1.4 m) → `horns == 1`, on the
   deck → `horns == 0`; (4) startled driver same level → `lane_change._reacting` true;
   (5) startled driver on the deck → `_reacting` false and `reaction_brake == 0.0`.
   Run it on the OLD code: 2, 3 (deck) and 5 must FAIL, 1, 3 (same level) and 4 must PASS.
3. Fix `traffic_player_events.gd`: `const LEVEL_GAP := 2.5`, `_side_gap` returns `INF` when
   `absf(local.y) > LEVEL_GAP` (a car is 1.5 m high: the player is on another level).
4. Fix `traffic_lane_change.gd`: `const REACT_LEVEL := 4.0`, `_react_to_player` forgets the
   player (clears `_reacting`, `_reaction`, `reaction_brake`) when `absf(delta.y) > REACT_LEVEL`.
5. Verify: the new test (`TRAFFIC LAYER TESTS OK`), `gd.py check --only=res://ai/traffic/`,
   `python tools/mutation_check.py --test res://ai/traffic/tests/test_layers.gd --files auto`,
   the whole traffic folder with `tools/run_tests.py --filter res://ai/traffic/ ... --allow-fail test_lanes_world`.

## Done
- The test was written first and failed on the old code for the right reasons (the wrong-level
  cases only).
- The fix is in the two files of the brief; nothing else was touched.
- Files changed:
  - `game/ai/traffic/traffic_player_events.gd` (new const `LEVEL_GAP`, the level test in `_side_gap`).
  - `game/ai/traffic/traffic_lane_change.gd` (new const `REACT_LEVEL`, the level test in
    `_react_to_player`, the new helper `_forget_player()`).
  - `game/ai/traffic/tests/test_layers.gd` (new test).
  - `status/improve/layers-traffic.md` (this file).

## The cause (the numbers of the test on the old code)
The traffic measured the player in 3D and never asked which level he is on:
* `TrafficPlayerEvents._side_gap` looked at `local.x` and `local.z` only (`half.y` was computed
  and never used), so a player 10.6 m above the car had a gap of 0.3 m: the near miss and the
  horn fired (the car was 10.8 m away, inside `CHECK_RANGE` = 12 m).
* `TrafficLaneChange._react_to_player` used the 3D length of `player.global_position - position`
  and never looked at `delta.y`, so a player on the deck 10.6 m up, 25 m behind and closing at
  30 m/s startled the car (the old test: "the car does not react to a player on the deck" FAILED).

## The fix
* `traffic_player_events.gd`: `const LEVEL_GAP := 2.5` (a car is 1.5 m high: the player is on
  another level above this). `_side_gap` returns `INF` when `absf(local.y) > LEVEL_GAP`, so
  neither the near miss nor the horn can fire for a player on another level. Nothing changes
  for a player on the same level.
* `traffic_lane_change.gd`: `const REACT_LEVEL := 4.0` (the "AI that looks at a car" level of
  `briefs/improve/_layers-common.md`). `_react_to_player` treats a player on another level as
  out of sight: the new `_forget_player()` clears `_reacting`, `_reaction` and `reaction_brake`
  (exactly what the "further than `REACT_FORGET_DISTANCE`" branch did) and returns.
  No new allocation in the per-tick path (a call and two `absf`).

## In progress / next
- (nothing; the job is done)

## How to test (exact commands)
- `python tools/gd.py test res://ai/traffic/tests/test_layers.gd`
- `python tools/gd.py check --only=res://ai/traffic/`
- `python tools/mutation_check.py --test res://ai/traffic/tests/test_layers.gd --files auto`
- `python tools/run_tests.py --filter res://ai/traffic/ --jobs 3 --out F:/dev/skyrush-out/tmp/layers-traffic/tests --allow-fail test_lanes_world`

## Evidence (key output lines)
* On the OLD code (before the fix), `python tools/gd.py test res://ai/traffic/tests/test_layers.gd`:
```
PASS the near miss on the same level is counted (1, distance 2.2 m)
FAIL no near miss for a player on the deck (1, distance 10.8 m)
FAIL no horn for a player on the deck (1)
PASS the horn on the same level is sounded (1, distance 3.3 m)
FAIL no horn for a player on the deck (1, distance 11.1 m)
PASS the car on the same level is startled by the player behind it
FAIL the car does not react to a player on the deck
PASS the car does not brake for a player on the deck (0.00)
TRAFFIC LAYER TESTS FAILED (4 failures)
```
* With the fix:
```
PASS the near miss on the same level is counted (1, distance 2.2 m)
PASS no near miss for a player on the deck (0, distance 10.8 m)
PASS no horn for a player on the deck (0)
PASS the horn on the same level is sounded (1, distance 3.3 m)
PASS no horn for a player on the deck (0, distance 11.1 m)
PASS the car on the same level is startled by the player behind it
PASS the car does not react to a player on the deck
PASS the car does not brake for a player on the deck (0.00)
TRAFFIC LAYER TESTS OK (0 failures)
```
* `python tools/gd.py check --only=res://ai/traffic/` → `CHECK 36 files, 0 failed, 0 engine errors, 0 warnings`
* `python tools/mutation_check.py --test res://ai/traffic/tests/test_layers.gd --files auto` →
  `mutating: game/ai/traffic/traffic_lane_change.gd game/ai/traffic/traffic_player_events.gd` and
  `MUTATION_CHECK OK: the test fails on the old code of 927b86a6cf (4 FAIL lines, first: FAIL no near miss for a player on the deck (1, distance 10.8 m))`
* `python tools/run_tests.py --filter res://ai/traffic/ --jobs 3 --out F:/dev/skyrush-out/tmp/layers-traffic/tests --allow-fail test_lanes_world` →
  `10 tests, 9 passed, 1 failed or timed out` / `allow list: test_lanes_world` / `RUN_TESTS_RATCHET OK (1 failing, all of them on the allow list)`

## Known issues
- `test_lanes_world` fails on this machine on the millisecond budgets only (1.475 ms/tick against
  0.5 ms, 3.424 ms p99 against 2.0 ms, 0.170 ms/spawn against 0.100 ms); it is on the allow list
  of the acceptance command and it is not caused by this change (the events cost is 0.033 ms).
- The import step of the tools rewrote the `uid=` lines of 12 `game/assets/city/_tex/*.import`
  files (a side effect of the first import in this worktree); they were put back, the diff of the
  job is only the two source files and the new test.
- `game/modes/tests/test_gate_layers.gd.uid` and `game/world/tests/test_route_layers.gd.uid` are
  untracked files that the import wrote for the test files of other jobs in the base commit; they
  are not mine and were left alone.

## Requests
- (none)
