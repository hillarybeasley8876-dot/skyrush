# traffic status

Unit: Shanghai night traffic (lane graph, IDM, kinematic until hit). Owns `game/ai/traffic/**` and
the shared AI driving helpers `game/ai/common/**`.

Round 2 (the review of round 1). The numbers below are measured on this machine, which ran with
a load average of 50-62 on 10 cores while the other units worked in parallel - the cost numbers
are therefore roughly twice what an idle machine would show.

## Done (review round 2)

### 1. The lamps are the real lenses of the model (r2 #1)
- The lamps are found **recursively** (`find_children("Lamp_*", "MeshInstance3D", true, false)`),
  the lamp meshes live at `Visual/sedan_ev2/sedan_ev/Lamp_R`.
- Every lens is a **surface** of a lamp mesh, so the state is a per-surface material swap
  (`set_surface_override_material`), never a `material_override` on the whole mesh:
  `NPC_lamp_rear` -> tail, `NPC_lamp_brake` -> brake, `NPC_lamp_front` on `Lamp_F` -> head,
  `NPC_lamp_front` on `Lamp_R` -> the reversing lens, `NPC_gloss_black` (the housing) is never
  touched.
- The materials are the **model's own** materials, duplicated once per model and per state
  (`traffic_lamp_materials.gd`), so the lens texture of the atlas stays. No instance uniform is
  used any more (the instance buffer of the city is full).
- The brake lens is 0.25x the imported energy while cruising and 1.5x while braking (6x apart);
  the tail 1.0x, the reversing lens 0.02x, the head 1.0x. The emission is tinted #FF1A2E (tail,
  brake), #F4F7FF (head), #DDE6FF (reversing).
- The lamp shader is opaque, back-face culled and samples a texture when one is given, so the far
  side of a lamp cannot shine through the cabin any more.
- `test_lamps.gd` checks all eight models: a tail, a head and a brake lens, the brake switch
  (6x) and the housing.
- Captures: `captures/traffic_close_t12_0.jpg` (the tail bar, the side blocks and the dim
  reversing lens of a car) and `captures/traffic_brake_t12_0.jpg` (the same car braking, the bar
  blazing and a red reflection on the wet road). Measured on the lamp crop: **cruise 1 965 red
  pixels, brake 10 062 red pixels (5.1x)**, the review asks for 1.6x.

### 2. The AI sees the player (r2 #2)
`ctx.player` is written **every tick** in `traffic_director.gd` (and in `_refresh_world`), with a
validity check. `test_mobil.gd` puts a fast player behind the traffic: **21 % of the cars move
out of the way, 10 % brake** (1000 rounds, the review asks for 15-25 % and 5-15 %).

### 3. MOBIL fires (r2 #3)
- The gain is measured on the **target lane** at the point of the target lane that lies beside
  the car (`LaneGraph.aligned_offset`), not on the same number of metres.
- The neighbour is only used when the gap is 2.8-4.5 m, the two lanes are at the same height
  (0.3 m) and point the same way (15 deg).
- The car takes the place on the new lane that lies beside it (`follower.s = s_t`), so it does not
  jump when the change starts.
- The indicator blinks 1.0 s before the move (the test measures it).
- `test_mobil.gd`: the car changes the lane, the indicator is on 1.00 s before, the body jumps
  0.21 m (the limit is 0.3 m). The world test counts **3.8-5.4 lane changes per car and minute**
  on the roads with more than one lane.

### 4. The traffic sees through the junction (r2 #4)
- A car on a junction connector is indexed on **two lanes**: at `lane_length(from) + connector_s`
  on the lane it came from and at `entry - (connector_length - connector_s)` on the lane it is
  merging into (`traffic_index.gd`).
- The car looks for its leader at that place (`LaneFollower.index_s`), so it no longer finds
  **itself** as its own leader - that was the reason for 45 000 stopped car samples in the middle
  of a junction.
- Every car plans the lane it will continue into (100 m before the end) and looks for a leader
  in it, with the connector length added to the distance.
- The IDM never gets a negative gap (it brakes at the emergency cap instead).

### 5. Only a street has a traffic light (r2 #5)
- A lane gets a junction only when its road is a **surface** street (the kind comes from the
  city data, so ramps and decks are out), the lane is not elevated, its end is below 2 m and it
  ends within 20 m of a junction with `signals: true`.
- The light is not used when the car is already past the stop line (`to_end < 0`) or on a
  connector, and an amber light only stops the car when it can still stop
  (`v^2 / (2 * B_COMF) < to_end`).
- `test_junctions.gd`: 358 lanes of the city have a light, **0 of them on a deck, on a ramp or
  above the ground**; a car stops in front of a red line and goes on when it turns green.

### 6. The speed limit of the road (r2 #6)
`desired_speed = limit(lane) * driver_factor` is set on **every lane entry** (a continuation, a
junction connector or a lane change). The world test: **0 of the 70 cars have the wrong speed
limit** (the limit was 8.33 m/s off before).

### 7. The wrecks (r2 #7)
- A wreck has `speed = 0` and its lane distance follows the **body** (it is re-projected every
  tick and indexed at the body), so the car behind it brakes for the wreck and not for the place
  where it was hit.
- The impulse lands on the **contact point** (`point - origin`), there is no extra linear
  momentum, and the angular kick is `0.35 rad/s per m/s` of closing speed about
  `(point - centre of mass) x push` - no random values any more.
- The wreck lives for 8 s, is removed when it is 2 s out of sight and more than 60 m away.
- `test_wreck.gd`: a 15 m/s ram 0.6 m off the centre **turns the car 43 deg**, it comes to a
  stop after 2.2 s, the follower keeps 12.4 m from the wreck and the car in the next lane
  drives past.

### 8. Dead ends and loops (r2 #8)
- A loop needs a lane of at least 50 m (a six metre stub that links to itself is a dead end).
- A car that reaches the end of the road stops there (with its brake lamps on) and leaves the
  traffic when it has been out of sight for 2 s - it never vanishes in the view of the player.
- The world test: **0 cars vanish in view**, the 20 cars that left the traffic all stood still
  at the end of a road.

### 9. The cost (r2 #9)
- The index is a flat list with a linked list per lane (`lane_hash.gd`): nothing is allocated
  while it is filled, and the leader and the follower are found without a sorted bucket.
- A far car within 120 m of the player is updated every second tick, a far car beyond that every
  fourth tick, and it only moves its body (no lamps, no shadow, no lane change).
- The models are preloaded (`ResourceLoader.load_threaded_request`) and the cars come out of a
  **pool** (`traffic_pool.gd`): a spawn is a placement, a despawn is a hide.
- The player is re-projected within 8 m, and the signal state is only asked for a lane that has
  a light.
- Measured (load 50-62): the city with 70 cars **0.58-1.75 ms per tick** (the median moved
  between 0.58 and 1.75 in the runs of the day), the parts: index 0.08-0.15, cars 0.26-0.79,
  modes 0.02-0.07, events 0.04-0.08, ring 0.01-0.04, the physics of the near cars 0.07-0.29.
  The budget of the dossier is 0.5 ms per tick (1.0 ms per 60 fps frame) - **still over on this
  machine, see "Left"**.

### 10. The tests (r2 #10)
- Every test waits for `Game.world_ready()`; the city part **fails** (exit 1) when the world has
  no lanes, it never skips.
- The budget metric is the **raw** time of every tick plus the sum of the physics of the near
  cars; the median and the p99 are printed with the cost of every part.
- The jump is measured against the step the car is allowed to make (`speed * dt`, the far cars
  with the period they tick with) plus 0.3 m.
- New tests: `test_mobil.gd` (the lane change and the reaction to the player), `test_lamps.gd`
  (the lenses of all eight models), `test_wreck.gd` (the wreck), `test_junctions.gd` (the
  lights), and `test_lanes_world.gd` rewritten (the path, the jumps, the standstill, the
  overlaps, the speed limit, the lane changes, the removals, the cost).
- `test_spawn_ring.gd` and `test_paint.gd` still pass.

### 11. The road ahead is not empty (r2 #11)
- The ring is weighted to the **road of the player**: the traffic of the road the player drives
  on is measured over 0-350 m (one car per 45 m on a deck, one per 60 m on a street), the other
  roads of the city never carry more cars than the road of the player. 60 % of the new cars are
  on the road of the player, 70 % of those in front of it.
- The road of the player is the **closest** lane, not the lane the player was on a moment ago
  (the player flies, hops or drives on the pavement).
- Measured on the Yan'an deck (the demo, 20 s): **70 cars, 54 within 300 m, 12-16 ahead within
  150 m** (the review asks for 8 and 6).
- Captures: `captures/traffic_deck_t26_0.jpg` (the chase camera on the deck: the Roadster with
  its lamp pool, a van with lit tail lamps next to it and three cars ahead), `traffic_close_t12_0`
  (the tail lamps of a car), `traffic_brake_t12_0` (the brake lamps), `traffic_front_t12_0` (the
  front of a car).

### 12. The code (r2 #12)
- Every file of the unit is **at most 400 lines** now: `lane_graph.gd` was split into
  `lane_links.gd` and `lane_neighbours.gd`, `traffic_car.gd` into `traffic_car_physics.gd`
  (the body, the contacts, the wreck) and `traffic_car_driving.gd` (the IDM step, the lights,
  the junction), the director into `traffic_index.gd`, `traffic_pool.gd`, `traffic_modes.gd`,
  `traffic_ring.gd`, `traffic_junctions.gd` and `traffic_player_events.gd`.
- The dead code of the review is gone (`HORN_RADIUS`, `HORN_COOLDOWN`, `_horn_cooldown`,
  `_was_close`, `from_prefill`, `NEAR_MISS_RANGE`, `unresolved_world`, `_turn_angle`,
  `_closest_lateral`, `is_braking`, `dropped_neighbours`, the magic numbers of the old code).
- The horn needs 5 m/s of relative speed and the cooldown dictionary is emptied when a car
  leaves the traffic.
- `vehicle_collided` is rate limited per collider (once per 0.25 s).
- The new cars appear 180-350 m away (the dossier), the fleet has the `robotaxi` and the size of
  the car comes from the AABB of the glb body.

## Left (carries over to the next round)

1. **The cost is still over the budget on this machine.** 0.58-1.75 ms per tick with 70 cars
   (the budget is 0.5 ms per tick). The biggest part is the tick of the cars (0.26-0.79 ms).
   The next step: the far cars beyond 120 m only need the transform, not the IDM step, and the
   lane change of the near cars can run every second tick.
2. **The jump of the body is 0.7-1.0 m** (the limit is 0.3 m more than the step of the car).
   It happens when a car changes between the frozen (FAR) and the dynamic (NEAR) mode: the
   frozen body lags behind the lane by up to one period. The car is put on the lane at the
   switch, but the lag of the frozen car is still there.
3. **Two cars of a lane overlap** in 294 samples of the world test (the limit is 0.8 x the
   length of the shorter car). The cause is mostly the **duplicate lanes of the world**: 132
   roads of the city are built twice (the same start, the same end, the same links - see
   Requests). The traffic now drives on the first copy only (`LaneGraph.is_duplicate`), but two
   cars can still meet on the copy that is left.
4. **A car stands still for up to 80 s** on a lane without a light. It is a queue for a red
   light of the next lane, or a jam at a junction where the cars of the connector and the cars
   of the lane want the same piece of road. The next step: the queue for a light has to be
   recognised (the leader of the car is waiting at a light), and the junction has to hand the
   right of way to the lane that is not full.
5. The cars of a dead end road stand still until they are out of sight (2 s). They are parked at
   the end of a road, which is right, but 20 of the 70 cars of the test end up there. The traffic
   should not drive into a dead end when there is another way.

## How to test (exact commands)

- `tools/godot.sh check --only=res://ai/traffic/,res://ai/common/`
- `tools/godot.sh test res://ai/traffic/tests/test_idm.gd` (24 PASS)
- `tools/godot.sh test res://ai/traffic/tests/test_paint.gd` (10 PASS)
- `tools/godot.sh test res://ai/traffic/tests/test_mobil.gd` (6 PASS)
- `tools/godot.sh test res://ai/traffic/tests/test_lamps.gd` (37 PASS)
- `tools/godot.sh test res://ai/traffic/tests/test_wreck.gd` (5 PASS)
- `tools/godot.sh test res://ai/traffic/tests/test_spawn_ring.gd` (8 PASS)
- `tools/godot.sh test res://ai/traffic/tests/test_junctions.gd -- --timeout=290` (8 PASS)
- `tools/godot.sh test res://ai/traffic/tests/test_lanes_world.gd -- --timeout=290` (the long run)
- Captures:
  `tools/godot.sh shot --scene=res://ai/traffic/demo/traffic_demo.tscn --out=traffic_deck --deck --times=20 --warm=300`
  `... --out=traffic_close --close --times=12 --warm=240`
  `... --out=traffic_brake --brake --times=12 --warm=240`
  `... --out=traffic_front --front --times=12 --warm=240`

## Evidence

- `captures/traffic_deck_t26_0.jpg` - the Yan'an deck at night, the chase camera: the Roadster
  with its lamp pool, a van with lit tail lamps next to it, three cars ahead on the deck.
- `captures/traffic_close_t12_0.jpg` - the tail lamps of a traffic car from 6 m: the red bar of
  the model, the side blocks and the dim reversing lens.
- `captures/traffic_brake_t12_0.jpg` - the same car braking: the bar blazes, the road under it
  turns red. 5.1x more red pixels than the cruise shot.
- `captures/traffic_front_t12_0.jpg` - the front of a car.
- Tests: `test_idm` 24 PASS, `test_paint` 10 PASS, `test_mobil` 6 PASS, `test_lamps` 37 PASS,
  `test_wreck` 5 PASS, `test_spawn_ring` 8 PASS, `test_junctions` 8 PASS, `test_lanes_world`
  8 failures (the jump, the overlaps, the standstill and the cost, see "Left").
- The demo prints the traffic around the player every second:
  `TRAFFIC cars 70 in view 54 ahead 12`.

## Known issues

- The world builds some roads **twice** (132 pairs of lanes with the same start, the same end
  and the same links, e.g. `bund_zhongshan_e1` and the roads of the bridges). Two cars on the
  twin lanes drive through each other. The traffic uses the first copy only, but the world
  should not build the road twice.
- The world has **323 dead end lanes** (55 on the decks). A car that drives into one stops at
  the end of the road.
- The prefill of the ring (the cars that fill the road in front of the player) is spread over
  the first ticks after the world is ready, so a few cars still pop in in the first second of
  the game.
- The traffic has no sound of its own: the horn is a signal (`TrafficCar.horn_requested`, the
  car is in the group "traffic") and the audio unit has to pick it up.

## Requests

- (to world) **the city builds 132 roads twice** (the same start, the same end, the same
  `next_lanes`): `bund_north` 139/140, `st_d0_ns_3` 141/142, `bund_north` 145/146 and 147/148,
  `waibaidu_bridge` 151/152 and 153/154, ... The traffic skips the second copy
  (`LaneGraph.is_duplicate`), but the world should not build the road twice.
- (to world) `LanePath` could name the junction of a lane (`LanePath.junction_id` or
  `WorldBase.get_lane_junction(lane) -> StringName`). The traffic reads the junctions from the
  city data today (a surface street that ends within 20 m of a junction with `signals: true`).
- (to world) the **decks have no traffic lights** by design now (the traffic only stops on a
  surface street). If the elevated roads should have lights, the world has to name them.
- (to core) the instance buffer of the scene is full; the traffic uses no instance uniform for
  the lamps any more (the paint colour of the car is the only one left).
- (to damage) the traffic reports `Events.vehicle_collided` (rate limited to once per 0.25 s
  per collider) and `Events.vehicle_wrecked` when a car tumbles.
- (to audio) `TrafficCar.horn_requested(car)` is emitted when a car honks at the player (a gap
  under 1.5 m at more than 5 m/s of relative speed); the car is in the group "traffic".

## 2026-10-24: cars of different lanes, kerbs in a lane (the traffic soak)

`game/tools/soak_traffic.gd` parks the player beside a lane for a few minutes of game time and watches every near traffic car
(STUCK: 30 s without moving, nothing in front of it and no light; OVERLAP: two bodies 2.4 m apart for 3 s; OFFLANE; FAST; LOW).
First run, 14 sites of 120 s: 10 problems, i.e. 7 cars that never moved again, 3 overlaps at junctions, 1 car 33 m off its lane.

* **Cars of different lanes did not see each other.** The lane hash knows the cars of ONE lane and the lane after it; two lanes that
  cross in a junction (a left turn against the oncoming traffic), merge, or lie over each other at the end of a lane were
  invisible to each other: the cars drove through each other or stood pressed together for ever. `DriveContext.cells` (a grid of 12 m,
  refilled with the lane hash by `TrafficIndex.rebuild`) and `TrafficCarDriving._conflict_gap`: the car whose instance id is the
  younger yields to an older car (or to a wreck, whatever its age) that stands within the corridor in front of it (the two half
  widths plus 0.3 m, 8 to 30 m ahead, same level, other lane). The order is total, so no two cars wait for each other and no ring
  of cars forms. Test: `test_conflict_yield.gd` (the crossing, the lane beside, the lane that lies over, the same lane, the
  deck, the wreck).
* **A kerb in the lane was a wall.** The box of a traffic car started on the road (`_shape.position.y = size.y / 2`); the median strips
  and kerbs of the city (15 cm) cross some lanes, and the car stood against them for ever (`touching roads_2_0_concrete`).
  `TrafficCarPhysics.DRIVING_FLOOR = 0.34` m while the car drives, `set_box_floor(0)` when it becomes a wreck (a wreck lies on the road
  with the whole box). Test: `test_kerb_lane.gd` (a shape query over a 15 cm strip: fails with the old floor).
* **The bus shelters and the noise walls stood across the road** (see status/world.md): the rest of the stuck cars of the soak stood
  against them; with the boxes along the road no traffic car stood against a prop in the last soak.
* Not done: a stuck car at (-967, 526) lane 10898 s 132/222 touching `roads_-2_1_concrete` under the viaduct (found three times, 1 m
  grid does not show it: a pier or a barrier in the lane; `check_path_blockers` should find it).
