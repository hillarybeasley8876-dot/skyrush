# Brief: fx_thrusters — the Roadster's cold-gas thruster plumes (signature effect)

## Goal
The money shot of the game: physically convincing, gorgeous **cold-gas** thruster jets, vapour
trails and ground clouds for the Roadster's 10 nozzles, driven by `telemetry.thrusters`. The user
asked for "飞行喷气细节超高精度还原" — ultra-faithful jet details. Match the reveal footage.

## You own
`game/fx/thrusters/**`. Entry: `res://fx/thrusters/thruster_system.tscn` (the fx unit's director
instances it once and calls `attach(vehicle)` for every car that has nozzle markers).

## Read first
1. `ref/roadster/DOSSIER.md` §5 (nozzle table, positions, directions, roles), §6 (plume reference
   with timestamps, §6.3 Godot recipe per nozzle — your starting point), §8.3.
2. Photos `ref/roadster/img/18_thrusters_firing_studio.jpg`, `27_live_flight_plumes_side.jpg`,
   `28_live_kickflip_plumes.jpg`, `29_live_launch_plume_overhead.jpg`; video
   `ref/video/roadster.mp4` t=100–154 s (extract frames with ffmpeg: landing clouds t=118–123,
   138–143, flip t=146–154). Keyframes in `ref/video/keyframes/`.
3. `ref/gameplay/DOSSIER.md` §5.3–§5.6 (when each nozzle fires), `ref/art/DOSSIER.md` §4.8 (plume
   colour, emission limits), `ref/tech/GODOT.md` §3.2 (particle budgets: ≤ 20k billboards, ≤ 4k with
   trails), `core/contracts/car_telemetry.gd`, `vehicle_base.gd` (`get_marker()`), `core/events.gd`.

## Spec (lead decisions)
- Markers: `vehicle.get_marker(&"Nozzle_R1")` … `&"Nozzle_P6"`; the marker's **−Z axis = jet
  direction**. If a marker is missing (stub car), fall back to the dossier §5 positions converted to
  Godot coords (x, z_blender→y, −y_blender→z) and directions, parented to the car.
- Intensity per nozzle = `telemetry.thrusters[name]` (0..1), smoothed: attack 40 ms, release 120 ms.
- Per nozzle layers (dossier §6.3, tune by eye against the photos):
  1. **JetCore**: cone mesh 0.03 → 0.09 m radius, length 0.9 m (R) / 0.6 m (P1–P4) / 0.35 m (P5/P6)
     × intensity; custom spatial shader: unshaded, additive, colour #EAF4FF, alpha fading along the
     length, **4 shock diamonds** (brighter rings at 0.06/0.15/0.24/0.33 m, relative 1.0/0.7/0.45/0.25),
     ±8 % length flicker at 25–35 Hz, emission energy ≈ 1.5 (just enough bloom), fresnel-soft edges.
  2. **JetVapour**: GPUParticles3D in world space (`local_coords = false`), 300–600/s per nozzle at full
     thrust, lifetime 0.8–1.4 s, speeds per dossier (R 30, P 30–35, yaw 15 m/s), spread 7°, damping
     100, scale 0.12 → 1.4 m, colour #F2F6FA a .85 → #D8DEE6 a .35 → 0, turbulence on, **lit** soft
     billboards (so neon and street lights tint them) using a noise-textured soft-puff sprite you
     generate (no hard circles). Sorting/blend so 4 overlapping plumes don't turn into a white wall.
  3. **GroundCloud**: when a down-firing jet (P1–P4) is ≤ 6 m above ground (raycast), spawn at the
     hit point: 60–90 large lit particles, radial 6–12 m/s, up 1–3 m/s, damping 3, size 1.5 → 5 m,
     life 2.5–4 s, #E6EAEE α .7 → 0; re-trigger every 0.25 s while firing. Target: ~20 m wide,
     ~2.5 m tall after 1 s (dossier §6.1). Rear launch: same but elongated behind the car.
  4. **LandingPuff** on `Events.landed` (quality clean/wobble, impact_speed > 4 m/s) and on sky-lane
     exit: ring burst at wheel height (gameplay dossier §5.5) + a faint ground ring decal 0.25 s.
  5. **Nozzle glow**: throat emission #9FD8FF up to energy 3 while firing (cold gas does not glow,
     this is the lit throat), plus one OmniLight3D per *group* (rear / under-body), #CFE3FF, energy
     0.5–1, range 2 m — max 2 lights per car.
  6. **Air distortion**: optional subtle screen-space refraction cone near the nozzle (≤ 2 % UV
     offset) — only if it costs < 0.2 ms; no heat haze tint.
- NO orange, NO fire, NO sparks, NO black smoke. Cold gas = white/blue-white vapour.
- Performance: whole system ≤ 1.2 ms GPU at 1080p with all 10 nozzles at full + 2 ground clouds;
  respect `Settings.feature("particles")` (scale emission amounts); max 2 cars with full FX
  (player + one), others get core + reduced vapour.
- API: `ThrusterSystem.attach(vehicle: VehicleBase) -> void`, `detach(vehicle)`; it reads
  telemetry every frame — no dependencies on vehicle internals.

## Test scene and evidence
- `fx/thrusters/demo/thruster_demo.tscn`: the roadster glb if present (`res://assets/cars/roadster/
  roadster.glb`) else a stand-in body with the markers, on a wet dark ground with a couple of neon
  lights, the stub environment, a script cycling: idle → hop burst → hover (P1–P4 0.5) → landing
  cushion → N₂ boost (R1–R4) → barrel-roll yaw bursts. Camera presets matching photos 18 (rear,
  low), 27 (side, hovering 6 m), 29 (overhead launch).
- Captures: `tools/godot.sh shot --scene=res://fx/thrusters/demo/thruster_demo.tscn --cams=... --times=...`
  side by side with the reference photos (PIL composite) → `captures/fx_thrusters/compare_*.jpg`.
- `tools/godot.sh check --only=res://fx/thrusters/` clean; a perf print (frame ms with/without FX,
  measured with the 8-view method or at least min/mean fps) in your status file.

## Acceptance
Side-by-side comparisons read as the same phenomenon as photos 18/27/29 and the landing clouds;
shock diamonds visible up close, soft billowing vapour, ground cloud scale right; no hard sprite
edges, no orange; performance budget met; works on the stub car and the real glb.
