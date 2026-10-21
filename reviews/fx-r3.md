# fx review round 3 — VERDICT: FAIL

Reviewer: strict review and art direction, 2026-10-20. The user asks: 贴图纹理什么都要细化 (refine the
textures and the detail everywhere). The lead notes F-INT1, F-INT3 and LEAD-SMOKE are met. F-INT4 is met
for the grain: the puffs are soft billows now. Its other half fails: puffs must read grey-blue at night,
but the puffs I measured are near black (MUST-FIX 3). The main scene now fails the lead's standard drive with
renderer errors (MUST-FIX 1).

## Scores (0-10): function 5, visual 3, code 4
- **function 5.**
  - What is now right:
    - the rain splash points (64 RGBF directed points);
    - reversing leaves no skid mark and no smoke;
    - the arcs stay on the shell;
    - the 8-emitter cap and the 50-car spawn/free test;
    - 51/51 tests pass and the check is clean.
  - What is broken:
    - The lead's main drive exits 1 with 110–154 renderer errors. With `--stub=fx` it has 0.
    - There are 0 skid quads in the real game during a full drift at 276 km/h.
    - The skid ribbon is tilted, so half of it is under the asphalt.
    - The splash rings spawn about 2.5 m under the road, and they are only 5 cm wide.
    - The ICE fire leaves a 10 m trail of cards behind the sliding car.
- **visual 3.** Only the spark streaks, the arcs, the arch glow and the charge ground ring read right.
  - The tyre smoke is a dotted line of cotton balls, and it is near black on an unlit road.
  - In the real game the smoke and the spray cannot be seen at all.
  - The skid marks are 5 cm hairlines, or cannot be seen.
  - The ICE fire is a row of cream trapezoid cards.
  - The charge flash is a hard cyan sphere, and a full whiteout from above.
  - No splash ring can be seen.
  - The wreck column is a thin wisp that leans over.
- **code 4.**
  - Three files are over the 400-line limit.
  - Many calls are dynamic, on variables typed as `Node`.
  - There are 17 dead TUNE constants. Some of them hold the very numbers the status claims; the code
    uses other literals.
  - There are dead textures and a dead re-colour path.

## MUST-FIX

### 1. The main scene logs renderer errors, and only with fx loaded
- **Evidence:**
  - `tools/godot.sh drive --timeline=res://tools/timelines/smoke_drive.json --skip-menu
    --shots=5,8,8.8,9.4,10.4,14` exits 1.
  - Run 1 logged 110 `ERROR: Parameter "uniform_set" is null` (`draw_list_bind_uniform_set`). Run 2
    logged 154.
  - The errors come in bursts: at t 5.5–7.5 (nitro, 235–300 km/h) and at t 8.6–10.5 (drift).
  - The same command with `--stub=fx` gives 0 errors and exit 0. So does a run without screenshots.
  - Logs: `tmp/review/fx/r3_main.log`, `r3_main_rep_none.log`, `r3_main_rep_fx.log`, `r3_bisect_none.log`.
- **Do:**
  - Bisect inside the fx unit. Add a dev option `--fx-no-thrusters` in `fx_director.gd`, then switch
    off one family at a time:
    - the ignition puffs and rings (created and `queue_free`d for every boost);
    - the near-miss and charge ImmediateMesh ribbons;
    - the skid ArrayMesh, rebuilt every frame;
    - the rain splash `ImageTexture.update()`;
    - the debris pool.
  - If the cause is fx, fix it. If it is the thruster system, put the repro and the log lines under
    Requests in `status/fx.md`.
- **Verify:** the same drive command run twice gives exit 0 and 0 errors both times.

### 2. Skid marks: the ribbon is buried in the road, and no mark is made at speed
- **Evidence:**
  - `captures/review/fx/r3top_t3_4.jpg` (9 m up, 83 px/m): the marks are dark lines 4–5 px wide,
    about 5–6 cm. They are 25–40 % below the road median of 26/255. The 24 cm band does not show.
  - `r3q_t16_9_down6.jpg` (6 m above the dry drift): no mark can be seen at all.
  - In main, the probe prints `skids=0` at t 8.0, 8.8 and 9.3, with drift=drift, slip 1.00,
    grounded 4 and 276 km/h.
- **Cause (a), the tilt:** in `fx_skid_ribbon.gd:98-100`, `offset = right*HALF + normal*SKID_LIFT`.
  Then `left = point - offset` puts the left edge 1 cm UNDER the asphalt, and the right edge sits 1 cm
  above it. The quad cuts through the road, and only a sliver survives the depth test.
- **Cause (b), the first quad:** `_cross_section()` (line 225) starts every strip with zero width. The
  probe shows the first quad edge as 0.0.
- **Likely cause (c), no marks at speed:** `add_point()` line 88 cuts the strip whenever `travelled >
  SKID_MAX_GAP` (3.0 m), and `_update_skids` runs in `_process`. At 77 m/s, any frame below 26 fps
  moves the car more than 3 m. Every point then starts a new strip, and no quad is ever made. Confirm
  it by printing `travelled` for each call in a main drift.
- **Do:**
  - Lift both edges: `var lift := normal * TUNE.SKID_LIFT`, `left = point - right*HALF + lift` and
    `right_point = point + right*HALF + lift`.
  - Start every strip at full width, using the car's right vector.
  - Add the points in `_physics_process` at 120 Hz.
  - Let the gap threshold grow with the speed:
    `maxf(TUNE.SKID_MAX_GAP, speed_mps * 3.0 / Engine.physics_ticks_per_second)`.
  - Cut a strip only after the airborne grace period.
- **Verify:**
  - A test: every vertex of every live quad is at least SKID_LIFT − 1 mm above the ray-probed road,
    and the first quad is 0.24 m wide.
  - A main probe after a 2 s drift at 270 km/h shows `skids > 0`.
  - In a 9 m top-down capture, the band that is at least 15 % darker than the road median is
    18–22 px (22–26 cm) wide and shows at least 6 stripes. Put the numbers in the status.
  - Captures: `skid_top_9m.jpg`, `skid_5m.jpg` and `skid_main.jpg`.

### 3. Tyre smoke and wet spray: separate cotton balls, black in the dark, unseen at speed (F-INT4 colour half)
- **Evidence:**
  - `r3chase_t15_8.jpg` (dry drift at 91 km/h): a dotted line of single puffs about 1.5 m apart. The
    brightest puff is #1F212E on a road of #0C0D12, so it is near black.
  - `r3q_t16_9_down6.jpg`: the brightest puff is #1C1C24.
  - `r3side_t2_0.jpg` (under a lamp): lumpy, separate cotton balls of #9F9895.
  - `r3q_t5_8_q8.jpg`: the spray at 165 km/h lies on the road as separate grey "popcorn" clumps.
  - Main, `r3main_t8_0.jpg` and `r3pm_t8_0_rear5.jpg` (drift at 201 and 276 km/h, TyreSmoke and 14
    WetSpray emitters on): no smoke or spray can be seen at all.
  - Side by side with the reference: `captures/review/fx/r3_compare_ref.jpg` (with
    `ref/art/img/cp04_nfs2015_wet_night.jpg`).
- **Causes:**
  - The rate is per second, not per metre:
    - 120 × 0.8 / 1.4 s = 68 puffs/s, which is 1 puff every 1.1 m at 77 m/s;
    - `fixed_fps` stays at the GPUParticles3D default of 30, so the puffs come out in clumps every
      1/30 s.
  - There is one smoke box, ±0.6 m wide, across the axle (`fx_emitters.gd:40`, `fx_car_rig.gd:176`),
    not one emitter per tyre.
  - The sprites are 0.35–0.6 m (`fx_emitters.gd:32`) at alpha 0.32, so they never overlap.
  - The shared material is lit only: with no lamp nearby, a puff renders black.
- **Do:**
  - **Smoke:**
    - One emitter per rear tyre at the contact patch, as for the spray. Use `fixed_fps = 0` and
      `interpolate = true`.
    - Aim for at least 2.5 puffs per metre per tyre up to 300 km/h:
      - `amount = 300 × quality`;
      - `amount_ratio = intensity × clamp(speed_mps / 83.0, 0.15, 1.0)`.
      - Update the worst-case count in the director.
    - Birth size 0.6–0.9 m with growth ×3; alpha 0.22–0.30, so 3–4 puffs overlap into one plume.
    - `inherit_velocity_ratio` 0.2; rise 0.4–0.7 m/s.
    - Add an ambient floor after `SmokeFX.setup()`:
      - `emission_enabled = true`, `emission` = #3A4050 × 0.5;
      - this keeps every LEAD-SMOKE lesson;
      - put the same idea to the lead as a SmokeFX "ambient" field under Requests.
    - Targets: an unlit puff reads #343A48 or brighter; a puff under a lamp reads #8F98A8–#B0B8C8.
  - **Spray:**
    - Keep it apart from the smoke: a fine mist at alpha ≤ 0.2 (`SPRAY_ALPHA` 0.35 → 0.18).
    - Sprites grow from 0.4 to 1.6 m and stretch along the velocity.
    - Turn the droplet streaks on whenever the spray runs. Today `fx_car_rig.gd:329` runs them only
      while sliding.
    - 40–80 droplet streaks per tyre, 2–4 × 10–25 cm, #D9E8FF.
- **Verify:** captures, each with the measured numbers in the status:
  - `smoke_5m` (6 m side), `smoke_20m` (q20) and `smoke_main` (main drive, t 8.8, behind the car):
    the plume is continuous over at least 8 m behind each rear tyre, with no gap wider than 0.3 m;
  - `spray_160kmh_rear`: a continuous mist fan 3–8 m long per tyre, with droplet streaks.

### 4. ICE wreck fire: cream trapezoid cards that trail behind the car (texture and colour)
- **Evidence:**
  - `r3p_t30_0_tq8.jpg` (8 m from the wrecked traffic car; crop in `r3_crops_detail.jpg`): 6–8
    upright cards of #E7DFD4, 1–2 m tall, in a line 2–10 m behind the car, which lies on its roof.
    There is no flame on the car.
  - `game/fx/textures/flame_atlas.png` (sheet `captures/review/fx/r3_textures.jpg`): 16 near-identical
    trapezoids. Between cells the mean |Δα| is only 0.044–0.047. They are filled with vertical
    per-pixel grain and have no tongues.
- **Causes:**
  - Energy 3.2 × FIRE_HOT #FFF2C0 in the first 20–55 % of the life tonemaps to cream white.
  - The particles are in world space on a car that is still sliding, so they leave a trail.
  - `angle_max = TAU` is read in DEGREES (0–6.3°). The roll is almost zero, and the cell hash in
    `fx_add.gdshader` picks from only 11 of the 16 cells.
- **Do:**
  - **Atlas:** re-bake at 1024² (4 × 4 cells of 256 px) with 16 DIFFERENT licks:
    - a teardrop: the base about 45 % of the cell wide, 2–3 tongues splitting in the top third, the
      tips at the top;
    - a soft edge about 25 px wide;
    - 2 octaves of noise stretched upwards, 4–6 lumps per cell, and no grain (mean neighbour
      |Δα| < 0.01);
    - an empty gutter of 12 px around every cell.
  - **Colour:**
    - energy 1.5–2.5;
    - ramp #FFD27A (0) → #FF7A1A (0.35) → #B83A0C (0.7) → #3A1A0E at α 0 (1.0);
    - the white-hot is only in the texture core (luminance 1.0 in the core, 0.4 at the edge).
  - **Size and life:** 0.35 → 0.9 → 0.25 m, life 0.5–0.8 s, 30–40 licks.
  - Set `local_coords = true` on the fire (lean it with the car's velocity), or stop it while the
    wreck slides faster than 2 m/s.
  - Set `angle_max = 360.0`, so every cell is picked evenly.
- **Verify:**
  - `wreck_ice` at 8 m and 30 m, 2 s after the ICE car comes to rest: orange flames on the engine bay
    with a yellow core, no cream cards and no trail.
  - A sheet of the 16 atlas cells.

### 5. 闪充 charge flash: a hard cyan sphere that hides the car and whites out the view from above
- **Evidence:**
  - `r3p_t5_55_q8.jpg` (0.17 s after the event, crop in `r3_crops_detail.jpg`): a disc 4.2 m wide
    around the car, core #E2F6F7.
  - `r3side_t5_52.jpg`: the disc hides the whole car.
  - Your own `captures/fx/r3/charge_top.jpg` is a full whiteout: the frame median is #D9F6FA. It was
    listed as evidence.
  - The three ribbons read as static stacked hoops (`charge_rear.jpg`).
- **Cause:** `fx_charge.gd:80-95` draws a 2.6 m quad, scaled up to 1.6 (4.2 m), with the `glow()`
  texture at energy 10, pushed 2 m towards the camera. The halo still has alpha ≈ 0.1 at 70 % of the
  radius. At energy 10 that is 1.0 HDR, which gives a visible rim. From 7–9 m above, the quad fills the view.
- **Do:**
  - The flash:
    - a hot core 0.8–1.2 m wide at the roof or charge port, peaking at 0.08 s and gone by 0.25 s;
    - a halo of exp(−8·d²), with no visible rim;
    - push ≤ 0.6 m, and scale the quad by `min(1, 6 m / distance to the camera)`.
  - Let the OmniLight do the rest: #19E6FF, energy 9 → 0 over 0.35 s, range 6 m, painting the road
    and the body.
  - Arcs: 6–10 short arcs over the body (`fx_arcs`) during the 1.0 s.
  - Ribbons: make them spiral, rising 0.4 m while they turn 360° in 1.0 s, with scrolling chevrons.
- **Verify:**
  - Capture `charge_side`, `charge_rear` and `charge_top` at 0.05, 0.15 and 0.4 s.
  - No frame may have more than 25 % of its pixels above 0.9 luminance.
  - The car's silhouette can still be read at the peak.
  - The ring and a cyan light pool lie on the asphalt.

### 6. Rain splash rings cannot be seen
- **Evidence:** `r3s_t8_0_splash.jpg`, camera 2.6 m above the wet road, held 60 frames: not one ring
  (1:1 crop in `r3_crops_rain_hit.jpg`). Your own `rain_splash_3m.jpg` shows none either.
- **Causes:**
  - **The rings spawn under the road.**
    - `fx_rain.gd:217` puts the splash and crown emitters at `(cam.x, 0, cam.z)`.
    - `_update_splash_points()` (line 233) stores `hit - camera_position`, the camera's y included.
    - Every ring therefore spawns at world y = `hit.y - cam.y`: about 2.4–2.6 m UNDER the asphalt
      with the demo cameras. The crowns start there too.
    - The code comment says the heights are absolute; they are not.
    - The tests only check the texture format, so none of them catches this.
  - `fx_rain.gd:108-109` sets `scale_min = scale_max = SPLASH_SIZE_MIN` (0.05 m), so the rings grow
    from only 1 to 5 cm. `SPLASH_SIZE_MAX` (0.35) is never used.
  - The flat rings use `fx_soft.gdshader` with a soft distance of 0.15 m. Even once lifted 2 cm, a
    ring would fade to 10–25 % alpha.
  - The points are spread over a 24 m box, so only about 4 % of the 220 rings are in a close view.
- **Do:**
  - Store `hit - Vector3(cam.x, 0.0, cam.z)` + 0.02 m up in the point texture, or put the emitter at
    the camera's position.
  - Scale 0.12–0.35 m, growing ×1 → ×1.8 over 0.4 s.
  - Set `depth_fade = 0` for the flat rings and lift them 0.02 m (`SPLASH_LIFT`, unused today).
  - Put 70 % of the probe points within 8 m in front of the camera.
  - Rim tint #C7DBED at energy 1.5–2.5, so the rings catch the lamps. Amount 300 on high.
- **Verify:**
  - A test: the emitter's transform × each texel lands within 0.03 m of its ray hit.
  - The held 2.6 m `ground` capture shows at least 25 rings spread over the road. Write the count
    in the status.
  - The chase camera shows a fine sparkle of rings within 10 m.

### 7. Wreck column: a thin wisp that lays over; the status claim is false
- **Evidence:**
  - `r3p_t23_5_q20.jpg` (20 m): a wisp 4–6 m tall, bent about 45°. Its brightest pixel is #6B6972,
    against #151621.
  - The status says "the column rises 2.0–2.6 m/s over 5.5 s (11–14 m)". The code does otherwise:
    - `fx_emitters.gd:104` uses a speed of 1.0–1.8;
    - `WRECK_SMOKE_RISE_MIN`, `WRECK_SMOKE_RISE_MAX` and `WRECK_SMOKE_SCALE` are never used;
    - `fx_emitters.gd:114` sets gravity (1.5, 0.9, 0.3). That is a constant SIDEWAYS ACCELERATION of
      1.5 m/s², so the column keeps bending over.
- **Do:**
  - Speed 2.0–2.6 m/s from TUNE, in a 10° cone; buoyancy +0.6 m/s².
  - Wind ≤ 0.3 m/s² sideways.
  - Size 0.8 → 4.5 m (`WRECK_SMOKE_SCALE`); 70–90 puffs at alpha 0.3; the ambient floor of MUST-FIX 3.
  - ICE: core #2A2A2E, lit orange from below for the first 15 % of the life. EV: #CFD6DE.
- **Verify:** `wreck_ev` at 20 m and 40 m: the column stands at least 8 m above the car and leans at
  most 20°, and it is at least 1.5× the luminance of the sky behind it.

### 8. Code rules: files over 400 lines, dynamic typing, dead code (CONTRACTS §3)
- **Files over 400 lines:** `fx_car_rig.gd` 539, `fx_director.gd` 437, `demo/fx_demo.gd` 409. The
  status names only the rig.
  - Split the rig's collision and near-miss code into `fx_rig_collision.gd`.
  - Split the director's takedown, charge and wreck handlers into `fx_events.gd`.
  - Split the demo beats into `fx_demo_beats.gd`.
  - Do the split as its own step, before any logic change.
- **Typing:** use preload types (`const RIG := preload("res://fx/fx_car_rig.gd")`, `var rig: RIG`), and
  typed `Array[Dictionary]` for the contacts. Today:
  - `fx_car_rig.gd:32-35` types `_skid`, `_spark`, `_debris` and `_lights` as `Node` and calls them
    dynamically;
  - `fx_rig_manager.gd:136,150,165,171` uses `rig.call(&"is_wrecked")` and the like;
  - `_contacts: Array` and `fx_arcs._paths: Array` are untyped.
- **Dead code:**
  - 17 TUNE constants are never used: SMOKE_SOFT_DISTANCE, SPRAY_SPEED_FACTOR, DROPLET_STREAK,
    SPLASH_SIZE_MAX, SPLASH_LIFT, CHARGE_RIBBONS, ARC_HALO, SPARK_TRAIL_FACTOR,
    IMPACT_SURFACE_OFFSET, VAPOUR_WIDTH, IGNITION_SCALE_MIN, IGNITION_SCALE_MAX, WRECK_SMOKE_SCALE,
    WRECK_SMOKE_RISE_MIN, WRECK_SMOKE_RISE_MAX, NEAR_MISS_LENGTH, NEAR_MISS_SPEED;
  - `EMITTERS.vapour()` is never called;
  - `PALETTE.FIRE_MID` and `PALETTE.AIR` are never used;
  - `smoke_atlas.png` and `smoke_normal.png` (1024² each) have been unused since the switch to
    SmokeFX, and `test_fx.gd:75` checks only the dead atlas;
  - `_recolour_smoke()` casts the StandardMaterial3D to `ShaderMaterial`, gets null and does
    nothing, so the wet/dry tint never changes. Set `process_material.color` instead.
- **Verify:**
  - `wc -l game/fx/*.gd game/fx/demo/*.gd` shows every file ≤ 400;
  - a scan for unused TUNE/PALETTE names prints nothing;
  - no `.call(&` on the unit's own scripts.

### 9. Evidence: several captures do not show what the status claims (r2 #11 repeated)
- **Captures that do not show their claim:**
  - `charge_top.jpg` is a whiteout;
  - `wreck_ice.jpg` is framed on the player, and the ICE car is an orange dot about 100 m away;
  - `near_miss.jpg` shows no ribbon;
  - `rain_splash_3m.jpg` shows no ring;
  - `skid_3m_top.jpg` is taken 9 m up, and the marks can hardly be seen.
- **Demo cameras:**
  - The `side` camera sits behind the guard wall after t 17, so `r3side_t17_3.jpg` and
    `r3side_t23_0.jpg` show only the wall.
  - The `top` camera prints 1,540 "Target and up vectors are colinear" warnings per run
    (`fx_demo.gd:194`).
- **Do:**
  - Make one capture per claim, framed on the effect.
  - Write a line on what can be seen in it, with the measured numbers (sizes, hex values, counts).
  - Use the car's forward direction as the up vector of the `top` camera, and put `side` on the open
    side of the road.
- **Verify:** every image named in `status/fx.md` shows its effect at first glance.

## SHOULD-FIX
1. **N₂ shock rings** (`fx_ignition.gd:47-60`) are horizontal PlaneMeshes. Orient each one across its
   `Nozzle_R*` axis (marker −Z). Show them at 0.05 s; today no capture shows them.
2. **Impact sparks and debris:**
   - At 233 km/h the hit burst (70 sparks, 8 debris) sits about 4 m behind the car and reads small at
     7 m (`r3s_t13_03_front7.jpg`).
   - The takedown is only 60 sparks and 8 + 6 debris, as literals in `fx_director.gd:283-285`.
     Gameplay DOSSIER §3.3 asks for oversized parts and ×2 counts: 120–160 sparks, 20–30 glass and
     12–20 plastic, at 2.2× size in slow motion.
   - The burst must stay on the flank.
3. **Scrape:** it reads as a dashed line of spark clumps, because it bursts every 0.045 s
   (`r3chase_t17_4.jpg`). Emit 2–4 sparks every physics tick for a continuous shower.
4. **Textures (细化):**
   - `ripple.png` is two perfect rings. Add 3–4 thinner secondary rings of falling amplitude, with a
     slight noise wobble.
   - `energy_ribbon.png` is flat chevrons. Add filament noise and a hot leading edge (#E6FDFF).
5. **Magic numbers in logic:**
   - `fx_emitters.gd:31-32,40,52-55,59,71-77,86-94,104-114,144-150,171-182`;
   - `fx_charge.gd:55,72,81,95`;
   - `fx_ignition.gd:55-56,72`;
   - `fx_director.gd:283-285`.
6. **Near miss in the demo:** it cannot be seen in `r3chase_t9_3.jpg`, `r3p_t9_25_rear5.jpg` or your
   own `near_miss.jpg`, although main shows the ribbons (`r3main_t8_8.jpg`). Pass the demo's traffic
   car on the camera side and capture it.
7. **Performance:** there are still no fps numbers with and without fx. My samples are noisy on the
   shared machine: 63 fps in one run and 104 fps in another, at the same EV-column beat. Report
   `tools/godot.sh perf` with a wreck column 6 m in front of the camera, and with a full drift.
8. **Scratch:** delete the leftovers in `tmp/fx/` (doc, jpg and log files) and the orphan
   `game/fx/tests/_probe.gd.uid` (lead rule: scratch is deleted when done).

## Verified OK
- **Check:** `tools/godot.sh check --only=res://fx/` gives `CHECK 49 files, 0 failed, 0 engine errors,
  0 warnings`.
- **Tests:**
  - `test_fx.gd`: 35 PASS, `FX TESTS OK`. Among them:
    - 50 cars spawned and freed: rigs are released, and none survives a same-frame spawn/free;
    - the tiers at 10/30/59/61/120/151 m;
    - worst case 13,460 and live 5,075 billboards.
  - `test_fx_effects.gd`: 16 PASS:
    - reversing leaves no skid and no smoke;
    - bolts ≤ 0.80 m (0.634) and ≤ 0.15 m from the shell;
    - no arcs at 50 % health, arcs at 10 %;
    - 12 wrecks run 8 emitters;
    - 64 RGBF directed splash points;
    - no spark below a deck at 10 m;
    - the skid mark is 0.241 m wide.
- **Lead F-INT1:** 0 script errors in the demo and in main.
- **Lead F-INT2 logic:** density = slip × speed, capped at 0.8; life 1.4 s; no smoke below 10 km/h.
  Now the opposite problem: the smoke cannot be seen at speed (MUST-FIX 3).
- **Lead F-INT3:** with the EV wrecked, `r3q_t22_0_right4.jpg` and `_t23_0` show only small cyan
  glints on the glasshouse and the body. There are no sticks in the air.
- **Lead F-INT4 grain:** the puffs are soft billows, with no dithered noise; alpha 0.32 ≤ 0.35; growth
  ×2.5. The "grey-blue at night" half fails (MUST-FIX 3).
- **LEAD-SMOKE:** the tyre smoke, the spray, the ignition puffs and the wreck column are all built
  with `SmokeFX.preset()` + `SmokeFX.setup()`, and no lesson is undone.
- **Rain:**
  - the probe prints `splash emission_point_count=64 tex=(8, 8) fmt=10` (RGBF);
  - the rain streaks can be seen;
  - the rain is off on the low preset (`Settings.feature("rain")`).
- **Budgets:**
  - main probe: 93 rigs, 4.6–5.4k live billboards, worst case 12,439;
  - demo: worst case 8,555;
  - 0 Decal nodes, and the skid pool is ≤ 400 quads.
  - Particle quality scales 0.4–1.3 with `Settings.feature("particles")`.
- **What reads right in the images:**
  - the arch glow at the rear wheel (`n2_arch_side.jpg`);
  - the charge ring on the asphalt (`r3side_t5_75.jpg`, `r3q_t6_1_q8.jpg`);
  - the near-miss ribbons in main (`r3main_t8_8.jpg`);
  - the takedown spark fan (`r3p_t25_12_front7.jpg`).
- **Spray emitters:** there is one per tyre (WetSprayL/R/Front). In main, 7 cars spray at once
  (t 6.0).
- **Ownership:** round 3 used Write/Edit only in `game/fx/**` (never `thrusters/`) and `status/fx.md`.
  No Godot run was left in the background (`jobs/fx/log.jsonl`, sessions 7–8).

## Evidence
- **Logs and scripts:**
  - logs: `tmp/review/fx/r3_check.log`, `r3_test.log`, `r3_test2.log`;
  - probe: `tmp/review/fx/r3_probe.gd`, the r2 probe with the extra cameras `down6` and `right4`;
  - measuring scripts: `profile.py`, `puffcol.py`, `texstats.py`.
- **Demo sweeps** (`tools/godot.sh shot --scene=res://fx/demo/fx_demo.tscn --warm=20 --fxcam=chase|side|top
  --times=…`):
  - `captures/review/fx/r3chase_*`, `r3side_*`, `r3top_*`;
  - sheets `r3_sheet_chase.jpg` and `r3_sheet_side_top.jpg`.
  - The charge fired at 5.29–5.44.
- **Probe runs:**
  - `r3p_*` (sheet `r3_sheet_probe.jpg`);
  - `r3q_*` (`r3_sheet_probe2.jpg`);
  - `r3s_*` (`r3_crops_rain_hit.jpg`);
  - detail crops in `r3_crops_smoke.jpg` and `r3_crops_detail.jpg`.
  - Key probe lines:
    - t 15.8: a dry drift at 91 km/h, slip 1.00, gives `TyreSmoke` 96 live puffs only;
    - t 25.12: the takedown gives sparks 60 and debris 6;
    - t 30: `WreckSmoke` ×2 + `WreckFire`.
- **Main:**
  - `r3main_*` (`r3_sheet_main.jpg`) and `r3pm_*` (`r3_sheet_probe_main.jpg`).
  - Probe at t 8.0 / 8.8 / 9.3: `drift=drift slip=1.00 grounded=4 kmh=276-277 … skids=0`.
  - The errors are counted in MUST-FIX 1. In the log names, `r3_main_rep_fx.log` is the
    `--stub=fx` run. The screenshot-free run (`r3_bisect_none.log`) had 0 errors, but it also had no
    drift.
- **Measurements:**
  - The skid lines in `r3top_t3_4.jpg` are 4–5 px at 83 px/m, 25–40 % below the median of 26.1.
  - Puff colours: #1F212E (t 15.8) and #1C1C24 (down6) on a road of #0A0B10 to #0C0D12; under a
    lamp #9F9895.
  - Fire cards #E7DFD4.
  - The charge disc core is #E2F6F7; the median of `charge_top.jpg` is #D9F6FA.
  - The flame atlas cells differ by only 0.044–0.047 in mean |Δα|.
- **Worker captures:** `captures/review/fx/r3_worker_A.jpg` and `r3_worker_B.jpg` (22 files, no
  duplicates by md5).
- **Textures:** `captures/review/fx/r3_textures.jpg`.
- **Reference:** `r3_compare_ref.jpg` puts my wet drift, `cp04_nfs2015_wet_night.jpg` and my dry
  drift side by side.
