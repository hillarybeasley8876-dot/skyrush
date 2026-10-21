# fx review round 4 — VERDICT: FAIL

Reviewer: strict review and art direction, 2026-10-20. This is the last round, so no feedback was sent. The user
asks: 贴图纹理什么都要细化 (refine the textures and the detail everywhere).

Round 4 fixed the hard engineering failures of round 3:
- the lead's main drive runs clean twice (exit 0, 0 `uniform_set` errors);
- the real game now lays skid marks (104 quads, each 0.24 m wide);
- the rain rings sit on the road;
- the fire lives in the car's space;
- the charge flash no longer whites out the view;
- the 400-line splits are done and the dead constants are gone.

What still fails is mostly what the player sees:
- at game speed, the tyre smoke and the wet spray cannot be seen;
- the rain rings look like glowing cyan donuts;
- the near-miss streak cannot be seen;
- impacts throw no dust (a LEAD-SMOKE requirement);
- the scrape sparks are dull orange sticks;
- the flame atlas is 16 copies of the same symmetric cream "tuning fork".

## Scores (0-10): function 6.5, visual 5, code 6
- **function 6.5.**
  - What works:
    - the check and 56 tests are clean;
    - the main drive has 0 errors;
    - skid marks appear at 277 km/h;
    - the rain rings are on the road;
    - the wreck effects and the arcs work;
    - the 50-car spawn/free test passes;
    - budgets are met.
  - What is broken:
    - smoke and spray are invisible at game speed;
    - the near miss is invisible;
    - impacts make no dust;
    - a runtime change of quality preset is ignored.
- **visual 5.**
  - What reads well:
    - the takedown spark fan;
    - the soft smoke plume at 75–95 km/h;
    - the straight wreck column;
    - the cyan charge light pool.
  - What does not:
    - the rain rings look like donuts;
    - the spray looks like a row of popcorn;
    - no plume shows at speed;
    - the flame cards are crude;
    - the scrape is a fence of orange sticks;
    - the droplets render as square chips.
- **code 6.**
  - What is right:
    - every file is ≤ 400 lines;
    - there are no dead constants;
    - the contacts are typed.
  - What is wrong:
    - there are still about 240 magic float literals in the logic, and the status claims they were moved out;
    - one helper is still typed `Node` and calls its arguments dynamically;
    - an orphan `.uid` file was left behind;
    - Godot runs were started in the background.

## MUST-FIX

### 1. Tyre smoke and wet spray cannot be seen at game speed (r3 MUST-FIX 3, main-scene half)
- **Evidence:**
  - **Main drive** (the lead's timeline), full drift at 277–279 km/h on a wet road:
    - `captures/review/fx/r4main_t8_8.jpg` and `r4main_t9_4.jpg`, plus the probe view
      `r4pm_t8_0_rear5.jpg` (crop in `r4_crops_main.jpg`): no plume and no mist behind the car.
    - The probe shows the emitters are running (`tmp/review/fx/r4_probe_main.log`):
      `TyreSmokeL:ON r=0.80 n=380`, `TyreSmokeR:ON r=0.80`, `WetSprayL/R:ON r=1.00 n=64`, `Droplets:ON`.
  - **Demo**, wet road, 131–197 km/h:
    - rear camera, `r4rear_t4_5.jpg`, `r4rear_t6_5.jpg`, `r4rear_t8_5.jpg`: no mist fan;
    - side camera at 157 and 191 km/h, `r4side_t5_55.jpg` and `r4side_t9_15.jpg`: the spray is a row of separate grey
      "popcorn" puffs lying on the asphalt.
  - **Where the plume does read:** only at 75–95 km/h (`r4chase_t2_1.jpg`, `r4chase_t15_6.jpg`).
    - Unlit puffs measure p99 #2B3347 (chase) and #252B3C (top, `r4top_t15_8.jpg`) on a road of #0C0D12.
    - The r3 target was #343A48 or brighter.
  - **Missing captures:** the worker delivered neither `smoke_main` nor `spray_160kmh_rear`, although r3 asked for
    both.
- **Causes:**
  - **Inherit too low.** `SMOKE_INHERIT` is 0.2 and `SPRAY_INHERIT` 0.25.
    - At 77 m/s a puff falls back at about 62 m/s relative to the car.
    - It passes the chase camera, 6–7 m behind, after about 0.1 s.
    - The SmokeFX fade-in (8 % of 1.4 s = 0.11 s) has not finished by then, so the camera never sees a puff at full
      alpha.
  - **Spray too faint.** `SPRAY_ALPHA` is 0.18 and the life is 0.55 s.
  - **Proximity fade raised, against LEAD-SMOKE.**
    - `fx_emitters._soft_particles()` (line 165) raises the shared proximity fade from 0.35 m to
      `SMOKE_SOFT_DISTANCE` 0.5 m for every soft effect.
    - The sprites are born only 0.16 m (spray) and 0.28 m (smoke) above the road.
    - LEAD-SMOKE says: proximity fade 0.35 m, lift the sprite by half its size, "do not undo".
- **Do:**
  - **Inherit from speed.** In `fx_rig_tyres.drive()`, set `process_material.inherit_velocity_ratio` from the speed
    every frame, with new TUNE constants:
    - smoke: 0.2 at ≤ 60 km/h, rising to 0.6 at ≥ 200 km/h;
    - spray: 0.25, rising to 0.7.
  - **Damping.** Raise it (smoke 2–3.5, spray 3–5), so the plume opens up 4–10 m behind the wheel.
  - **Proximity fade and lift.**
    - Delete the proximity override in `_soft_particles()` and keep SmokeFX's 0.35 m.
    - Lift the birth point by half a sprite: `SMOKE_EMIT_HEIGHT` 0.45, `SPRAY_EMIT_HEIGHT` 0.30.
  - **Spray:**
    - alpha 0.28, life 0.8 s;
    - size 0.5 m, growing ×4;
    - 90 puffs per rear tyre at quality 1.0; the front tyres stay at 30 %.
  - **Unlit colour.** Raise `SMOKE_AMBIENT_ENERGY` until an unlit puff reads #343A48 or brighter, but never above
    #4A5262, so it never glows.
  - **Budget.** Update the director's worst-case count; it must stay ≤ 20k.
- **Verify:**
  - `tools/godot.sh drive --timeline=res://tools/timelines/smoke_drive.json --skip-menu --shots=8,8.8,9.4`: in all
    three frames a continuous plume or mist can be seen behind the drifting car over ≥ 6 m.
  - Demo with `--fxcam=rear --times=6.5,8.5`: a mist fan 3–8 m long behind each rear tyre, rising to ≥ 0.8 m.
  - Write the measured puff colours (unlit and lit) in the status.

### 2. Rain splash rings look like glowing cyan donuts (r3 MUST-FIX 6 overshot)
- **Evidence:**
  - **Main at 66 km/h**, `captures/review/fx/r4int_t2_0.jpg` (crop in `r4_compare_ref.jpg`):
    - the near road is covered with bright blue-white rings up to about 0.6 m wide;
    - the ring peak is #829CB4 on a road median of #05060B, about 25× the road;
    - next to `ref/art/img/cp04_nfs2015_wet_night.jpg`, where rain shows only as faint glints, they read as HUD markers.
  - **Demo**, `r4chase_t2_1.jpg` and `r4top_t2_0.jpg` / `r4top_t2_6.jpg` (crops in `r4_crops_chase.jpg` and
    `r4_crops_top.jpg`): crisp "o" glyphs with a dark hole.
  - **Texture**, `ripple.png` (`r4_textures.jpg`): one thick rim, about 10 % of the radius, plus perfectly round thin
    rings. There is no wobble.
- **Cause:**
  - The rings are additive at `SPLASH_ENERGY` 2.0 with the #C7DBED rim. Those were the r3 numbers, and they turn out
    too hot now that the rings sit on the road.
  - The rim is thick and solid.
- **Do:**
  - Set `SPLASH_ENERGY` 2.0 → 0.45, and change the rim to #8E9AA8.
  - Rings 0.06–0.18 m wide, growing ×2.6 over 0.35 s. Alpha falls from birth, 1 → 0, with no hold.
  - Re-bake `ripple.png`:
    - leading rim ≤ 4 % of the radius;
    - 2–3 trailing rings at 50 %, 25 % and 12 % amplitude;
    - a ±3 % radial noise wobble on each ring;
    - an empty centre.
  - Spawn rings only within 10 m of the camera.
- **Verify:** main at t 2 (66 km/h) and the demo with `--fxcam=ground --times=8`:
  - on an unlit road, no ring is brighter than 3× the local road (≤ #1E2430 on #0A0C12);
  - under a lamp, no ring is brighter than 1.5× the lit road;
  - the rings read as faint ripples.
  - Write the numbers in the status.

### 3. The near-miss streak cannot be seen (brief §7; r3 SHOULD-FIX 6 still open)
- **Evidence:**
  - No streak in `r4chase_t9_15.jpg`, `r4side_t9_15.jpg` or `r4nothr_t9_2.jpg` (`BEAT 0 at 9.01`).
  - The worker's own `captures/fx/r4/side_t9_1.jpg` shows the box car but no ribbon; the status calls it "still weak".
  - In main, the HUD shows 擦身而过 (`r4int_t10_0.jpg`) with no streak on screen.
- **Cause:** `fx_spark_pool.wind_streak()` spawns 6 world-space quads, 0.8 m thick, moving sideways at 9 m/s, at
  `AIR_ENERGY` 0.3.
  - The player leaves them behind at 50+ m/s within 0.2 s.
  - While they are on screen, they are a faint, wide smear.
- **Do:**
  - **Velocity:** give every streak the player car's velocity plus a sideways drift of about 4 m/s
    (`car_velocity + side * 4.0`), so it stays beside the car for its whole life.
  - **Streaks:**
    - 8–12 of them, each 0.03–0.06 m thick and 2.5–5 m long;
    - #CFE8FF at E3 (total energy 4–6);
    - life 0.35–0.5 s;
    - spread along the gap between the two cars, from the B-pillar to 3 m behind the rear bumper.
  - All of these numbers go in TUNE.
- **Verify:** at least 6 thin white-blue streaks between the cars in each of these:
  - demo chase and side captures 0.1, 0.25 and 0.4 s after `near_miss`;
  - one main frame with 擦身而过 on the HUD.

### 4. Impacts throw no dust (LEAD-SMOKE mandatory; the brief title says "debris dust")
- **Evidence:**
  - `grep -rni dust game/fx` finds nothing.
  - `fx_impact_fx.burst()` throws only sparks, glass, plastic and a light.
  - `r4chase_t13_05.jpg` (hit) and `r4chase_t25_12.jpg` (takedown) show no puff at the contact.
  - LEAD-SMOKE says: "Use the tyre_smoke / dust / wreck_smoke presets for the car rig, impacts and wrecks".
- **Do:** in `fx_impact_fx.burst()`, add a one-shot SmokeFX `dust` burst for dv ≥ `DV_HIT`:
  - 24–40 puffs, ×1.6 on takedowns; explosiveness 0.9;
  - dry #6E6A66 at α 0.35, wet #9AA3B0 at α 0.25;
  - size 0.5 m growing ×3; life 1.2–1.6 s;
  - placed at the contact and lifted by half a sprite;
  - pooled, at most 4 bursts alive, and counted in the worst case.
- **Verify:**
  - Hit and takedown captures show a grey dust puff at the contact, gone by 1.6 s.
  - The worst case stays ≤ 20k.

### 5. Scrape sparks: a fence of dull orange sticks, not bright E5 streaks (brief §4)
- **Evidence:** `r4chase_t17_4.jpg` (1:1 crop in `r4_crops_chase.jpg`) and `r4top_t17_3.jpg`.
  - 40–60 short orange sticks (about #E07030) stand in a row along the barrier.
  - They have no white-hot core, no bloom, no fan and no bounce.
  - The takedown fan in the same run blooms properly (`r4chase_t25_12.jpg`).
- **Cause:** `fx_spark_pool.scrape()`:
  - the velocity is mostly `-car_velocity * 0.5`, so the streaks fly straight away from the chase camera and are seen
    end-on, as stubs;
  - the length is 0.1–0.22 m, the thickness 0.02–0.035 m and `energy_mult` 0.8, all as literals;
  - the colour is `SPARK_COOL` for most of the 0.28 s life.
- **Do:**
  - Fan the sparks ±35° around the wall tangent, with 1.5–3.5 m/s up and out from the wall.
  - Length 0.3–0.6 m (stretched by velocity), `energy_mult` 1.0.
  - `SPARK_HOT` #FFFBF0 for the first 40 % of the life.
  - Bounce them on the road, with 4–6 sparks per tick while the contact lasts.
  - Move the literals into TUNE.
- **Verify:** chase and side captures during the scrape:
  - a fan of white-yellow streaks behind the contact, some bouncing on the road;
  - bloom can be seen;
  - no row of upright sticks.

### 6. Flame atlas: 16 copies of one symmetric cream "tuning fork" (r3 MUST-FIX 4, texture half unmet; status numbers inflated)
- **Evidence:** `captures/review/fx/r4_textures.jpg`, measured with `tmp/review/fx/flamecheck.py`:
  - **No core gradient:** core luminance 0.98 against edge 0.97 (r3 asked for 1.0 against 0.4). The colour ramp
    therefore cannot give a hot core or red edges.
  - **Too narrow:** the widest part is 25–38 % of the cell. r3 asked for about 45 %; the status says 38–48 %.
  - **Mirror shapes:** left/right asymmetry is only 0.009–0.023.
  - **No more variety than before:** pairwise mean |Δα| between cells has a median of 0.039 and a max of 0.086.
    - The status says 0.040–0.157.
    - The r3 atlas measured 0.044–0.047.
  - **In game:** in the worker's `captures/fx/r4/side_t29_0.jpg` (1:1 crop in `r4_textures.jpg`), the fire reads as a
    yellow comb of vertically streaked cards.
- **Do:** re-bake in `fx/tools/bake_textures.gd`:
  - **Shape:**
    - a rounded teardrop base, not a trapezoid;
    - a lean of ±15°;
    - 2–3 tongues of different lengths, one of them dominant;
    - 4 shape families × 4 variations.
  - **Breakup:** domain-warped noise inside the alpha (2 octaves, stretched ×3 vertically), so every lick has holes
    and wisps near the top.
  - **Core gradient:** the RGB is a luminance gradient from 1.0 in the core to 0.35 at the alpha-0.5 contour. The ramp
    then gives #FFE3A0 cores and #B83A0C edges.
  - Keep the 12 px gutter and the mipmaps.
- **Verify:**
  - flamecheck: core/edge ≥ 2.5, asymmetry ≥ 0.05, median pairwise |Δα| ≥ 0.08;
  - a sheet of the 16 cells;
  - ICE-wreck captures at 5 m and 20 m on a car-shaped traffic car (not the demo's box), showing a yellow core, an
    orange body, dark red edges and smoke above.

### 7. Code rules: magic numbers and an untyped helper (the status claims both are fixed)
- **Magic numbers.**
  - The status says: "The magic numbers of the emitters, the charge, the ignition, the takedown and the tuning block
    are in fx_tuning.gd".
  - Float literals outside `const` lines (not counting 0.0, 0.5 and 1.0), per file:

    | File | Literals |
    |---|---|
    | `fx_emitters.gd` | 74 |
    | `fx_debris_pool.gd` | 43 |
    | `fx_rain.gd` | 41 |
    | `fx_spark_pool.gd` | 40 |
    | `fx_charge.gd` | 15 |
    | `fx_events.gd` | 10 |
    | `fx_rig_tyres.gd` | 8 |
    | `fx_ignition.gd` | 6 |

  - Examples:
    - `fx_emitters.gd:36,74,98,113-115,133-134`: damping, speed and size `Vector2` literals;
    - `fx_spark_pool.gd:43`: `energy 20.0`;
    - `fx_spark_pool.gd:132,137-141`: 0.02–0.035, 8.0, 2.0, ±0.4 jitter;
    - `fx_ignition.gd`: energy 3.0, thickness 0.12, 1.8 and 0.4;
    - `fx_rig_tyres.gd:133,136,160`: 0.5, 1.6, 0.35, 0.3.
- **Untyped helper.**
  - `fx_impact_fx.gd:45` is `burst(spark: Node, debris: Node, lights: Node, ...)` and calls `spark.burst()`,
    `debris.burst()` and `lights.flash()` dynamically.
  - The status says every helper is a preloaded type.
- **Do:**
  - Move every tunable literal into `fx_tuning.gd` / `fx_palette.gd`, each with a name and a unit comment.
  - Type the three parameters with the preloaded pool types.
- **Verify:**
  - The same scan prints ≤ 5 literals per file, each with a comment.
  - `grep -n ": Node[,)]" game/fx/*.gd` prints only `_on_node_added`.

## SHOULD-FIX
1. **Charge ribbons (闪充) cannot be read.**
   - The helices are in the code, but no capture shows them: not `r4side_t5_55.jpg`, `r4side_t5_65.jpg`, nor the
     worker's `chase_t5_1.jpg` or `chase_t5_2.jpg`.
   - Fix: width 0.25 m, energy E3–E4, and stronger chevron contrast. Then show 3 spirals in captures at 0.15 s and
     0.4 s.
   - The cyan light pool and the small core are good; keep them.
2. **Droplets render as square chips.** See the `r4_crops_top.jpg` top views. Align them to their velocity, at
   0.02–0.04 × 0.10–0.25 m.
3. **Wreck column is thin at 20–40 m.**
   - It is 1.53× the luminance of the sky at 8 m (`r4pd_t29_0_tq8.jpg`), but it reads as a thin wisp in
     `r4pd_t30_5_q20.jpg` and `r4pd_t31_5_q40.jpg`.
   - Fix: grow it to 6 m, with 100 puffs at α 0.35 and a gentle widening in its upper half.
4. **Skid marks on unlit asphalt.**
   - From 3 m above the drift path (`r4sk_t3_9_top3.jpg`), no mark can be seen. The multiply-only mark is lost on a
     #0B0B0E road.
   - Fix:
     - add a small reflectance difference, as in the art DOSSIER §6.2 (#121212, α 0.75, roughness 0.45);
     - re-bake `tyre_track.png`, which today is plain corduroy stripes: add tread blocks with lateral sipes and blotchy
       rubber deposits along the length.
   - Note: in main the count stays at 104 quads from t 8.0 to 9.4 while the drift goes on. Check that the ground ray
     (layer 1) still hits once the car is off the road network.
5. **Runtime quality change is ignored.**
   - `fx_director.gd` applies the particle quality only in `_ready`, and nothing connects to `Settings.changed`.
   - Connect to it, and rescale the pools and rebuild the rig emitters.
6. **The demo's fallback traffic car.**
   - When the traffic unit's car does not load, the box is about twice the height of a car and hides the ICE fire
     (`r4pd_t29_0_tq8.jpg`, `r4side_t29_0.jpg`).
   - Make it 4.6 × 1.8 × 1.45 m with the fire on the hood, or load an `assets/cars/npc/*.glb` directly.
7. **N₂ shock rings.**
   - The 4 rings merge into a dotted frame of white dots around the rear bumper (`r4nothr_t11_1.jpg`; t11.1 crop in
     `r4_crops_chase.jpg`).
   - Fix: one clean ring per nozzle, 0.25–0.6 m, with no dotted texture. Move the literals (energy 3.0, thickness
     0.12) into TUNE.
8. **Performance.**
   - My sequential perf runs, on a loaded machine:
     - with fx: 12 fps and 3,322 draws;
     - with `--stub=fx`: 27 fps and 1,993 draws.
     - The FxDirector row is 196 draws and 364 objects.
   - The worker's 13 vs 40 fps came from two perf runs started in parallel, so that number cannot be used.
   - Profile one `--fx-no-*` family at a time on a quiet machine, and report ms and draws per family.
9. **Process.**
   - The worker started Godot runs in the background, against the lead's rule:
     - `(tools/godot.sh perf …) & (tools/godot.sh perf --stub=fx …)`;
     - `(… drive …) & sleep 115`.
   - `tmp/fx/` still holds 37 files (53 MB).
   - `game/fx/tests/_probe_props.gd.uid` is an orphan, the same mistake as `_probe.gd.uid` in r3.
10. **Status accuracy.**
    - The status says the blown-out band in `chase_t5_1.jpg` is "the canopy of the charge station lit by the flash
      light". That is false.
    - The sandbox canopy is already saturated at 5.30 s, before `CHARGE at 5.48` (`r4chase_t5_3.jpg`). It is
      core-owned and not an fx defect.
    - The status also says `check` covers 55 files; it covers 54.

## Verified OK
### Acceptance (brief)
| # | Item | Verdict |
|---|------|---------|
| 1 | Director | **PASS.** The thruster system is instanced and attached. Rigs follow `node_added`. Tiers at 10/30/59 m → 0, 61/120 m → 1, 151 m → 2. 50 cars spawned/freed with no surviving rig. |
| 2 | Tyre smoke | **FAIL at speed** (MUST-FIX 1). The logic and the look are right at 75–95 km/h. |
| 3 | Skid marks | **PASS.** #151515, strength 0.6, 20 s fade, pool of 400. In main: 104 quads, 0.24 × 1.36 m, at 277 km/h (r3: 0). At 9 m top-down (`r4top_t3_6.jpg`) the dark runs are 18–31 px. |
| 4 | Sparks and debris | **Hit and takedown PASS:** takedown 140 sparks, 26 glass, 16 plastic, ×2.2, a fan that blooms (`r4chase_t25_12.jpg`). **Scrape FAIL** (MUST-FIX 5). |
| 5 | Rain | **Streaks PASS:** 6k cap, off on low. **Rings** are on the road (worst 0.020 m) but look wrong (MUST-FIX 2). **Tyre spray FAIL** (MUST-FIX 1). |
| 6 | Charge | **PASS:** no whiteout from fx, a cyan pool on the asphalt and the body, a small core, arcs. Ribbons cannot be read (SHOULD-FIX 1). |
| 7 | N₂, near miss, wreck | Vapour: **PASS** (soft puffs, `r4nothr_t11_1.jpg`). Arch glow: unchanged since r3, where it passed. Near miss: **FAIL** (MUST-FIX 3). Wreck column: straight, ≥ 8 m after 9 s, 1.53× the sky at 8 m. ICE fire: in car space, orange ramp, no trail, but a crude texture (MUST-FIX 6). EV arcs: **PASS**. |
| 8 | Demo | **PASS.** Every beat fires on the real Roadster. The fallback box is SHOULD-FIX 6. |
| – | Budgets | **PASS.** Worst case 16,868 (test) and 17,150 (main probe); live 4.2–5.2k; 0 Decal nodes; skid pool ≤ 400. |
| – | Quality presets | **PASS at boot only** (SHOULD-FIX 5). |
| – | Check, 50-car test | **PASS.** |

### Lead notes
- **F-INT1: met.** 0 script errors in the demo and in main.
- **F-INT2: met** in logic:
  - density = slip × speed, capped at 0.8;
  - life 1.40 s;
  - no smoke below 10 km/h.
- **F-INT3: met.**
  - Bolts ≤ 0.635 m, and ≤ 0.150 m off the shell.
  - No arcs at 50 % health; arcs at 10 %.
  - With the car on its side (`r4int_t14_0.jpg`), no sticks.
- **F-INT4: met.**
  - Soft billows, no grain.
  - α 0.26, grey-blue.
  - Unlit, still a little dark (MUST-FIX 1).
- **LEAD-SMOKE: not fully met.**
  - The presets and `setup()` are used, and `keep_scale` and the random frame are untouched.
  - But the dust preset is unused (MUST-FIX 4), and the 0.35 m proximity fade is overridden (MUST-FIX 1).

### r3 MUST-FIX status
| r3 item | Status |
|---|---|
| 1. Renderer errors | **Closed.** Two lead drives, each with exit 0, `DRIVE done t=18.0 errors=0 warnings=0` and 0 `uniform_set` (r3: 110–154). |
| 2. Skid marks | **Closed.** |
| 3. Smoke and spray | **Open** (MUST-FIX 1). |
| 4. Fire | Colour, space and angle **closed**; atlas **open** (MUST-FIX 6). |
| 5. Charge | **Closed.** |
| 6. Rings | Placement **closed**; look **open** (MUST-FIX 2). |
| 7. Column | **Closed.** |
| 8. Code | Splits, dead code and typing of contacts and pools **closed**; magic numbers **open** (MUST-FIX 7). |
| 9. Evidence | **Mostly closed.** The smoke and spray captures are missing. |

### Code and ownership
- **Line counts:** every file is ≤ 400 lines. The largest are `fx_car_rig.gd` at 392 and `tests/test_fx.gd` at 398.
- **Constants:** a scan for unused TUNE/PALETTE constants prints nothing (`tmp/review/fx/deadconst.py`).
- **Calls:** there is no `.call(&` in the logic.
- **Ownership:** the job log shows Write/Edit only in `game/fx/**` (never `thrusters/`) and `status/fx.md`. The shell
  commands wrote only to `game/fx`, `tmp/fx` and `captures/fx`.

### ART §10 on my captures
- **Value and palette:** the car stays the brightest clean object. SAT is 0.0–4.2 % in the frames I measured (the limit
  is 15 %). There are no fx blow-outs.
- **Texture detail at 5 / 20 / 100 m:**
  - The smoke billows hold at 5–20 m.
  - At 5 m, the flame cards, the ripple donuts and the stripes of `tyre_track` look crude.
  - At 100 m, the fx are rightly invisible.
- **Repetition:** the 16 flame cells are near-identical, so the fire visibly repeats.
- **Scale:** the rings reach about 0.6 m, which is too big; the droplets are chips.
- **Contact:** no z-fighting. The skid lift of 1.5 cm and the ring lift of 2 cm both work.
- **Store screenshot:** the takedown frame would pass. The wet main frames with the donut rings would not.

## Evidence
All scratch is under `tmp/review/fx/`; all captures are under `captures/review/fx/`. I viewed 14 images, all contact
sheets or crops.

### Commands
- **Check:** `tools/godot.sh check --only=res://fx/` gives `CHECK 54 files, 0 failed, 0 engine errors, 0 warnings`
  (`r4_check.log`).
- **Tests:**
  - `tools/godot.sh test res://fx/tests/test_fx.gd`: 35 PASS, `FX TESTS OK`. It includes `worst case … (got 16868)`
    and `live … (got 5246)`.
  - `tools/godot.sh test res://fx/tests/test_fx_effects.gd`: 21 PASS, `FX EFFECT TESTS OK`. It includes:
    - `a drift at 270 km/h leaves a mark (356 quads)`;
    - `every vertex of the ribbon is above the road (0.0150 m …)`;
    - `every splash ring is on the road (worst 0.020 m)`;
    - `every bolt is shorter than 0.80 m (0.635)`.
- **Main drives:**
  - Run 1: `tools/godot.sh drive --timeline=res://tools/timelines/smoke_drive.json --skip-menu
    --shots=5,8,8.8,9.4,10.4,14`. Exit 0, 0 `uniform_set`, `DRIVE done t=18.0 errors=0 warnings=0`
    (`r4_main1.log`; captures `r4main_t*.jpg`).
  - Run 2: the same with `--debug --shots=2,6,8.5,10,14`. Exit 0, 0 `uniform_set`, errors=0 (`r4_main2.log`;
    captures `r4int_t*.jpg`).
  - The only error lines in either run are the leak notices at exit (`N shaders of type ParticlesShaderRD were never
    freed`).
- **Main probe** (`r4_probe.gd` on `res://main.tscn` with the drive inputs; `r4_probe_main.log`):
  - At t 8.0–9.4: `kmh=277 slip=1.00 drift=drift grounded=4`, `TyreSmokeL/R:ON r=0.80`,
    `WetSprayL/R:ON r=1.00`, `skids=104`.
  - Skid quads `[0.24, 0.24, 1.36]`; `fx billboards=4926-5218 worst=8529-17150 rigs=122`.
- **Demo sweeps** (`tools/godot.sh shot --scene=res://fx/demo/fx_demo.tscn --warm=20 --fxcam=…`):
  - Runs: `r4chase_*` (log `r4_chase.log`, `CHARGE at 5.48`), `r4top_*` (`CHARGE at 5.47`), `r4side_*`
    (`CHARGE at 5.46`), `r4ground_*`, `r4rear_*`, and `r4nothr_*` (with `--fx-no-thrusters`).
  - Every run: `CAPTURE errors=0 warnings=0`.
- **Demo probes:**
  - `r4pd_*`: wreck views at 8, 20 and 40 m (`r4_probe_demo.log`: `WreckSmoke` ×2, `WreckFire`).
  - `r4sk_*`: skid close-ups (`skids=42`, quads 0.24 × 0.92–1.05 m).
- **Perf:**
  - `tools/godot.sh perf --skip-menu --warm=200`: `PERF baseline fps=12 draws=3322`, `FxDirector draws=196 objs=364`.
  - The same with `--stub=fx`: `fps=27 draws=1993`.
  - The two runs were sequential, but the machine was shared (`r4_perf_fx.log`, `r4_perf_nofx.log`).

### Measurements (scripts in `tmp/review/fx/`)
- **Charge, % of pixels above 0.9 luminance** (`stats.py`):
  - side 11.9 % and 10.7 % at +0.09 s and +0.19 s;
  - the worker's chase frames 15.6 % and 13.1 %;
  - top 54.6 % and 84.0 %. The top camera sits above the sandbox canopy, which is saturated before the event too, so
    this is not an fx defect.
- **Unlit puffs** (p99): #2B3347 in `r4chase_t15_6.jpg` and #252B3C in `r4top_t15_8.jpg`, on a road of #0C0D12 to
  #0F0E14.
- **Rain rings:** peak #829CB4 on a road median of #05060B (`r4int_t2_0.jpg`).
- **Wreck column:** 75.1 against a sky of 49.2 (1.53×) at 8 m (`boxlum.py`, `r4pd_t29_0_tq8.jpg`).
- **Flame atlas** (`flamecheck.py`):
  - core 0.98 and edge 0.97 in every cell;
  - width 0.25–0.38;
  - asymmetry 0.009–0.023;
  - pairwise mean |Δα|: min 0.016, median 0.039, max 0.086.
- **Skid band widths** in `r4top_t3_6.jpg` (`profile.py`): runs 18–31 px that are at least 15 % below the median.

### Sheets and crops (`captures/review/fx/`)
- `r4_worker_sheet.jpg`: the worker's 16 r4 captures.
- `r4_sheet_chase.jpg` and `r4_crops_chase.jpg`: drift smoke and rings, N₂, scrape, takedown.
- `r4_sheet_top.jpg` and `r4_crops_top.jpg`: plume, droplets, rings and skid arcs from 9 m.
- `r4_sheet_main.jpg` and `r4_crops_main.jpg`: the main drives (no plume at 279 km/h; donut rings at 66 km/h; car on
  its side with no arcs).
- `r4_sheet_probe_main.jpg`: the main probe.
- `r4_sheet_side.jpg`: charge side, popcorn spray, EV column, ICE wreck hidden by the box.
- `r4_sheet_wreck.jpg`: column and fire at 8, 20 and 40 m.
- `r4_sheet_rear.jpg`: spray from behind at 131–197 km/h; ignition without thrusters; near miss.
- `r4_textures.jpg`: every fx texture, plus the worker's fire at 1:1.
- `r4_compare_ref.jpg`: charge crops, `ref/art/img/cp04_nfs2015_wet_night.jpg`, and the main donut rings.
- `r4_skid_close.jpg`: 3 m top view and low view of the drift path.
