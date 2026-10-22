# Job: street traffic must not react to the player on the deck above (traffic layers)

Godot GDScript, unit `game/ai/traffic/`. Read `briefs/improve/_godot-common.md` and `briefs/improve/_layers-common.md` first.

## Goal
The traffic cars measure "the player is near / behind me" with a 3D distance or a plan distance and never ask which LEVEL the player is on. On the map a street runs under the elevated roads, so:
- a player who drives on the deck 10 m above a street car gets a **near miss** (+5 N2 boost, a toast) and the street car **honks**, although they never came close;
- street cars **brake or swerve** ("startled driver") for a player who comes up fast on the deck above them.
Fix both, so the traffic only reacts to a player on its own level.

## Evidence (read the code first)
1. `game/ai/traffic/traffic_player_events.gd`: `update()` checks cars within `CHECK_RANGE := 12.0` m by 3D distance, then `_side_gap(car, player_position)` uses the player's position in the CAR's frame and looks only at `local.x` and `local.z`: `half.y` is computed and never used. A player 10 m above the car has `local.y = +10` and still gets a gap of a few metres.
2. `game/ai/traffic/traffic_lane_change.gd`: `_react_to_player(ctx, follower, position, speed)` uses `delta := player.global_position - position` with a 3D length (`PLAYER_REACT_RANGE := 40.0`, `REACT_FORGET_DISTANCE := 70.0`), and "ahead" from the flat tangent. The y of `delta` is never tested, so a player on a deck 10 m up, 25 m behind and closing at 30 m/s makes 30 % of the street cars move or brake.

## What to build (small changes in these two files only)
1. `TrafficPlayerEvents._side_gap`: return `INF` when `absf(local.y) > LEVEL_GAP` with `const LEVEL_GAP := 2.5` (metres, a doc comment: "a car is 1.5 m high: the player is on another level above this"). Then neither the near miss nor the horn can fire for a player on another level, and nothing changes for a player on the same level.
2. `TrafficLaneChange._react_to_player`: when `absf(delta.y) > REACT_LEVEL` with `const REACT_LEVEL := 4.0`, treat the player as out of sight: clear `_reacting`, `_reaction`, `reaction_brake` (exactly what the code does when the player is further than `REACT_FORGET_DISTANCE`) and return.
Nothing else changes. No new allocations in these per-tick functions.

## Files you own
`game/ai/traffic/`. Existing tests there are read-only. You add ONE new test file `game/ai/traffic/tests/test_layers.gd`.

## The test you write FIRST (`game/ai/traffic/tests/test_layers.gd`)
Look at `game/ai/traffic/tests/test_wreck.gd` and `test_player_hits_traffic.gd` for how a test builds a road (`TrafficTestRoad.build(3)`), a `DriveContext`, a ground, and a `TrafficCar` (`traffic_car.tscn`, `car.build(...)`, `car.place(lane, s)`), and `res://core/stubs/stub_car.tscn` for a player (a `VehicleBase`: set `gravity_scale = 0.0`, put it where you want it, give it a `linear_velocity`).
Checks (print `PASS ...` / `FAIL ...`, end with `TRAFFIC LAYER TESTS OK (0 failures)` and quit 0, or `TRAFFIC LAYER TESTS FAILED` and quit 1):
1. **Near miss, same level (control)**: a traffic car on lane 0 at s = 50 and the stub player beside it, the lateral gap such that `TrafficPlayerEvents.update(0.016, player, [car])` counts exactly 1 near miss (player speed 40 m/s along the lane, car about 10 m/s, side gap under 1.2 m: tune the lateral offset in the test until the control gives `near_misses == 1`; if the car has no speed set `car.linear_velocity` yourself).
2. **Near miss, player on a deck**: the same setup with the player 10.6 m higher: `near_misses == 0` and `horns == 0`.
3. **Horn, same level** with a side gap under 1.5 m and a relative speed over 5 m/s: `horns == 1`; the same on the deck: `horns == 0`.
4. **Startled driver, same level**: a `TrafficLaneChange` (see how `traffic_car.gd` creates and calls it, or build one with `start(rng)` and a `LaneFollower` on the test graph) and the player 25 m behind it on its level, closing at 30 m/s: after at most 200 calls of `update(...)` with different seeds of `ctx.rng` the car has reacted at least once (`_reacting` is true; read the private variable, GDScript allows it).
5. **Startled driver, player on a deck**: the same with the player 10.6 m higher, 200 calls: `_reacting` stays false and `reaction_brake == 0.0`.
Run it BEFORE you change the code: checks 2, 3 (deck half) and 5 must fail, checks 1, 3 (same-level half) and 4 must pass. If check 1 or 4 fails the test is wrong, not the code.

## Acceptance (the runner executes these itself)
1. `python tools/gd.py check --only=res://ai/traffic/` prints `CHECK N files, 0 failed, 0 engine errors`.
2. `python tools/gd.py test res://ai/traffic/tests/test_layers.gd` prints `TRAFFIC LAYER TESTS OK`.
3. `python tools/mutation_check.py --test res://ai/traffic/tests/test_layers.gd --files auto` prints `MUTATION_CHECK OK` (the old version of every source file you changed is put back for one run and your test must FAIL on it).
4. `python tools/run_tests.py --filter res://ai/traffic/ --jobs 3 --out F:/dev/skyrush-out/tmp/layers-traffic/tests --allow-fail test_lanes_world` ends with `RUN_TESTS_RATCHET OK` (test_lanes_world checks millisecond budgets that a busy machine fails; every other traffic test must pass).

## Pitfalls
- A check that passes because the car never reacts at all (check 4 is the guard) or because the player is out of the 12 m / 40 m range (keep both setups inside the ranges).
- Changing the ranges, the chances or the brake values.
- A `TrafficCar` that falls (no ground): build a ground like `test_wreck.gd` does or freeze the car.
- Using the player's height from `telemetry` instead of `global_position.y`.
