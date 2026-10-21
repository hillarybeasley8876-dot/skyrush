# damage review round 1 — VERDICT: FAIL

Reviewer: lead/art director. Tests pass, but they only use box-mesh stub cars. On the real
Roadster and the npc glbs, the core flows break. The visuals also miss the brief and the user's
demand ("贴图纹理什么都要细化": refine every texture and material).
Every number below was measured by me (see Evidence). Fix MUST-FIX items in order. 1–4 are blockers.

## Scores (0-10)
- function: **3**. The formula, takedown credit and wreck events work. Respawn, ghost, parts, wheels, vertical takedown and the hit budget are broken.
- visual/feel: **2**. No dent reads at 6 m. A hit turns the hero car's black trim white, rivals and taxis lose their paint, the smoke is untextured blobs, there are no EV arcs, and wrecks lose all four wheels.
- code: **5**. Clean module split and files ≤ 400 lines. But the shader copy is stale, two members are untyped, structs are passed as dictionaries, numbers sit inline, constants are dead and state leaks.

## MUST-FIX

1. **The player stays `is_wrecked = true` forever after the first respawn.** `wreck_flow._respawn()`
   sets `health` but never clears `is_wrecked`, so `apply_damage()` returns early.
   Probe on the real Roadster: `after respawn: is_wrecked=true hp=60.0`, then a 25 m/s hit: `hp 60.0 -> 60.0`.
   Result: the player can't be damaged or wrecked again, and `charge_station.gd:30` refuses to charge them.
   Do: call `car.repair()`, then set `car.health = RESPAWN_HP` and `telemetry.health_norm`, then reset the
   damage state (item 11). Verify: in `test_respawn.gd` assert `not player.is_wrecked`. Then hit a wall
   at 20 m/s and assert the HP drops by 16.9 ± 0.5 (33.75 × 0.5 front-ram).

2. **The 2 s ghost doesn't ghost.** Jolt reports a contact when *either* body's mask has the
   other's layer. Clearing bit 2 on the player's mask isn't enough. Probe: a body with layer 2 / mask 1
   was rammed by a layer-2 / mask-7 car at 8 m/s, and the rammer stopped against it (`rammer at z=4.38`).
   Do: for the ghost, call `car.add_collision_exception_with(c)` for every node in group `vehicles`.
   Remove the exceptions after 2.0 s. Keep world collisions.
   Verify: a test car driven at 10 m/s passes through the ghost player in the first 2 s, then collides after the ghost ends.

3. **The paint swap repaints surfaces that aren't paint.** `dent_painter.gd:47-48` overrides *every*
   surface of `Body`. The Roadster Body has 3 surfaces: `[car_paint, M_BlackTrim, M_InnerDark]`.
   After one hit, all three become `dent_paint.gdshader`. The black sills, the black canopy visor
   (#111113) and the dark door cavity turn Ano White. See `captures/review/damage/crop_roadster_s.jpg`
   (left: before, right: after). The npc `NPC_trim` surface turns into paint too.
   This breaks ART.md §3 and Pillar 1 ("the car is the star").
   Do: override only the surface indices whose active material passes `_is_car_paint()`.
   Verify: in a test on `res://vehicle/player_car.tscn`, after a hit, surfaces 1 and 2 still return
   `M_BlackTrim` and `M_InnerDark`.

4. **`dent_paint.gdshader` is a stale copy, so every hit car changes look and loses its colour.** The
   current `res://shaders/car_paint.gdshader` has:
   - a plain `base_color` plus `instance uniform vec4 base_color_override` and `instance uniform float panel_offset_y`
   - `albedo_texture` and `roughness_texture`
   - orange peel and flake sampled in OBJECT space (`peel_scale` 6/m, `flake_scale` 60/m). The Roadster's UV0 is in mm,
     so your `UV*45` / `UV*420` averages to flat.
   - `cull_disabled` and wetness-aware grime

   Your copy has an instance `base_color` that defaults to #ECEDEF, and it skips copying `base_color`.
   Evidence in `captures/review/damage/r1_t3_05.jpg`:
   - A rival painted **#D81E2C** through `RivalVisual` (`base_color_override`) ends up with a white body and red doors.
   - The teal taxi **#1E8C8A** turns white.

   Do the structural fix: write a Request asking the shaders unit to move the paint into
   `res://shaders/car_paint.gdshaderinc`, then `#include` it in `dent_paint.gdshader`. Until then:
   - Copy the CURRENT shader 1:1 and copy ALL uniform values, including `base_color`.
   - Add `tests/test_paint_sync.gd`. It fails if the dent shader's uniform names and types aren't a superset of car_paint's.

   Verify: shoot the taxi and the rival before and after a hit (as in `tmp/review/review_crash.gd`).
   The body colour must not change.

5. **No dent reads at 6 m. This fails the acceptance criterion.** In `dent_t2_8.jpg` / `dent_t3_4.jpg` vs
   `dent_t0_5.jpg` / `dent_t1_0.jpg`, no dent shows on either car after 16, 22 and 14 m/s hits. The causes:
   (a) Dents only go on `Body`. `Bumper_F/R`, `Hood`, `Door_*`, `Skirt_*` and `Wing` are separate meshes that
   cover the Body exactly where hits land, so the dent is hidden behind them.
   (b) `_contact_local()` ignores the reported `point` and always projects to the centre of a box face.
   Dents stack at the front-centre and door-centre.
   (c) The only shading is a per-vertex normal tilt toward −dir. That flattens the bowl. The meshes are
   also coarse: the Roadster paint has p90 edge 0.18 m, the npc 0.36 m, and §7.5 asks for ≤ 0.12 m.

   Do:
   - Install the damage material on EVERY painted mesh of the car. Give each mesh its own local dents
     (`mesh.global_transform.affine_inverse() * world_point`, dir via `basis.inverse()`).
   - Use the reported `point`.
   - Shade per pixel: add an `obj_pos` varying, and in `fragment()` bend the normal by the analytic gradient of
     `depth·f²`. Add a crumple term: 3D value noise at 14/m × 0.2·depth·f, applied to both the
     vertex offset and the pixel normal.
   - Restore the dossier depth `clamp(v_n·0.012, 0.03, 0.25)` × 1.5. Scale it by
     `clamp(dot(NORMAL, -dir)·2, 0, 1)` so side faces don't fold. This replaces your 0.11 m cap (judgement call 2 is rejected).
   - Write a Request for ≤ 0.12 m panel edges from `car_model` / `npc_cars`.

   Verify: run a before/after lineup at 6 m like `tmp/review/review_dent.gd`. The dent must read as a dark
   crease at least 30 px wide at 1600×900 on both the Roadster and the police car.

6. **The paint-scrape mask does nothing on the hero car, and the lookup is slow.**
   - The Roadster's UV0 spans (−2.2, −3789)…(5467, 3.3), so `_splat()` writes outside 0..511.
     The shader samples with `repeat_disable`, so out-of-range UVs read the clamped edge texels.
   - Probe: `mask_coverage=0.000000` after a 27 m/s hit. A later hit painted 0.2 % of the mask at an arbitrary UV.
   - On the police car (UV0 −1.9..2.9) most splats are clipped.
   - `_uv_at()` scans all 31,833 vertices in GDScript on every hit.

   Do: replace the UV lookup with a **car-space projection atlas**.
   - Split the 512² mask into 5 regions: left side, right side, front, rear, roof (~100 px/m).
   - Pick the region in the shader from the dominant object-space normal (the `puv` logic of car_paint).
   - Splat straight from the car-local hit point, with no vertex search.
   - Make the splat a streak along the slide direction, not a disc:
     - length `clamp(0.15 + 0.03·|v_t|, 0.15, 1.2)` m
     - width 0.5 × the dent radius
     - noise-broken edge, intensity scaled by v_n

   Verify: on the real Roadster, a 23 m/s front hit gives coverage > 0.002, all inside the front region.

7. **The damage material is flat colour.** ART.md §5 says "no flat untextured surface", and the user wants every texture refined.
   Build the layers by mask value `m`:
   - **0.05–0.25, clear-coat scuff:** roughness +0.35, clearcoat ×(1−3m), directional micro-scratch lines
     (~300 lines/m) along the slide direction. Store the direction in the mask G channel, or derive it from the region.
   - **0.25–0.55, chipped paint:** primer `#8C8F93`, mottled ±8 % in value with noise at 25/m, roughness 0.7.
     Where m crosses 0.25, draw a dark chip rim `#2B2C30` 2–4 mm wide with a small normal step.
   - **0.55–1, bare substrate:**
     - Roadster: carbon 2×2 twill, 8 mm pitch, `#15171B`, anisotropic highlight, roughness 0.3.
     - npc cars: bare steel `#9EA3A8`, metallic 1.0, roughness 0.35, with scratch streaks.
   - **Soot:** darken toward `#1A1A1C`, α ≤ 0.4, around each dent centre.

   Verify: close-ups at 2 m and 6 m of a Roadster and a police car after 3 hits. All three layers must be distinguishable.

8. **Detachable parts: wrong part matching, wrong visuals, wrong physics.**
   a) Prefix matching tears off interior and child meshes as separate debris (the probe printed every case):
      - A Roadster rear hit at 18 m/s spawns 6 bodies: `Wing`, `Wing_EndPlate_L/R`, `Wing_Slat` and `Wing_Strut_L/R`.
      - The `*_Inner` meshes fly off on their own.
      - The interior `DoorCard_L/R` fly off. `DoorCard_L` went on a RIGHT-side hit.
      - A 16 m/s right-side hit on the police car took ALL FOUR doors. The npc door origins are the car origin,
        and `same_side()` returns true when |x| < 0.05.

      Do:
      - Match an exact name whitelist: CONTRACTS §6 names plus `Door_FL/FR/RL/RR` and `Mirror_L/R`, ignoring any `.NNN` suffix.
      - Duplicate the part's subtree and its `<Part>_Inner` sibling into ONE debris body.
      - Decide the side from the mesh AABB centre and drop the |x| < 0.05 shortcut.
      - Doors never come off below a wreck. At a side hit ≥ 18 m/s, spring the Roadster door 15° open on its hinge.
        npc doors come off only on a wreck with impact ≥ 0.7.
   b) `debris_pool.spawn()` sets `material_override` to surface 0's material:
      - The Roadster wheel has 4 surfaces, and all render as `M_WheelWhite`.
      - The npc wheel is tyre + rim, and all of it renders as tyre.
      - Roadster `Bumper_F` is paint + `M_BlackTrim`, and all of it renders as paint.
      - The instance paint isn't copied, so a red rival's bumper flies off white.

      Do: copy each surface with `set_surface_override_material(i, src.get_active_material(i))`, and copy
      `base_color_override`, `base_color` and `panel_offset_y` from the source mesh.
   c) The debris box is centred on the node origin. npc part origins are the car origin, so
      `npc debris mesh centre offset from its box = 2.48 m` (police `Bumper_R`).
      Do: set the box centre and size from the mesh AABB (min 0.03 m). npc `Bumper_F/R` are zero-thickness
      planes (AABB z = 0.00001). Give their debris material `cull_disabled`, and write a Request for real thickness to npc_cars.

   Verify: add `tests/test_parts_real.gd` with the real Roadster and police car. Check the body count per hit,
   that no far-side part comes off, that the box-to-mesh offset is ≤ 0.05 m, and that the materials per surface match.

9. **Every wreck takes all four wheels off and ignores the §7.6 `impact ≥ 0.7` rule.** `car.wreck(null)`, with no
   impact at all, detached `Wheel_FL/FR/RL/RR`, and test_parts itself proves it. The wrecked police car sits with four
   empty arches (`r1_t1_95.jpg`, background of `heavy_t3_0.jpg`).
   Do: store the impact ratio and contact zone of the hit that wrecked the car. If impact ≥ 0.7, detach only
   the ONE wheel nearest the contact. Tilt the visual so the bare hub corner rests on the road (drop ≈ 0.34 m at that corner).
   Verify: wrecking by HP through scrapes leaves 4 wheels; a 32 m/s front-left head-on removes only `Wheel_FL`.

10. **Respawn speed and direction are wrong.**
   - `pre_crash_speed = max(v_rel.length())` is a lifetime maximum of the RELATIVE speed, and it is never reset.
     A 30 + 30 m/s head-on gives a respawn speed of 42 m/s (151 km/h).
   - `_respawn()` takes "30 m back" from the wreck's current facing, which is random after a tumble.
   - It also pushes the car along that facing, not along the road transform, so a spun car is launched sideways.

   Do:
   - At the wrecking hit, store the car's OWN pre-impact speed `_pre_velocity(car).length()` and its horizontal heading.
   - Respawn at `nearest_road_transform(wreck_pos - heading·30)`. Flip it 180° if it faces against the heading.
   - Set the velocity to `-xform.basis.z × max(0.7·speed, 16.67)`.
   - Reset the stored speed after the respawn.

   Verify: wreck the player at 25 m/s, spin the car 120°, respawn. The velocity must have dot > 0.99 with the road forward and |v| = 17.5 ± 0.5.

11. **Respawn state and the ghost look.**
   The 10 Hz strobe toggles `visible` on every mesh and then forces all of them visible.
   - Detached parts come back while `state.detached` still lists them, so they can never come off again
     (probe: `Wheel_FL visible=true, still marked detached=true`).
   - It also un-hides meshes that other units hide.

   Do:
   - Ghost: drive `GeometryInstance3D.transparency` at 0.5 ± 0.2, 6 Hz, on the visual meshes, and save/restore their values.
     Godot 4 per-instance transparency works with ANY material, so the "no alpha uniform" limit in your status doesn't apply.
     Use the same for the debris fade (0→1 over 0.5 s instead of shrinking).
   - On respawn, restore the car explicitly: show the detached meshes and clear `detached`, zone damage and the hung bumper.
     Set the tier fx to match HP 60, keep at most 2 dents at half depth, and halve the mask.

12. **AI wreck sink leaves an invisible obstacle.** It tweens `global_position` of a live RigidBody3D into the road,
   scales `Visual` to 0.01, then sets `visible = false` with collisions still on.
   Do: set `freeze = true` and `collision_layer = collision_mask = 0` first. Then fade transparency 0→1 over 1.5 s
   while sinking 0.4 m.
   Verify: 8 s after an AI wreck, the car has layer 0 and transparency 1.

13. **The head lamp flickers on every car that was ever touched, at any tier.** Probe: 3 flips per second at tier 0
   with HP 60.1. It also hides the whole `Lamp_FL` mesh, which leaves a hole in the front fascia.
   Do: flicker only at LIGHT and HEAVY. Duplicate the lamp material once and dim its emission
   (energy multiplier 1.0 ↔ 0.12) with irregular dropouts at 3 Hz (on-times 0.05–0.25 s). Dim the headlight light with it. Restore on repair.
   Verify: CLEAN gives 0 changes in 2 s; LIGHT gives 4–8 dropouts in 2 s.

14. **The player's EV heavy tier has no blue arcs** (`damage_fx.gd` sets `_arc_light.light_energy = 0`, and there is
   no arc geometry), and the white smoke barely shows (`captures/review/damage/heavy_pair_s.jpg`). Do:
   - 2–4 jagged polylines (8 segments, midpoint jitter ±0.06 m) between random points on the front arches and the frunk seam.
   - Regenerate every 0.05 s during bursts of 0.12–0.25 s, with a burst every 0.4–1.4 s.
   - Core 0.012 m `#EAF6FF`, HDR ×8, additive. Halo 0.08 m `#3D7BFF` at α 0.5.
   - OmniLight `#5AB8FF`, energy 0→3 during a burst, range 4 m.

   `res://fx/fx_arcs.gd` shows the technique. Build it in `game/damage/`, or write a Request for an Events hook so the fx unit draws tier arcs.
   Verify: in 4 frames 0.3 s apart at 5 m, at least 3 show an arc.

15. **Smoke and sparks are untextured blobs.** The particle is a radial-gradient quad that never changes size and has no alpha
   ramp, so it reads as polka dots (worker `crash_t1_9.jpg`).
   Smoke:
   - Texture: a static cached 128² noise texture (FastNoiseLite simplex FBM, 5 octaves, freq 0.035,
     × radial `(1−d²)^1.5`) or a 4×4 flipbook.
   - `color_ramp`: α 0 → 0.55 (at 15 %) → 0.3 (60 %) → 0.
   - `scale_curve`: 0.4 → 1.0 → 2.2.
   - Turbulence on (strength 1.2, scale 2.5), random angle with ±30°/s spin, `inherit_velocity_ratio` 0.3,
     proximity fade 0.4 m.
   - Lifetime 2.2 s (light) / 2.8 s (heavy). Keep the dossier counts (24/40) and colours
     (#8A8F96 α0.5, #2B2D31 α0.7, EV #DCE8FF α0.6). Light it so it reads at night.

   Sparks:
   - Spawn your own only when `Modules.loaded.get(&"fx") != "real"`. Otherwise the fx unit already
     sparks every contact, and you double them.
   - Make them unshaded additive HDR streaks: `BILLBOARD_PARTICLES` + align_y, 0.015 × 0.18 m,
     colour (1.0, 0.75, 0.35) × 6, gravity, lifetime 0.25–0.5 s.

   Build every texture and material once in a static cache. Today each car rebuilds a 64² texture with 4,096 `set_pixel` calls.

16. **Each hit costs about 10× the 0.3 ms budget.** Real-car probes:
   - Roadster: first hit **8.4 ms**, then **2.7 ms** per hit.
   - Police: first hit **8.6 ms**, then **1.8–2.4 ms** per hit.

   `test_pool` only times the idle `_physics_process` on box stubs (0.012 ms), so it hides this.
   Do:
   - Item 6 removes the vertex search.
   - Cache `part_nodes()` per car when its state is created.
   - Use static texture and material caches.
   - Build each car's state when it joins `vehicles` (≤ 1 car per frame) instead of on the first crash.

   Verify: new `tests/test_budget.gd` on the real `player_car.tscn` and `police_patrol.glb`: 20 hits,
   mean ≤ 0.3 ms, max ≤ 1.0 ms including the first hit.

17. **The vertical takedown depends on which car reports first.** When the car below reports first (normal pointing down),
   the landing becomes an ordinary 6 m/s hit, and the player's report is then dropped as a duplicate.
   Probe: `victim wrecked=false hp=99.9`.
   Do: make `is_vertical` symmetric (|n.y| > 0.7 and closing speed ≥ 5 m/s). The lower `global_position.y` is the car below.
   Give the vertical credit only when the player is the car on top.
   Verify: a test that sends the two reports in both orders.

18. **The hanging bumper drops into the road.** The pivot is `origin + (0, 0.10, 0.20)`, and npc bumper origins are the
   car origin, so the police bumper centre drops **1.00 m** (probe).
   Do: pivot on a lower corner of the bumper's mesh AABB (the corner away from the hit). Rotate 25° about the
   car's forward axis plus 5° of yaw, and clamp so the lowest corner stays ≥ 0.02 m above the road.
   Verify: the drop is ≤ 0.6 m.

19. **The damage state leaks memory.** `_states`, `_prev_velocity` and `_pairs` are never erased.
   Each hit car keeps a 512² mask, a mesh-array copy (~0.6 MB for the Roadster) and a reference to a freed vehicle.
   Do: on each car's `tree_exiting`, erase its entries and free its painter and fx. Prune `_pairs` older than 1 s on each refresh.
   Verify: spawn, hit and free 200 stub cars, then assert all three dictionaries are empty.

20. **The §7.2 classification never changes behaviour.** `classify()`, `GRIND_HP_PER_S` and `GRAZE_HP` are dead code,
   and a wall grind costs 0 HP because v_n < 5. Do:
   - **Scrape** (impact < 0.35 against something static): 2 HP/s × the time since the pair's last report (≤ 0.15 s),
     a streak in the mask, and sparks along the tangent.
   - **Traffic glance** (impact < 0.3 against a traffic car): the player takes 1 HP and gets no dent.
   - **Takedown contact**: §3.5 counts "relative speed ≥ 3 m/s", which is `v_rel.length()`, not v_n.
     Otherwise grinding and pinning a car never count as contact.

## SHOULD-FIX
- Banner labels per kind (§3.5): "碾压！VERTICAL TAKEDOWN!", "心理战！PSYCHE OUT!", and the streak sub-line
  "连击 ×N" / "狂暴 RAMPAGE" (×5). Put them in the `Events.stunt` label so the HUD needs no contract change.
- Typing: `car_damage.gd:29/31`. Type `painter` and `fx` with the preloaded script types, use `Array[DentPainter]`,
  and replace the contact `Dictionary` with a small `Contact` inner class.
- Name the inline numbers as constants (in `damage_rules.gd` where they are rules):
  - dent radius/depth coefficients (`dent_painter.gd:57-59`)
  - zone limits 0.9/0.55/0.45 (`part_catalog.gd:49-55`)
  - spark speeds (`spark_burst.gd:35-36`) and spray constants (`damage_director.gd:214-215`)
  - hang pivot (`damage_fx.gd:139`)
- Derive `ENGINE_BAY` from the body AABB (front 30 %, top 70 %); a bus smokes from its middle today.
  Add a 0.4 s fireball billboard to the wreck flash.
- When a debris body goes back to the pool, freeze it and park it off-map. Today 32 invisible bodies lie at the world origin.
  Cache one shape per part instead of `BoxShape3D.new()` on every spawn.
- Process: keep scratch in `tmp/damage/`, never `/tmp` (you used `/tmp/dbg.py` and `/tmp/dbg_test.gd`).
  The fx unit now checks clean (`CHECK 39 files, 0 failed`), so shoot every capture WITH fx; remove `--nofx` from the status commands.

## Verified OK
- `check --only=res://damage/`: 22 files, 0 failed, 0 errors. All 6 tests pass.
- The §7.3 numbers (3.75/33.75/60/79.35 HP), k_mass (1.1556 for the SUV), and the ×0.5 front ram with head-on symmetry.
  Judgement call 1 is accepted.
- Measuring on pre-step velocities: a correct and important finding, pinned by `test_contact_normal`. Pair dedupe works.
- Takedown credit: 2.0 s window, 10 s streak, 50 + 25·(n−1) points, `Events.takedown` and `Events.stunt` emitted.
- Player wreck events: `camera_focus(car, 2.2)`, `slowmo_request(0.35, 2.2, car)`, `toast("撞车 WRECKED", &"danger")`.
- Debris pool: 32 bodies, layer 5, world-only mask, 8 s life + 0.5 s fade, oldest recycled.
- Judgement call 3 is accepted: `fx_car_rig.set_wrecked()` spawns wreck smoke + fire (ICE) / arcs (EV).
- Lead note **D-INT1 is satisfied**: a mesh without UVs raises no error, and the test covers it.
- Ownership: every write is inside `game/damage/**` or `status/damage.md`. Tests extend Node. Files are ≤ 400 lines (max 364).
- Your requests are valid: the `vehicle_collided` impulse is ~0 because `impact.gd` computes it after the hit, the N₂ reward goes to the vehicle unit, and the HUD needs the takedown kind.

## Evidence (all run by the reviewer on 2026-10-20 from ~/m/skyrush)
- `tools/godot.sh check --only=res://damage/` → `CHECK 22 files, 0 failed, 0 engine errors, 0 warnings`.
  `check --only=res://fx/` → `CHECK 39 files, 0 failed`, so fx can run in captures.
- `tools/godot.sh test res://damage/tests/test_{contact_normal,damage_formula,takedown,parts,pool,respawn}.gd`
  → all `PASS` (pool: `damage logic ... (0.012 ms)` is idle-only).
- `tools/godot.sh test /Users/minimax/m/skyrush/tmp/review/probe_assets.gd`, real glbs:
  - Roadster `Body`: 3 surfaces `[car_paint, M_BlackTrim, M_InnerDark]`, 31,833 verts,
    `uv0 min=(-2.18, -3789.1) max=(5466.9, 3.29)`, edges p90 0.182 m.
  - police/taxi/sedan `Body`: `[car_paint, NPC_trim]`, edges p90 0.360 m.
  - npc `Bumper_F` origin (0,0,0), AABB centre (0, 0.515, −2.42), thickness 0.00001.
  - Roadster `Wheel_*` have 4 surfaces; `Wing` has 5 child meshes; `DoorCard_L/R` origin (0,0,0).
- `tools/godot.sh test .../tmp/review/probe_roadster.gd` (real Roadster):
  - `body materials after: [dent_paint ×3]`
  - `first 27 m/s front hit: cost usec=8385`, `second 12 m/s hit: cost usec=2717`
  - `dents=1 mask_coverage=0.000000`
  - `lamp flips in 120 frames at tier 0 (hp 60.1): 3`
  - `plain wreck (no impact): ... Wheel_FL, Wheel_FR, Wheel_RL, Wheel_RR`
  - `after respawn: is_wrecked=true hp=60.0`, `hit after respawn: hp 60.0 -> 60.0`
  - `after ghost: Wheel_FL visible=true, still marked detached=true`
- `.../tmp/review/probe_rules.gd`:
  - `vertical, victim reports first: victim wrecked=false hp=99.9`
  - `ghost (mask=1) hit by a car (mask=7): ... rammer at z=4.38` (it was blocked)
- `.../tmp/review/probe_npc.gd` (police glb):
  - `rear hit cost usec=8588 / 1835 / 2374`
  - `hanging bumper centre moved (0.0, -0.996, -0.05) (1.00 m)`
  - `npc debris mesh centre offset from its box = 2.48 m`
- Lineup (`tmp/review/review_dent.gd`, 16/22/14 m/s, + 18 m/s rear with `--heavy`):
  - `PlayerCar ... dents=3 mask=0.00000 detached=[Door_Inner_R, Door_R, DoorCard_L, DoorCard_R, Skirt_Inner_R, Skirt_R, Bumper_F, Bumper_F_Inner]`
  - `police ... detached=[Door_FL, Door_FR, Door_RL, Door_RR, Bumper_F]`
  - with `--heavy`, the Roadster also lost `Wing, Wing_EndPlate_L/R, Wing_Slat, Wing_Strut_L/R`.
- Captures, all `CAPTURE errors=0`, in `captures/review/damage/`:
  - `r1_t*.jpg` (+ `sheetA_s.jpg`, `sheetB_s.jpg`): the worker's demo WITH fx, plus a taxi and a red rival hit at 1.3 s.
  - `dent_t0_5|t1_0|t2_8|t3_4.jpg` (`sheetC_s.jpg`): 6 m before/after.
  - `crop_roadster_s.jpg`: trim turned white, no dent, no scrape.
  - `heavy_t3_0|t3_6.jpg` (`heavy_pair_s.jpg`): EV heavy tier, no arcs.
  - `worker_sheet_s.jpg`: the worker's `--nofx` captures; the police car has no wheels and the smoke reads as dots.
- No reference photos exist for this unit (`ref/gameplay/dl/b08_damage` and `b13` are text/PDF only). The
  targets above come from dossier §7.1/§7.4 and ART.md §3/§5.
- Re-shoot: `tools/godot.sh shot --scene=/Users/minimax/m/skyrush/tmp/review/review_dent.tscn
  --outdir=$HOME/m/skyrush/captures/damage --out=dent --warm=1 --times=0.5,1.0,2.8,3.4`.
  Copy that scene and script into `game/damage/demo/`; it is the acceptance shot for dents, scrapes and paint.
