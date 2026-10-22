# Job: obstacles in the sky lanes (drones, neon billboards, crane arms)

Godot GDScript, unit `game/world/` (the builder of the sky lanes). Read `briefs/improve/_godot-common.md` first, and `ref/gameplay/DOSSIER.md` section 5.6 (Sky Lanes).

## Goal
A sky lane (飞行航道) is a flight tube, 14 m wide and 8 m high, along a spline of 400 to 1500 m (the map has 5 of them). The dossier gives it **obstacles - drones, neon billboards, crane arms; a hit costs 15 HP and 30 % of the speed, never a wreck**. The lanes have none: the flight is an empty tunnel of ring gates. The car side is done: `ArcadeCar.flight_hit()` (new, returns true when the hit counted; it only counts while the car flies in a lane and once per second) does the damage and the slow-down.
Build the obstacles into the lanes.

## Evidence (read the code)
- `game/world/build/sky_lane_builder.gd` builds each lane in `_build_lane(spec, parent)`: the `SkyLane` node (`game/core/contracts/sky_lane.gd`, a `Path3D` with the exported `tube_half_width = 7.0`, `tube_up = 5.0`, `tube_down = 3.0`, `curve`, `length()`, `frame_at(offset)`), the launch pad, the ring gates (`_build_rings`) and the gantry. No obstacle anywhere.
- `game/world/loader/proc_meshes.gd` has the helpers `ProcMeshes.box(size)` and `ProcMeshes.glow(color, energy)` that the builder uses for the pad and the rings.
- The trigger layer is `1 << 3` and the vehicles are `1 << 1` (the launch pad does `pad.collision_layer = 1 << 3; pad.collision_mask = 1 << 1`).
- A flying car reports `telemetry.flying == true` (`CarTelemetry`).

## What to build
1. A new file `game/world/build/sky_obstacles.gd` (`extends RefCounted`) with `func build(lane: SkyLane) -> int` that places the obstacles of one lane and returns how many it made. Rules:
   - The first obstacle is 200 m after the start of the curve, the next ones every 180 to 260 m (a seeded `RandomNumberGenerator`, the seed is `hash(str(lane.name))`, so the same lane always gets the same obstacles), none within 120 m of the end of the curve. A lane shorter than 400 m gets one obstacle at its middle.
   - Three kinds, in this order, repeating: `drone` (a flat 1.6 x 0.35 x 1.6 m glowing body with a ring light, magenta), `billboard` (a 4.2 x 2.4 x 0.3 m glowing panel, cyan, hanging on two thin poles), `crane` (a thin 10 m long arm that reaches into the tube from one side, amber, with a red warning light at its tip).
   - The position inside the tube: the lateral offset of the centre is a random value in [-4.5, 4.5] m and the height a random value in [-1.5, +3.0] m relative to the lane centre, both along `lane.frame_at(offset)` (so the obstacle follows the curve and the bank). Each obstacle covers at most 40 % of the 14 x 8 m cross-section, so there is always a line past it.
   - Each obstacle is a `Node3D` named `SkyObstacle_<lane id>_<n>` in the group `sky_obstacle`, with the meshes as children and an `Area3D` child named `Hit` with a `BoxShape3D` that matches the meshes (a little larger is fine), `collision_layer = 1 << 3`, `collision_mask = 1 << 1`, `monitoring = true`. It is added as a child of the lane (the lane is at the identity transform: the positions are world positions).
   - `Hit.body_entered(body)`: `var vehicle := body as VehicleBase`; when it is not null, has the method `flight_hit` and `vehicle.telemetry.flying` is true, call `vehicle.call("flight_hit")`. Nothing else (a car on the ground under the lane is not hit).
   - Use one shared material per kind (do not create a material per obstacle), no per-frame work, no allocation in `_process`.
2. In `sky_lane_builder.gd` `_build_lane`: after `_build_rings(lane, points)` call `SkyObstacles.new().build(lane)` (preload the new file at the top like the other helpers).
Nothing else changes: the pad, the rings, the gantry, the data of the city.

## Files you own
`game/world/build/sky_lane_builder.gd`, `game/world/build/sky_obstacles.gd`, and the new test `game/world/tests/test_sky_obstacles.gd`. Everything else is read-only (`ArcadeCar.flight_hit` exists already).

## The test you write FIRST (`game/world/tests/test_sky_obstacles.gd`)
Build the real world like `game/world/tests/test_route_layers.gd` does (`CityData.forced_city_path`, instantiate `res://world/world.tscn`, wait until `loading_fraction >= 1.0`). Then check, with `PASS ...` / `FAIL ...` lines and a last line `SKY OBSTACLE TESTS OK (0 failures)` (quit 0) or `SKY OBSTACLE TESTS FAILED` (quit 1):
1. There are 5 `SkyLane` nodes (find them with `find_children("*", "SkyLane", true, false)`).
2. Every lane of 400 m or more has at least `floor(length / 300) - 1` nodes of the group `sky_obstacle` among its children; a lane has at least one.
3. Every obstacle lies inside the tube: transform its position into the lane frame at the nearest offset (`lane.curve.get_closest_offset`, `lane.frame_at`): |lateral| <= 7.0 and -3.0 <= height <= 5.0.
4. The obstacles of a lane are at least 120 m apart along the curve, the first is at least 150 m and the last at least 100 m from the ends.
5. The three kinds all occur on the longest lane (check the node names or a metadata `kind` you set with `set_meta`).
6. Deterministic: a second call `SkyObstacles.new().build(lane)` on a fresh copy of the same lane (or the second world build) gives the same positions (compare the first three).
7. The hit: add a fake flying car (a small script class `extends VehicleBase` defined inside the test with a `flight_hit()` that counts calls, `telemetry.flying = true`, a `CollisionShape3D`, `collision_layer = 1 << 1`, `gravity_scale = 0.0`) inside the first obstacle's `Hit` area; wait 3 physics frames: `flight_hit` was called exactly once. A second fake car with `telemetry.flying = false` inside the same area: its count stays 0.
Run it BEFORE you change anything: 2 to 7 must fail (check 1 passes).

## Acceptance (the runner executes these itself)
1. `python tools/gd.py check --only=res://world/` prints `CHECK N files, 0 failed, 0 engine errors`.
2. `python tools/gd.py test res://world/tests/test_sky_obstacles.gd` prints `SKY OBSTACLE TESTS OK`.
3. `python tools/mutation_check.py --test res://world/tests/test_sky_obstacles.gd --files auto` prints `MUTATION_CHECK OK`.
4. `python tools/run_tests.py --filter res://world/ --jobs 3 --out F:/dev/skyrush-out/tmp/world-sky-obstacles/tests --allow-fail test_route_layers,test_world_api` ends with `RUN_TESTS_RATCHET OK` (those two are judged by another job; every other world test must still pass, the world build must not slow down noticeably).

## Pitfalls
- Do NOT `preload` your new file in the test: use `ResourceLoader.exists(path)` and `load(path)` at run time, so that the OLD code (where the file does not exist) prints `FAIL` lines instead of a script error: the runner checks that your test fails on the old code.
- Obstacles that block the whole tube, or that sit on the centre line at the start (the player must be able to enter the lane and see the obstacle coming).
- One `ShaderMaterial`/`StandardMaterial3D` per obstacle (use shared materials), or a node per ring: the world build time is measured.
- `body_entered` hits for every vehicle: only flying vehicles are hit.
- Random positions that differ between runs (the lane builds on every game start; the obstacles must be the same).
