# Lead notes for fx_thrusters (mandatory; from the lead's look at fxth_*.jpg, round 1 in progress)
1. The plumes read PINK/MAGENTA and blotchy ("cotton balls") — wrong. Cold-gas vapour must read white / pale blue-white (#F2F6FA core, #D8DEE6 body) in neutral light. The demo scene is lit by a strong magenta light: change the demo lighting to match photo 18 (dark studio, one cool-white key light from behind/above + low cyan fill), keep at most a faint coloured neon far away. Plumes may pick up colour only from nearby coloured lights, never dominate as pink.
2. Vapour sprites need much softer, larger-scale noise (no visible individual puffs at 2–6 m): use a soft gradient sprite + 3D-ish noise (or flipbook) with alpha ≤ 0.35 per particle and more overlap, turbulence for billowing; the column must look continuous and dense near the nozzle, breaking into billows lower down (compare photo 27).
3. The jet core with 4 shock diamonds must be clearly visible in a close-up (camera 1.5 m from a rear nozzle) — add a capture `compare_core.jpg` side by side with a crop of photo 18.
4. Ground cloud scale: after 1 s it must be ~20 m wide and ~2.5 m tall around the car (photo 18/28 and video t=118–123 / 138–143). Show a 4-frame strip (0, 0.5, 1.0, 2.0 s).
5. Use the real roadster glb once `game/assets/cars/roadster/roadster.glb` exists (check status/car_model.md); until then the stand-in must at least have correct proportions (4.38 × 1.98 × 1.15 m) and the nozzle positions from the dossier table.

## Project-wide rules added by the lead (include in your feedback if the worker violates them)
- Tests must be `extends Node` scripts run with `tools/godot.sh test res://...` (test_host loads them at runtime after autoloads; see CONTRACTS.md §3 and `game/core/tests/test_core_smoke.gd`). `-s` SceneTree scripts compile before autoloads and break on Events/Game/VehicleBase.
- Every run must end by itself: tools/slots.py now kills headless runs after 300 s, windowed after 600 s, Blender after 2400 s. No Godot/Blender in the background, no scratch tests left running.
- Scratch files go to tmp/<unit>/ and are deleted when done; nothing outside owned paths.

## LEAD-SMOKE (10-20 10:50) — mandatory: the lead wrote the shared vapour particles
`game/core/fx/smoke.gd` (class SmokeFX) + atlas `res://assets/textures/fx/smoke_billow.png` (+ `_n` normal map,
generator tools/textures/gen_smoke.py). Look-dev: `res://core/fx/smoke_demo.tscn`; evidence captures/lead_smoke7_{jet,top,side}.jpg
(a jet firing onto wet asphalt -> a 10-12 m billowing ground cloud tinted by the neon lights).

    var p := GPUParticles3D.new()
    var spec := SmokeFX.preset(&"ground_cloud")    # jet_vapour, ground_cloud, tyre_smoke, dust, wreck_smoke
    spec["amount"] = int(spec["amount"] * float(Settings.feature("particles")))   # or your budget scaling
    SmokeFX.setup(p, spec)                          # lit soft billboards, random frame + angle, growth, fade

Lessons baked in (do not undo): `billboard_keep_scale = true` (or the particle scale/growth is dropped), one RANDOM
frame per particle with anim_speed 0 (the flipbook never animates: no "Pac-Man" frame 0), turbulence influence
<= 0.012 (larger values blend the launch velocity away and the cloud never spreads), proximity fade 0.35 m and the
ground cloud lifted half a sprite (a ground-level sprite is eaten by the soft fade).

Round 3: build JetVapour and GroundCloud (and the landing puff) on SmokeFX presets; keep your JetCore cone mesh for
the first 0.3–0.9 m (shock diamonds). Ground cloud: one emitter per down-firing group at the raycast hit point,
`emitting` while a P1–P4 jet fires within 6 m of the ground; rear launch: same preset with direction along -car Z.
Delete soft_puff.png / soft_puff_n.png and their generator if nothing else uses them (no dead assets).
