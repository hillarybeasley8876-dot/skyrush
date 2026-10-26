# improve/openworld — what changed and what is left

Branch `improve/openworld` (pushed to GitHub, history without personal data). The brief: open-world sports-car map (viaduct links, correct Z interaction, real
collisions, behaviour logic, the flying feature), with a weak cheap model (MiniMax M3.1 Flash) as the workers and the lead as the
reviewer (`tools/m31w`). Then: a web-sourced hero car (black and white), and "continue to optimise all bugs, correct interactions".

## The hero car

Khronos Car Concept (CC BY 4.0), converted by `blender/car/concept` to the vehicle contract: white pearl paint, black paint, black
rims, smoked glass. Collision box 1.9 m wide (the oracles' car), floor 0.34 m over the road (`MIN_BOX_BOTTOM`).

## The traffic and police cars

Real car models now (the player: "the cars are still placeholders"): Daniel Zhabotinsky's Kiri '10, Ace '11, Urban '10 and LCT 3000 '07,
Comrade1280's minivan and denniswoo1993's SHC MC (CC BY 4.0, via Objaverse; their Sketchfab pages still say CC Attribution) and
Grab3D's City Bus (CC0), converted to the car contract by `blender/npc_cars/web/convert_real.py` from the files of
`blender/npc_cars/sources.json` (status/npc_cars.md): 7-27 k triangles and 20-28 surfaces a car, no textures; the credits are in
`CREDITS.md` and on the title screen. They replace the CC0 pack of 1.4-1.9 k triangles; the nodes, the lamps, the wheels and the
tear-off parts of the contract are kept, so the traffic, the police, the vehicle specs and the damage unit work unchanged. Two things
came with them: the rear indicator cards of the traffic sat on the front face of the tail lamp (inside the car: the new tail lamps are
0.2-0.4 m deep), and the PIT unit hovered 5.2 m behind the player with the new interceptor (`police_tactics.gd`: it aims at its line at
least 8 m ahead now; it weaved at a point a metre in front of its nose). The drone is still procedural.

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
| after a crash that knocked a wheel off, the respawned car was drawn 20-40 degrees on its side and drove on like that (the player's screenshot: HP 60 = a respawn after a wreck) | a violent wreck tilts the drawn car on the bare hub of the lost wheel (`PartManager._tilt_on_hub`); the respawn put the parts back but not the drawn car (only an AI car out of its pool got it back), and every such wreck added another 23 degrees. The body stood upright: a probe of the body saw nothing | `CarDamage.reset` (every respawn) puts the drawn car back at its rest | `damage/test_respawn.gd` (a wheel off, the drawn car leans 23.2 degrees, level after the respawn; without the fix 23.17 degrees), `tools/reset_tilt_probe.gd` (R in 7 states and a wreck at places of the city: the roll of the body and the drawn car against the body for 3 s) |
| a reset at a lane that starts over the river put the car on the bed of the river | 6 lane points have no road under them (a street that runs into the river, a junction turn that bulges over it) | a respawn spot needs its road within 1 m under the lane; the respawn walks on along the lane | same test |

## Found and not fixed yet

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

**The physics runs at 60 Hz.** In the same drive in turns (`--ab=rate`) the frame went from 19.6 to 12.7 ms (mean), 17.9 to
12.8 ms (median), 34 to 20 ms (p95): at 120 Hz the median frame did not fit into a frame of a 60 Hz screen (16.7 ms), and with vsync
a frame that misses waits for the next one (30 fps). The cornering depended on the step: the lateral force of a wheel cancelled its
slip in one tick for a quarter of the mass, so at 60 Hz the rears over-corrected (their slip changed its sign every tick at
160 km/h) and the full wheel turned 9-18 % less. Now the two axles are solved together (the impulse of one axle changes the lateral
speed at the other through the turn and the roll of the body), and the contact patches, found by the probes of the last tick, are
moved to the lag of a 120 Hz tick (the tuning was made with it): `steer_report.gd` gives the same yaw rates at 60, 120 and 240 Hz
(57.8, 31.4, 21.9, 17.3, 14.8 deg/s at 40-200 km/h), and the feel report at 60 Hz gives the cornering, the drift, the hops, the
brake and the launch of 120 Hz. At most 2 ticks a frame
(it was 4): below 30 fps the game slows down instead of falling into a spiral of ticks. The physics interpolation is on: at 60 ticks
and 120 frames a second the car moved on every other frame only (`tools/smooth_probe.gd`: the speed on the screen 100 km/h with a
spread of 50 km/h, 20 % of the frames a judder), interpolated the spread is 0.07 km/h for the car and 0.3 km/h for the camera. The
nodes moved every drawn frame are left out of it (the wheels, the wing, the rain, the pools, the multimeshes), every teleport resets
it, and so does the safety pass of the camera when it moves the camera (from 1 cm: a reset draws the camera at the tick). A fast
hit counts the speed the continuous collision of Jolt leaves to the next step (a head-on at 100 km/h: 42,600 N*s at 60 Hz before,
51,600 now, 51,700 at 120 Hz). The traffic, the police and the far rivals think at 60 Hz as before; the tests and the reports count
the ticks of the rate (`--hz=N` runs a test at another rate). Two tests failed at 60 Hz for reasons of their own: the ramming box of
`test_wreck` stood half under the road and fell through it, `test_rival_driving` parked the player on the line of the rivals.

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
Check: `vehicle/test_steer_assist.gd` (mutation-checked). A swap of the keyboard wheel from one side to the other took the slow
turn-in rate (4 /s) all the way, the half back to the centre too: 0.5 s from lock to lock. The player's keyboard goes through the
centre at the return rate now (6 /s): 0.42 s. The AI drivers keep the old rule to the tick (a quick swap for them sent a rival into
the marshal at the start of `rivals/test_real_start`).

## The sky lane flight (the player: "the flight feels terrible")

The sky lanes were polylines with corners of up to 111 degrees in one point (huangpu_jump 78 and 108, bund_riverside 87, the gates
of century_canyon 32 and 67 each way, nanpu_cables 35), so the car turned its heading in one tick: -4,285 deg/s of yaw and 322 g on
huangpu_jump, 16-46 ticks of a snap per lane (`game/tools/flight_probe.gd` flies every lane hands-off). The lane rose 10 m in the
8 m after the pad (51 degrees), and the car stood still in the air at the end of the lane while it descended the 8 m to the road
(2.7 s): the frame of the lane was clamped to the end of the curve. The generator (`tools/city/city_skylanes.py`, called by
`city_marks._sky_lane`) makes a lane of straight legs and arcs now: the corners of the plan (Douglas-Peucker, 2 m), neighbouring
corners may merge into the corner where the legs before and after them meet, every corner gets the widest arc its legs allow (at
most 400 m), narrowed while it passes less than 10 m over a lot or, off the plan, less than 9 m beside a lot the tube reaches; of
the ways to merge, the widest tightest turn wins (a corner list whose legs are 10 % longer than the plan, or with a corner 150 m
off it, is a detour and does not count). The height climbs from the pad with the slope ramping in over 80 m, cruises, dives and
ramps out 1 m over the road. The player: "it does not fly high enough": the lanes climb at 25 degrees now (20 before; the rule
and `selftest_skylanes.py` allow 26 and a cruise up to 240 m) and keep climbing over the city when the road of the pad is too
short: huangpu_jump cruises at 220 m (100 before), bund_riverside at 200 (100), century_canyon at 127 (85), dragon_stack at 86
(60) and nanpu_cables at 80 (45), the last three as high as their length allows. The arcs: huangpu_jump 77 and 254 m, dragon_stack 200/172/172, century_canyon 72/45/44/44
(the S bend from the D7 street to the Century Ave: 75 m sideways in a 40 m street between the towers), nanpu_cables 106,
bund_riverside 400/317/317. `tools/city/build_city.py` makes city.json again (a fresh build gives the file byte for byte); the sky lane rules,
`selftest_skylanes.py` and the shape check pass. The rules check the pitch only on
segments over 60 m: a 99 m rise in the first 8 m passed them, the patch prints the steepest segment and the first rise.
In the game the curve has Catmull-Rom handles and is baked every 0.5 m (baked every 2 m the heading wobbled 15 % from tick to tick
in a turn), the car banks into the turns of the lane (0.6 of a coordinated turn, at most 50 degrees and 150 deg/s of roll, read
0.4 s ahead), slows before a turn that would need more than 70 deg/s (only the century S bend: 194 km/h), and the exit flies on
along the last tangent: the last 60 m bring the car back to the centre of the lane, and a car that has not touched the road
25 m past the end leaves the rails (the Nanpu lane lands on the curving Pudong loop: flying on straight, the car missed the
ramp and fell out of the world). Hands-off at 60 Hz the peaks of the heading went from -4285/644/2094/1078/-2889 deg/s to 50/24/86/36/17
(huangpu, dragon, century, nanpu, bund), the ticks of a snap from 33/16/46/16/37 to 0, the bank is 29-49 degrees, and the car lands
17-26 m (0.3-0.5 s) past the end of the lane (dragon_stack 63 m). Unchanged: the throttle and the brake still move the car up and
down in the tube (dossier 5.6), and a car that does not steer hits the obstacles of the lane (30 % of its speed). Check:
`vehicle/test_sky_lane.gd`, `world/test_sky_lanes_fly.gd`, `world/test_sky_obstacles.gd`, `flight_probe.gd` (`--lane=id`,
`--trace=FROM`, windowed `--shots=offsets --outdir=ABS`).

## The charging stations and the toll plaza (the player: "many charging stations and toll stations are not done")

The audit: the trigger of the charge bay stood on the centre of the bay model, so its 6 m box began 1.2 m over the road
and the Roadster (its collider ends 1.1 m up) never charged: the battery only fell, and under 15 % the car is held at
180 km/h (`test_gameplay_sites` charged a 1.3 m probe box). The three stations stood on the roads with columns, posts,
dispensers and a 7 m totem in live lanes, and the nearest one was 910 m from the median lane point. Now the trigger
stands on the ground (the test drives the real Roadster through it, mutation-checked), and the chargers are 12
申城闪充 gantries over the main roads (`tools/city/city_charge.py`): the 27 m guide gantry of the props unit over the
20-26 m roads, the 19 m one over the 15 m streets, placed farthest-first clear of the junctions, the other gantries, the
sky lane pads and the roadblocks, a cyan panel each way (`sign_factory` style "charge", unshaded: lit, it read as a grey
board), light bars and a light, the charge area over the carriageway; the nearest charger is 405 m from the median lane
point (90 % within 746 m, all within 1,084 m). The plazas of the three old stations stay open squares, so the lots and
the buildings do not change (a fresh build differs from the old file only in the POIs).
The toll plaza of the G50 stood turned by 90 degrees along the road with its 20 booths in one lane, 38 of its 40 signal
meshes red, the wrong arms up and every eastbound car counted as a toll dodger. The props unit has a 3+3 lane plaza now
(`blender/props/toll_road.py`, `toll_plaza_road.glb`): its lanes lie on the lane centres of the road (0.00 m in the
test), the inner lane each way is the ETC lane (green, its arm up), the closed lanes have their arms on slim islands on
the lane lines, the booths stand on the median and outside the shoulders, an ETC gantry 30 m before the canopy, the
canopy top at 7.4 m (a Big Hop clears it), the light markers are spot lights. A closed lane opens for the cars that pay:
the traffic and the police (their ETC tag) and the player under 30 km/h; the player who runs it at speed breaks the arm
and dodges the toll. `toll_plaza.gd` finds the lanes by their red signals, the arm of a lane by the lane in its extras,
and turns the plazas of the props unit (built for traffic along x) by the heading of the road. The atlas build of the
signs stopped on a module missing from its table (`tools/signs/prop_atlas.py`). Checks: `world/test_toll_road.gd` (the
real plaza: six lanes on the road, the ETC lanes, a fast run, a creep through, the ETC lane at 100 km/h),
`world/test_gameplay_sites.gd`, `assets/props/test_props.gd`.
The two gas stations stood with their columns, a dispenser and the shop on the roads (Zhongshan E-2 Rd, a D9 street): the
62 x 41 m of their ground colliders were searched on a 1 m raster for a spot with no collider on a carriageway or a lot,
the Sinopex station moved 26 m and the Petrochino one turned 90 degrees (`city_marks.build_pois`; their old lots stay).

## The input method took the keys (the player: "Ctrl and Space easily trigger the input method")

On a Chinese Windows the input method of the player (Sogou here, Microsoft Pinyin too) takes the keys of the game: Ctrl+Space
(the nitro and the hop together) turns it on, Shift (the drift) switches it between Chinese and English, and then W, A, S, D go
into its candidate box. `core/input_language.gd` (a child of the Game autoload) switches the game window to the English layout
of the machine while it has the focus, turns the input method of the window off, and gives the player's layout back when the
game loses the focus or quits (`--keep-layout` leaves it alone). Checked on this machine: the layouts are zh (Sogou, Microsoft
Pinyin) and en-US, the guard goes 0 -> 1 and back to 0. Ctrl+Space is the toggle of the Chinese input method here (Hot Keys
00000010), and Alt+Shift and Win+Space switch the language: the layout could be switched back in the middle of a drive. The guard
checks it every 0.25 s while the window has the focus (the menus and the pause too: the game has no text field) and puts the
English layout back; windowed, a switch to the Chinese layout was undone within 0.6 s.

## The lanes that led back into themselves, against the traffic or across the other lanes (the player: "there are still many bugs")

The movements of a junction whose exits are not found (a road that passes the junction uncut, an arm that is trimmed further
away) took the lanes of the road nearest to the centre, whatever their way: 79 led a lane "straight on" into its own start (the
car drove to the end of its lane, turned round and drove back along it, again and again: 52 loops in the AI graph of the game),
117 led into the far start of a lane that runs towards the junction (85 m on the median, up to 146 m down the road against its
traffic), 83 into the other carriageway of the same road (a U-turn called straight on). The game dropped 179 of those links
(the turn at their end was over 100 degrees), and 124 connectors were left without a way on: a car that took one stopped in the
middle of the junction. `blender/city/roads/lane_links.py` never links a lane to itself, and the fallback offers only the lanes
that leave the junction along the arm (their start nearer than their end, their first metres outward): the junction connectors
that go the wrong way fall from 541 to 203 (the rest come from the exits the junction finds itself). A straight movement swerved
too: when its plain curve left the fill of the junction, it was pulled to the centre and clamped to the fill, and 734 of 3306
straight connectors ran more than 4 m off their line, the outer lanes of Century Ave at its side streets 27 m (the fill of a
junction does not reach the far lanes of a wide road that passes it). `lane_paths.connector_points` keeps the plain curve of a
straight movement then: 67 are left over 4 m. The game drops 79 links instead of 179, and 45 connectors are left without a way on
instead of 124. 5 lanes end at a junction (6 before: the end of Pudong South Rd at the Nanpu loop,
which only comes in, and two side streets that stop 15-20 m short of the road they meet). A traffic car does not take a
continuation that ends at once when it has another way (`LaneFollower.choose_next`; a junction without a dead end draws the same
random numbers as before): `traffic/test_dead_end_choice.gd` (mutation-checked). Cutting the uncut roads at the dead ends and
U-turns there were tried and dropped: their connectors swerved 15 m off the road with 1-3 m radii. `world/test_respawn_direction.gd`
counts its every-7th lane among the street lanes (counted among all lanes, the connectors that went away moved the sample), and a
reset that walks along its own road to a clear spot (28 m on the Yan'an elevated road) stays on its street.

## The median barrier of the elevated roads let every car through (the player: "there are still many bugs")

`tools/parapet_probe.gd --median=1` drives a car into the median barrier of an elevated road from its inner lane (10 places,
10-45 degrees, 30-150 km/h): 84 of 90 runs ended in the oncoming carriageway, from 10 degrees at 30 km/h. The barrier that is
seen is 0.85 m high; its collider was the same profile pushed 0.6 m down (`collision.build_median_barrier`, like the parapet
collider of the first build), so its top stood 0.23 m over the road, under the floor of the box of a car (0.34 m). The collider is
a wall with vertical faces on the foot of the barrier now, 0.81 m high and 0.6 m deep into the deck: 0 of 90 runs cross, at 60 and
at 120 Hz (a first version that kept the sloped faces of the barrier threw the car over: the wheel probes stood on the 55-degree
faces, the lesson of the chamfer of the first parapet collider). 42 files of 21 road tiles of the four elevated roads change, the
lanes and the minimap do not; road_furniture.json moves 5 piers of the Yan'an elevated road (it was built before the last road
commits). The edge parapets: 0 of 192 runs over them at 60 Hz (16 places, 10-45 degrees, 20-170 km/h). The random viaduct drives
(`fuzz_drive --elevated=1`, traffic off, seeds 11-13) fall 8 times in 120 drives with the new tiles and 7 with the old: the falls
are open deck edges near the lanes (`check_open_edges.py`: 190 regular, 23 connector; the edge walls leave an edge alone where a
lane runs within 1.45 m of it) and cars that climb a parapet under full throttle after a spin, not the median.

## The deck ends where a wide elevated road meets a narrow one (the random viaduct drives)

Where the North-South Elevated (3 + 3 lanes) runs into the Inner Ring (2 + 2) and the Nanpu Bridge (3 + 3) into the upper deck of
the Nanpu spiral (2 + 2), the outer 4 m of the wide deck ended in the air, with no parapet across them, and the two end caps stood
at 10 and 5 degrees to each other with a wedge of hole between them: a car on an outer lane that drove straight on fell 10 or 42 m
(4 of 4 drives from the outer lane of the Nanpu Bridge at 140 km/h). `tools/city/check_joint_runoff.py` casts straight rays from every
lane end at a deck joint: 5 of 14 ran off. An M3.1 worker (job roads-joint-ends, one round) built `deck.build_joint_ends`: a nose of
deck that fills the hole between the two decks for 5 m and a parapet on its outer edge and across its far end, past the 3.5 m of the
merge curve of the outer lane (a fence on the line of the cap walls the merge curve off, measured). Now 0 of 14 run off; the chain
and attach paths, the lane blockers (32), the open edges (190/23) and the lane graph are unchanged, two road tiles change. The same
starts in the game: the cars of the outer lane hit the new parapet instead of falling (at 140 and 190 km/h). `fuzz_drive.gd` measures
a fall from where the car last stood (a hop on a deck that runs downhill was a "fall" from the height of the start) and prints what
lifts a car: a wheel on something that is not flat road, a contact of the box that pushes it up. The viaduct drives (traffic off,
seeds 11-13): 3 falls in 120, all three after scraping along a parapet for seconds (left for the next round).

## Tools added (game/tools, tools/)

`frame_probe.gd` (the frames of a whole-game drive, split; A/B switches), `spot_probe.gd` (what stands at a place, what the
queries of a wheel cost there), `ramp_mesh_probe.gd`, `tunnel_probe.gd`, `fuzz_drive.gd` (random whole-game drives with a flight recorder), `soak_traffic.gd`, `height_map.gd`, `touch_probe.gd` (what a car
touches at a place, `--mask=4` for the props alone), `frame_probe.gd` (`--seed`, `--heat=N` a pursuit for the whole drive,
`--ab=traffic|police|rate|steps|...`; a hitch prints what its ticks spent, unit by unit), `spot_probe.gd` (what stands at a place
and what the cast of a wheel probe costs there), `vehicle/tests/steer_report.gd` and `feel_report.gd` (`--hz=N`: the physics at N
ticks a second; the vehicle tests count their ticks with the rate of the engine), `prop_lane_clearance.gd`, `respawn_probe.gd` (the wreck flow of the game at random
places, followed for 4 s), `spawn_height_probe.gd` (the road height of every lane point), `flight_probe.gd` (every sky lane flown
hands-off: the peaks of the turn, the bank, the g, the landing), `smooth_probe.gd` (how smoothly the car, the camera and the far
traffic cars move on the screen), `fuzz_drive.gd --jumps=1` (a car moved by hand in sight), `parapet_probe.gd` (cars driven into the parapets and the medians of the elevated roads), `tools/city/restamp_blocks.py`,
`tools/city/check_joint_runoff.py` (straight rays from the lane ends at the deck joints: fenced, road or open),
`tools/run_follow.py` (follow trials),
`blender/city/roads/edgewalls.py`, `blender/city/roads/buildingcut.py`.

## Test state (157 tests, `python tools/run_tests.py --jobs 3 --timeout 420`)

The last full run (157 tests, the deck joints): 151 pass, 6 fail, the six of the baseline below (`roads/test_drive_collision`: 4332 bad
surface samples, 240 blocked). The run before (156 tests, 60 Hz with the interpolation): 149 pass, 7 fail: the six of the baseline below and `audio/test_audio`,
which passes alone (3 of 3, 11 s) and hung at its exit in the suite with three jobs and a Blender build beside it.
The run before (152 tests, before `test_respawn_direction`): 143 pass, 9 fail. Three of the nine are not baseline: `police/test_heat`
(the righting turned a police car off its roof before it counted as disabled: the righting is the player's now), `world/test_drive_lanes`
(its clearance ray started 4 m over the lane and met a deck: it starts at 1 m now) and `police/test_perf` (a 10 ms tick with three test
jobs running; alone 1.0 ms of its 3.0 ms). The other six are the baseline; `ai/rivals/test_real_route` passed in that run.

The baseline (147 tests): 140 pass, 7 fail. All 7 failed in the integration baseline of the first round as well (`ai/rivals/test_performance`: 0.54 ms against
0.35; `ai/rivals/test_race_flow`: 5 passes of 6 and 4 contacts over 800 N*s, the sandbox race now runs to its own thresholds;
`ai/rivals/test_real_route`: passes alone in 100 s, the suite gives a test 120 s and runs it without the stubs; `ai/traffic/test_lanes_world`;
`roads/test_lanes`: 5 lanes that end at a junction (6 before the connectors were cleaned); `roads/test_drive_collision`: the surface
oracle is not a hole detector, the ground backs it (7604 -> 6425 -> 4364 bad samples, parapet or pier in the way 791 -> 276 -> 240: the
connectors that ran against the traffic and the ones that swerved crossed the kerbs); `world/test_world_api`: the `test_loop` route, 5 failing checks -> 2).
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
