# Brief: traffic — Shanghai night traffic (lane graph, IDM, kinematic until hit)

## Goal
Believable, dense, cheap traffic on every road and elevated deck that the player can weave
through, near-miss, and smash into realistic wrecks.

## You own
`game/ai/traffic/**` and the shared AI driving helpers `game/ai/common/**` (lane following,
steering controllers, spatial queries — police and rivals will reuse them; keep them generic and
documented). Entry (Modules unit `traffic`): `res://ai/traffic/traffic_director.tscn`.

## Read first
`ref/gameplay/DOSSIER.md` §6.1 (all numbers: FAR kinematic / NEAR dynamic / WRECK modes, IDM game
values, MOBIL-lite, reactions to the player, spawn ring, density, variety), §7.2 traffic glance,
§7.7 budgets; `ref/tech/GODOT.md` §6.4 (physics CPU: kinematic path followers, ≤ 8 full cars);
`core/contracts/world_base.gd` (`get_lane_paths`, `signal_state`, `get_spawn_transform`),
`lane_path.gd`, `vehicle_base.gd`, `core/events.gd` (`near_miss`, `vehicle_collided`,
`vehicle_wrecked`); the vehicle unit's `CarSpec` presets and `res://vehicle/cars/npc_car.tscn`
(read `status/vehicle.md`); npc_cars glbs in `res://assets/cars/npc/` (`SH_car_paint_npc` with an
instance-uniform colour — read `status/npc_cars.md` / `game/shaders/README.md`).

## Deliverables
1. `ai/common/lane_follower.gd` (distance along a LanePath, look-ahead point, lane change S-curve,
   next-lane choice at lane ends incl. turn probabilities), `ai/common/idm.gd`, spatial hash of cars
   per lane for leader lookup (O(1) per car).
2. Traffic cars: lightweight scene (RigidBody3D box collider + visual glb) with the 3 modes of
   §6.1; NEAR mode steers velocity; WRECK on contact ≥ 6 m/s (unlock, tumble, emit nothing special —
   the damage unit handles HP via `vehicle_collided` if you extend VehicleBase; traffic cars MUST
   extend `VehicleBase` with team TRAFFIC so damage/takedown logic works). Headlights/tail lights
   emissive; brake lights when decelerating; indicators before lane changes; occasional horns
   (audio unit plays `Events`? — emit a `horn` via a method the audio unit can find in group
   `traffic`, or request a signal).
3. Respect traffic lights via `Game.world.signal_state()` at junction approaches (stop line = lane
   end), queueing with IDM.
4. Spawn ring + density per §6.1 (`Settings.feature("traffic")` scales it), variety (models/colours
   per art dossier §4.7 colour mix; 5 % taxis, 8 % vans, 4 % buses/trucks), despawn rules, hard cap 90.
5. `near_miss` detection for the player (within 1.2 m at ≥ 60 km/h relative) → `Events.near_miss`.
6. Tests: `test_idm.gd` (no overlaps, stable platoon), `test_spawn_ring.gd` (counts, distances, never in
   view < 120 m), `test_lanes_world.gd` (runs on the sandbox and on `res://world/world.tscn` when it
   exists: 60 cars for 120 s at 4× speed — no car leaves its lane by > 1 m, none falls through, no
   errors), perf print (ms per tick for 70 cars). Windowed captures: traffic on the sandbox loop and,
   when available, on the real Yan'an elevated deck at night.

## Acceptance
Smooth believable flow (no jitter, no teleports in view), wrecks look physical, ≤ 1.0 ms/frame for
70 cars (§7.7), tests pass, check clean.
