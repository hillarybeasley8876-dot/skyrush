# police status

Unit: 天巡 SKYPOL pursuits (heat, tactics, roadblocks, spikes, drones, busted/escape).
Owns `game/ai/police/**` only; reuses `game/ai/common/**` (traffic unit) and the vehicle unit's
`ArcadeCar` / `CarSpec` presets.

## Done

### Round 3 (the review round 3 must-fixes)

- **The push train (item 1).** `police_follow.gd` owns the car following of every unit: the
  leader in front is found with a ray on the vehicle layer and the IDM of the traffic unit
  gives the acceleration. A unit never pushes another police car or the traffic, and the
  player is the one car a unit brakes for: the gap to him is 1.0 m, so a unit stops right
  behind a standing player. Inside the press distance the speed of a pursuing unit is
  `min(player_speed, v_cached)` (`v_cached` = the speed of the player of the previous tick
  from the contact cache), never more than the player. The roles that hit the player on
  purpose (the ram, the PIT and the box) do not brake for him.
  **A bug of Godot found on the way:** `PhysicsDirectSpaceState3D.intersect_ray` has no
  "distance" key, so the gap of every unit was the length of the probe (60 m) and the IDM
  never braked for anything. The distance is measured from the two points of the ray now.
  The model has a speed of its own (`_follow_speed`): with the real speed of the car as the
  input of the model, the acceleration is a step above the speed and the throttle of the car
  is always zero.
  Tests: `tests/test_bust_crowd.gd` (the K4 setup: the player stops in 0.4 s of the brake
  and is busted in 2.8 s; the B3 setup with eight units: the same; zero police↔police
  contacts in both runs).
- **The city spawning (item 2).** The backup timer only runs when a running pursuit lost
  all its units, a failed spawn is retried in 1.0 s (`SPAWN_RETRY`), and a new pursuit
  spawns its first unit within `FIRST_SPAWN` (1.2 s). `PoliceSight.visible_to_player()`
  is the ONE test for "the player can see it": in the frustum, within 250 m and with a
  clear line of sight (a point behind a building is not visible). The places are the police
  stations of the world, the oncoming lanes, the lanes ahead and the lanes behind the
  player. `close_units` counts the units on the road, not the cars in the pool.
- **The roadblocks (item 3).** The block stands on the predicted route of the player,
  350-450 m ahead, out of his view. The route follows the STRAIGHTEST successor of a lane
  (`PoliceRoute.successor`), the walk reports a dead end (`found` is false) and a spot that
  is closer than `ROADBLOCK_MIN` is rejected. A roadblock site of the world is only used
  when its -Z faces the traffic that comes at it (`site.basis.z · route > 0.7`) and the
  width of the road is measured at the site, not at the lane of the player.
  `PoliceToll` closes the toll plazas at heat 5: the closure is on the road of the plaza,
  it faces the player and its cars are in `block_cars`. Test: `tests/test_toll.gd`.
- **The spike strip (item 4).** The strip is centred on its node: the cases run from -3.5 m
  to +3.5 m and unroll from the lamp end (+3.5 m) towards the other end. The lamp is a
  cylinder with the case material (the metal atlas reads at 512 px/m) at +3.62 m and it
  blinks on its own clock (2 Hz). The sweep of the review is in `tests/test_spikes.gd`:
  punctured at x = -3.0, -1.5, +1.5 and +3.0, not at ±4.5, and the cases run from -3.5 m to
  +3.5 m (±0.05).
- **The roadblock dressing (item 5).** A barrier is never stretched: whole barriers are
  placed (a run may overhang into the shoulder) and the invisible wall stays. A closed block
  has `floor(width / span)` cars at a pitch of `span + 0.1 m` and the rest of the road is
  closed with barriers. At heat 4 the cones are a straight line at z = +4 m, 1.2 m apart
  (never two on the same spot); a block with a gap keeps the taper that leads into the gap.
  The sign board stands at the kerb, but its place is checked with a down ray (the ground
  has to be there and nothing may stand over it) and it moves inward when it is not on the
  road. Test: `tests/test_roadblock.gd` (the barriers are not scaled, the cars of a closed
  block do not overlap for the widths 7, 10.5, 13.5 and 22.1 m, the cones stand 0.8 m
  apart, the distance is measured along the route).
- **The drone (item 6).** The beam is a shader now: the caps are off, the length is the ray
  from the gimbal to the ground (not to the player), the node is scaled instead of the mesh
  being rebuilt, and the alpha is the product of the rim fade, the length fade (full at the
  lamp, a quarter at the ground), the fade of the last two metres, the camera fade (nothing
  within 8 m of the axis) and slow 3D dust. With the volumetric fog of the quality preset
  the search light gets its fog energy and the mesh alpha is halved. The rotors spin about
  their own axis (`rotate_y`, the left ones one way and the right ones the other). The drone
  leads its hover point by the speed of the player, so it hangs 20 m behind him and not 35.
- **The light bar (item 7).** The unit builds its own lens texture: a 64x32 module tile with
  a 3x2 grid of round LED dots with a soft falloff and a reflector ring, on the dark red
  (#1A0306) and dark blue (#03081A) background of the halves. It is the emission and the
  albedo of the copies, with `uv1_triplanar` and a scale of 19 (about twelve modules on a
  half), and a roughness of 0.12. The emission energy is still 12 x the pattern plus the
  idle 0.3.
- **The hold-back (item 8).** One ranking per tick: the hold-back, the physics and the
  lights all read it. Every unit behind the three nearest holds back (a unit that is still
  far away is held back as well, or it would drive up to the player before it is stopped):
  it aims at a point at least 38 m behind the player and it brakes (the speed of the
  player minus 6 m/s) inside 31 m. A unit that is too close drives at the player and
  slows down: it does not turn around.
  Test: `tests/test_hold_back.gd` (the B3 setup: never more than 3 units within 30 m in
  2040 frames, the worst is 2, and the player is busted 2.8 s after the stop).
- **The ghost units (item 9).** A ghost drives its lane (the straightest successor) and is
  placed with the lane graph, so it does not cut through the blocks. It switches to the
  physics at once when the player can see it.
- **The pool (item 10).** A car that waits in the pool leaves the groups "police" and
  "vehicles" (the audio unit would give it a siren) and comes back when it is taken out.
  The cars of a roadblock that stand on the road are police cars, the ones under the road
  are not. Test: `tests/test_pool.gd`.
- **The test suites (item 11).** `test_offences.gd` is split: the offences (16 checks) and
  the contacts (`test_offences_contact.gd`, 12 checks) both pass with the documented command.
  The edge trigger uses the toll evasion (which needs no patrol in sight) and prints the
  delta. The PIT test asserts that the ramming unit really touched the player. New:
  `test_bust_crowd.gd`, `test_hold_back.gd`, `test_toll.gd`, `test_pool.gd`.
- **The performance (item 12).** The roles are only handed out when the set of units or the
  heat changes, the ranking of the units is built once per tick and reused, the light
  energies are only written on a pattern edge, the beam of the drone is not rebuilt, the
  toll plazas are read every five seconds and the group of the cars is not copied any more.
  The dispatcher has a timer per part and `test_perf.gd` prints the five most expensive
  ones and the load of the machine.
- **The captures (item 13).** The demo waits for the world (`await Game.world_ready()`),
  drives the straightest successor of the lane graph, has a stuck detector that puts the
  player back on his lane and starts the units of the box 30-45 m behind the player (the
  box is formed on the road, not placed in the frame of the capture). The place of the
  player is the longest road near the point of interest.
- **The code rules (item 14).** The files over 400 lines are split: `police_car.gd` (the
  state machine is in `police_car_roles.gd`), `police_roadblock.gd` (the dressing is in
  `police_roadblock_props.gd`), `police_director.gd` (the world setup is in
  `police_world_setup.gd`), `police_blockade.gd` (the strips are in `police_strips.gd`),
  `police_spawner.gd` (the places are in `police_spawn_spots.gd`), `police_demo.gd` (the
  freeze is in `police_demo_freeze.gd`). The magic numbers have names, the dead constants
  are gone and the gameplay timing runs on the tick clock (the radio, the PIT and the EMP
  blink).

### Bugs the round 3 review did not name (found while fixing the rest)

- The role cooldown was dead: the roles were handed out every tick, so `set_role` put a
  unit back into its role while it was cooling down. The PIT and the box were broken by it.
- The IDM of the police needs the headway of the police (0.4 s) and not the one of the
  traffic (1.2 s): a unit that waits a second and a half before it reaches the car in
  front is too far away to bust a player.
- The model of the following must not throw its speed away when a corner limits the speed
  of the car (`FOLLOW_RESYNC` = 8 m/s): the unit then trails the player for ever.
- The busted meter of the box faded instead of being reset, so a box that breaks up for a
  moment lost its hold.
- `DriveContext.rng` was null in a run (the context of the traffic unit is reloaded while
  the game runs): the dispatcher builds its own source when there is none.

## In progress / next
- The city sheet of the captures is made (the nine frames in `captures/`), but the frames
  have to be looked at one by one: the first run showed the player on a pavement and the
  units in front of him (the sign of the frame of the demo was inverted). Both are fixed;
  the sheet is made again now.

## How to test (exact commands)
```
tools/godot.sh check --only=res://ai/police/
tools/godot.sh test res://ai/police/tests/test_heat.gd
tools/godot.sh test res://ai/police/tests/test_busted.gd
tools/godot.sh test res://ai/police/tests/test_roadblock.gd
tools/godot.sh test res://ai/police/tests/test_drone.gd
tools/godot.sh test res://ai/police/tests/test_pit.gd
tools/godot.sh test res://ai/police/tests/test_box.gd
tools/godot.sh test res://ai/police/tests/test_head_on.gd
tools/godot.sh test res://ai/police/tests/test_spikes.gd
tools/godot.sh test res://ai/police/tests/test_bust_crowd.gd
tools/godot.sh test res://ai/police/tests/test_hold_back.gd
tools/godot.sh test res://ai/police/tests/test_toll.gd
tools/godot.sh test res://ai/police/tests/test_pool.gd
tools/godot.sh test res://ai/police/tests/test_offences.gd
tools/godot.sh test res://ai/police/tests/test_offences_contact.gd
tools/godot.sh test res://ai/police/tests/test_perf.gd
```
The captures (the city, 1600x900, the game chase camera):
```
tools/godot.sh shot --scene=res://ai/police/demo/police_demo.tscn --out=chase_h3 --city=true --scenario=chase --rcam=police --times=6
tools/godot.sh shot --scene=res://ai/police/demo/police_demo.tscn --out=pit_contact --city=true --scenario=pit --rcam=police --times=8
tools/godot.sh shot --scene=res://ai/police/demo/police_demo.tscn --out=box_formed --city=true --scenario=box --rcam=police --times=12
tools/godot.sh shot --scene=res://ai/police/demo/police_demo.tscn --out=roadblock_h3 --city=true --scenario=roadblock3 --rcam=chase --times=10
tools/godot.sh shot --scene=res://ai/police/demo/police_demo.tscn --out=roadblock_h4 --city=true --scenario=roadblock4 --rcam=chase --times=10
tools/godot.sh shot --scene=res://ai/police/demo/police_demo.tscn --out=spikes_close --city=true --scenario=spikes --rcam=chase --times=10
tools/godot.sh shot --scene=res://ai/police/demo/police_demo.tscn --out=drone_chase --city=true --scenario=drone --rcam=chase --times=10
tools/godot.sh shot --scene=res://ai/police/demo/police_demo.tscn --out=head_on --city=true --scenario=head_on --rcam=chase --times=14
tools/godot.sh shot --scene=res://ai/police/demo/police_demo.tscn --out=toll_closed_h5 --city=true --scenario=toll5 --rcam=chase --times=12
```
The demo freezes the scene the moment the tactic is there, so the shot at the time above
shows that moment. The scenarios `chase`, `pit` and `box` use the camera of the demo (it
stands behind and beside the player, so the units that come from behind are in the frame);
the other six use the game chase camera, because the tactic is in front of the player there.
With `--place=<n>` the player starts on the road at the n-th police station of the city: the
demo looks for the longest road (at least 600 m) near it, so the chase has room to run.

## Evidence
- `tools/godot.sh check --only=res://ai/police/`: `CHECK 61 files, 0 failed, 0 engine
  errors, 0 warnings`.
- The suites (the command of the test host, without the import step):
  `test_heat.gd` 19, `test_busted.gd` 8, `test_roadblock.gd` 28, `test_drone.gd` 13,
  `test_pit.gd` 6, `test_box.gd` 7, `test_head_on.gd` 8, `test_spikes.gd` 20,
  `test_bust_crowd.gd` 6, `test_hold_back.gd` 3, `test_toll.gd` 4, `test_pool.gd` 3,
  `test_offences.gd` 16, `test_offences_contact.gd` 12 - all "POLICE TESTS OK (n checks,
  0 failures, 0 engine errors of the police code)".
- `test_perf.gd` (the heat-5 unit count, 12 units, 1200 frames, the raw tick of the
  dispatcher): the mean 0.29-0.37 ms (the budget is 1.5), the peak 0.55-0.68 ms (the budget
  is 3.0) and the wall time of the physics frame +1.04 to +1.29 ms (the budget is 2.0) on
  a machine with a load of 20. The five most expensive parts: the squad 0.21 ms, the road
  0.04 ms, the watch 0.02 ms, the sight 0.01 ms, the spawning 0.01 ms. A third run on a
  machine with a load of 34 had a tick of 23 ms: a tick that is preempted is that long.

## Known issues
- The peak of the dispatcher (the slowest tick) is measured on a machine that runs the tests
  of the other units at the same time: the mean and the wall time of the police stay inside
  the budget, the slowest tick does not.
- The import step of `tools/godot.sh` is queued behind the other units (one import slot for
  the whole machine), so the checks and the tests above were run with the slot lock of
  `tools/slots.py light 6` and without the import step.
- `PoliceDriver.MAX_LATERAL` is 9.0 m/s^2 (0.92 g). The arcade car of the vehicle unit rolls
  over above ~0.8 g, so a unit that takes a corner at the limit can end on its roof.
- The road width is measured on the lanes that run beside the lane of the player. The world
  knows the width of its roads exactly; a `road_width(pos)` in the world API would be better
  than the measurement.

## Requests
- (to vehicle) the car of the police unit is the roadster of the fleet with a `CarSpec` of
  the vehicle unit. The arcade car rolls over above ~0.8 g, but the box of the dossier needs
  0.92 g of side force (the unit has to move 4.6 m to the side while it overtakes). Either
  the grip of the car goes up, or the box has to overtake over a longer distance.
- (to vehicle) the punctures of the police have no effect on the grip: the dossier §3.1 says
  the punctured car loses its grip (mu x 0.55) and it should spark at the rim. The police
  unit caps the speed of the player (65 % for eight seconds), the vehicle unit has to do
  the grip.
- (to vehicle) the EMP of the police needs the API of the vehicle unit: 30 % less speed and
  no N2 for three seconds. The police unit writes it into the boost module of the player.
- (to world) `res://world/world.gd:313 _closest_lane()` raised "Trying to assign an array of
  type Array to a variable of type Array[int]" every time the police asked the world for a
  lane. The police work around it (they use the lane graph of the world), but every capture on
  the city logged the error.
- (to world) the width of a road: the police measure it on the lanes that run beside the
  lane of the player. A `road_width(pos)` in the world API would give the block of the police
  the exact width of the road it stands on.
- (to npc_cars) the light bar halves of `police_patrol.glb` have no texture at all
  (`NPC_lightbar_red`/`NPC_lightbar_blue` have no base and no emission map) and they are
  3.5 cm slabs. The police unit builds its own lens texture in code (a module tile with LED
  dots), but a real lens model with a texture would be better.
- (to audio) the radio lines `radio_emp`, `radio_emp_pulse` and `radio_spikes` are not in
  the voice manifest: the police manifest asks for them, so the EMP and the spike strips have
  no voice yet.
- (to props) the sign board of the roadblock (`police_sign_board.glb`) reads "公安 POLICE",
  and ART.md §7 forbids 公安/警察/POLICE on the signs of the game: it should read something
  like "天巡 SKYPOL 前方设卡 减速慢行".
