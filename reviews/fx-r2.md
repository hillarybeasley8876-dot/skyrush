# fx review round 2 — VERDICT: FAIL

Reviewer: strict review and art direction, 2026-10-20. The user's requirement applies to every
effect: 贴图纹理什么都要细化 (refine the textures and the detail everywhere). The lead's notes
F-INT3 and F-INT4 in `reviews/fx-lead.md` (added 10-20 09:00) are still open. They are MUST-FIX 5
and MUST-FIX 1 below.

## Scores (0-10): function 5, visual 3, code 5
- **function 5.** The round-1 state bugs are fixed:
  - idle and OFF rigs run no emitter;
  - the tiers follow the brief, and `amount_ratio` is used everywhere;
  - the skid ribbon is a real 0.241 m strip;
  - the F-INT1/F-INT2 logic is in;
  - 35/35 tests pass, and there are 0 fx errors.

  Still broken:
  - every rain splash spawns at one point;
  - the 闪充 ring is drawn 6 cm under the road, and the energy ribbons do not exist;
  - the takedown burst spawns 42.6 m from the victim;
  - impact sparks bounce at y = 0 and hang 6 m behind a car doing 250 km/h;
  - the arch lights sit in the centre of the car;
  - traffic cars never spray, because fx reads 0 km/h for them;
  - the car smokes and leaves skid marks while reversing;
  - the 8-emitter cap is not enforced.
- **visual 3.** Almost nothing reads as the real thing:
  - smoke is grainy grey static (F-INT4), and the spray is white "popcorn" crescents;
  - skid marks are 5 cm pure-black hairlines;
  - arcs are 2–6 m straight cyan sticks (F-INT3);
  - the wreck columns cannot be seen at 20 m, and the fire is upside-down flat cards;
  - the near miss cannot be seen at all.

  Only the rain streaks and the hot spark core work.
- **code 5.** The good: files are ≤ 400 lines, there is a tuning block, and the tests are typed. The problems:
  - dead code and shadowed constants;
  - dynamic calls on `Node`-typed variables;
  - `DEBRIS_SPEED` is passed as a count;
  - one Godot run was started in the background.

## MUST-FIX

### 1. Smoke, spray and vapour puffs are grainy noise cards (lead F-INT4; r1 #4 not met)
- **Evidence:**
  - `captures/review/fx/r2demo_t2_2_rear5.jpg` (5 m) and `r2demoB_t2_3_q20.jpg` (20 m);
  - lead `captures/lead_int3_t10_0.jpg` and `_t14_0.jpg`;
  - white crescent spray in `r2demo_t5_5_rear5.jpg` and `r2demo_t11_3_rear5.jpg`;
  - side by side with `ref/art/img/cp04_nfs2015_wet_night.jpg`: `captures/review/fx/r2_compare_ref.jpg`.
- **Causes:**
  - `fx/tools/bake_textures.gd:62-78`: the detail noise is 0.045 × 1.6 per px, about 18 lumps across a
    256 px cell. The erosion `smoothstep(0.30, 1.15, …)` then punches holes. The result is
    salt-and-pepper alpha.
  - `fx_soft.gdshader:64,68` samples with `textureLod(…, 0.0)`. With no mips, a puff 40 px wide on
    screen aliases the 256 px cell into speckles.
  - `fx_soft.gdshader:50`: the frame is `floor(TIME × 7)` over 16 cells baked from 16 unrelated
    seeds, so each puff pops to a different shape 7 times a second.
  - `_normal_from_field` (gradient × 4) with `normal_strength` 0.8 lights one rim of every puff,
    which makes the white crescents.
  - `INSTANCE_CUSTOM` is ignored, so the angle and angular velocity set in `_spin()` do nothing.
- **Do:**
  - Re-bake `smoke_atlas.png` at 1024² (4×4 cells of 256 px):
    - a soft gaussian core (σ ≈ 0.33 of a cell) multiplied by low-frequency billows: 2–3 octaves,
      3–5 lumps per cell in the first octave (FastNoiseLite frequency ≈ 0.012–0.02 per px, no ×1.6);
    - alpha = smoothstep(0.05, 0.7, density), core alpha at most 0.85, and an empty gutter of
      at least 12 px around every cell;
    - the 16 cells must be ONE evolving sequence (3D noise, z += 0.08 per cell), not 16 seeds.
  - Build the normal map from the density blurred by 4 px, with a gradient scale ≤ 1.5. Set
    `normal_strength` ≤ 0.35. Use wrap diffuse (0.5) to soften the shading.
  - Shader:
    - sample with `texture()` and mipmaps (the gutters stop the bleed between cells);
    - take the rotation from `INSTANCE_CUSTOM.x`;
    - take the frame from the life fraction `INSTANCE_CUSTOM.y × 15`, and cross-fade frames n and
      n+1 with `fract()`.
  - Lead F-INT4 numbers:
    - depth fade 0.5 m;
    - alpha per puff ≤ 0.35 (`SMOKE_ALPHA` 0.5 → 0.32, `SPRAY_ALPHA` 0.4 → 0.22);
    - scale grows ×2.5 over the life;
    - grey-blue tint: a puff under a street lamp reads ≈ #9AA3B5 on screen and ≈ #3A4050 in
      shadow, never black and never pure white.
- **Verify:**
  - your own frames `captures/fx/smoke_5m.jpg` and `smoke_20m.jpg`;
  - a strip of 6 frames 0.05 s apart (ffmpeg `tile=6x1`) with no popping;
  - a test on the atlas: fewer than 2 % of pixels may differ from a 3 px box-blurred copy by
    more than 0.12 alpha.

### 2. Skid marks render as 5 cm black hairlines, with no tread and with marks while reversing (r1 #3 not met)
- **Evidence:**
  - The geometry is right. The probe prints quads 0.241 m wide, sharing edges, 0.61–0.81 m long.
  - In `r2demoB_t3_2_top3.jpg` (3 m above, 250 px/m) the dark run is only 16–19 px, about 5–7 cm,
    and it is pure black (0/255). The rest of the 24 cm band cannot be seen.
  - `r2demo_t4_0_low5.jpg` and `r2demo_t25_1_front7.jpg` show thin uniform black lines with no
    striations.
- **Likely cause:** `fx_skid.gdshader` is lit and uses `blend_mul`. It multiplies the road by ALBEDO ×
  scene light (≈ 0 at night) instead of by ALBEDO alone.
- **Do:**
  - Use `render_mode unshaded, blend_mul, depth_draw_never, cull_disabled` with
    ALBEDO = mix(vec3(1.0), vec3(0.082), a × 0.6), i.e. #151515 at α 0.6. A fresh mark then
    multiplies the road by 0.45–0.8, its wet reflection included.
  - Re-bake `tyre_track.png` with tread that reads:
    - 7 grooves with an alpha contrast of 0.35 → 1.0 (today it is 0.55 → 1.0 × wear);
    - 2 shoulder lines at 12 % and 88 % of the width;
    - scuff breaks along V (fbm at a 0.3 m scale);
    - the first 1.5 m of a strip 1.3× darker, where the tyre bites.
  - Fade the end of a strip over 0.4 s. Today the last quad drops to 0 at once.
  - Reversing is not braking. In `fx_car_rig.gd:186-187`, use
    `tel.forward_speed_kmh > 25.0 and tel.brake > 0.5` (`core/contracts/car_telemetry.gd:9`: the
    value is negative when reversing). In the demo probe at t 23–30, the car reverses at 40 km/h
    with TyreSmoke on, and the skid quads grow from 92 to 348.
- **Verify:**
  - In a top-down capture from 3 m, the darkened band (≥ 15 % below the road median) must be
    22–26 cm wide, its darkest pixel must keep ≥ 20 % of the road value (not 0), and it must show
    ≥ 6 stripes across.
  - A test with `forward_speed_kmh` −40 and `brake` 1 must produce no smoke and no new quads.
  - Captures: `skid_3m_top.jpg`, `skid_5m.jpg` and `skid_20m.jpg`.

### 3. Every rain splash spawns at ONE point (r1 #6c/e not met)
- **Evidence:**
  - Every probe report, demo and main, prints `splash emission_point_count=1 tex=(8, 8) fmt=5`
    (RGBA8).
  - In `r2demoB_t4_0_splash.jpg` the camera was held for 60 frames, 2.6 m above the road. All the
    rings and crowns sit in one 0.5 m clump about 1.4 m from the foot of the camera. The rest of
    the road has none.
- **Cause:** `fx_rain.gd:155-226` paints white pixels into an RGBA8 mask. Godot reads the texels of
  `emission_point_texture` as POSITIONS (RGB = xyz offset in metres, in a float format), and it only
  uses the first `emission_point_count` texels (here 1). Every splash therefore spawns at texel 0,
  which is (1, 1, 1) m: 1 m above the road.
- **Do:**
  - Build an `Image.FORMAT_RGBF` texture with one texel per ray hit: texel = hit point − emitter
    position + 0.02 m up. Set `emission_point_count = hits`.
  - Use `EMISSION_SHAPE_DIRECTED_POINTS` with the hit normals in `emission_normal_texture`, so the
    rings lie flat on ramps.
  - Jitter the 8×8 grid by ±0.7 m on every probe, and keep one height per point (drop `_ground_y`).
  - Use `TUNE.SPLASH_GRID` and `TUNE.SPLASH_PROBE_INTERVAL` (0.25 s). Today the local `GRID` and
    `PROBE_INTERVAL` (0.5 s) shadow them.
- **Verify:**
  - The probe prints `emission_point_count` = hits (≥ 50 of 64 on the demo road) and fmt 10 (RGBF).
  - A camera held for 1 s at 2.6 m shows ≥ 25 separate ripples spread over the road and none
    above it. Capture `rain_splash_3m.jpg`.

### 4. 闪充 charge flash: the ring is under the road, there are no energy ribbons, and the flash is clipped into a dome (r1 #7 not met)
- **Evidence:**
  - `r2demoB_t5_3_q8.jpg` (0.3 s in, 8 m): no ring and no light pool.
  - `r2demo_t5_15_side6.jpg`: the flash is a cyan dome on the roof, and the arcs are straight
    sticks over the car.
  - The car origin is at y = 0.50 and the road top at 0.56. The ring is drawn at the car origin
    (`fx_charge.gd:35-47`), so it is 6 cm under the asphalt.
  - `TUNE.CHARGE_RIBBONS` is never used: the "闪充 style energy ribbons" of brief §6 do not exist.
- **Do:**
  - **Ring:** set `top_level = true`. Every frame, place it at `GROUND.probe()` under the car,
    0.03 m along the hit normal, oriented to the normal.
  - **Ribbons:** 3 additive ImmediateMesh strips, 0.12–0.18 m wide.
    - They run on an ellipse sized from the visual AABB (rx = x/2 + 0.3, rz = z/2 + 0.3, about
      1.3 × 2.6 m) at heights of 0.3, 0.7 and 1.1 m.
    - They rise and turn 360° in 1.0 s.
    - Texture: a baked 512×64 energy texture (bright leading edge #E6FDFF, chevron dashes,
      #19E6FF tail), energy 6–8.
  - **Flash:** push the quad 2 m towards the camera in the vertex shader, so the body does not
    clip it. It peaks at 0.08 s and is gone by 0.35 s. Put the OmniLight 1.2 m above the ground,
    not at the car origin.
  - **Arcs:** see MUST-FIX 5. Use the same generator, with bolts ≤ 0.8 m from the body edges to
    the ground.
- **Verify:**
  - Drive the real sandbox ChargeStation lane at ≥ 60 km/h instead of emitting fake events
    (`fx_demo.gd:220-222`).
  - Capture `charge_side.jpg`, `charge_rear.jpg` and `charge_top.jpg` at 0.1, 0.3 and 0.6 s. The
    ring must be on the asphalt, the ribbons around the body, and a cyan light pool on the road.

### 5. Arcs are 2–6 m straight sticks in the air (lead F-INT3)
- **Evidence:** lead `captures/lead_int3_t10_0.jpg` and `_t14_0.jpg`; `r2main_t21_game.jpg`
  (sticks above a car at 252 km/h); `r2demo_t5_5_rear5.jpg`.
- **Cause:**
  - `fx_arcs.gd:89-117` joins two random points on an ellipse shell (radius up to 2.5 m, height
    up to 1.4 m), which gives chords across and above the car.
  - `DEPTH` 2 gives only 4 straight segments, and there are no branches.
  - The ribbons use `dir.cross(UP)`, so they are flat and edge-on when seen from the side.
  - `SEGMENTS`, `CHARGE_ARC_SEGMENTS` and `CHARGE_ARC_WIDTH` are never used.
- **Do (the lead's rules):**
  - Put both endpoints ON the body shell. Cache about 200 surface points, in car-local space, from
    the meshes under `get_visual_root()`. Pick B within 0.8 m of A.
  - Every vertex stays ≤ 0.15 m off the surface.
  - Use 4–5 recursion levels (16–32 segments, displacement ≤ 0.12 m) plus 1–2 branches of
    0.2–0.4 m.
  - Make the ribbon face the camera (side = dir × the direction to the camera).
  - Rebuild the arcs in the car's local space every frame.
  - Show them only while `telemetry.health_norm < 0.3`.
  - They must never span the car when it is flipped.
- **Verify:**
  - A test generates 200 bolts and asserts a bolt length ≤ 0.8 m and a distance from the cached
    surface ≤ 0.15 m.
  - With health 0.5 there are no arcs.
  - Capture `wreck_ev.jpg` at 6 m, with the car upright and on its side.

### 6. Wreck: the column cannot be seen, the fire is upside-down flat cards, and the ICE wreck has no car (r1 #8 not met)
- **Evidence:**
  - `r2demo_t23_0_q20.jpg` (EV wreck, 2 s in, 20 m): no column.
  - `r2demo_t29_5_q20.jpg` and `r2demoB_t30_5_tq8.jpg`: one orange torch 2.5 m tall, no smoke and
    no car.
  - `r2main_t24_q20.jpg`: the flames lie on the ground as flat orange triangles.
- **Causes:**
  - `fx_emitters.gd:201-212` (`_add_quad`) never sets `billboard`, so the flame quads keep the
    emitter's orientation and are flat or edge-on.
  - `bake_textures.gd:219` sets width = 1 − v × 0.85 with v = 0 at the top of the image, so the
    flame is wide at the top and pointed at the bottom: upside down.
  - The column: 80 puffs × 3.4 s with a rise of about 1.4 m/s, alpha 0.7 × the grainy atlas, and
    #2A2A2E on a #05060F–#1A1033 sky. There is no contrast, and it is only about 5 m tall.
- **Do:**
  - **Fire:**
    - Make it an UPRIGHT billboard: it faces the camera around world Y only, with a roll of
      ±10° at most. Today `fx_add.gdshader:28` gives a random 0–360° roll.
    - Flip the teardrop so the tip is at the top.
    - Life 0.5–0.9 s, rise 1.5–3 m/s, scale 0.4 → 1.0 → 0.2.
    - Colour ramp #FFF2C0 → #FFD27A → #FF7A1A → #6A2A10 at α 0, energy 4–8 (E3–E4).
    - Re-bake the flame atlas at 1024² (4×4 cells of 256 px) with 2 octaves of noise stretched
      upwards.
    - Light: #FFB04A, energy 2–5 with a noise flicker (not a sine), 1.0–1.4 m above the ground.
  - **Column:**
    - 8–12 m tall, widening from 0.8 m to 4–5 m, drifting with the wind at 1–2 m/s.
    - Life 5–6 s, rise 2.0–2.6 m/s, `scale_max` 4–5 m, 60–80 puffs, alpha ≤ 0.35 (F-INT4).
    - Colour: core #2A2A2E, lit orange from below by the fire for the first 15 % of the life
      (#FF7A1A × 0.6, ICE). The EV column is white-grey #CFD6DE.
    - It must stand out from the sky behind it: luminance ≥ 1.5× the sky, or a darker silhouette
      against lit buildings.
  - **Demo:** give the ICE victim a visible model (`res://assets/cars/npc/*.glb` or the traffic
    unit's visual). Today the fire burns on an empty road.
- **Verify:** 3 s after the wreck, capture `wreck_ice.jpg` at 8 m and 30 m, plus a side view at 90°,
  and `wreck_ev.jpg` at 20 m. The column must reach ≥ 8 m above the car, and the fire must be
  upright from every side.

### 7. Wet spray: one box under the diffuser, a popcorn look, and traffic never sprays (r1 #5 not met)
- **Evidence:**
  - `r2demo_t5_5_rear5.jpg` and `r2demo_t11_3_rear5.jpg`: white crescents coming from under the
    diffuser.
  - The worker's `spray_100kmh.jpg` is byte-identical to `drift_smoke.jpg` and `skid_5m.jpg`.
  - Main probes (25–115 rigs): no traffic car ever emits WetSpray. Traffic is kinematic
    (`ai/traffic/traffic_car.gd:132-133`) and never writes `telemetry.speed_kmh`, so fx reads
    0 km/h. The near miss also reads 0 m/s from `linear_velocity`.
- **Cause:** `fx_emitters.gd:51` uses one box, 0.7 × 0.24 m, centred between the rear wheels
  (`fx_car_rig.gd:108-121`).
- **Do:**
  - One spray emitter per rear tyre at the contact patch: the `Wheel_RL`/`Wheel_RR` x, ground +
    0.05 m, 0.25 m behind the tyre. Add one per front tyre at 30 %.
  - Shape: a fan 25° wide and 10–20° up. Velocity = 0.35–0.5 × the car speed backwards plus
    1–3 m/s up, in world space (not `inherit` alone).
  - Life 0.5–0.9 s, which gives a tail 3–8 m long at 100 km/h.
  - Mist puffs 0.25 → 1.2 m, alpha ≤ 0.22, with the soft look of MUST-FIX 1.
  - On top: 40–80 droplet streaks, velocity-stretched to 2–4 × 10–25 cm, #D9E8FF, catching the
    light.
  - For cars that do not drive their own telemetry, take the speed from the position delta of each
    physics tick.
- **Verify:**
  - Your own frames `spray_100kmh_rear.jpg` and `spray_100kmh_side.jpg`, side by side with
    `ref/art/img/cp04_nfs2015_wet_night.jpg`.
  - A probe in main: traffic within 60 m and above 30 km/h shows WetSpray.

### 8. Impact sparks and debris: wrong ground, detached at speed, stale takedown point (r1 #9 not met)
- **Evidence:**
  - `r2demo_t13_05_side6.jpg`: the hit burst hangs about 6 m behind a car doing 250 km/h.
  - `r2demo_t17_3_rear5.jpg` and `r2main_t18_2_rear5.jpg`: a symmetric radial "firework" star.
  - Probe at t = 24.95: `cached contact … 42.6 m from the car`. The takedown burst goes off screen;
    `r2demo_t25_1_front7.jpg` shows none.
- **Causes:**
  - `fx_impact_fx.gd:47-50` passes no ground, so sparks bounce at y = 0.0. The decks are 8–12 m
    up, so sparks fall through them.
  - The scrape uses a ground of 0.0 (`fx_spark_pool.gd:101`), and the takedown uses the player's
    ground (`fx_director.gd:259-260`).
  - Sparks get none of the car's velocity.
  - The spread is a uniform sphere (`fx_spark_pool.gd:87-88`).
  - `fx_rig_manager.gd:124-127` caches a world-space point with no timestamp.
- **Do:**
  - Make one `GROUND.height()` raycast per burst at the burst point and pass the result to every
    spark and debris piece.
  - Add 0.8 × the car velocity to impact sparks and debris.
  - Throw the burst in a 60–90° cone around reflect(v_rel, n), along the surface.
  - Cache the contact in the victim's local space with a timestamp. Use it only if it is less than
    0.5 s old; otherwise use the victim's side that faces the attacker, at 0.6 m.
- **Verify:**
  - A test: after a burst on a deck at y = 10 m, no live spark is below 9.9 m 0.2 s later.
  - `hit_sparks.jpg` at 250 km/h: the sparks stay within 1.5 m of the car.
  - `takedown.jpg`: the burst is on the victim and oversized in slow motion.

### 9. Near miss, N₂ ignition and arch glow
- **Near miss:** it cannot be seen in `r2demo_t9_05_rear5.jpg` or in the worker's `near_miss.jpg`.
  - Cause: `fx_spark_pool.gd:105-117` draws the AIR and VAPOUR kinds with the spark material: the
    orange tail of `spark_streak.png` × energy 20 × 0.9 or 0.35. That makes a hot orange streak,
    not cold air or N₂.
  - Fix: a separate material with a soft white 16×256 px streak (no orange), additive, energy
    1.2–2.0, #D9E8FF.
  - Show 2–4 ribbons along the passing car's side at a height of 0.5–1.1 m. Length = relative
    speed × 0.12 s (3–8 m), life 0.35 s.
  - The ribbons move with the player, and the relative speed comes from position deltas (see
    MUST-FIX 7).
- **N₂ ignition:**
  - 6–10 soft white puffs: the MUST-FIX 1 material, 0.4 → 1.4 m, alpha 0.3, 0.6 s.
  - A white shock ring (`fx_ring.gdshader`) lasting 0.15 s at `Nozzle_R1..R4`.
- **Arch glow:** `fx_arch_glow.gd:24-33` never positions the two OmniLights, so both sit at the car
  centre (range 0.8 m, inside the body). Put the lights and the cards at the `Wheel_RL`/`Wheel_RR`
  markers, 0.1 m outward and 0.15 m up.
- **Verify:**
  - `near_miss.jpg` from a real traffic pass;
  - `n2_ignition.jpg` at 0.05 s and 0.2 s;
  - `n2_arch_side.jpg` at 4 m, with cyan light visible on the tyre sidewall and the arch lip.

### 10. Emitter cap and budget accounting (r1 #2 and #11c)
- **Problems:**
  - `TUNE.MAX_ACTIVE_EMITTERS` (8, gameplay DOSSIER §7.7) is declared and never used.
  - The probe in main at t = 24 printed `worst=24756`, over the 20,000 budget, with 115 rigs.
    Emitters are never freed when a rig goes OFF.
  - The budget test leaves out the fx_thrusters particles.
- **Do:**
  - The rig manager grants at most 8 smoke and fire emitters, nearest first.
  - Count the spray separately and cap it at 12 REDUCED cars.
  - Free or pool the emitters of OFF rigs.
  - `worst_case_count()` = rain + pools + player + 3 FULL + 20 REDUCED + the thruster system (the
    sum of its GPUParticles3D amounts).
- **Verify:**
  - A test with 12 wrecked cars inside 60 m gives `active_emitter_count() == 8`.
  - The worst case, thrusters included, is printed and is ≤ 20,000.

### 11. Demo and evidence (r1 #10 not met)
- **The same frame was reused for different claims** (identical md5):
  - `drift_smoke.jpg` = `skid_5m.jpg` = `spray_100kmh.jpg` = `fx_chase_t2_45.jpg`;
  - `rain_200kmh.jpg` = `fx_chase_t11_4.jpg`.
- **Claims that are not in the images:**
  - `hit_sparks.jpg` has no sparks;
  - `near_miss.jpg` shows nothing;
  - `wreck_ev.jpg` has no column;
  - `compare_smoke.jpg` and `compare_spray.jpg` show no smoke or spray in either half.
- **Demo bugs:**
  - `fx_demo.gd:127-145` never stores the rail in `_barrier`, so the rail stays far away and the
    "scrape" grinds on air.
  - The scrape emits `other = null`, so the scrape path (`fx_car_rig.gd:289,303`) never runs.
  - The rail is an untextured grey StandardMaterial3D (ART.md §5).
  - After `STOP_AT` the demo holds `brake`, which means reverse, so the "wrecked" car drives
    backwards at 40 km/h.
  - The traffic car cannot be seen.
- **Do:**
  - Make one capture per claim, and look at it before you claim it.
  - Scrape along a textured rail, passing the rail as `other`.
  - Stop the car with zero input plus `freeze`.
  - Give the NPC car a visible model.
  - Use the real ChargeStation lane.
- **Lead rule:** the worker ran `( tools/godot.sh test … ) & sleep 300`. Never start Godot in the
  background; always wait for the run in the foreground.
- **Verify:** `status/fx.md` lists every capture with one line on what can be seen in it.

## SHOULD-FIX
1. **Dead code and shadowed constants.** Keep one source of truth: use the TUNE constants.
   - Unused in `fx_car_rig.gd`: `_last_contact`, `_sliding`, `_contact_normal`.
   - Unused functions: `EMITTERS.vapour()`, `LightPool.set_flicker()` and `clear_light()`,
     `PALETTE.hot()`.
   - Unused constants: `SEGMENTS` (`fx_arcs.gd`), `CHARGE_ARC_SEGMENTS`, `CHARGE_ARC_WIDTH`.
   - Unused `seed_value` parameters.
   - Duplicated constants: `SKID_MAX_QUADS` vs `MAX_QUADS`, `SPARK_MAX` vs `MAX_SPARKS`,
     `DEBRIS_GLASS/PLASTIC` vs `MAX_GLASS/PLASTIC`.
   - Shadowed: `SPLASH_GRID` and `SPLASH_PROBE_INTERVAL` are hidden by local values (8, 0.5).
2. **Wrong arguments.**
   - `fx_impact_fx.gd:50` passes `DEBRIS_SPEED` (8.0) as the plastic COUNT.
   - `fx_director.gd:260` passes 14.0 to an int parameter.
   - `fx_emitters.gd:171` `_base(lifetime, amount_ratio)` receives 26.0, 18.0, 24.0, 22.0 and 20.0
     (the old amounts). Remove the parameter.
3. **Static typing.**
   - `_rigs`, `_vehicles` and `_contacts` should be typed dictionaries.
   - `var rig: Node` with dynamic `set_wet`, `on_collision` and `set_tier` calls should use `CarRig`.
   - The pools typed as `Node` should use their preload types.
4. **Reconnection error.** `fx_car_rig.gd:59` connects `tree_exiting` on every `setup()`. The reuse
   path in `fx_rig_manager.gd:41-51` calls `setup()` again when a car is re-added, which gives an
   "already connected" error. Guard the call with `is_connected`.
5. **Debris.** There is one shard shape and one chip shape (r1 asked for 3–4). The limits from
   `set_quality()` are never used by `_spawn()`.
6. **Duplicates.** `_ramp()` exists in both `fx_rain.gd` and `fx_emitters.gd`. There are three ground
   probes: the director (fallback 0.0), `fx_charge.gd` (fallback −0.6) and `fx_ground.gd`.
7. **Rain streaks** share one axis (`fx_rain.gdshader:17-23`). At speed they should converge on the
   vanishing point: compute the axis per particle from its view-space position.
8. **Magic numbers still in logic.**
   - `fx_emitters.gd`: box extents, damping, scales.
   - `fx_rain.gd`: 0.12, −6.0, 9.0.
   - `fx_charge.gd`: 2.6, 0.9, 14.0, 1.3, 2.6, 1.5, 0.35.
   - `fx_spark_pool.gd`: 8, 0.03, 0.06, 0.12, 0.3, 10, 2.2.
   - `fx_car_rig.gd`: 0.12, 0.08, 0.06, 0.5, 25.0, 0.25, 1800.0.
9. **Tests.**
   - "A near miss throws a streak" and "a takedown throws glass and plastic" pass on the
     particles left over from the previous hit. Clear the pools first.
   - `_probe_ground` runs in `_process`, but `fx_ground.gd` says it must be called from a physics
     callback.
10. **Flame bake.** `bake_textures.gd:213` `cell := cy * FLAME_CELL + cx` should use `FLAME_CELLS`.
11. **Performance.** There are still no fps numbers with and without fx (r1 SHOULD-FIX 9).

## Verified OK
- **Check:** `tools/godot.sh check --only=res://fx/` → `CHECK 44 files, 0 failed, 0 engine errors,
  0 warnings`. The wrapper's exit code 2 came from `tools/godot.sh` being rewritten mid-run, not
  from fx.
- **Tests:** `tools/godot.sh test res://fx/tests/test_fx.gd` → 35 PASS, `FX TESTS OK (0 failures)`,
  with no errors or warnings in the log.
- **r1 #1:** idle and OFF rigs run no emitter, and the wreck smoke starts only on `vehicle_wrecked`.
- **r1 #2 tiers:** cars at 10, 30 and 59 m are FULL, at 61 and 120 m REDUCED, at 151 m OFF.
  `amount_ratio` replaces `amount`.
- **Lead F-INT1:** the rain emitters are built in `_ready()` and guarded. The ribbon uses
  `clear_surfaces()` + `add_surface_from_arrays()`. There are 0 errors in the demo run and none
  from `res://fx/` in main.
- **Lead F-INT2 logic:** no smoke below 10 km/h, density = max(slip, brake) × speed ≤ 0.8, life
  1.4 s. The reversing case is MUST-FIX 2.
- **Skid ribbon geometry:**
  - strips 0.241 m wide with shared edges;
  - a 0.6 m step;
  - height and normal from a raycast;
  - FULL tier only;
  - 86 quads for the 0.9 s demo drift.
- **Rain:**
  - `RAIN_MAX` is fixed at 6000 and faded in with `amount_ratio`;
  - it switches off with the `rain` feature;
  - the streak shader stretches with the relative speed.
- **Sparks:**
  - the streak texture is 32×256, with a white head and an amber tail;
  - E5 energy 20, life 0.28 s;
  - an impact light from a pool;
  - a surface offset of 0.03 m.
- **Demo:** sandbox + the environment unit + the real Roadster on `SH_wet_asphalt`, with the rain on.
- **N₂ trail split:** the trail belongs to fx_thrusters (JetVapour ×4 emitting during the boost),
  and fx no longer doubles it.
- **Ownership:** Write and Edit were used only in `game/fx/**` (never `thrusters/`) and
  `status/fx.md`. Bash wrote only in `game/fx`, `captures/fx` and `tmp/fx`. Files are ≤ 400
  lines; the largest is `fx_car_rig.gd` at 388.
- **Live budgets:** 2.1k–5.1k particles in the demo and in main, thruster vapour included. There
  are 0 Decal nodes.

## Evidence
- **Logs:** `tmp/review/fx/r2_check.log` and `r2_test.log`.
- **Probe:** `tmp/review/fx/r2_probe.gd`, a SceneTree probe. It prints the emitting systems, the
  fx counters, the splash emission texture, the cached contact and the skid quad widths. Run it
  through the slot wrapper:
  `python3 tools/slots.py heavy 4 -- godot --path game --windowed --resolution 1600x900 -s
  <abs>/tmp/review/fx/r2_probe.gd -- --scene=res://fx/demo/fx_demo.tscn --quality=high --mark=2.0
  --shots=…`
- **Demo run** (`tmp/review/fx/r2_demo.log`, `r2_demoB.log`, `r2_demoC.log`):
  - t=2.2: drift at 98 km/h, slip 0.91. TyreSmoke, WetSpray, Droplets and rain: 2,096 particles;
    skids 39.
  - t=5.15: JetVapour ×4 + WetSpray + rain: 4,550 particles.
  - t=13.05: sparks 70, debris 18. t=17.3: sparks 220, the pool is full.
  - t=23–30: the car reverses at 40 km/h with TyreSmoke on; skids grow from 92 to 348.
  - Every report prints `splash emission_point_count=1 tex=(8, 8) fmt=5`.
  - t=24.95: `cached contact (-412.8, 1.05, -1175.6), 42.6 m from the car`.
  - Skid quads: `[0.0, 0.241, 0.79], [0.241, 0.241, 0.61], …` (edge widths and length in metres).
  - 0 errors.
- **Main run** (`--scene=res://main.tscn --skip-menu --rain --quality=high`, `tmp/review/fx/r2_main.log`):
  - rigs grow from 25 to 115, with 3,786–4,416 live particles;
  - `worst=24756` at t=24, and `active_smoke_fire` ≤ 5;
  - no traffic car emits WetSpray.
  - Errors: 724 renderer "material is null", and 261 from `world_builder.gd:164` →
    `asset_library.gd:221`. None come from `res://fx/`.
- **Skid width:** in `r2demoB_t3_2_top3.jpg` the dark runs are 16–19 px at 250 px/m, minimum 0.
- **Worker captures:** checked with md5 for duplicates, then reviewed as sheets:
  `captures/review/fx/r2_worker_A.jpg`, `r2_worker_B.jpg`, `r2_worker_C.jpg`.
- **Reviewer sheets** (in `captures/review/fx/`):
  - `r2_sheet_drift.jpg`: smoke at 5 m, skids at 20 m and from low at 5 m;
  - `r2_sheet_charge.jpg`: charge, near miss, N₂;
  - `r2_sheet_crash.jpg`: hit, scrape, EV and ICE wrecks;
  - `r2_sheet_main.jpg`: takedown and the main scene;
  - `r2_sheet_detail.jpg`: smoke at 20 m, skids from 3 m, splash clump, charge from 8 m, fire at 8 m;
  - `r2_compare_ref.jpg`: compared against `cp04_nfs2015_wet_night.jpg` and `sh07_nanjing_rd_neon_rain.jpg`.

## Notes for the lead (not the fx worker's fault)
- In main with `--skip-menu`, the player started at y = 608 m and fell at 414 km/h until t ≈ 18 s,
  so a drift could not be tested in main (vehicle or world unit).
- Traffic cars never fill `telemetry.speed_kmh`. Either the traffic unit should write it, or fx
  keeps its position-delta fallback (MUST-FIX 7).
- Brief §5 still says to use `global_shader_parameter_get`. fx correctly reads the `weather` group.
