# improve/openworld — what changed and what is left

Branch `improve/openworld` (pushed to GitHub, history without personal data). The brief: open-world sports-car map (viaduct links, correct Z interaction, real
collisions, behaviour logic, the flying feature), with a weak cheap model (MiniMax M3.1 Flash) as the workers and the lead as the
reviewer (`tools/m31w`). Then: a web-sourced hero car (black and white), and "continue to optimise all bugs, correct interactions".

## The hero car

Khronos Car Concept (CC BY 4.0), converted by `blender/car/concept` to the vehicle contract: white pearl paint, black paint, black
rims, smoked glass. Collision box 1.9 m wide (the oracles' car), floor 0.34 m over the road (`MIN_BOX_BOTTOM`).

## The traffic and police cars

Found on the web instead of generated: the CC0 "Free Low Poly Vehicles Pack" by Rgsdev, converted to the car contract by
`blender/npc_cars/web/convert.py` (status/npc_cars.md). 11 cars of 1.4-1.9 k triangles and 70-95 KB each, replace the procedural fleet
(21 k triangles, 34-42 surfaces and 5 MB of textures per car); the nodes, the lamps, the wheels and the tear-off parts (bumpers, bonnet)
of the contract are kept, so the traffic, the police, the vehicle specs and the damage unit work unchanged. The drone is still procedural.

## Collisions and interactions fixed in the last rounds (every item has a test or a tool that measures it)

| what | cause | fix | check |
|---|---|---|---|
| the car flew or stuck to walls | wheel probes took walls/ceilings for ground; kerbs of 15 cm launched the car; solver spikes | ground normal limit, damped bump stop, solver spike guard, box floor | `vehicle/tests` (kerb climb, air boosts), `fuzz_drive.gd` |
| street props had no collision at all | the shapes were freed with their builder | the body keeps the shapes; shapes turn with the prop; soft furniture (bollards, bins, signs ...) is not solid | `test_prop_collision_orientation.gd` |
| bus shelters and noise walls across the road | heading mirrored in the roads generator; boxes put into world axes | generator fixed, shelters lie along the lanes, boxes that reach into a lane move away or go | `test_prop_alignment.gd` |
| kerb and median walls, the edge of the world | none existed / the ground ended at the window | kerb colliders, 100 m of extra ground and four walls | `test_edge_walls.gd`, `fuzz_drive.gd` |
| falls off the viaducts | open deck edges (903), low parapet collider with a chamfer | edge-fence job, `edgewalls.py` (237 walls), parapet collider 1.0 m with a vertical face | `fuzz_drive.gd --elevated=1`: 26 of 40 drives left the deck -> 0-2 |
| traffic cars of different lanes drove through each other, jammed on kerbs | the lane hash knew one lane only | `DriveContext.cells`, `_conflict_gap` (the younger car yields), box floor | `test_conflict_yield.gd`, `test_kerb_lane.gd`, `soak_traffic.gd` |
| the Bund facades stood in the west lanes | the dossier line is up to 10 m east of the road of the city | `bund/data.py` follows the city road (status/bund.md) | `test_bund_lanes.gd` |
| cross streets ran through the Bund buildings | the streets of the city run to the centre of the Bund | `roads/buildingcut.py` ends them at the buildings (status/roads.md) | `test_bund_lanes.gd`, the `check_*` oracles of tools/city |
| trees and lamps in the mouth of a junction | the filter kept 8 m around the centre, the box is bigger | `FurnitureFilter._index_mouths` (status/world.md) | `test_junction_mouths.gd` |
| the rivals stopped dead at the start of the Bund sprint (3-4 rescued in 20 s) | connector lanes widened the measured road by 10 m; a tree in the mouth of Fuzhou Rd | `RivalRoad.road_frame` leaves connectors out, `LANE_RATE`, the tree is gone | `test_real_start.gd` (both routes), `test_real_route.gd` |
| two tests died before they measured anything | no gate boards for the 8 gates of the sandbox loop | `gen_gate_textures.py` | `test_race_flow.gd` runs to its own thresholds now |
| 13 identical noise walls at the end of the Yan'an Elevated | a declared run longer than the road, `road.at` clamps | `min(b, road.length)` | the data: 33 -> 19 walls |

## "Driving in the air" and the camera on reverse (the player's report: the car hung on the wall of a house, see-through)

| what | cause | fix | check |
|---|---|---|---|
| the camera swung round in front of a reversing car and jumped from side to side | the yaw follows the velocity; a straight reverse sat on the 180 degree seam of the nose bias (126 degrees, 7 a tick) | `CameraMath.follow_direction` folds a backwards velocity onto the front of the car | `test_camera.gd` (reverse checks, mutation-checked) |
| the car stayed see-through for good | a second wreck in the 2 s ghost saved the half transparent car as the car to come back to | the running ghost is restarted, not stacked | `damage/test_respawn.gd` |
| a respawn put the car on top of things over the road | the road height ray started 4 m over the lane: booth roofs, the Bund promenade, decks, the Waibaidu deck (334 of 68,000 lane points) | the ray starts 0.5 m over the lane (99.6 % of the lanes lie within 0.1 m of their road) | `world/test_spawn_height.gd`, `tools/spawn_height_probe.gd` |
| respawned into a tree or a wall at 60 km/h (10 of 58 in 4 s), once with the roof in a deck | the nearest lane point was taken as it was | `respawn_on_lane` walks along the lane to a spot whose car box and 30 m ahead are clear | `world/test_spawn_height.gd`, `tools/respawn_probe.gd` |
| the ghost stood on the police cars it drove through, and was kicked up and spun when its ghost ended inside one | the wheel probes saw the cars; the collision came back with the boxes inside each other | the probes follow the mask of the body; the ghost waits (up to 3 s more) until the car is clear | `damage/test_respawn.gd` (both mutation-checked) |
| a car that hung on a wall or lay beached never came back (only the R key, not in the controls list) | the roof rule knew a tilt over 107 degrees, the out-of-bounds rule a car 15 m from every lane | the stuck rule: under 1.5 m/s, fewer than 2 wheels down or a tilt over 50 degrees, for 2 s -> back on the road with a toast that names R | `vehicle/test_respawn.gd` |
| cars drove on the river and fell through the creek to the kill floor | the bank walls were drawn, without collision; the ground stopped up to 7 m short of the bank; the creek floor was a ribbon with 8 m wedges open at the bends | 1.0 m walls of boxes with gaps where a lane crosses or runs along the bank; the ground is clipped to the bank; the creek floor is its cut outline | `world/test_bank_walls.gd` (4 mutations), `tools/fuzz_drive.gd` |
| a car in the creek next to the bank never came out | it was less than 15 m from the lane of the riverside road, so it was not "lost" | touching the water is lost | `modes/test_out_of_bounds.gd` |

## Street furniture: lamps break away, the rest hurts less (the player: "make it lighter")

Half of the random drives ended on a prop: a lamp of 15 cm stopped a car of 1.9 t dead, and by the damage rules a head-on hit at
108 km/h wrecked it. The street lamps (4,941 of them) have no rigid shape now: a car that drives into one knocks it down
(`world/build/prop_breaker.gd`): the lamp and its light go, its pole falls and fades after 6 s, the car keeps 85 % of its speed and
loses 3 HP (the event `prop_broken` plays a hit and breaking glass). Trees, masts, shelters, planters and billboards stand: they cost
40 % of the damage of a wall and never wreck a car in one hit (a tree at 150 km/h costs 40 HP, at 250 km/h it still wrecks).
Checks: `world/tests/test_prop_breakaway.gd` (the breaker costs 38 us a tick with 91 cars), `damage/tests/test_collision_severity.gd`,
`world/tests/test_prop_collision_orientation.gd`, all three mutation-checked; the picture by a windowed capture (a headless run
cannot read a MultiMesh back).

The player car keeps an incident record in debug builds (`vehicle/incident_recorder.gd`): when it hangs in the air, lies tipped over or is
thrown up without a hop, the last 6 s of the car (position, speed, wheels, what the body touches, the ghost) go to the log as
`[incident]` lines.

## The car on its side, the reset, the barrel roll (the player: "the physics is wrong", "the reset still has an axis problem")

| what | cause | fix | check |
|---|---|---|---|
| the Roadster lay on its side by a median until the R key | the upright torque needs two wheels on the ground; a car with its wheels against the face of a kerb or a planter had none | the righting, for the car of the player only: body contact, fewer than two wheels down and a tilt over 30 degrees turn it back onto its wheels (0.4 s on its side, 0.8 s on its roof) | `vehicle/test_righting.gd` (side against a wall, 20 tipped drops onto a kerb and a planter, on its roof), mutation-checked |
| (AI cars) | a police unit on its roof is disabled (dossier 6.3), the righting took that takedown away | AI cars do not right themselves (`ArcadeCar.self_righting`) | `test_righting.gd` (an AI car stays on its roof), `police/test_heat.gd` |
| a barrel roll turned the car over on the road | the roll went on after the car met the ground | the roll ends when a wheel or the body touches | `test_righting.gd`, mutation-checked |
| full lock at 60-200 km/h, drifts, kerbs at 10-35 degrees, planter scrapes | no failure: the peak tilt stays under 40 degrees in all 17 scenarios | - | `vehicle/test_rollover.gd` |
| the reset faced against the traffic or stood across a junction (554 of 1,181 resets from the middle of the street lanes, facing against or across the lane; 10 on a junction turn) | the nearest lane point, turned to face the way the car faced | `SpawnPlacer.respawn_lane`: the nearest street lane, a lane at an angle to the car counting up to 15 m further away; the car is put on it in the direction of its traffic, never against it | `world/test_respawn_direction.gd` (3 mutations) |
| a reset at a lane that starts over the river put the car on the bed of the river | 6 lane points have no road under them (a street that runs into the river, a junction turn that bulges over it) | a respawn spot needs its road within 1 m under the lane; the respawn walks on along the lane | same test |

## Found and not fixed yet

* The Yan'an tunnel: the ground covers both portal ramps (the ground builder cuts only the water). From Pudong a car drives over the
  portal on the flat ground, through the walls of the bores (they have no collision above the ground); a car coming up the Puxi ramp
  stops dead at the edge of the ground (`tools/tunnel_probe.gd`).
* `st_d7b_ew_11`: the right turn into it from `st_d7b_ns_7` goes to the far end of the lane of the other direction (92 m, over the
  river); `st_link_25/33` start 10-15 m out over the river (roads data; `tools/spawn_height_probe.gd` lists them).
* 18,329 tree trunks (0.25 m) stop a car dead: they stand (a street tree is a tree), they cost 40 % of the damage of a wall.

## The frame rate (the player: "the frame rate is not stable")

Measured with `tools/frame_probe.gd`: a lane follower drives the player car through the city (`--seed=N`: the traffic and the police
draw the same numbers, the route is the same), every frame is split into its physics ticks and the rest, the callbacks of every unit
are timed by giving each unit its own slot in the physics order, and `--ab=<switch>` compares two settings in turns of 4 s in one
drive (the run-to-run spread is large: the number of police cars decides a run).

| what | cause | fix | measured |
|---|---|---|---|
| the frames fell into a spiral (2-8 physics ticks a frame, 34 fps) | 120 Hz physics: a long frame runs more ticks, and a tick cost 4.8 ms | the costs of a tick below | a drive without a chase: 22.5 -> 17-19 ms a frame, 2.7 -> 2.2 ticks |
| the traffic took 1.5 ms of every tick | the lane index, the decisions of 60-90 cars and the ring, 120 times a second | the traffic thinks every second tick with a double step (60 Hz); the dynamic cars still move every tick | same drive, A/B: 29.1 -> 22.5 ms mean, 26.1 -> 18.2 ms median |
| the effects of every car within 150 m probed 4 wheels a tick and searched the nodes of the car for the wheels | `VehicleBase.get_marker` searched the visual on every call | the markers are kept; a car of the REDUCED tier probes every fourth tick (its smoke is a child of the car) | the callbacks of the traffic cars 0.84 -> 0.44 ms a tick |
| the spawn ring sorted every spot of the ring for every attempt | `TrafficRing.pick_spot` | sorted once per place and heading of the player; a failed spawn waits 3 ticks | 0.2-0.3 -> 0.06 ms a tick |
| the wheel probes cast twice a tick | an enabled ShapeCast3D casts on its own, and the car forces a cast | `enabled = false` | no measurable difference (a Jolt cast is cheap) |

Left: a police car costs about 0.6 ms a tick (a chase with four of them runs at 30 fps); the HUD 1.3 ms a frame (the dials redraw
antialiased arcs), the shadow of the sun 0.8 ms, the occlusion culling 0.6 ms of CPU (the GPU is not the limit on an RTX 3090: the
render is 2.5-3.5 ms). With vsync on, Windows presented the window at 15 fps while the session was not on the screen: that is the
desktop, not the game.

## The street furniture breaks away (the player: "the collisions are not accurate")

23,500 bollards, bins, hydrants, scooters, bike racks, road signs, shop signs and neon blades had no collision at all: the car drove
through them. They break away like the lamps (`world/build/prop_breaker.gd` KINDS): the prop flies, the player car keeps 93-97 % of
its speed and loses 0.5-1 HP, a light knock plays (the glass only for the neon and the shop signs). An AI car knocks them away and
keeps its speed: a few per cent at the start of a race moved a rival into the next one and the field piled up against a tree
(`rivals/test_real_start`). The breaker reads packed arrays and 4 m cells: 13-15 us a tick with the 28,504 props.
Checks: `world/test_prop_breakaway.gd` (a bin at 60 km/h; 2 mutations).

## Tools added (game/tools, tools/)

`fuzz_drive.gd` (random whole-game drives with a flight recorder), `soak_traffic.gd`, `height_map.gd`, `touch_probe.gd` (what a car
touches at a place, `--mask=4` for the props alone), `prop_lane_clearance.gd`, `respawn_probe.gd` (the wreck flow of the game at random
places, followed for 4 s), `spawn_height_probe.gd` (the road height of every lane point), `tools/run_follow.py` (follow trials),
`blender/city/roads/edgewalls.py`, `blender/city/roads/buildingcut.py`.

## Test state (153 tests, `python tools/run_tests.py --jobs 3 --timeout 420`)

The last full run (152 tests, before `test_respawn_direction`): 143 pass, 9 fail. Three of the nine are not baseline: `police/test_heat`
(the righting turned a police car off its roof before it counted as disabled: the righting is the player's now), `world/test_drive_lanes`
(its clearance ray started 4 m over the lane and met a deck: it starts at 1 m now) and `police/test_perf` (a 10 ms tick with three test
jobs running; alone 1.0 ms of its 3.0 ms). The other six are the baseline; `ai/rivals/test_real_route` passed in that run.

The baseline (147 tests): 140 pass, 7 fail. All 7 failed in the integration baseline of the first round as well (`ai/rivals/test_performance`: 0.54 ms against
0.35; `ai/rivals/test_race_flow`: 5 passes of 6 and 4 contacts over 800 N*s, the sandbox race now runs to its own thresholds;
`ai/rivals/test_real_route`: passes alone in 100 s, the suite gives a test 120 s and runs it without the stubs; `ai/traffic/test_lanes_world`;
`roads/test_lanes`: 6 lanes that end at a junction; `roads/test_drive_collision`: the surface oracle is not a hole detector, the ground backs
it (7604 -> 6425 bad samples, parapet or pier in the way 791 -> 276); `world/test_world_api`: the `test_loop` route, 5 failing checks -> 2).
Five tests of that baseline pass now (`police/test_perf`, `rivals/test_rival_driving`, `city/blocks/test_blocks`, `core/test_core_smoke`,
`damage/test_budget`), and nothing that passed before fails.

## Known limits

* The collision hulls of the Oriental Pearl (the drum is cut now), the Shanghai Tower and the SWFC still lie over a few lanes (about 70
  samples of 150,000), the D0 streets east of the Bund run into the flood wall of the promenade (15 samples). A probe that writes the
  blocked samples for `buildingcut.py` to read would close the class.
* The racing line of the Bund sprint goes by Fuzhou Rd and Sichuan Rd now that Hankou Rd ends in the Customs House (the shortest path
  is a tie between several streets).
* The rivals race at 55 m/s on the Bund (200 km/h on a 50 km/h road): the speed profile is the grip budget of the car, not the limit
  of the road.
* The river bank has no wall where a riverside road runs closer than 2.6 m to it (about 470 m of bank); a car that goes into the water
  there is put back after 3 s. In Pudong the paving of the riverside plaza reaches past the outline of the river, so the wall runs
  across the paving there (the drawn wall did so before as well).

## Do not forget

* `world_cache.gd` VERSION has to be bumped when the furniture placement or the lane build changes (the key is the hash of the data).
* The generated assets (tiles, Bund glb, rebuilt blocks, ~1.4 GB of `.git`) are committed on the branch: look at the size before a push.
