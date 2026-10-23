# police-layers-2 — the police must not cross the levels of the map (spawn spots, roles, ranking, roadblocks)

## Plan
1. Write `game/ai/police/tests/test_layers_2.gd` (four defects, each with a same-level control
   and a wrong-level case; hand-built lane graphs, the stub car, a `TestCop`, a `TestWorld`).
   Verify: `python tools/gd.py test res://ai/police/tests/test_layers_2.gd` → the wrong-level
   checks FAIL, the controls PASS, the run ends `POLICE LAYER 2 TESTS FAILED` (exit 1).
2. `game/ai/police/police_spawn_spots.gd`: `oncoming_spot` skips a lane whose middle is more than
   `PolicePursuit.LEVEL` above or below the player; `oncoming_lane_at` skips a lane whose
   closest point is not on the level of the point.
   Verify: the test file → the six spawn checks PASS.
3. `game/ai/police/police_car_roles.gd`: `_try_role_state` enters RAM / PIT / BOX only when the
   unit is on the level of the player (HEAD_ON stays as it is).
   Verify: the test file → the six role checks PASS.
4. `game/ai/police/police_squad.gd`: `_sort_by_distance` sorts the units of the player's level
   before the units of another level (the 3D distance keeps the order inside the groups).
   Verify: the test file → the two squad checks PASS.
5. `game/ai/police/police_roadblock.gd`: `tick` only counts a player that is on the level of the
   block; `game/ai/police/police_blockade.gd`: `_site_on_route` only takes a site that is on the
   level of the route.
   Verify: the test file → the four roadblock checks PASS.
6. `python tools/gd.py check --only=res://ai/police/` → `CHECK N files, 0 failed, 0 engine errors`.
7. `python tools/mutation_check.py --test res://ai/police/tests/test_layers_2.gd --files auto`
   → `MUTATION_CHECK OK` (the test fails on the old code).
8. `python tools/run_tests.py --filter res://ai/police/ --jobs 3 --out
   F:/dev/skyrush-out/tmp/police-layers-2/tests --allow-fail test_perf` → `RUN_TESTS_RATCHET OK`.

## Done
- The test was written FIRST and run on the old code: the 11 wrong-level checks FAILED and the 7
  same-level controls PASSED (`POLICE LAYER 2 TESTS FAILED`, exit 1). The controls are the proof
  that the fix does not switch the rules off for everybody.
- `game/ai/police/police_spawn_spots.gd`:
  - `oncoming_spot`: a lane whose middle is more than `PolicePursuit.LEVEL` (4 m) above or below
    the player is skipped; the distances (150-320 m), the "ahead" rule and the "out of sight"
    rule are untouched.
  - `oncoming_lane_at`: the closest point of the lane has to be within `LEVEL` of `point.y`
    (the head-on role). The radius of the search (15 m) is unchanged.
- `game/ai/police/police_car_roles.gd`: `_try_role_state` computes `on_level` (the height of the
  unit against the player) and enters RAM / PIT / BOX only on the level of the player. The
  geometry numbers (RAM_DISTANCE, RAM_LATERAL, PIT_*, BOX_ENTER_DISTANCE) and the role of the
  head-on unit (the spawn decides it) are unchanged.
- `game/ai/police/police_squad.gd`: `_sort_by_distance` adds `OTHER_LEVEL_KEY` (1e9, larger than
  any squared distance of the world) to the key of a unit that is not on the level of the
  player: the units of the player's level rank first, the 3D distance keeps the order inside
  the groups. The sort is still the same insertion sort on the same one array: no new
  allocation in the tick (`test_perf` is green).
- `game/ai/police/police_roadblock.gd`: the block counts a player as "met" only when the player
  is on its level (`_level_closest`); the flag `passed` says that. The block still leaves the
  road when the player has gone past it (the old 3D rule, `_closest`), so a block the player
  only drove over does not stay on the road for ever.
- `game/ai/police/police_blockade.gd`: `_site_on_route` only takes a site that is within `LEVEL`
  of the height of the route point; `SITE_ROUTE_DISTANCE` and the facing rule are unchanged.
- `game/ai/police/tests/test_layers_2.gd` (new, 19 checks): the four defects with a same-level
  control each. The world is hand-built: a lane graph with an oncoming street lane at y = 0 and
  an oncoming deck lane at y = 10, a straight route lane of 600 m, the stub car of the core
  (frozen, `gravity_scale = 0`) and a `TestCop` (a `PoliceCar` without the car physics).

## In progress / next
- Nothing: the job is finished. The lead commits.

## How to test (exact commands)
- `python tools/gd.py test res://ai/police/tests/test_layers_2.gd`
- `python tools/gd.py check --only=res://ai/police/`
- `python tools/mutation_check.py --test res://ai/police/tests/test_layers_2.gd --files auto`
- `python tools/run_tests.py --filter res://ai/police/ --jobs 3 --out F:/dev/skyrush-out/tmp/police-layers-2/tests --allow-fail test_perf`
- `python tools/run_tests.py --filter res://ui/hud/ --jobs 2 --out F:/dev/skyrush-out/tmp/police-layers-2/tests_hud --allow-fail test_hud_perf`
- `python tools/run_tests.py --filter res://modes/ --jobs 2 --out F:/dev/skyrush-out/tmp/police-layers-2/tests_modes`

## Evidence (key output lines)
Test BEFORE the fix (the old code of 0b5c824, the base of the job):
```
FAIL the oncoming spot of a player on the deck is on the deck lane
PASS the oncoming spot of a player on the street is on the street lane
FAIL there is no oncoming spot for a player on the deck when the street is the only lane
FAIL the oncoming lane of a point on the deck is the deck lane
PASS the oncoming lane of a point on the street is the street lane
FAIL there is no oncoming lane on the deck when the street is the only lane
PASS a PIT unit on the level of the player takes its role
FAIL a PIT unit 10 m below the player keeps the state PURSUE
PASS a RAM unit on the level of the player takes its role
FAIL a RAM unit 10 m below the player keeps the state PURSUE
PASS a BOX unit on the level of the player takes its role
FAIL a BOX unit 10 m below the player keeps the state PURSUE
FAIL the unit on the street below the player holds back
FAIL the three units on the level of the player keep their roles
FAIL a block on the street is not passed by a player on the deck
PASS a block on the street is passed by a player on the street
PASS a roadblock site on the route is used
FAIL a roadblock site 10 m below the route is not used
POLICE LAYER 2 TESTS FAILED
```
Test AFTER the fix:
```
PASS the oncoming spot of a player on the deck is on the deck lane
PASS the oncoming spot of a player on the street is on the street lane
PASS there is no oncoming spot for a player on the deck when the street is the only lane
PASS the oncoming lane of a point on the deck is the deck lane
PASS the oncoming lane of a point on the street is the street lane
PASS there is no oncoming lane on the deck when the street is the only lane
PASS a PIT unit on the level of the player takes its role
PASS a PIT unit 10 m below the player keeps the state PURSUE
PASS a RAM unit on the level of the player takes its role
PASS a RAM unit 10 m below the player keeps the state PURSUE
PASS a BOX unit on the level of the player takes its role
PASS a BOX unit 10 m below the player keeps the state PURSUE
PASS the unit on the street below the player holds back
PASS the three units on the level of the player keep their roles
PASS a block on the street is not passed by a player on the deck
PASS a block on the street is passed by a player on the street
PASS the block the player drove over leaves the road anyway
PASS a roadblock site on the route is used
PASS a roadblock site 10 m below the route is not used
POLICE LAYER 2 TESTS OK (0 failures)
```
Checks:
```
CHECK 66 files, 0 failed, 0 engine errors, 0 warnings      (res://ai/police/)
CHECK 726 files, 0 failed, 0 engine errors, 0 warnings     (the whole project)
```
Folders:
```
20 tests, 20 passed, 0 failed or timed out
RUN_TESTS_RATCHET OK (0 failing, all of them on the allow list)      (res://ai/police/)
5 tests, 5 passed, 0 failed or timed out
RUN_TESTS_RATCHET OK (0 failing, all of them on the allow list)      (res://ui/hud/)
7 tests, 7 passed, 0 failed or timed out                              (res://modes/)
```
Mutation:
```
mutating: game/ai/police/police_blockade.gd game/ai/police/police_car_roles.gd game/ai/police/police_roadblock.gd game/ai/police/police_spawn_spots.gd game/ai/police/police_squad.gd
MUTATION_CHECK OK: the test fails on the old code of 0b5c8247bc (11 FAIL lines, first: FAIL the oncoming spot of a player on the deck is on the deck lane)
```

## Known issues
- `test_perf` is on the allow list of the brief: it measures the wall time of the tick. It
  failed once in a parallel run of the whole folder (4.75 ms of 3.0 ms) and passed alone
  (1.44 ms / 1.90 ms of 3.0 ms) and in the other folder runs: the machine was busy, not the
  code. The squad ranking adds one `absf` and one addition per unit and no allocation.
- The block of `police_roadblock.gd` now leaves the road on the old 3D rule (the player went
  past it) and not only when the flag `passed` is set: otherwise a block the player only drove
  over (on the deck above it) would stay on the road for the whole pursuit. The flag `passed`
  itself says whether the player really met the block on its level (the rule of the brief).

## Requests
- None.
