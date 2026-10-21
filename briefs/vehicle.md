# Brief: vehicle — arcade car physics, QQ飞车 drift/boost, thrusters, sky-lane flight

## Goal
The driving heart of the game: a `RigidBody3D` arcade car (Jolt, 120 Hz, ShapeCast wheels) that
feels like QQ飞车 with the Roadster's thruster tricks, reusable for every car in the game (player,
rivals, police, crashed traffic) through a `CarSpec` resource.

## You own
`game/vehicle/**` except `game/vehicle/camera/` (another unit). Entry scenes the core loads:
`res://vehicle/player_car.tscn` (the player's Roadster) and generic `res://vehicle/cars/npc_car.tscn`.

## Read first
1. `ref/gameplay/DOSSIER.md` §0 (TL;DR), §1.4–1.6, §4 (physics recipe — implement literally),
   §5 (N₂ resource, hop, Big Hop, hover, roll, landing, sky lanes, obstacles), §7 (crash rules: you
   only expose impacts; the damage unit does the rest), §8 (tuning table) — your numbers.
2. `ref/tech/GODOT.md` §6 (physics facts) and the VERIFIED snippet
   `ref/tech/snippets/raycast_wheel_car.gd` — start from it (ShapeCast3D sphere probes, load cap,
   slip cancel, air levelling: keep those stabilisers).
3. `ref/roadster/DOSSIER.md` §2 (dimensions), §5 (nozzles), §6.2 (how the real car moves).
4. `CONTRACTS.md`, and the core sources: `core/contracts/vehicle_base.gd`, `car_telemetry.gd`,
   `sky_lane.gd`, `charge_station.gd`, `stunt_gate.gd`, `core/events.gd`, `core/input_setup.gd`,
   `core/sandbox/*` (your test track), `core/stubs/stub_car.gd` (what you replace).

## Lead decisions (override the dossiers where they differ)
- **Forward is −Z** (Godot convention; `VehicleBase.get_forward()`), right +X, up +Y. The gameplay
  dossier writes "+Z nose" — translate every formula to −Z. Front wheels at z < 0.
- Roadster geometry (Godot coords, origin = ground centre between axles): wheel centres front
  (±0.78, 0.3425, −1.4125) r 0.3425, rear (±0.815, 0.367, +1.4125) r 0.367; body box ≈ 1.95 ×
  0.80 × 4.38 m centred y 0.62. Mass 1,900 kg, CoM (0, 0.42, −0.05), inertia per dossier §4.3.
- Single resource **N₂** (0–200) exactly as dossier §5.2; battery (`telemetry.battery`) drains
  0.4 %/s at full throttle (0.05 %/s idle), < 0.15 caps top speed at 180 km/h; charge bays refill.
- Charge bays: on `Events.charge_finished(vehicle, …)` for your car → N₂ = 200, battery = 1,
  +20 HP (`repair` partially: `health = min(max_health, health + 20)`), `boost_kind = &"charge"`
  0.6 s (+6 m/s² push), emit `boost_started(.., &"charge")`.
- Sky lanes: on `Events.sky_lane_launch(vehicle, lane)` for your car, if speed ≥ lane.min_entry_kmh
  and N₂ ≥ lane.min_n2 → fly per dossier §5.6 using `lane.frame_at(offset)`; emit
  `flight_changed(true/false, lane)`, `n2_ring` when passing `lane.n2_ring_offsets`. Gravity 0 while
  flying; "flight" action (F) exits early; exit = descend + landing puff. Otherwise it's just a jump.
- 完美起步 (thruster launch): if accelerate is pressed within 0.28 s before `Events.race_started`
  (modes unit emits it) OR from standstill with accelerate+nitro together and N₂ ≥ 50 → 0.9 s
  0–100 launch, R1–R4 thrusters at 1.0, `boost_kind = &"launch"`.
- Impacts: in `_integrate_forces`, detect hits from the velocity change per tick (Jolt contact
  impulses are estimates — tech dossier §6.5) and emit `Events.vehicle_collided(self, other,
  impulse_Ns, point, normal)` once per contact pair per 0.15 s. Do NOT apply damage yourself; the
  damage unit listens and calls `apply_damage()`. Wall-glance assist per dossier §7.2 is yours.
- Thruster FX/audio interface: write `telemetry.thrusters[&"Nozzle_R1"]`… (0..1) every tick:
  R1–R4 for N₂ boost/launch/air 小喷; P1–P4 for hop (spike 1.0 for 0.15 s), Big Hop, hover,
  landing cushion; P5/P6 for yaw corrections in flight and barrel rolls; 0 otherwise.
- Visual binding (`car_visual.gd`): instance `spec.visual_scene` (the glb) under the `Visual` node,
  call `MaterialLibrary.apply()` on it, find `Wheel_FL/FR/RL/RR` and spin/steer/offset them with the
  suspension; `Wing` follows poses from its `extras.poses` metadata (stowed < 60 km/h, low_drag on
  straights, high_downforce when cornering/drifting, air_brake when braking > 150 km/h — angles
  change at ≤ 0.25 s); brake light/`LightBar_Rear` emission energy 4 → 10 on braking (set via
  `set_instance_shader_parameter` if the material is a ShaderMaterial, else a per-car material
  duplicate). If the glb is missing, build a tidy placeholder (white wedge + 4 wheels) so the game
  runs. The roadster glb is produced by the car_model unit at `res://assets/cars/roadster/roadster.glb`.
- Every hard-coded number lives in `vehicle/tuning/*.gd` const files or `CarSpec` presets — no magic
  numbers in logic files. Files ≤ 400 lines; split per dossier §4.9.

## Deliverables
- `vehicle/car_spec.gd` (`class_name CarSpec`, Resource) + presets in `vehicle/specs/`: `roadster.tres`
  and NPC presets from dossier §3.4/§6 (patrol, interceptor, heavy_suv, sedan, suv, taxi, bus, van).
- `vehicle/arcade_car.gd` (`class_name ArcadeCar extends VehicleBase`) + modules (wheel probe,
  suspension/tyre, drive/brake, drift_state, boost_state with CW/WCW/CWW caps, thruster_state:
  hop/Big Hop/hover/barrel roll/landing, sky_flight, charge/battery, impact detection).
- `vehicle/player_input.gd` (reads InputMap actions only; keyboard steer ramps per §4.5; gamepad curve).
- `vehicle/player_car.tscn`, `vehicle/cars/npc_car.tscn` (spec assigned before `add_child`).
- Tests (headless, `tools/godot.sh test res://vehicle/tests/<name>.gd`) printing PASS/FAIL:
  `test_launch.gd` (0–100 2.3 ± 0.3 s; launch 0.9 ± 0.2 s), `test_top_speed.gd` (250 ± 5 km/h,
  N₂ 300 ± 8, cap 330), `test_brake.gd` (100–0 ≤ 35 m), `test_drift.gd` (scripted 3 s drift at
  200 km/h → 95–105 N₂ committed, β 26–52°, no spin-out), `test_boost_caps.gd` (CW/WCW/CWW),
  `test_hop.gd` (hop apex 3.1 ± 0.3 m, Big Hop 7.8 ± 0.4 m, clean landing), `test_roll.gd`
  (360° in 0.70 ± 0.05 s, lands upright), `test_landing.gd` (drop from 8 m at 150 km/h: no flip,
  lateral drift < 0.3 m), `test_stability.gd` (300 km/h lane changes, no tunnelling, no roll-over),
  `test_sky_lane.gd` (sandbox lane: launch, stay in tube, rings refill, exit puff),
  `test_charge.gd` (sandbox bay refills), plus `tests/feel_report.gd` that prints one table of all
  measured numbers. Use the sandbox world (`res://core/sandbox/sandbox.tscn`) for all of them.
- Windowed evidence: `tools/godot.sh shot --press=accelerate --times=2,5 --stub=camera` style
  captures of driving, drifting, hopping and flying with `--debug` (overlay shows telemetry).

## Acceptance
All tests PASS; `feel_report` numbers inside the ranges; `tools/godot.sh check` clean; the player
car drives in `main.tscn` with real units loaded; ≤ 0.25 ms physics CPU per car per tick (measure
with `Time.get_ticks_usec()` around `_integrate_forces`, print in feel_report).

## Pitfalls
- Read input in `_physics_process`, never `_process`. Use `state` in `_integrate_forces`.
- Jolt: `continuous_cd = true`, `contact_monitor = true`, `max_contacts_reported = 8`.
- Don't fight the player: assists fade, never snap; no binary switches in feel code.
- Keep the car stable when the visual glb is missing or replaced at runtime.
