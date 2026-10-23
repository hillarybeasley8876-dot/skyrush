# Job: police units and roadblocks must respect the level (second round: spawn spots, roles, ranking, roadblocks)

Godot GDScript, unit `game/ai/police/`. Read `briefs/improve/_godot-common.md` and `briefs/improve/_layers-common.md` first. The first round (`police-layers`, merged) fixed the busted meter and the hiding spots; read its test `game/ai/police/tests/test_layers.gd` and its status `status/improve/police-layers.md`: you build on it (the rule is `PolicePursuit.LEVEL := 4.0` m).

## Goal
Four more places of the police code measure with a 3D radius or in the player's flat frame and never ask which level a car is on. On the real map a street runs under the elevated roads, so a cop 10 m below the player is not "next to" the player. Fix them.

## The four defects (read each function first; the line numbers are from an audit, they may have moved)
1. **Oncoming spawn on the wrong level.** `police_spawn_spots.gd` `oncoming_spot(player, ...)` takes the first lane (in index order) that opposes the player, is 150 to 320 m away (3D) and not visible. It never looks at the height of that lane: a unit can spawn on the street under the deck the player is on, "oncoming", 150 m away, and can never reach the player. The same in `oncoming_lane_at(point, forward)` (used for the head-on role): the lane found within `HEAD_ON_LANE_RADIUS` may be 10 m above or below `point`.
   Rule: the spot (the middle of the lane) must be within `LEVEL` of the player's height; `oncoming_lane_at` only returns lanes whose closest point is within `LEVEL` of `point.y`.
2. **Roles on the wrong level.** `police_car_roles.gd` `_try_role_state(distance)` enters RAM / PIT / BOX when the unit is near the player in the player's frame (`rel := PoliceDriver.relative_to_player(car, player)`, `rel.x` sideways, `rel.z` along; check what `rel.y` is) or `distance < BOX_ENTER_DISTANCE` (3D). A cop under the deck takes a RAM/PIT/BOX role against a car 10 m above. Rule: no role state is entered while the unit is more than `LEVEL` above or below the player (HEAD_ON is decided by the spawn and stays as it is).
3. **The three nearest units are ranked by 3D distance.** `police_squad.gd` `_ranked` / `_hold_back`: the units that count as "the nearest three" (they keep their roles, the rest hold back) are the nearest by 3D distance, so a unit on the street under the player holds a slot that a unit on the player's level should have. Rule: units on the player's level rank before units on another level (keep the 3D distance as the order inside each group). Find where `_ranked` is sorted.
4. **Roadblocks and sites.** `police_roadblock.gd` `tick`: the block counts as "passed" when the player came within `PASSED_DISTANCE := 25` m (3D) and then went away: a player that drives over a block on another level, or under it, "passes" it. Rule: only a player on the level of the block (height difference at most `LEVEL`) counts as having met or passed it. `police_blockade.gd` `_site_on_route(...)`: a roadblock site is accepted when `site.origin.distance_to(route[index]) < best_distance` (3D, with `SITE_ROUTE_DISTANCE`): a site 10 m below the route passes when the radius is 25 m. Rule: the site must also be within `LEVEL` of the route point's height.

## Files you own
`game/ai/police/` (existing tests are read-only). You add ONE new test file `game/ai/police/tests/test_layers_2.gd`.

## The test you write FIRST (`game/ai/police/tests/test_layers_2.gd`)
Use the helpers the first round used (`police_test.gd` `T`, the stub car `res://core/stubs/stub_car.tscn`, `TrafficTestRoad`-like hand-built lane graphs for the spawn spots: look at how `test_hold_back.gd`, `test_head_on.gd` and `test_roadblock.gd` build their worlds). One test per defect, each with a same-level control that must still behave as before and a wrong-level case that must be rejected. Print `PASS ...` / `FAIL ...` lines and end with `POLICE LAYER 2 TESTS OK (0 failures)` (quit 0) or `POLICE LAYER 2 TESTS FAILED` (quit 1):
1. `oncoming_spot`: a lane graph with an oncoming street lane at y = 0 and an oncoming deck lane at y = 10, both 200 m ahead, the player on the deck (y = 10.6) driving towards them: the spot returned is on the deck lane (control: with the player at y = 0.6 it is the street lane); with ONLY the street lane present and the player on the deck, `oncoming_spot` returns an empty dictionary. `oncoming_lane_at` the same.
2. `_try_role_state`: a PIT unit 6 m behind and 3 m beside the player at the same height enters `State.PIT`; the same unit 10 m lower stays in `PURSUE`. Same for RAM and BOX.
3. The squad: three units on the player's level 60 m, 70 m, 80 m away and one unit on the street 20 m away (10 m lower): after the squad's ranking, the street unit is not among the three that keep their roles (`hold_back == true` for it), the three on the level are not held back.
4. The roadblock: a block at y = 0, the player drives over it at y = 10.6 (25 m radius crossed twice): `passed` stays false; at y = 0.6 it becomes true. `_site_on_route`: a site 10 m below the route is not chosen, a site on the route is.
Run it BEFORE you change anything: every wrong-level check must fail for the right reason, every control must pass. If a control fails the test is wrong, not the code.

## Acceptance (the runner executes these itself)
1. `python tools/gd.py check --only=res://ai/police/` prints `CHECK N files, 0 failed, 0 engine errors`.
2. `python tools/gd.py test res://ai/police/tests/test_layers_2.gd` prints `POLICE LAYER 2 TESTS OK`.
3. `python tools/mutation_check.py --test res://ai/police/tests/test_layers_2.gd --files auto` prints `MUTATION_CHECK OK`.
4. `python tools/run_tests.py --filter res://ai/police/ --jobs 3 --out F:/dev/skyrush-out/tmp/police-layers-2/tests --allow-fail test_perf` ends with `RUN_TESTS_RATCHET OK`.

## Pitfalls
- A level test that also rejects the sky-lane flight or airborne players where the existing rules allow them.
- Changing the spawn distances, the role geometry numbers or the hold-back count.
- Ranking by "plan distance" instead of the level-first order (the units far away on the same level must still rank after the near ones on the same level).
- Per-tick allocations in the squad ranking (the police tick has a time budget, `test_perf`).
