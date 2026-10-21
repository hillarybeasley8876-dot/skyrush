# fx review round 1 — VERDICT: FAIL

Reviewer: strict review + art direction, 2026-10-19. No `reviews/fx-lead.md` exists yet; the lead's
project-wide rules in `reviews/environment-lead.md` apply to every unit (MUST-FIX 11).
User requirement: 贴图纹理什么都要细化 (refined textures and detail everywhere).

## Scores (0-10): function 3, visual 2, code 5
- function 3: the plumbing exists (director, pools, events, thruster attach, 50-car test). But every car
  emits wreck smoke and fire from spawn. The distance tiers are wrong, the skid pool overflows in under
  2 s, the demo car falls off its stage, the budget is blown in the real game, and the rain test is vacuous.
- visual 2: smoke, vapour and wreck smoke render as identical round "soap bubbles"; skid marks are
  flat light-grey stripes; arcs are hard vector lines; fire does not glow; the demo is a black void
  with a box car. Not believable in any capture.
- code 5: files ≤ 400 lines, mostly typed, clear structure. But there are many magic numbers,
  duplicated helpers, dynamic `Node` calls, and the test breaks the `extends Node` rule.

## MUST-FIX

### 1. Every car emits wreck smoke + fire from spawn; far cars emit all 5 emitters (state bug)
- Why: `GPUParticles3D.new()` defaults to `emitting = true`. `fx_emitters.gd` never sets it false.
  In `fx_car_rig.gd`, `var tier := TIER_OFF` (l.22), so `set_tier(TIER_OFF)` returns early (l.153)
  and `_stop_all()` never runs. `_wreck()` returns early while not wrecked (l.234), so
  `WreckSmoke`/`WreckFire` are never switched off.
- Evidence: main scene at t=10, player `wrecked=false`, yet `PlayerCar/FxRig/WreckSmoke amount=52` and
  `WreckFire amount=33` are emitting. 35 rigs emit wreck smoke + fire. 32 traffic rigs 200–600 m
  away also emit TyreSmoke + WetSpray + BoostVapour. 168 particle systems are live with nothing happening.
  This is the grey column with orange dots above the parked Roadster on the title screen
  (`captures/review/fx/r1_mainA_t14_0.jpg`) and above both demo cars at t=0.5 (`r1_demo_t0_5_game.jpg`).
- Do: set `emitting = false` in every factory function and in `_build()`. Start `tier` at `-1` (or
  apply the tier and `_stop_all()` inside `setup()`) so the first `set_tier()` always applies. In
  `_wreck()`, drive the wreck emitters explicitly from `_wrecked`. OFF-tier rigs must run zero systems.
- Verify: new test, i.e. spawn a car, wait 3 frames, and assert no `GPUParticles3D` under `FxRig` is
  emitting. Repeat with a car 200 m away. Then emit `vehicle_wrecked` and assert the smoke is on. In the
  main scene with no drift/boost/wreck, print the emitting systems: only the rain may be listed.

### 2. Distance tiers do not follow the brief; amounts restart the emitters
- Brief §1: "full effects for the player + 3 nearest cars, reduced beyond 60 m, none beyond 150 m".
  `fx_director.gd:159-172` has no 60 m threshold, so the 3 nearest get FULL even at 140 m. The player sits
  inside `rank < NEAR_CARS`, so only 2 other cars get FULL.
- Do: FULL = the player, or one of the 3 nearest NON-player cars when ≤ 60 m. REDUCED = ≤ 150 m.
  OFF beyond that. Add named consts `FULL_RANGE := 60.0` and `OFF_RANGE := 150.0`. Cap simultaneously
  active smoke/fire emitters at 8 (gameplay DOSSIER §7.7: "≤ 8 active smoke/fire emitters, ≤ 64
  particles each").
- Do: scale by tier/quality/intensity with `amount_ratio`, not `amount`. Writing `amount` reallocates
  and restarts the system: you get visible pops on tier changes, and rain vanishes while the weather fades.
- Verify: a unit test places cars at 10/30/59/61/120/151 m and asserts FULL/FULL/FULL/REDUCED/REDUCED/OFF
  (the 4th-nearest at 30 m is REDUCED).

### 3. Skid marks: the pool overflows in 1.7 s, quads instead of a ribbon, no texture, lighter than the road
- `_drive()` adds a segment every 120 Hz physics tick per wheel (`fx_car_rig.gd:214-217`), i.e. 240
  segments/s. The 400-segment ring is full after 1.9 s of ONE drift (demo probe: skids=240 at t=2.0,
  400 at t=2.9), so the 20 s fade never shows. In the main game, traffic cars had filled the pool
  (400 live at t=10) before the player had drifted at all.
- Each segment is an independent PlaneMesh quad (`fx_skid_pool.gd:54-71`). That gives saw-tooth gaps on
  the outside of curves and double-dark overlaps on the inside (α0.6 over α0.6 = 0.84).
- `fx_skid.gdshader` is a flat colour, with no texture. It is lit with ROUGHNESS 0.42 / SPECULAR 0.55
  over a glossy road, so the marks read as LIGHTER grey stripes, like lane lines
  (`r1_demo_t2_0_rear5.jpg`, `r1_demo_t2_9_high20.jpg`).
- Always horizontal (`delta.y = 0`, `up = Vector3.UP`) at wheel centre − 0.34 m, so marks cut into or
  float above ramps, the spiral ramp and banked decks.
- Do:
  - Add a ribbon point only after ≥ 0.6 m of travel per wheel.
  - Build real ribbons: one strip per wheel in an ArrayMesh/ImmediateMesh where consecutive quads share
    edge vertices (art DOSSIER §6.2: "runtime ArrayMesh ribbon … drift = long arcs"). Start a new strip
    when the wheel lifts or the slip ends.
  - Raycast (layer 1) at each contact point for height + normal; lift 0.01 m along the normal.
  - Only the player and FULL-tier cars write marks.
  - Texture: procedural tyre track 256×1024, i.e. 6–8 tread grooves, darker edges, fbm breakup,
    feathered 15 % edges, U = accumulated metres / 1.2.
  - Shader: `blend_mul`, or ALBEDO = mix(vec3(1.0), rubber, a), so a mark always DARKENS the road and
    its wet reflections. Fade in and out at strip ends.
  - Keep #151515 α0.6, the 20 s fade and ≤ 400 segments.
- Verify: test that a 3 s drift at 60 km/h uses ≤ 200 segments and every one is still live after 10 s.
  Captures `captures/fx/skid_5m.jpg` + `skid_top_20m.jpg` on `SH_wet_asphalt` showing continuous dark
  arcs with tread detail.

### 4. Every particle texture is a 64–128 px smooth gradient: no detail (贴图纹理什么都要细化)
- `fx_textures.gd`: `blob()` 64², `ring()` 128², `streak()` 16×64 and `glow()` 64², all noise-free.
  Every puff has one size (`scale_min == scale_max`). There is no rotation, because the billboard in
  `fx_soft.gdshader` ignores `INSTANCE_CUSTOM.x`. Result: tyre smoke, vapour and wreck smoke are round
  "bokeh/soap bubbles" (`r1_demo_t2_0_rear5.jpg`, worker `demo_t1_6.jpg`).
  `r1_compare_cp04_s.jpg` sets them beside `cp04_nfs2015_wet_night.jpg`: no resemblance.
- Do (smoke/vapour/mist):
  - Bake a seeded procedural atlas with FastNoiseLite: fbm + cellular billows, soft edge mask,
    alpha erosion. Use a 4×4 flipbook at 1024² (256 px cells) or 8×8 at 2048².
  - Bake a fake normal from the noise gradient so lit smoke has volume. Save to `game/fx/textures/` with
    a bake script under `game/fx/tools/` (do not generate 2K images per run in GDScript).
- Do (ParticleProcessMaterial): `angle_min/max` ±180, `angular_velocity` ±25 °/s, scale 0.7–1.6,
  random `anim_offset` + `anim_speed`, turbulence on (strength 0.6–1.2, noise scale 2–4 m).
- Do (`fx_soft.gdshader`): rotate by `INSTANCE_CUSTOM.x` like BaseMaterial3D BILLBOARD_PARTICLES. Add
  `MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);`: it is missing, so lit puffs shade with the quad's
  world +Z normal and lighting changes with camera yaw. Read the flipbook frame from
  `INSTANCE_CUSTOM.z`, and add a wrap/back-light term for translucency.
- Do (sparks): a dedicated 32×256 streak texture with a white-hot head and a fading orange tail, instead
  of the round `glow()` stretched into a "rice grain".
- Do (debris): 3–4 irregular shard meshes for glass (jittered triangles, 2–6 cm) with a fresnel glint,
  and chips for plastic instead of the crossed "+" quads. Shrink over the last 0.3 s instead of popping out.
- Verify: captures at 5 m and 20 m of drift smoke, N₂ vapour and the wreck column. Save
  `captures/fx/compare_smoke.jpg` side by side with a real night drift-smoke photo kept in
  `captures/fx/ref/`.

### 5. The wet road is the normal case, but the wet tyre effect is just recoloured smoke, with no speed spray
- The environment's default `skyrush_wetness` is 0.85, so the main game is always wet and players never
  see dry smoke. `set_wet()` only recolours the puff to #AFC4D0, which keeps the same slow rising
  behaviour. Droplets only appear while sliding (`fx_car_rig.gd:209`). Brief §5: "spray from tyres
  when skyrush_wetness > 0.5".
- Do: build a separate wet-spray system per rear contact patch (lighter at the fronts).
  - Shape: a low, wide, backward fan of fine mist (rooster tail, 0.3–0.9 m high, 3–8 m long at 100 km/h).
  - Trigger: emit whenever grounded on a wet road above 30 km/h; `amount_ratio` ∝ speed (full at
    150 km/h); life 0.5–0.9 s; inherit 30–60 % of the car velocity; cool tint lit by the neon.
  - Add droplets with gravity on top, and a dense mist cloud in a wet drift.
- Do: smoke, spray and droplets stop when `airborne` or `grounded_wheels < 2`. Today the smoke keeps
  emitting in mid-air while braking (demo probe: TyreSmoke emitting at y = −105 m, t=9.4).
- Do: emit from each rear contact patch (`Wheel_RL/RR` minus radius), not from one 1.56 m box under
  the axle centre. Use the markers of the real car, not `REAR_AXLE_FALLBACK`.
- Verify: chase-cam capture `captures/fx/spray_100kmh.jpg` on the wet road, side by side with
  `ref/art/img/cp04_nfs2015_wet_night.jpg` (`compare_spray.jpg`).

### 6. Rain: budget cap, streak orientation, floating splash rings, per-frame restarts
- a) `amount = int(6000 × rain × quality)` reaches 7,800 on ultra with `skyrush_rain` 1.0
  (`fx_rain.gd:162`). Clamp to `MAX_RAIN`; the brief limit is ≤ 6k.
- b) A StandardMaterial3D with BILLBOARD_PARTICLES overrides `particle_flag_align_y`, so the streaks
  are always screen-vertical and never stretch with speed.
  - Write a rain shader: axis = (rain velocity − camera velocity), quad faces the camera around that
    axis, and length grows with the relative speed. At 200 km/h the streaks should rush at the camera.
  - Offset the emission box ahead of the camera by camera velocity × 0.4 s.
- c) Splash rings are launched UP at 0.6–1.6 m/s with gravity −4, so they float up to 0.32 m above
  the road and then sink through it. Replace them with two parts:
  - a flat expanding ripple (2 concentric rings, ≥ 512 px texture, 0.05 → 0.35 m in 0.4 s, no velocity);
  - a tiny crown splash (3–6 droplet streaks, 3–6 cm high, catching light; sh07_nanjing_rd_neon_rain.jpg).
- d) The director calls `set_intensity()` every frame and `_apply()` rewrites `amount`; use
  `amount_ratio` (see 2).
- e) The 26 m splash box at the camera's ground height hangs rings in the air beyond deck edges.
  Spawn only where a raycast grid (e.g. 8×8 rays every 0.25 s) found ground, using
  `EMISSION_SHAPE_POINTS` (emission point texture).
- Verify: a test asserts streaks ≤ 6000 at ultra with rain 1.0. Captures `rain_0kmh.jpg` +
  `rain_200kmh.jpg` (chase cam, on the elevated deck).

### 7. 闪充 charge flash: no bloom, arcs inside the car, hard-edged lines, blurry ring
- a) The "bloom flash" is a Sprite3D with billboard OFF (edge-on from the side) and an LDR white
  modulate, which cannot pass glow threshold 1.1. There is no E4 bloom and it is not even cyan. Use an
  additive HDR billboard (`fx_add` at energy 8–12 = E4, #19E6FF) plus the OmniLight.
- b) Arcs sit on a circle of r 1.1–1.9 m and ribbons at r 1.45 m around the car origin. The Roadster is
  4.38 × 1.98 m, so many arcs are inside the body and the ribbons pass through the nose and tail.
  Generate them from the car's visual AABB (`get_visual_root()`): arcs jump from body edges to the
  ground or charging rails; ribbons follow an ellipse with rx ≈ 1.3 and rz ≈ 2.6.
- c) Arcs are untextured flat quads (`use_texture` false), i.e. vector lines. Give them:
  - a glow-falloff profile (white #FFFFFF core → #19E6FF halo);
  - recursive midpoint displacement with 1–2 short branches;
  - per-frame flicker in width and brightness.
- d) The ground ring is a 128 px texture scaled to 6.5 m. Draw it analytically in a shader (SDF ring,
  segmented tick marks, scrolling energy) or with a ≥ 1024 px texture.
- Verify: drive through the sandbox's real flash-charge lane (ChargeStation). Captures `charge_side.jpg`
  and `charge_rear.jpg` at 6 m, where the bloom and the 1.0 s timing must be visible.

### 8. N₂ vapour, wheel-arch glow, near miss and wreck do not read
- N₂ vapour: 48 round 0.9 m blobs, 0.6 s, in world space, so at speed it becomes a "string of pearls"
  (`r1_demo_t6_5_rear5.jpg`, worker `demo_t6_2.jpg`).
  - Make it a continuous streak from `Nozzle_R1..R4`: velocity-stretched quads, or trails
    (≤ 4,000 particles with trails, tech GODOT.md §3.2). Blue-white #CFE8FF, 8–15 m long at 300 km/h.
  - The fx_thrusters unit already emits rear JetVapour (dossier §5.5 vapour trail). Agree the split
    with them and write it in `status/fx.md`: no doubling.
- Wheel-arch glow is a 1.4 m camera-facing cyan disc (64 px × `pixel_size` 0.022) floating over the
  rear wheels (`r1_probe_main_sheet_s.jpg`, bottom-right).
  - Replace it with a small OmniLight3D per arch (range 0.8 m, #19E6FF, energy ~2) plus an additive card
    aligned with the wheel and occluded by the body.
  - Ramp with `delta`: `move_toward(…, 0.08)` per tick is frame-rate dependent.
- N₂ ignition throws 14 ORANGE sparks (`fx_director.gd:293-297`). Cold gas means "No fire, no
  smoke-black" (dossier §5.5); use a white vapour puff / shock ring instead.
- Near miss: 3 orange spark quads with gravity (`spark_pool.streak`), invisible in every capture. Make a
  dedicated wind streak: 2–4 thin #D9E8FF additive ribbons along the passing car's side, no gravity,
  0.35 s, length ∝ relative speed.
- Wreck fire uses the LIT soft shader with emission 0 (`fx_emitters.gd:212`), so it shows as dull
  orange dots.
  - Fire must be additive/emissive E3–E4 with a flame flipbook or noise mask: #FFD27A core → #FF7A1A
    → smoke, 60 particles (dossier §7.4), plus a flickering OmniLight (#FFB04A, range 5 m).
  - Smoke column: dense, 8–12 m tall, widening, drifting with wind, dark core #2A2A2E.
- EV arcs call `spark_pool.arc()`, which draws ORANGE spark quads (`PALETTE.ARC` is never used). Reuse
  the charge-arc generator with #CCEDFF jagged arcs jumping across the body, plus white smoke.
- Verify: `n2_6m.jpg`, `near_miss.jpg` (a real traffic pass at speed), `wreck_ice.jpg` (traffic car)
  and `wreck_ev.jpg` (player).

### 9. Sparks and debris physics
- a) Scrape sparks (`fx_car_rig.gd:315-319`) fly along the wall normal. Real grinding sparks trail
  BEHIND the contact: v = −car_velocity × 0.3–0.7 + normal × 1–2 m/s + up 0–2 m/s, rate ∝ speed.
- b) One global ground height under the PLAYER serves every spark and shard (`fx_director.gd:221-230`).
  A crash on another deck bounces in mid-air or falls through. Raycast at the burst point and keep the
  ground y per particle.
- c) The takedown burst starts at the victim centre + 0.6 m with normal UP, i.e. a fountain from the
  roof. Use the last contact point and normal on the victim (cache them from `vehicle_collided`).
- d) Big hits get a pooled impact light: orange-white, 0.12 s, range 5 m.
- Verify: `scrape.jpg` along the sandbox deck barrier at 120 km/h; `takedown.jpg` in slow-mo.

### 10. The demo is not in the sandbox, uses a box although the real car exists, and the car falls off
- `fx_demo.gd` builds a 120 m void plane. The car reaches 85 km/h and leaves the plane at about 4.3 s.
  Probe: y = −0.87 m at 4.55 s, −24.6 m at 6.5 s, −161 m at 10.95 s. So the charge, N₂, wreck,
  near-miss and takedown beats were all filmed on a box falling through black space (worker
  `demo_t6_2` … `demo_t10_9`).
- The road is an untextured StandardMaterial3D (ART.md §5 violation) and the neon tubes lie on the road.
- Brief §8 says "in the sandbox". Build the demo from:
  - `res://core/sandbox/sandbox.tscn` (the core's "tuning ground for vehicles/AI/FX");
  - `res://world/env/environment.tscn` plus `SH_wet_asphalt` on any added road;
  - the real `res://vehicle/player_car.tscn` (roadster.glb exists);
  - real NPC/traffic cars.
- Drive the car along the circuit. Use the flash-charge lane, the deck barriers (scrape) and the parked
  cars (hits, near miss). Shoot each beat with a chase cam plus 5 m / 20 m close-ups into `captures/fx/`.
- The worker's `main_t3_0.jpg` is the LOADING screen at 0 %, not "the real game with the fx director
  running". Use `--skip-menu` and t ≥ 12 s.
- Several report claims are not in the images: `demo_t9_1` shows no smoke column, `demo_t9_85` no
  streak, `demo_t10_9` no oversized sparks. Look at every capture before claiming it.

### 11. The rain test is vacuous, the budget test proves nothing, and the test style breaks the lead rule
- a) `tests/test_fx.gd` uses `extends SceneTree` with Variant-typed cars. The lead's project-wide rule
  (`reviews/environment-lead.md`) and CONTRACTS.md §3 require `extends Node` tests run by
  `test_host.gd`, statically typed (`VehicleBase`, `CarTelemetry`).
- b) `_test_rain` sets the `skyrush_rain` global, which the director never reads. `billboard_count()`
  returns `amount` (≥ 1 even when off), so "rain is on" passes with rain OFF, and "switches off" passes
  because the rain was never on. Add a stub `weather` node, as the demo does, and assert
  `is_emitting()` both ways.
- c) The budget test measures 1 car with rain off (386). The real game reached fx-owned 10,902–12,442
  and 25,242–26,902 particles in total, including the thruster JetVapour (5 × 3,200).
  - `billboard_count()` must count emitting systems (report both live and worst case).
  - Test the worst case: rain 1.0 on ultra + player + 3 FULL + 20 REDUCED cars + the thruster system
    ≤ 20,000.
- d) Add the tests named in items 1, 2, 3 and 6.

## SHOULD-FIX
1. **Magic numbers in logic.** Float literals in function bodies: `fx_car_rig.gd` 77, `fx_spark_pool.gd` 67,
   `fx_debris_pool.gd` 78, `fx_charge.gd` 68, `fx_rain.gd` 84, `fx_emitters.gd` 139. Move the tuning
   into named consts or a typed `fx_tuning.gd` (one block per effect); logic keeps only 0/1.
2. **Duplicated code.**
   - `_recolour_smoke` and `_recolour_wreck_smoke` are identical (`fx_car_rig.gd:93-105` / `347-359`).
   - `_ramp()` exists in both `fx_rain.gd` and `fx_emitters.gd`.
   - The ground probe is written 3 times with 3 different NaN fallbacks (director 0.0, rain 0.03,
     charge y − 0.6). Make one helper, e.g. `fx_ground.gd`.
3. **Static typing.** `_rigs: Dictionary` → `Dictionary[int, CarRig]`. `var rig: Node` + a dynamic
   `rig.set_tier()` → type with the preload const `CarRig`. `_skid_pool/_spark_pool/_debris_pool: Node`
   → typed. `_find_vehicles() -> Array` → `Array[VehicleBase]`.
4. **Rig lifecycle.** `tree_exiting` drops the dictionary entry but leaves the `FxRig` child on the
   car. If any unit ever re-adds a car (pooling), `_attach_vehicle` builds a second rig. Reuse an
   existing `FxRig` child, or free it on exit.
5. **Emitters per car.** Every VehicleBase gets 5 GPUParticles3D + 2 Sprite3D (42 rigs = 210 systems at
   t=10; the traffic budget is 70 cars). Create emitters lazily for FULL/REDUCED and return them to a
   director pool on OFF.
6. **Quality scaling.** The spark, debris and skid pools (220/168/400) are not quality-scaled, so `low`
   gets the same pools as `ultra`.
7. **Spark offset.** Sparks spawn 0.25 m off the surface (`fx_car_rig.gd:307`), leaving a visible gap.
   Use 0.03 m plus depth-fade.
8. **Weather defaults.** `_wetness` defaults to 0.85 even without a weather node; say so in the doc
   comment, or default to dry.
9. **Performance numbers.** Report frame time with/without fx (`--stub=fx`) in the sandbox at fixed
   settings. My comparison was inconclusive (10 vs 8 fps; the machine was saturated by other jobs).

## Verified OK
- `tools/godot.sh check --only=res://fx/` → `CHECK 32 files, 0 failed, 0 engine errors, 0 warnings`.
- `tools/godot.sh test res://fx/tests/test_fx.gd` → 16/16 PASS, `FX TESTS OK`. The 50-car
  spawn/free leaves no rigs and no errors (the acceptance item), and the thruster system is attached
  (`attached_count() > 0`) and re-attached on a player change.
- Ownership: the worker's log shows Write/Edit only under `game/fx/**` (never `game/fx/thrusters/`)
  and `status/fx.md`. The scratch `_probe.gd` / `fx_probe.*` files were deleted.
- Files ≤ 400 lines (largest: `fx_car_rig.gd` 374).
- Weather source: `RenderingServer.global_shader_parameter_get()` is editor-only at runtime, so reading
  the `weather` group's `rain_amount()` / `wetness()` is right. It matches
  `world/env/weather_controller.gd:77-82`. Good catch. The lead should amend brief §5.
- Quality: `--quality=low` gives no rain, and amounts scale with `Settings.feature("particles")`
  (smoke 26→10, spray 30→12, wreck 40→16).
- Palette: SMOKE #C9CCD2, RUBBER #151515 α0.6, WRECK #2A2A2E, CHARGE #19E6FF, FIRE #FF7A1A /
  #FFD27A all match the brief and dossier §7.4.
- Sparks: E5 (energy 20), life 0.28 s, gravity + bounce, ×2.0 when `Engine.time_scale < 0.7`,
  ×2.2 on takedown. Zero `Decal` nodes (budget ≤ 64).
- Impulse convention matches the vehicle unit (`vehicle/modules/impact.gd:72`
  `impulse = mass * v_n`, reported at most every 0.15 s per pair), so `DV_SCRAPE` / `DV_HIT` are
  consistent.
- No engine/script errors from `res://fx/` in any main-scene run. All logged errors came from
  `ai/traffic/traffic_director.gd:165`, `ui/menu/menu.gd:97` and `ui/hud/*` (other units).

## Evidence
- `tools/godot.sh check --only=res://fx/` → CHECK 32 files, 0 failed, 0 engine errors, 0 warnings.
- `tools/godot.sh test res://fx/tests/test_fx.gd` → 16 PASS lines, "billboard budget under 20k
  (got 386)", `FX TESTS OK (0 failures)`.
- `tools/godot.sh shot --scene=res://main.tscn --out=r1_mainA --times=12,14,16
  --press=accelerate,drift,steer_left --rain` (no `--skip-menu`): the game stayed on the title screen;
  the parked, unwrecked Roadster shows the wreck-smoke column. 427 errors: 426 from
  traffic_director.gd:165, 1 from menu.gd:97, 0 from fx. Sheet: `captures/review/fx/r1_mainA_sheet_s.jpg`.
- Probe `tmp/review/fx_probe.gd`, run on main with `--skip-menu --rain`; accelerate; drift +
  steer_left from 13 to 15.6 s; nitro at 16 s. Log: `tmp/review/fx_probe_main.log`.
  - t=10: player 237 km/h, `wrecked=false`; 168 emitting systems; WreckSmoke ×35, WreckFire ×35,
    TyreSmoke ×32, WetSpray ×32, BoostVapour ×32; fx `billboards=13210 rigs=42 skids=400`.
  - t=15.4: 26,902 particles in emitting systems (fx 10,902 + fx_thrusters JetVapour 5 × 3,200).
  - t=18: 25,242.
  - The drift flipped the car (a vehicle-unit issue). Sheet: `captures/review/fx/r1_probe_main_sheet_s.jpg`
    (floating rings, 1.4 m cyan arch discs, blotchy puffs).
- Probe on `res://fx/demo/fx_demo.tscn` (log `tmp/review/fx_probe_demo.log`):
  - t=0.5: WreckSmoke + WreckFire emitting on BOTH cars.
  - skids=240 at t=2.0 and 400 at t=2.9.
  - car y −0.87 / −24.6 / −106 / −161 m at 4.55 / 6.5 / 9.4 / 10.95 s; TyreSmoke emitting at y −105 m.
  - Sheets: `captures/review/fx/r1_demo_sheetA_s.jpg` (smoke 5 m, skids 20 m, sparks, charge) and
    `r1_demo_sheetB_s.jpg` (vapour, wreck, takedown in free fall).
- `--quality=low` probe (`tmp/review/fx_probe_low.log`): no RainStreaks; TyreSmoke 10, WetSpray 12,
  WreckSmoke 16.
- Reference compare: `captures/review/fx/r1_compare_cp04_s.jpg`, i.e. `ref/art/img/cp04_nfs2015_wet_night.jpg`
  against my 5 m drift close-up.
- Worker captures, reviewed as sheets: `captures/review/fx/worker_sheet1_s.jpg` (demo_t1_6, t3_22,
  t4_6, t6_2) and `worker_sheet2_s.jpg` (demo_t9_1, t9_85, t10_9, main_t3_0 = loading screen).

## Notes for the lead (cross-unit, not the fx worker's fault)
- fx_thrusters JetVapour uses 3,200 particles per nozzle. With 4–5 nozzles active that is 12.8–16k,
  most of the 20k scene budget. Please set a per-unit split (suggestion: rain ≤ 6k, fx rigs + pools
  ≤ 3k, thrusters ≤ 8k).
- Brief fx §5 tells the worker to read `skyrush_rain` with `global_shader_parameter_get`. That call
  errors outside the editor, so please update the brief to the `weather` group API.
- The vehicle flipped during a held drift + steer at about 86 km/h (probe t=14.6), and traffic logs
  426 "previously freed" errors per run (`traffic_director.gd:165`).
