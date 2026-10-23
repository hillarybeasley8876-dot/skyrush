# traffic-layers-2 — the traffic index and the player road respect the level

## Plan
1. Baseline: `python tools/gd.py check --only=res://ai/traffic/` → `CHECK N files, 0 failed, 0 engine errors`.
2. New test `game/ai/traffic/tests/test_layers_2.gd` (written FIRST): a two level road by hand
   (a street lane at y = 0, a deck lane at y = 10, the same x/z, `road_id` "street_road" /
   "deck_road"), a `DriveContext`, a `LaneGrid`, a `TrafficCar` and the stub player.
   Checks: (1) a wreck whose body fell to the street (y = 0.6, 30 m from the deck lane it was
   hit on) is indexed on the street lane and NOT on the deck lane; (2) a wreck with no lane
   under it is indexed nowhere; (3) the control: a wreck within `WRECK_LANE_DISTANCE` of its
   lane is still indexed on that lane; (4) `_player_road()` with the player on the street
   (y = 0.6) and `_player_lane` on the deck answers "street_road"; (5) the control: the player
   on the deck answers "deck_road".
   Run it on the OLD code: 1, 2 and 4 must FAIL, 3 and 5 must PASS.
3. New helper `game/ai/traffic/traffic_level.gd`: `class_name TrafficLevel`, `const LEVEL := 4.0`
   (the level rule of `briefs/improve/_layers-common.md`, in ONE place of the folder),
   `same_level(y_a, y_b)`, `nearest_lane_at_level(grid, pos, radius)` and
   `player_road(graph, grid, lane, s, position, radius)`.
4. Fix `traffic_index.gd` `index_wreck`: a wreck that is further than `WRECK_LANE_DISTANCE`
   from the lane it was hit on is indexed ONLY on the lane it really lies on, and only when
   that lane is on the level of the body; with no lane under it the wreck is indexed nowhere.
5. Fix `traffic_director.gd` `_player_road`: the stale lane is kept only while the player is
   within `LEVEL` of the lane position in height; otherwise the nearest lane ON THE PLAYER'S
   LEVEL is used.
6. Verify: `python tools/gd.py test res://ai/traffic/tests/test_layers_2.gd` →
   `TRAFFIC LAYER 2 TESTS OK`, `python tools/gd.py check --only=res://ai/traffic/`,
   `python tools/mutation_check.py --test res://ai/traffic/tests/test_layers_2.gd --files auto`
   → `MUTATION_CHECK OK`, and
   `python tools/run_tests.py --filter res://ai/traffic/ --jobs 3 --out F:/dev/skyrush-out/tmp/traffic-layers-2/tests --allow-fail test_lanes_world`
   → `RUN_TESTS_RATCHET OK`.

## Done
- The test was written first and failed on the old code for the right reasons (the wrong-level
  cases only: 3 FAIL lines, the two controls passed).
- Both defects are fixed; the level constant lives in ONE new file of the folder.
- Files changed:
  - `game/ai/traffic/traffic_level.gd` (NEW): `const LEVEL := 4.0`, `same_level()`,
    `nearest_lane_at_level()` (the nearest lane of the grid that is on the level of the point)
    and `player_road()` (the road of the player, the lane of the player only while the player
    is on its level).
  - `game/ai/traffic/traffic_index.gd`: `index_wreck` no longer registers the wreck on the
    lane it was hit on when the body left that lane; it registers it on the lane it really
    lies on (on the level of the body) or nowhere.
  - `game/ai/traffic/traffic_director.gd`: `_player_road` delegates to
    `TrafficLevel.player_road` (the file was 402 lines before and is 395 now, under the limit
    of 400).
  - `game/ai/traffic/tests/test_layers_2.gd` (NEW): the test.
  - `status/improve/traffic-layers-2.md` (this file).

## The cause (the numbers of the test on the old code)
* `TrafficIndex.index_wreck` inserted the wreck on the lane it was hit on (`follower.lane`,
  `follower.s`) UNCONDITIONALLY and only added a second lane when the body was more than
  `WRECK_LANE_DISTANCE` away. A wreck that fell from the Nanpu approach to the street 30 m
  below therefore kept blocking the deck lane for the whole wreck time (8 s): the cars of the
  deck braked for a car that was not there. `grid.nearest_lane` (3D) answered the street under
  the deck, but the deck lane kept the wreck as well.
* `TrafficDirector._player_road` kept the lane of the player while the 3D distance to the lane
  position was under `PLAYER_ROAD_RADIUS` (40 m). A player that came down a ramp and drives
  on the street under the deck is 9.4 m from the deck lane (10 m below it) - inside the
  radius - so the traffic ring filled the deck's road instead of the street's.

## The fix
* `traffic_level.gd` holds the rule of the level: two things are on the same level when their
  heights differ by at most `LEVEL` (4.0 m) - the value of `briefs/improve/_layers-common.md`
  for the AI. `nearest_lane_at_level` is the level-aware version of `LaneGrid.nearest_lane`:
  the grid holds the samples of the lanes with the height of the lane, so the samples on the
  level of the point are the ones that count and the closest of them gives the lane. Nothing
  is allocated (the search walks the cells of the grid) and the search only runs when the
  common case (the player on its own lane) does not answer.
* `traffic_index.gd` `index_wreck`: the wreck is indexed on the lane it was hit on only while
  the body is within `WRECK_LANE_DISTANCE` of that lane position; otherwise it is indexed on
  the lane it really lies on, and only on a lane that is on the level of the body. With no lane
  under the body the wreck is indexed nowhere.
* `traffic_director.gd` `_player_road`: the lane of the player is kept only while the player
  is on its level (the height of the lane position against the height of the player); otherwise
  the nearest lane on the level of the player is used. The rule is the same as the one the
  spawn ring already uses (`TrafficRing.LEVEL_TOLERANCE` = 4.0 m), so the road of the player
  and the measured lanes of the ring now agree.

## In progress / next
- (nothing; the job is done)

## How to test (exact commands)
- `python tools/gd.py test res://ai/traffic/tests/test_layers_2.gd`
- `python tools/gd.py check --only=res://ai/traffic/`
- `python tools/mutation_check.py --test res://ai/traffic/tests/test_layers_2.gd --files auto`
- `python tools/run_tests.py --filter res://ai/traffic/ --jobs 3 --out F:/dev/skyrush-out/tmp/traffic-layers-2/tests --allow-fail test_lanes_world`

## Evidence (key output lines)
* On the OLD code, `python tools/gd.py test res://ai/traffic/tests/test_layers_2.gd`:
```
PASS the wreck that fell to the street is indexed on the street
FAIL the wreck that fell to the street is not indexed on the deck
PASS the wreck without a lane under it is not indexed on the street
FAIL the wreck without a lane under it is not indexed on the deck
PASS the wreck that stayed on the deck is indexed on the deck
PASS the wreck that stayed on the deck is not indexed on the street
FAIL the road of the player on the street is the street (deck_road)
PASS the road of the player on the deck is the deck (deck_road)
TRAFFIC LAYER 2 TESTS FAILED (3 failures)
```
* With the fix:
```
PASS the wreck that fell to the street is indexed on the street
PASS the wreck that fell to the street is not indexed on the deck
PASS the wreck without a lane under it is not indexed on the street
PASS the wreck without a lane under it is not indexed on the deck
PASS the wreck that stayed on the deck is indexed on the deck
PASS the wreck that stayed on the deck is not indexed on the street
PASS the road of the player on the street is the street (street_road)
PASS the road of the player on the deck is the deck (deck_road)
TRAFFIC LAYER 2 TESTS OK (0 failures)
```
* `python tools/gd.py check --only=res://ai/traffic/` → `CHECK 39 files, 0 failed, 0 engine errors, 0 warnings`
* `python tools/mutation_check.py --test res://ai/traffic/tests/test_layers_2.gd --files auto` →
  `mutating: game/ai/traffic/traffic_director.gd game/ai/traffic/traffic_index.gd` and
  `MUTATION_CHECK OK: the test fails on the old code of 0b5c8247bc (3 FAIL lines, first: FAIL the wreck that fell to the street is not indexed on the deck)`
* `python tools/run_tests.py --filter res://ai/traffic/ --jobs 3 --out F:/dev/skyrush-out/tmp/traffic-layers-2/tests --allow-fail test_lanes_world` →
  `12 tests, 11 passed, 1 failed or timed out` / `allow list: test_lanes_world` /
  `RUN_TESTS_RATCHET OK (1 failing, all of them on the allow list)`

## Known issues
- `test_lanes_world` fails on this machine on the millisecond budgets only (1.187 ms/tick
  against 0.5 ms, 3.099 ms p99 against 2.0 ms, 0.173 ms/spawn against 0.100 ms); it is on the
  allow list of the acceptance command and it is not caused by this change (the same job
  measured 1.475 ms/tick before it, on a busier machine).
- `game/ai/traffic/traffic_level.gd` and `game/ai/traffic/tests/test_layers_2.gd` are new
  files: the import wrote the `.uid` files next to them (they are in the folder the job owns).

## Requests
- (none)
