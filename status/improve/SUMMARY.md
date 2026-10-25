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

* `st_d7b_ew_11`: the right turn into it from `st_d7b_ns_7` goes to the far end of the lane of the other direction (92 m, over the
  river); `st_link_25/33` start 10-15 m out over the river (roads data; `tools/spawn_height_probe.gd` lists them).
* 18,329 tree trunks (0.25 m) stop a car dead: they stand (a street tree is a tree), they cost 40 % of the damage of a wall.
* The physics at 60 Hz would make the frames 35 % shorter, but the tyre law depends on the step (the frame rate below): a decision
  of the brief.

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
| the police dispatcher thought in every tick | the pursuit, the sight, the spawning and the roles and the driving of the units: 0.3-0.5 ms a tick with five units | it thinks every second tick with a double step (60 Hz), like the traffic; the units still drive every tick, and the contact cache, the debuffs of the player, the strips and the drones stay in every tick (the boost module writes over a debuff every tick, a drone moved every second tick judders) | a heat-4 chase (`--heat=4`, 8.6 units), A/B in one drive: 5.15 -> 4.91 ms a tick, 26.7 -> 24.7 ms a frame; `police/test_perf`: the dispatcher 0.55 -> 0.35 ms |
| a far rival (it thinks every second tick) was given one tick for two | its brain clock ran at half the speed of the clock | it gets the time since its last think (`RivalCar.brain_wait`); the brains stay in every tick: at 60 Hz the field of the sandbox race overtook once instead of five times | `rivals/test_performance` takes the cost of the brains per tick over its window (it summed the last think of every rival); the race unchanged (5 passes, 4 contacts over 800 N*s, the baseline) |
| the visual of every car (the wheels, the wing, the lamps) was placed in every tick | 2-4 times a frame, only the last was drawn | `ArcadeCar._process`: once a frame | 17 us a car a tick -> once a frame |

The probe measured itself at first: it searched the tree for the cars every frame (20-30 ms), its follower walked all 11,724 lanes
every tick while the car was wrecked or at a dead end, and a pass over every node every 3 s gave 40 ms frames. It is cheap now (the
nodes get their slot as they join the tree, the follower searches a lane twice a second, its own time is taken out of the frames),
and the clean numbers are lower than the table: a drive with the traffic and the police 13.6 ms a frame (median; mean 16.9 ms, the
long frames come in the wrecks), the traffic alone 12.5 ms, the city without cars 4-7 ms. The AI cars are the cost.

What a car of the player, the police or the rivals costs (timed part by part in a chase, `ArcadeCar`): about 170 us a tick, of
which the four wheel probes 59 us, the dynamics 48 (the tyres 12, the drive and the drag 9, the suspension 6), the visual 17 (once a
frame now), the telemetry 13, the impacts 6. A wheel probe is a sphere cast, and Godot's Jolt server answers a cast_motion with a
binary search: about nine overlap tests against every body the cast reaches, 3-8 us for a body it hits, and a wheel on a road
reaches the road tile and the ground 2 cm under it (`tools/spot_probe.gd`; a point on a vertex of the ground, where eight
triangles meet, costs 40-80 us). The ground was not the cause: cut into 200 m chunks, or into 25 m triangles, it cost the same. A
ray instead of the sphere (1.3-3 us) would meet the kerbs differently, a lower ground would show at the edges of the roads: the
probes stay.

The heaviest frames come in the chases: with a heat-4 pursuit the drive runs at about 25 ms a frame. The long frames of the
seed-7 drive are a pile-up: the car of the follower boxed in by eight police units against the planters of Nanjing East Rd (the
follower holds the throttle, so it lasts 10 s; a player reverses). A frame of N ticks of c ms and 10 ms of the rest needs
N = frame / 8.33 ms ticks, so it settles at 10 / (1 - c / 8.33) ms: 25 ms at 5 ms a tick (3 ticks), 62 ms at 7 ms (the cap of 8
ticks). With the cap at 4 ticks (`--ab=steps`, the heat-4 chase) the mean frame was 23.9 -> 20.8 ms and the p95 94 -> 62 ms; the
price is a game that runs slower than the clock below 30 fps. The player chose it: `max_physics_steps_per_frame` is 4. The frame probe
writes down what the ticks of every long frame spent (the units, the engine part, the cars' own physics) and the events of the
drive with their time; `--heat=N` starts a pursuit with the record, `--ab=police|rate` are new switches. The run-to-run spread of
the drives is also other work on the machine: a test run beside a drive made every unit 2-3 times slower.

**The physics at 60 Hz (a decision of the brief, not made).** In the same drive in turns (`--ab=rate`) the frame went from 19.6 to
12.7 ms (mean), 17.9 to 12.8 ms (median), 34 to 20 ms (p95): at 120 Hz the median frame does not fit into a frame of a 60 Hz screen
(16.7 ms), and with vsync a frame that misses waits for the next one (30 fps). Everything of the feel report is the same at 60 Hz
(the 0-100, the top speed, the brake, the launch, the drift and its exits, the hops, the stability) except the cornering: the yaw
rate at the full wheel 9-18 % lower at 80-200 km/h (`steer_report.gd --hz=60`: 80 km/h 31.4 -> 28.5 deg/s), the lateral grip
1.24-1.46 -> 1.13-1.20 g, a small swing back after the release. The cause is the tyre law: the lateral force of a wheel is the force
that cancels its slip in one tick for a quarter of the mass, capped by the friction; the fronts are at the cap at both rates (the
same 15 kN), the rears are not, and at 60 Hz they over-correct (their slip changes its sign every tick at 160 km/h) and give 6.3
instead of 8.5 kN. A move to 60 Hz needs a lateral solver that does not depend on the step (the four wheels solved together with the
effective mass of the body at each contact), and then the cornering tuned back to the numbers of 120 Hz. The vehicle reports count
the ticks of the rate now (`vehicle_test.gd`, `steer_report.gd`, `feel_report.gd`) and `--hz=N` runs them at another rate.

Left: a police car costs about 0.6 ms a tick (a chase with four of them runs at 30 fps); the HUD about 0.1 ms a frame (the 1.3 ms of a
drive was the spread of the drives: in a parked A/B it is 0.1 ms), the shadow of the sun 0.8 ms, the occlusion culling 0.6 ms of CPU (the GPU is not the limit on an RTX 3090: the
render is 2.5-3.5 ms). With vsync on, Windows presented the window at 15 fps while the session was not on the screen: that is the
desktop, not the game.

## The street furniture breaks away (the player: "the collisions are not accurate")

23,500 bollards, bins, hydrants, scooters, bike racks, road signs, shop signs and neon blades had no collision at all: the car drove
through them. They break away like the lamps (`world/build/prop_breaker.gd` KINDS): the prop flies, the player car keeps 93-97 % of
its speed and loses 0.5-1 HP, a light knock plays (the glass only for the neon and the shop signs). An AI car knocks them away and
keeps its speed: a few per cent at the start of a race moved a rival into the next one and the field piled up against a tree
(`rivals/test_real_start`). The breaker reads packed arrays and 4 m cells: 13-15 us a tick with the 28,504 props.
Checks: `world/test_prop_breakaway.gd` (a bin at 60 km/h; 2 mutations).

## The Yan'an tunnel opens (the player: "the collisions are not accurate")

The ground of the city was cut out of the water only, and it lay over both ramps of the tunnel: from Pudong a car drove over the
portal on the flat ground, through the drawn bores; a car that came up the Puxi ramp stopped dead at the edge of the ground; the
plate of the junction at each portal reaches over the ramp at street level, and a car coming up drove its nose into its edge and
stopped from 145 km/h in one tick. `world/build/tunnel_trench.gd` (from the lanes of the data, before the lane graph): the ground is
cut between the walls of a bore where its lanes are 0.03-6 m under the ground; the bores are solid where they stand out of the
ground (walls to the crown at 6 m, a roof under it: from outside a wall, from inside a tube); the road surfaces of the tiles lose
their collision where they lie 0.3 m or more over the road of a ramp (79 triangles), and they are not drawn there (1,179 triangles
of asphalt, markings, kerbs and pavements; the bores stay): a car that drove down the ramp disappeared under the plate. Check: `world/test_tunnel_portals.gd` (down
into the tunnel from both ends, up out of it, a car at the tube from the side; 3 mutations), `tools/tunnel_probe.gd`,
`tools/ramp_sweep_probe.gd` (a box of the size of a car swept along the ramps). A test that drives the player car with the input
sets `Game.options["skip-menu"]` before it builds the game: the title menu holds the car otherwise (the suite runs every unit).

## The steering (the player: "the handling is terrible")

`vehicle/tests/steer_report.gd` measures how the car answers the wheel (the yaw rate it builds, how fast, the lateral g, the slip,
the speed it keeps, how it settles), and sweeps the wheel from a tenth to the full lock. The full wheel (a keyboard knows nothing
else) turned the car 20-24 % less than a third of it at 80-120 km/h: the wheel angle fell linearly from 32 deg at rest to 7 deg at
the top speed, 24 deg at 80 km/h, and the grip curve of the tyres falls after 8 deg of slip. The steering assist of the player
(`Drive.assist`, `DriveTuning.STEER_GRIP_*`) makes the full wheel the angle where the front tyres give the most (20 deg at 40 km/h,
11 at 80, 8.7 at 120, 7.3 at 200): the full wheel turns the car 23-31 % harder at 40-120 km/h (80 km/h: 23.9 -> 31.4 deg/s, 0.95 ->
1.24 g), a gamepad gets the whole travel of the stick for the useful angles. The response stays quick (63 % in 0.05-0.2 s), the car
settles in 0.17 s after the release, the drift, the hops, the roll and the brake are unchanged (`feel_report.gd --assist=1`). The AI
cars keep the linear fall: the police and the rivals turn a wanted side force or a heading error into an input with it.
Over 120 km/h the car is at the friction of its tyres (1.3-1.46 g): a sharper car needs more grip, a decision of the brief.
Check: `vehicle/test_steer_assist.gd` (mutation-checked).

## Tools added (game/tools, tools/)

`frame_probe.gd` (the frames of a whole-game drive, split; A/B switches), `spot_probe.gd` (what stands at a place, what the
queries of a wheel cost there), `ramp_mesh_probe.gd`, `tunnel_probe.gd`, `fuzz_drive.gd` (random whole-game drives with a flight recorder), `soak_traffic.gd`, `height_map.gd`, `touch_probe.gd` (what a car
touches at a place, `--mask=4` for the props alone), `frame_probe.gd` (`--seed`, `--heat=N` a pursuit for the whole drive,
`--ab=traffic|police|rate|steps|...`; a hitch prints what its ticks spent, unit by unit), `spot_probe.gd` (what stands at a place
and what the cast of a wheel probe costs there), `vehicle/tests/steer_report.gd` and `feel_report.gd` (`--hz=N`: the physics at N
ticks a second; the vehicle tests count their ticks with the rate of the engine), `prop_lane_clearance.gd`, `respawn_probe.gd` (the wreck flow of the game at random
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
