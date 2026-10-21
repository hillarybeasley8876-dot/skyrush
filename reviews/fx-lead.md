# Lead notes for fx (mandatory)
F-INT1 (lead integration run): `res://fx/fx_rain.gd:169/197/219` assign to a Nil node (≈ 650 errors in 18 s) — guard/create the
  emitters before use. `res://fx/fx_skid_ribbon.gd:128` calls a non-existent `ArrayMesh.surface_set_arrays` (Godot 4 API: clear_surfaces()
  + add_surface_from_arrays(), or ImmediateMesh / a pooled MultiMesh of quads).
F-INT2: tyre smoke / wet spray volume is overwhelming in the real game (the whole lower half of the frame is grey puffs while the car is
  nearly stationary against a wall). Scale emission with slip × speed, cap density, fade faster (≤ 1.5 s), no smoke below 10 km/h.

## Project-wide rules added by the lead (include in your feedback if the worker violates them)
- Tests must be `extends Node` scripts run with `tools/godot.sh test res://...` (test_host loads them at runtime after autoloads; see CONTRACTS.md §3 and `game/core/tests/test_core_smoke.gd`). `-s` SceneTree scripts compile before autoloads and break on Events/Game/VehicleBase.
- Every run must end by itself: tools/slots.py now kills headless runs after 300 s, windowed after 600 s, Blender after 2400 s. No Godot/Blender in the background, no scratch tests left running.
- Scratch files go to tmp/<unit>/ and are deleted when done; nothing outside owned paths.

## INT3 — lead integration drive 10-20 09:00 (evidence: captures/lead_int3_t2_0.jpg / _t6_0 / _t10_0 / _t14_0 (lead integration drive 10-20 09:00, `tools/godot.sh drive --timeline=res://tools/timelines/smoke_drive.json --skip-menu --debug --shots=2,6,10,14 --out=lead_int3`, all 13 units real))
F-INT3: the wrecked-EV arcs (`fx_arcs.gd`) draw 3–6 m long straight cyan lines sticking out of the car into the air (t10, t14: car
  at 5–15 km/h against a wall and on its side). Arcs must stay ON the body shell (≤ 0.15 m off the surface, each bolt ≤ 0.8 m), be
  computed in the car's local space every frame, appear only below 30 % health, and never span the car when it is flipped.
F-INT4: tyre smoke / dust puffs read as grainy dithered noise squares (t10, t14). Use a soft, blurred puff texture (no high-frequency
  grain), soft particles (depth fade 0.5 m), lit/unshaded-with-ambient tint so they are grey-blue in the night, alpha ≤ 0.35, growing
  and fading — never a crisp noise card.

## LEAD-SMOKE (10-20 10:50) — mandatory: fixes F-INT4 (grainy noise-square smoke)
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

Use the tyre_smoke / dust / wreck_smoke presets for the car rig, impacts and wrecks (adjust amounts/colours per
effect, keep the material and process settings). Steam/spray on wet roads may reuse jet_vapour with a low speed.
