# damage review round 2 — VERDICT: FAIL

Reviewer: lead/art director, 2026-10-20. I measured every number below myself (see Evidence).
Round 2 fixed the respawn flag, the ghost collisions, the trim swap, the paint colour, leaks and
the rules. But the two things the player sees most are broken:
- **The paint-scrape mask never reaches the GPU.** The scrape layer never renders.
- **The dents push the paint skin behind the car's black trim and inner surfaces.** That makes
  the black, blotchy rectangles in your captures. They are not "the carbon of the scrape".

Also, every car in the city now carries a live damage rig from the moment it spawns. Undamaged
traffic shows blue electrical arcs and strobing head lamps.
The user asked for refined textures everywhere ("贴图纹理什么都要细化"). Right now the damage reads
as black stickers.

## Scores (0-10)
- function: **4**. The formula, takedowns, respawn flag, ghost collisions and leaks are good.
  The mask upload, wheels, respawn speed, doors, atlas, debris colour, rig gating and budget test are broken.
- visual/feel: **2**. Black rectangles instead of dents. No visible scrape layers. Arcs show in 1 of 4 frames.
  Smoke is weak. No flying parts in the crash.
- code: **4**. The module split is clean. But the budget test can't fail, `wreck_point` is never set,
  some code is dead, structs are still dictionaries, damage_fx.gd sits at exactly 400 lines,
  and the evidence is stale.

## Claims in status/damage.md and result.md that are false (fix the status too)
- "the median cost of a hit is 0.124 ms": `hit_usec` is never assigned, so the test prints 0.000 for every hit (item 4).
- "the head lamp only flickers at LIGHT/HEAVY": it flickers at HP 100 on every car (item 3).
- "one wheel only, and only above impact 0.7": every violent wreck loses 4 wheels (item 5).
- "the carbon of the scrape on the door": that is M_BlackTrim/M_InnerDark showing through the pushed-in door (item 2).
- "a coarse panel keeps the scrape of the mask": a panel the dent skipped never gets `mask_enabled` (item 9).
- "every surface keeps … the paint colour of the car" (debris): `base_color_override` is null on debris (item 10).
- "respawn at 70 % of the pre-crash speed": after a 30+30 head-on it is 42 m/s, not 21 m/s (item 6).

## MUST-FIX (in this order; 1–3 are blockers)

1. **The scrape mask is never uploaded.** `dent_painter.add_dent()` splats into the CPU image but never
   calls `_notify_dirty()`. Only `soften()` calls it (dent_painter.gd:184). So the painter never joins
   `dirty_painters` and `MaskAtlas.upload()` never runs after a hit.
   Probe F replays the shader lookup on Door_R after a 16 m/s side hit: the CPU mask reads **0.50**
   at (0.93, 0.50, 0.09). The mask-only frame (`captures/review/damage/r2y_mask_crop.jpg`, dents off) still shows a clean white door.
   Do: call `_notify_dirty()` at the end of `add_dent()`, and count uploads (`upload_count`).
   Verify:
   - A test: after a hit + 0.3 s, `upload_count ≥ 1`.
   - A windowed 2 m mask-only capture shows primer `#8C8F93` at the hit.

2. **The dents sink the paint behind the un-dented trim and inner surfaces. These are the black rectangles.**
   Only surfaces that pass `_is_car_paint()` move. The Roadster's `M_BlackTrim`/`M_InnerDark`, the door
   cavity, door cards and npc `Trim`/`Interior` stay put. A 0.12–0.19 m push therefore puts the door skin behind them.
   Proof (`captures/review/damage/r2y_layers_sheet.jpg`, `r2ab_sheet.jpg`):
   - dents only (mask off) gives the same black patch
   - crumple 0 still gives the black patch
   - `dent_scale` 0.15 makes the patch disappear
   - default brings it back

   The blotchy black is the trim texture (the same pattern as the undamaged black sill). The straight
   edges are the door opening. On the police (`r2y_t4_6.jpg`):
   - Both doors show flat dark rectangles.
   - A white jagged notch sits at the window line.
   - The B-pillar between them stays un-dented, because the coarse-panel rule skipped `Body`.

   Do:
   - a) Apply ONE displacement field to EVERY surface of every mesh inside the dent sphere: paint, trim, inner,
     door cards and lamp lenses. Write `game/damage/dent_basic.gdshader`. It reproduces the BaseMaterial3D it
     replaces (albedo colour + texture, roughness + texture, metallic, normal map, emission) and adds the same
     `dent_pos/dent_dir` vertex code. Install it lazily on the first dent that reaches the mesh, using the same
     slots as that mesh's paint panel. CPU deformation of all meshes (§7.5 B) is an accepted alternative.
   - b) Delete the "coarse panel is not dented" rule (`DENT_RESOLUTION_FACTOR`). A skipped panel tears away from its
     neighbours. Keep the dossier depth. Keep the edge clamp only if the 6 m read below passes.
   - c) Keep the vertex crumple ≤ 0.01 m. Cap the per-pixel tilt at 25° (|grad| ≤ 0.47).

   Verify by re-shooting the lineup with panel contact points (copy `tmp/review/damage/r2_lineup.gd`) and
   `res://world/env/environment.tscn` instanced, so the dents are judged under the game's reflections:
   - 2 m, dents only, inside the dent: no trim-dark pixels (≤ #2A2A2E) except real seams. Mean luminance ≥ 0.6 × the clean panel. A darker crease ring at 0.7–0.9 r.
   - On the police, the two doors and the B-pillar must form one continuous bowl.
   - At 6 m (1600×900), the dent must distort the highlights over ≥ 30 px.

3. **Every car runs a live damage rig from the moment it spawns.** I ran a full-game probe
   (`tools/godot.sh test /Users/minimax/m/skyrush/tmp/review/damage/probe_r2e.gd -- --skip-menu`, after 12 s):
   - 115 vehicles, of which 97 are at full HP. 115 rigs and **230 OmniLights**.
   - Arcs were visible on **1,526 car-frames out of 120 frames** (about 13 cars per frame flash blue arcs plus a #5AB8FF energy-3 light).
   - **167 `Parameter "material" is null` engine errors.** With `--stub=damage` there are 0.

   Single cars:
   - The Roadster at HP 100: lamp energy changed 11× in 2 s, and arcs showed in 58 of 240 frames.
   - The police car at tier 0: arcs in 30 of 240 frames.

   Causes:
   - `EvArcs._process` runs whatever the tier, and `_arcs` starts visible.
   - `_tick_lamp` runs at every tier.
   - `_set_lamp` writes absolute 1.0/0.12 values. The npc lamps are designed at 6.0, so they are dimmed by 83 %.
   - `_set_lamp` also writes the `energy` instance uniform, which the traffic unit owns (traffic_lamps.gd:52,
     traffic_visual.gd:98). So every traffic car's head lamps strobe.

   Do:
   - **This replaces r1 #16's "build at join".** At join, build only the cheap part: the panel list from a
     per-Mesh cache, ≤ 0.3 ms. Create materials, mask, lights, particles and arcs at the first damaging hit,
     or when the tier needs them. Keep idle nodes at `visible = false` and `set_process(false)`.
   - Arcs only when `electric and tier == HEAVY`.
   - Lamp flicker only at LIGHT and HEAVY:
     - Save each surface's original `emission_energy_multiplier` and flicker between ×1.0 and ×0.12 of it.
     - Restore the original exactly on repair.
     - Never write another unit's instance uniforms. For traffic lamps (a `material_override` from
       TrafficMaterials), write a Request asking the traffic unit to flicker its own `energy` on `vehicle_damaged`.
   - Find the source of the null-material errors and remove it. Bisect: rig, painter, debris.

   Verify:
   - Re-run probe_r2e: rigs exist only on damaged cars, 0 arc car-frames on non-heavy and non-EV cars,
     and 0 null-material errors.
   - Lamps: CLEAN gives 0 changes in 2 s, LIGHT gives 4–8 dropouts, and an npc lamp is back at 6.0 after repair.

4. **The budget test can't fail, and the real costs are far over budget.** `hit_usec` (damage_director.gd:48)
   is never assigned, so test_budget prints 0.000 ms for the median, mean, p90 and worst.
   I measured (probe_r2a, probe_build):

   | what | cost |
   |---|---|
   | side hit | 0.62 ms |
   | front hit | 0.20 ms |
   | the hit that enters LIGHT tier (`FxAssets.smoke_texture()` builds 16k noise samples) | **13.9 ms** |
   | respawn `soften()` (`MaskAtlas.halve()` loops over 262,144 pixels in GDScript) | **11.3 ms** |
   | state build at join | **4.1–12 ms per car**, 58 ms for the first |

   With 115 cars, that is a 5 ms spike on 115 frames at start and on every traffic spawn. The 512² RGBA8 masks
   (a 1 MiB image + a 1 MiB texture each) add up to about 230 MiB, for cars that were never hit.

   Do:
   - Time the whole `_on_vehicle_collided` into `hit_usec`.
   - Prewarm the static textures and brushes in the director's `_ready`.
   - Cache `_average_edge`/AABB per Mesh resource in a static Dictionary.
   - Use a mask pool of ≤ 16, FORMAT_R8 (or RG8, see 9), with LRU recycle.
   - Halve the mask on respawn with a `mask_gain` uniform, not a pixel loop.

   Verify: test_budget asserts the following and prints every number:
   - mean ≤ 0.3 ms and max ≤ 1.0 ms over 20 hits, including the first hit of a fresh car and a tier change
   - join ≤ 0.3 ms per npc car (10 cars)
   - respawn ≤ 0.5 ms

5. **Every violent wreck still takes all four wheels, and the "nearest" wheel is measured to the world origin.**
   Two bugs:
   - `CarDamage.wreck_point` is never written, so part_manager.gd:178 measures to `Vector3.ZERO`.
   - `parts.check()` runs after `apply_damage()` has wrecked the car, so every `Wheel_*` (zone ANY, MODE_WRECK) passes.

   Probe C, a 30+30 head-on: `detached=[Skirt_L, Wheel_RR, Bumper_F, Hood, Wheel_FL, Wheel_FR, Wheel_RL]`.
   The other car lost 4 wheels too. The wheel debris cylinder is h = **0.69 m** (the wheel's height). The dossier says r 0.36 h 0.28.
   The r1 hub tilt is not done.

   Do:
   - Skip MODE_WRECK parts in `check()`.
   - Set `state.wreck_point = contact.world_point` in `hit()` BEFORE `apply_damage`.
   - Cylinder height = the AABB size along the spin axis (x). Radius = max(y, z) / 2.
   - Tilt the Visual so the bare hub corner drops ≈ 0.34 m.

   Verify in test_parts_real, on the real Roadster AND police_patrol.glb:
   - A front-left 32 m/s head-on takes exactly one wheel, `Wheel_FL`.
   - An HP wreck by scrapes takes 0 wheels.
   - The cylinder h is 0.25–0.35 m.

6. **Respawn: speed, flicker, timing, doors.**
   - **Speed.** `pre_crash_speed = maxf(pre_crash_speed, v_rel.length())` (impact_handler.gd:28) is still
     the lifetime maximum of the RELATIVE speed. After a 30+30 head-on the player respawns at **42.0 m/s**
     (151 km/h, probe C), which is exactly r1 #10. Store the car's own `_pre_velocity(car).length()`, passed
     from the director, at the wrecking hit only.
   - **Flicker.** 14 ghost alpha samples were all **0.50**. `_flicker` steps exactly 1/6 s at 6 Hz, so
     `sin(elapsed·6·TAU)` is always 0. Drive it from `_process` with the real elapsed time.
   - **Timing.** The respawn uses the wall clock (`Time.get_ticks_msec`, wreck_flow.gd:239), which breaks
     `--fixed-fps` movie runs. Use `create_timer(CAM_TIME, true, false, true)`, like the AI path does.
   - **Doors.** A sprung door stays open after respawn (Door_L at 15°). Save the rest transforms in CarDamage and restore them in `reset()`.

   Verify in test_respawn:
   - A 30+30 head-on gives |v| = 21.0 ± 0.5 m/s.
   - Spun 120°: dot(v̂, road forward) > 0.99.
   - The ghost alpha reaches ≤ 0.35 and ≥ 0.65 within the 2 s.
   - The doors are back at rest.

7. **The doors spring INTO the cabin and keep turning.** `_spring_open` turns every door +15° about its
   local Y on every side hit ≥ 18 m/s. After two 20 m/s left hits, Door_L's centre moved from x **−0.783 to
   −0.526** (inward) and the rotation is 30° (probe B).
   Do: open outward, choosing the sign that increases the |x| of the trailing edge in car space. Open once, to 15° at most.
   Verify: after two hits the angle is 15° and the trailing edge's |x| grew by ≥ 0.15 m.

8. **The atlas box is the collision box, and brushes bleed across regions.**
   - `_read_body_box()` takes the BoxShape3D: Roadster min (−0.975, 0.22, −2.19), size (1.95, 0.8, 4.38).
     The Body spans y 0.12–1.145 and z −2.29–2.09. So anything below 0.22 m or above 1.02 m samples outside
     its region. For example, the upper-left canopy reads the front and rear regions.
   - `splat()` clamps the brush to the whole 512² image, not to its region. A LEFT-rear hit added **55.4**
     to the RIGHT-side region (probe A).
   - Half the atlas is unused. The sides get only 58 × 160 px/m.

   Do:
   - Box = the merged AABB of all painted meshes in car space, + 0.02 m.
   - Use R8 1024² (the same 1 MiB as today's RGBA8 512²), packed so every region gets ≥ 150 px/m on both axes, with a 4 px gutter.
   - Clip each brush to its region rect. Never shift it.

   Verify with a test:
   - The 8 AABB corners of every painted mesh map inside their own region.
   - A left-rear hit leaves the right region at 0.

9. **The paint-damage layers (r1 #7) are not there, even after fix 1.**
   Problems:
   - `_region_slide()` returns an angle whose `perp` is parallel to the panel normal: π/2 gives (−1,0,0) on the
     sides, and 0 gives (0,0,1) on the front and rear. So `scratch_lines_at()` is constant there: no scratches.
   - The carbon "twill" is an XZ checker. On the sides and front it renders as stripes, with no weave and no anisotropy.
     It also aliases: an 8 mm cell is about 1 px at 6 m, and nothing uses `fwidth`.
   - Bare steel uses the same broken scratches.
   - The brushes use a per-texel white-noise hash (salt and pepper on 1.8 cm texels).
   - The streak length uses v_n, not the tangential speed |v_t| (r1 #6).
   - `mask_enabled` is set only on panels a dent touched.
   - The Roadster's sloped nose samples the ROOF region (840 of Body's vertices do), but front hits splat into FRONT only.

   Do:
   - Compute region-plane coordinates in metres in the shader: sides (z, y), front/rear (x, y), roof (x, z).
     Drive the scratches, the weave and the mottle from them.
   - Store the slide angle in the mask's G channel (0..π maps to 0..1). Draw scratches along it at 300 lines/m.
     Fade them to their mean with `fwidth` when a line is narrower than 2 px.
   - Carbon: follow the art dossier spec (ref/art/DOSSIER.md, carbon row: acg `Fabric004`, 6 mm weave, `#1C1E22`,
     roughness 0.35, anisotropy 0.5). Request that the lead add Fabric004 to `game/assets/textures/`. Until then,
     build a procedural 2/2 twill (tows go over 2, under 2, shifted one cell per row) with a cosine tow profile,
     the highlight stretched along the tow, and an `fwidth` fade.
   - Brushes: smooth 3-octave FBM streaks, elongated along the slide, with 3–6 gouge lines in the core.
   - In the shader, break up the edges: m' = m + (fbm(uv_m·80) − 0.5)·0.18.
     Then draw each layer edge with `smoothstep(t − fwidth(m'), t + fwidth(m'), m')`.
   - Set `mask_enabled = 1` on all painted panels once the car has any splat.
   - Splat nose hits into both FRONT and ROOF.

   Verify with 2 m close-ups of the Roadster door and the police door (side 16, front 22, rear 14 m/s; dents and mask on):
   - a whitish scuff band with parallel scratches along the slide
   - primer `#8C8F93` ±8 % with a dark rim `#2B2C30`
   - a bare core: a visible weave on the Roadster, bright steel `#9EA3A8` on the police
   - no straight axis-aligned edges, and no visible texel steps

10. **Debris loses the car's colour and does not fly.**
    - `_debris_spec()` copies `mesh_node.get("instance_shader_parameters")`, which returns null. Probe B: the
      red rival's bumper debris has `base_color_override = <null>`, so it flies off white (#ECEDEF).
    - Debris starts at `car.linear_velocity`, which is the POST-impact velocity, so the parts drop at the car.
      In the crash demo at +0.2 s and +0.5 s (`r2c_debris_crop.jpg`) no part is in the air.

    Do:
    - Copy each instance uniform with `source.get_instance_shader_parameter(name)`: `base_color_override` and `panel_offset_y`.
    - Spawn at the pre-impact velocity × 0.8 plus a kick of (±3, 2..6, ±3), per dossier §7.6. Today the upward kick tops out at `KICK.y + 3.0` = 5.

    Verify:
    - In test_parts_real, a RivalVisual car's debris has `base_color_override` == `#D81E2C`.
    - In the crash frames at +0.2 s and +0.5 s, at least one part is in the air ≥ 1 m from the cars.

11. **The EV heavy state, the smoke and the fireball still don't read (r1 #14, #15).**
    In `r2h_sheet.jpg` (5 m, 4 frames 0.3 s apart):
    - An arc shows in only **1 of 4** frames (r1 asked for ≥ 3), and it is thin, with no bloom.
    - The white smoke is barely visible.
    - At the police wreck (+0.1 s), only the flash light shows. There is no fireball.

    Causes:
    - The ribbon's side vector is dir × UP, so the ribbons are horizontal and edge-on to the chase cam.
    - Unshaded materials ignore emission, so the arcs and the fireball stay LDR (≤ 1.0), below the glow threshold of 1.1.
    - The smoke `soft_quad` uses BILLBOARD_ENABLED without keep_scale, which discards the scale curve (0.4→2.2) and the spin.
      Every puff is a constant 0.7 m quad.
    - There is no proximity fade.
    - `_engine_bay()` adds 0.70·size.y to the box CENTRE. That puts the point at 1.74 m on the police (box top 1.445 m)
      and 1.18 m on the Roadster (frunk ≈ 0.73 m), so the smoke, flash and fireball start in mid-air.

    Do:
    - Make the ribbons face the camera (side = dir × to_camera).
    - Make the core HDR (colour × 8) and the halo × 2, using vertex colour or a small unshaded shader.
    - Shorten the burst gap to 0.15–0.5 s.
    - Smoke: BILLBOARD_PARTICLES, `proximity_fade` 0.4 m, and a faint emission so it reads at night.
    - Engine bay = (0, min.y + 0.70·size.y, min.z + 0.15·size.z), snapped to the hood surface.
    - Fireball: a 4×4 flipbook or a noise-broken texture, HDR × 6, 1.5–2.5 m wide, 0.4 s long.

    Verify with a capture like `tmp/review/damage/r2_heavy.gd`:
    - an arc in ≥ 3 of 4 frames at 5 m
    - the smoke starts at the hood and visibly grows
    - the fireball is visible at +0.1 s

12. **The tests and the evidence must prove the r1 numbers.** Today:
    - test_budget measures nothing (item 4).
    - test_respawn only asserts |v| > 5.
    - test_parts uses a stub car with ONE wheel, so a 4-wheel loss can't be seen.
    - test_parts_real has no police car.
    - The vertical takedown is tested in one report order only.
    - test_paint_sync only compares uniform lists. Embed the source's hash in the generated header and
      compare it in the test, so a code change in `car_paint.gdshader` fails the test.
    - The acceptance lineup passes `car.global_position` (the car's floor centre) as the contact point
      (demo/dent_lineup.gd:132), so it never tests a panel hit.
    - `captures/damage/crash_t*.jpg` were shot at 05:50, before the 09:00 code.

    Do:
    - Add the asserts given in items 1–10.
    - Use panel contact points and instance `res://world/env/environment.tscn`.
    - Re-shoot every capture after the fixes, including the crash at impact +0, +0.2, +0.5 and +1.0 s (the brief's list).

## SHOULD-FIX
- **Hanging bumper (r1 #18).** Pivot on the lower corner away from the hit and turn 25° about the car's forward
  axis plus 5° of yaw. Today it pitches about X at the rear-bottom edge centre, and the angle shrinks ×0.6 up to
  4 times, so it can end at 3°.
- **damage_fx.gd is exactly 400 lines.** Split it before the fixes: damage_lamp.gd, bumper_hang.gd, tier_emitters.gd.
- **Dead code.**
  - `Rules.classify()` and `Kind` (used only by tests)
  - `Parts.zone_of()`, `CarDamage.health_ratio()`, `EvArcs.active()`
  - `wreck_time` and `last_contact` (written, never read)
  - `damage_fx.ARC_COLOR`
  - the blank lines at dent_painter.gd:354–357
- **Structs as dictionaries.** Part templates, `part_nodes` entries, the debris spec, `body_box()`, `_pairs` and
  `_pending_respawn` should become inner classes. `_prev_velocity` should be `Dictionary[int, Vector3]`.
- **Magic numbers in logic.**
  - mask_atlas.gd:96: 0.2, 0.025, 0.62, 0.35, 0.65
  - impact_handler.gd:82–89: 4.0, 1.2, 1.5
  - `KICK.y + 3.0`
  - wreck_flow.gd:127: 0.25
  - damage_fx.gd:277: 0.70, 0.30
  - shader literals: 0.12, 0.25, 0.16, 45.0, 25.0
- **`_on_car_gone()` erases pairs by substring** (`str(id) in key`), so id 34 matches "12|345". Compare both ids.
- **Psyche-out credits a car the player touched 2–10 s ago.** Dossier §3.5 says "no contact happened".
- **Scratch files went to `/tmp` again** (`/tmp/dbg*.py`, `/tmp/dbg_run*.txt`, `/tmp/damage_tests*.log`). Use `tmp/damage/`.

## Verified OK
- `check --only=res://damage/`: 33 files, 0 failed, 0 engine errors, 0 warnings. All 9 tests exit 0
  (item 12 lists what they don't prove).
- r1 #1: the respawn clears `is_wrecked`. Probe C: wrecked=false, hp=60. test_respawn: a 20 m/s hit costs 16.838 HP.
- r1 #2: the ghost uses collision exceptions, and the test drives a car through it.
- r1 #3: only paint surfaces are swapped. The sills and canopy visor stay black.
- r1 #4: the body colour survives a hit: the red rival stays #D81E2C and the taxi stays teal (`r2l_npc_sheet.jpg`).
  The generator + sync test approach is accepted.
- r1 #11 (in part): the detached wheels come back on respawn (probe C: all 4 visible), and the hung bumper is restored.
- r1 #12: the AI wreck freezes, sets layer/mask to 0, sinks 0.4 m and fades over 1.5 s (code).
- r1 #17: the vertical rule is symmetric (|n.y|, and the lower car is the victim).
- r1 #19: no leaks. test_pool: states, velocities and contacts are empty after 200 cars.
- r1 #20: scrape 2 HP/s, traffic glance 1 HP, and contact counted at |v_rel| ≥ 3 m/s (code).
- Dossier numbers: 3.75 / 33.75 / 60 / 79.35 HP, k_mass 1.1556, front ram ×0.5, tier bounds, points 50/75/150.
  Labels: 撞毁！ / 碾压！VERTICAL TAKEDOWN! / 心理战！PSYCHE OUT! with 连击 ×N / 狂暴 RAMPAGE.
- Lead note D-INT1: a mesh without UVs takes a dent and the mask without errors (test_parts).
- Ownership: every Write/Edit in jobs/damage/log.jsonl targets `game/damage/**` or `status/damage.md`.
- The director's idle tick costs 0.011–0.022 ms. The crash sparks (fx unit) and the wreck flash light (#FFB04A on the road) read well.

## Evidence (run by the reviewer on 2026-10-20 from ~/m/skyrush; scratch in tmp/review/damage/)
- `tools/godot.sh check --only=res://damage/` → `CHECK 33 files, 0 failed, 0 engine errors, 0 warnings`.
- `tools/godot.sh test res://damage/tests/<9 tests>` → all PASS. test_budget prints
  `median cost of a hit is 0.000 ms … (mean 0.000 ms, p90 0.000 ms, worst 0.000 ms over 20 hits)`, and
  `grep hit_usec game/damage` finds only the declaration and the read.
- probe_r2a.gd (real Roadster):
  - `tier=0 hp=100 lamp=Lamp_FL energy changes in 240 frames=11`
  - `tier 0 arcs: visible core frames=58/240 max arc light energy=3.00`
  - `hit cost usec side/front/rear = 621 / 201 / 13912  director.hit_usec=0`
  - `right-region mask sum before/after a LEFT rear hit: 213.4 -> 268.8`
  - `soften() (respawn) cost usec=11302`
- probe_r2b.gd:
  - `police tier 0: arc core visible frames=30/240`
  - `rival debris mesh … base_color_override=<null>` (×3)
  - `Door_L centre x -0.783 -> -0.526 after two 20 m/s left hits (rot y 30.0 deg)`
  - `wheel debris cylinder r=0.34 h=0.69`
- probe_r2c.gd:
  - `head-on 30+30: … pre_crash_speed=60.0 detached=[Skirt_L, Wheel_RR, Bumper_F, Hood, Wheel_FL, Wheel_FR, Wheel_RL]`
  - `respawn |v|=42.0 m/s … wrecked=false hp=60 door rot y=15.0`
  - `ghost alpha samples (~140 ms apart): 0.50 ×14`
- probe_r2d.gd: `atlas car_min=(-0.975, 0.22, -2.19) car_size=(1.95, 0.8, 4.38)`, and the Body AABB is y 0.12..1.145.
- probe_r2f.gd (the shader's atlas lookup replayed on the CPU image): `Door_R … max mask=0.50 at (0.93, 0.50, 0.09)`,
  and `Body regions L/R/F/Rr/Roof=[633, 654, 107, 69, 840]`. It ran while the vehicle unit was mid-edit:
  car_dynamics.gd printed SCRIPT ERRORs, which are not from this unit.
- probe_build.gd: `build roadster usec=58021 / 11893 / 4129`, `build taxi usec=4992 / 4739 / 6282`.
- probe_lampenergy.gd: designed `taxi/Lamp_F energy=6.00`, `police_patrol/Lamp_F energy=6.00`, `Roadster/Lamp_FL 1.00`.
- probe_r2e.gd, full game `-- --skip-menu`:
  - `vehicles=115 full-hp=97 damage rigs=115 rig lights=230`
  - `dent materials installed=858 (with mask texture 858)`
  - `over 120 frames, arc-visible car-frames=1526, live rig light car-frames=1574`
  - `Parameter "material" is null` ×167. With `--stub=damage`: 0, and 0 rigs.
  - probe_err.gd (every npc glb, build + lamp + hit in isolation) gives 0 errors, so the cause is the interaction in the game.
- Captures in `captures/review/damage/` (all `CAPTURE errors=0` except r2c):
  - `r2l_roadster_sheet.jpg` / `r2l_6m_crop.jpg`: before/after at 6 m and 2 m. Black rectangle on the door, no dent shape.
  - `r2y_layers_sheet.jpg`: all layers / dents only / mask only / police door at 2 m. `r2y_mask_crop.jpg`: the mask is not visible.
  - `r2ab_sheet.jpg`: crumple 0 / dent_scale 0.15 / default. This shows the black patch is trim showing through.
  - `r2l_npc_sheet.jpg`: police at 6 m, and the red rival and teal taxi keep their colours.
  - `r2h_sheet.jpg`: EV heavy (an arc in 1 of 4 frames) and the police wreck flash (no fireball).
  - `r2c_crash_sheet.jpg` / `r2c_debris_crop.jpg`: the current crash demo, with no part in the air.
    Its 2 errors (fx_arch_glow.gd:57, get_global_transform) disappear with `--nofx`, so they come from the fx unit.
  - `r2_worker_sheet.jpg`: your dent_t0_5 / dent_t2_8 / close_t0_5 / close_t3_4.
- To re-shoot my lineup:
  `tools/godot.sh shot --scene=/Users/minimax/m/skyrush/tmp/review/damage/r2_lineup.tscn --outdir=$HOME/m/skyrush/captures/damage --out=dent --warm=1 --times=1.0,2.7,3.2,3.7,4.2,4.7,5.3`
- Note: at 09:49 I re-ran `game/damage/tools/make_dent_paint.py` by mistake. The output is identical: your last change to
  dent_paint.gdshader was that same generator run (log line 9062), and car_paint.gdshader has not changed since 06:43.
- No reference photos exist for this unit (ref/gameplay/dl/b08_damage and b13 are text/PDF). The targets come from
  dossier §7.1–7.8, ART.md §3/§5 and the carbon row of ref/art/DOSSIER.md.
