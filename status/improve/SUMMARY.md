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

The player car keeps an incident record in debug builds (`vehicle/incident_recorder.gd`): when it hangs in the air, lies tipped over or is
thrown up without a hop, the last 6 s of the car (position, speed, wheels, what the body touches, the ghost) go to the log as
`[incident]` lines.

## Tools added (game/tools, tools/)

`fuzz_drive.gd` (random whole-game drives with a flight recorder), `soak_traffic.gd`, `height_map.gd`, `touch_probe.gd` (what a car
touches at a place, `--mask=4` for the props alone), `prop_lane_clearance.gd`, `respawn_probe.gd` (the wreck flow of the game at random
places, followed for 4 s), `spawn_height_probe.gd` (the road height of every lane point), `tools/run_follow.py` (follow trials),
`blender/city/roads/edgewalls.py`, `blender/city/roads/buildingcut.py`.

## Test state (147 tests, `python tools/run_tests.py --jobs 3 --timeout 420`)

140 pass, 7 fail. All 7 failed in the integration baseline of the first round as well (`ai/rivals/test_performance`: 0.54 ms against
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
* Street props are solid now (trees, lamps, shelters, planters): by the damage rules a head-on hit at 108 km/h or more wrecks the car.
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
