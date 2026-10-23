# world-sky-obstacles — obstacles in the sky lanes

## Plan
1. Write `game/world/tests/test_sky_obstacles.gd` FIRST (loads `res://world/build/sky_obstacles.gd`
   at run time through `ResourceLoader.exists`/`load`, never `preload`).
   Verify: `python tools/gd.py test res://world/tests/test_sky_obstacles.gd` → checks 2..7 FAIL, 1 passes.
2. Write `game/world/build/sky_obstacles.gd` (`extends RefCounted`, `build(lane: SkyLane) -> int`):
   seeded offsets (first 200 m, gap 180..260 m, 120 m from the end), kinds drone/billboard/crane,
   lateral [-4.5,4.5], height [-1.5,3.0] on `lane.frame_at(offset)`, shared meshes + shared
   `ProcMeshes.glow` materials, `Hit` Area3D (layer 1<<3, mask 1<<1) calling `flight_hit()` on a
   flying `VehicleBase`.
   Verify: `python tools/gd.py test res://world/tests/test_sky_obstacles.gd` → `SKY OBSTACLE TESTS OK`.
3. Wire it into `sky_lane_builder.gd` `_build_lane` after `_build_rings`.
   Verify: same test again (the obstacles come from the real world build).
4. Acceptance: `python tools/gd.py check --only=res://world/`,
   `python tools/gd.py test res://world/tests/test_sky_obstacles.gd`,
   `python tools/mutation_check.py --test res://world/tests/test_sky_obstacles.gd --files auto`,
   `python tools/run_tests.py --filter res://world/ --jobs 3 --out F:/dev/skyrush-out/tmp/world-sky-obstacles/tests --allow-fail test_route_layers,test_world_api`.

## Done
- `game/world/build/sky_obstacles.gd` (new, 246 lines): `build(lane) -> int`, offsets 200 m / 180-260 m
  apart / 120 m from the end, a lane under 400 m gets one obstacle in its middle; kinds drone →
  billboard → crane; the centre is at lateral [-4.5, 4.5] and height [-1.5, 3.0] of
  `lane.frame_at(offset)`; seed `hash(str(lane.name))`; the meshes and the materials are shared
  (one mesh and one material per kind, `ProcMeshes.glow`); every obstacle is a `Node3D`
  `SkyObstacle_<lane id>_<n>` in the group `sky_obstacle` with a `Hit` Area3D (layer 1<<3,
  mask 1<<1, monitoring) whose `body_entered` calls `flight_hit()` only on a `VehicleBase` that
  flies.
- `game/world/build/sky_lane_builder.gd`: `SkyObstacles.new().build(lane)` after `_build_rings`.
- `game/world/tests/test_sky_obstacles.gd` (new, 343 lines): 40 checks — 5 lanes, the number of
  obstacles, inside the tube, in the flight box, the meshes and the trigger of every obstacle, the
  spread along the curve, the three kinds, the determinism, the hit (a flying car is hit once, a
  car on the ground is not hit).

## In progress / next
- nothing: the four acceptance commands all pass.

## How to test (exact commands)
- `python tools/gd.py test res://world/tests/test_sky_obstacles.gd`
- `python tools/gd.py check --only=res://world/`
- `python tools/mutation_check.py --test res://world/tests/test_sky_obstacles.gd --files auto`
- `python tools/run_tests.py --filter res://world/ --jobs 3 --out F:/dev/skyrush-out/tmp/world-sky-obstacles/tests --allow-fail test_route_layers,test_world_api`

## Evidence (key output lines)
- before the fix (the builder did not exist): `FAIL lane SkyLane_huangpu_jump: 0 obstacles (at
  least 4 wanted)`, `FAIL res://world/build/sky_obstacles.gd does not exist`, `FAIL no obstacle to
  hit`, `SKY OBSTACLE TESTS FAILED (13 of 14 checks)` — check 1 (5 lanes) passed.
- `CHECK 81 files, 0 failed, 0 engine errors, 0 warnings`
- `SKY OBSTACLE TESTS OK (40 checks)` — e.g. `PASS lane SkyLane_huangpu_jump: 7 obstacles (at least
  4 wanted)`, `PASS lane SkyLane_huangpu_jump: 0 of 7 obstacles are outside the tube`,
  `PASS lane SkyLane_huangpu_jump: the kinds { "drone": 3, "billboard": 2, "crane": 2 } (missing [])`,
  `PASS the rebuilt lane SkyLane_huangpu_jump: 3 of the first 3 obstacles are at the same place`,
  `PASS the flying car was hit 1 times (want 1)`, `PASS the car on the ground was hit 0 times (want 0)`.
- `MUTATION_CHECK OK: the test fails on the old code of 2ad0be3880 (13 FAIL lines, first: FAIL lane
  SkyLane_huangpu_jump: 0 obstacles (at least 4 wanted))` (also with
  `--files game/world/build/sky_lane_builder.gd game/world/build/sky_obstacles.gd`, the case after
  the commit, when the new file is removed by the mutation).
- `13 tests, 11 passed, 2 failed or timed out` / `RUN_TESTS_RATCHET OK (2 failing, all of them on
  the allow list)` — `test_route_layers` and `test_world_api` are on the allow list; their failures
  are about the ground lane network (4837 links join lanes more than 1.5 m apart in height, the
  routes do not report the leg meta data), not about the sky lanes.
- the world build is not slower: `[world] sites: 0.85 s` (the phase that builds the sky lanes;
  0.88 s before the change), the whole world 21.63 s with the cache.

## Known issues
- The obstacles are not visible from the ground: they are 20 to 200 m up in the lanes. No
  screenshot or drive was made (the brief does not ask for one, and the game would have to fly a
  lane to see them).
- A GDScript quirk of this Godot build: a string literal that appears more than once in a file is
  interned as a `StringName`, and `Array[String].has()` then does not find the equal `String` (the
  kinds are counted in a `Dictionary` in the test for that reason).

## Requests
- none
