# Job: the traffic index and the "player road" must respect the level (second round)

Godot GDScript, unit `game/ai/traffic/`. Read `briefs/improve/_godot-common.md` and `briefs/improve/_layers-common.md` first. The first round (`layers-traffic`, merged) taught the near-miss, the horn and the startled driver to ignore a player on another level; read its test `game/ai/traffic/tests/test_layers.gd` and `status/improve/layers-traffic.md`. The rule is "the same level when the heights differ by at most 4.0 m" (a constant `LEVEL`, in one place of the folder).

## Goal
Two more places of the traffic code mix the levels.

## The defects (read each function first)
1. **A wreck that fell off its deck stays a phantom obstacle on the deck lane.** `traffic_index.gd` `index_wreck(car)`: `ctx.hash.insert(follower.lane, s, car)` always registers the wreck on the lane it was on when it was hit, and only ADDS a second lane when the body is more than `WRECK_LANE_DISTANCE` (3D) from that lane. A car on the Nanpu approach that is hit hard and falls to the street 30 m below keeps blocking the deck lane for the whole wreck time (8 s): cars on the deck brake for a car that is not there. Rule: when the body is further than `WRECK_LANE_DISTANCE` from the lane position it was hit on, the wreck is indexed ONLY on the lane it really lies on (found with `grid.nearest_lane(body, WRECK_LANE_RADIUS)`, and that lane must be on the body's level: use the level rule, not just the 3D radius); if no lane lies under it, it is indexed nowhere.
2. **The traffic belongs to the wrong road for a while.** `traffic_director.gd` `_player_road()`: it keeps the player's last lane while `ctx.graph.position_at(lane, _player_s).distance_to(position) <= PLAYER_ROAD_RADIUS` (3D). A player who leaves the deck by a ramp and drives on the street under it is 10 m away from the deck lane's position, which is inside a 25 m radius, so for a few seconds `_player_road()` still answers the deck's road id and the traffic ring fills the wrong road. Rule: the stale lane is kept only while the player is also within `LEVEL` of the lane position in height; otherwise the nearest lane ON THE PLAYER'S LEVEL (`grid.nearest_lane`) is used (look at `LaneGrid.nearest_lane`; if it cannot filter by height, filter its candidates yourself: `grid.lanes_near(...)` plus a height test of the lane's closest point).

## Files you own
`game/ai/traffic/` (existing tests are read-only). You add ONE new test file `game/ai/traffic/tests/test_layers_2.gd`.

## The test you write FIRST (`game/ai/traffic/tests/test_layers_2.gd`)
Build a two level lane graph by hand (a street lane at y = 0 and a deck lane at y = 10, both along +X, the same x/z; use `TrafficTestRoad` as a model and extend it in your own test file, the helper itself is read-only), a `DriveContext`, a `LaneGrid`, a traffic car and the stub player (`res://core/stubs/stub_car.tscn`, `gravity_scale = 0.0`). Checks (`PASS ...` / `FAIL ...`; end with `TRAFFIC LAYER 2 TESTS OK (0 failures)` and quit 0, or `TRAFFIC LAYER 2 TESTS FAILED` and quit 1):
1. A wreck whose body lies on the street (y = 0.6, 30 m from the deck lane position it was hit on): `ctx.hash` has the wreck on the street lane and NOT on the deck lane (control: a wreck that stays within `WRECK_LANE_DISTANCE` of its lane is indexed on that lane as before).
2. A wreck with no lane under it: indexed nowhere (no error).
3. `_player_road()` with the player on the street (y = 0.6) while `_player_lane` still points at the deck lane: it answers the street road id (control: the player on the deck answers the deck road id).
Run it BEFORE you change anything: 1 and 3 (wrong-level halves) fail, the controls pass.

## Acceptance (the runner executes these itself)
1. `python tools/gd.py check --only=res://ai/traffic/` prints `CHECK N files, 0 failed, 0 engine errors`.
2. `python tools/gd.py test res://ai/traffic/tests/test_layers_2.gd` prints `TRAFFIC LAYER 2 TESTS OK`.
3. `python tools/mutation_check.py --test res://ai/traffic/tests/test_layers_2.gd --files auto` prints `MUTATION_CHECK OK`.
4. `python tools/run_tests.py --filter res://ai/traffic/ --jobs 3 --out F:/dev/skyrush-out/tmp/traffic-layers-2/tests --allow-fail test_lanes_world` ends with `RUN_TESTS_RATCHET OK`.

## Pitfalls
- Indexing a wreck on the nearest lane in the plan only (the street under a deck is exactly that).
- A per-tick scan over all lanes in `_player_road` (it is called often: keep the stale-lane shortcut for the common case).
- Changing `WRECK_LANE_DISTANCE`, `WRECK_LANE_RADIUS` or `PLAYER_ROAD_RADIUS`.
