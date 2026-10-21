# environment review round 4 — VERDICT: FAIL

Reviewer: art director (Opus). Brief `briefs/environment.md`; lead notes `reviews/environment-lead.md` (E1, 1–4 and the new
**E-INT1**) are mandatory. User demand: **贴图纹理什么都要细化**. Last round: no feedback sent; this is the record for the lead.
My captures: `captures/review_environment_r4_*.jpg` (31 lookdev cams + `_x_*` + `_rain_*` + `_game_*`, persisted preset),
`captures/review_environment_r4h_*.jpg` (same at `--quality=high`, + `_game2_*`); probes/sheets in `captures/review/environment/r4_*`.
NOTE: `user://settings.cfg` says `quality="low"` (written 08:54 by another unit) — low = SSR/SSAO/volumetric/rain OFF. Every
plain `tools/godot.sh shot` (and the lead's INT3 drive) ran at LOW. All verdicts below are from the `--quality=high` set.

## Scores (0-10)
- function: **6** — check + 3 suites green, factory deterministic, pools/sign faces/soffit E1/far bank fixed. But the measured
  scan means never reach the shaders (null in every .tres), the factory swallows an engine ERROR, SSR and the probes add
  ~nothing to the wet road (lead note 2 + E-INT1 fail), and two of the lead's views still miss the value targets.
- visual: **6** — big step from r3 (CJK canyon, far bank, soft pools, no crushed sign faces, bronze canopy, good 5 m asphalt,
  pier drips). Still: a flat red/amber 34×18 m slab at the vanishing point of every street view, a graph-paper soffit vs sh05,
  pale grey-box residential walls, flat-card signs, milky river, puddles that mirror nothing, matte-black road in the real game.
- code: **6** — typed, ≤ 317 lines/file, owned paths only. But a type mismatch silently nulls 15 parameters, wrong bond and
  contrast maths, `base_y` sign misuse in the look-dev, the bench persists the user's preset, wrapper bypassed, 4 false claims.

## MUST-FIX

1. **The measured scan means never reach the shaders: `tex_mean` / `detail_mean` are `null` in all 9 saved materials.**
   `grep "tex_mean\|detail_mean" game/shaders/materials/*.tres` → every line `= null` (SH_granite_bund, SH_kerb, SH_sidewalk,
   SH_tactile, SH_concrete_pier, SH_concrete_barrier, SH_facade_office, SH_facade_residential, SH_soffit_blue). Cause: the
   uniforms are `vec3 … : source_color` (a **Color** property) but `recipes_common.gd:44 mean()` returns a **Vector3**; it lives
   in memory, ResourceSaver writes `null`. Runtime probe `tmp/review/env4_mean_probe.gd`: `SH_granite_bund tex_mean=<null> (Nil)`,
   uniform `type=Color`. So every shader divides by its compile-time default (concrete 0.171/0.140/0.105):
   granite_bund (0.407/0.402/0.366) → ratio 2.4–3.5 → clamped at `SCAN_NORM_MAX 1.35` = the stone grain is flattened and too
   bright; PavingStones144 and TactilePaving003 likewise clamped; concrete_wall_008 (barrier, residential facade) +56–68 %
   → the pale "grey-box" canyon wall in `r4h_tower100` / `r4h_x_road20`. Probe `env4_mean_fix_probe.gd` (runtime only):
   bund3 crop 600×500 @ 500,150 **#675654 L90.3 → #584946 L76.3** with the real means; kerb2 500×300 @ 900,450 L58.1 → 51.6.
   r3 MUST-FIX 1(d) is therefore NOT done although status/README say so. Also `recipes_light.gd:24-26`: `Gradient.new()` has 2
   points, `set_color(2, …)` → `ERROR: Index pos = 2 is out of bounds (gradient.cpp:209)` during the factory, the pink stop never
   exists, yet the factory prints `MATERIALS 21 written, 0 failed`.
   Do: (a) declare `tex_mean` / `detail_mean` as plain `uniform vec3` (NO `source_color`: the MEANS are linear; a Color with the
   hint would also be sRGB-decoded) in `concrete_stained`, `facade_windows`, `soffit_blue` (grep every shader for `tex_mean`);
   (b) hologram: `grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])` + `grad.colors = PackedColorArray([...3 colours])`;
   (c) `material_factory.gd`: count engine errors with an `OS.add_logger` counter (as `tools/capture.gd` does) and exit 1 on any;
   after saving, reload each .tres and compare EVERY recipe key with the saved value (|Δ| ≤ 1e-4, non-null) → `MATERIAL FAIL`;
   (d) same check as a test line in `test_materials.gd`. Verify: `grep -c "tex_mean = Vector3" materials/*.tres` = 9;
   factory output has no `ERROR:`; bund3 crop luma 70–82 with sd ≥ 22 (my probe view); the residential canyon wall in
   `x_road20` (crop 300×200 @ 40,250, now #594F4D L81.3) ≥ 25 % darker than in `r4h_x_road20.jpg`, cladding grain visible at 1:1.
   (SH_concrete_pier / SH_facade_office / SH_soffit_blue use the `concrete` scan, whose mean equals the default — unaffected.)

2. **Lead note E-INT1 + lead note 2 are not met: the wet road mirrors nothing — SSR and the probes contribute ~0.**
   Real game, `--quality=high`, static cam at the player spawn (`spawn:-114.4,1.6,-250.9:-130,0.5,-193:62`,
   `r4h_game2_spawn.jpg`): uplit facade on the right, road region 1600×400 @ 0,500 **0 saturated streak columns, 33 bright
   columns ≤ 41 px**, P50 0.073 — matte black, as in the lead's `lead_int3_t2_0/t6_0`. The cause shows in the look-dev too:
   probe `env4_ssr_probe.gd` (runtime only) — road region of street/shop20, mean |Δluma| **SSR on vs off 1.73 / 1.66 per 255**,
   shipped vs probes removed + SSR off **2.94 / 3.45**; the streak count is identical (street 158/158/158 columns). See
   `r4_ssr_ab.jpg`: the orange 浦江电讯 panels, the red 东方霓虹 blade and the red end screen produce NO reflection with or without
   SSR/probes; the puddles (roughness 0.03) are dark blotches. The "streaks" the look-dev shows are the specular glints of the
   nine coloured OmniLights (`lookdev_hero.gd:43-62`), not reflections — the real game has no such lights, hence black.
   Also `lookdev_bench.gd:77` `Settings.set_quality()` persists the last preset (my run left `quality="ultra"`; I restored it).
   Do: (a) add `world/env/tests/test_ssr.gd`: a 20×20 m plane (StandardMaterial3D roughness 0.05) + an emissive 4×2 m quad (E3)
   4 m above it, camera 1.5 m up 12 m away; assert the plane's luma under the quad rises ≥ 30 % with SSR on vs off — then fix
   what it finds (compare `env_recipe.gd:136-140` and the road shader against `ref/art/lookdev/` where streaks were verified;
   `road_wet.gdshader:72-82` normal strength, the screen-space roughness limiter); (b) ReflectionProbes with `UPDATE_ONCE` are
   captured on the first frame, before the emissive pipelines exist: re-trigger them ~30 frames after `_ready` (lookdev) and
   expose a helper (`EnvRecipe.refresh_probes(root)`) that the world unit's `probe_placer.gd` can call — request it under
   Requests; (c) bench: save `Settings.quality` first and restore it with `Settings.set_quality(saved)` before `quit()`.
   Verify: test_ssr PASS; look-dev A/B (my probe): road |Δ| SSR on/off ≥ 8/255 and the 浦江电讯 panel visible in the puddles at
   shop20; lead gate: `tools/godot.sh shot --scene=res://main.tscn --skip-menu --env-only --quality=high --cams="spawn:…"` shows
   long vertical streaks under every uplit facade (≥ 100 bright/saturated columns ≥ 40 px in the road region).

3. **Value targets (acceptance) still fail on two of the lead's views; the street regressed from r3's default PASS.**
   High: `street` P5 **0.104** (fails default AND nanjing), SAT 17.0 (default); `pier5` SAT **26.3** (> nanjing cap 26, default 15).
   Main cause (and the worst composition problem of the set): the two 34×18 m flat light boxes that close the canyon
   (`lookdev_city.gd:181-187`, amber `bus_ad` at (5,13,−132), red `billboard_ad` at (−6,9,−112)) sit at the vanishing point of
   chase/street/road100/underchase/x_road20 — the r3 haze crop 200×50 @ 700,430 of street is now the slab, **#752328** — and fill
   half of `fardecal`/`decalstreet` as a flat amber card with 30 px text. Do: replace both with an office tower (SH_facade_office,
   own `building_seed`, h 60 m, at z −150) carrying ONE 12×7 m LED screen (duplicated SH_hologram, mode 0, energy 2.5, the ad art
   as in `build_signs`), so the street recedes into a lit facade with depth; trim the band row behind the pier for pier5.
   Verify (`--quality=high`, fresh captures): street and pier5 PASS `--zone nanjing` incl. P5 ≤ 0.10; chase, rear3, road5,
   tower100, npc, kerb2, river, river2, river_low still PASS default; underchase PASS underdeck.

4. **The soffit reads as a blue graph-paper ceiling, not sh05.** `recipes_light.gd:69` `joint_width_m 0.07` (r2 asked 2–3 cm;
   the smoothstep half-width gives a ~14 cm band) × `JOINT_DARK 0.7` + the v-lines = a hard square grid (`r4_ref_cmp.jpg` row 2;
   `r4_crops_1to1.jpg` bottom-left: 10 px black lines). sh05 is a smooth edge-bright gradient with longitudinal ribs. And
   `soffit_blue.gdshader:104` `mix(1.0 - CONTRAST, 1.0 + CONTRAST, luma)` averages **1.35**, not 1.0 as its comment says → the
   wash is effectively E1.2. Do: `joint_width_m 0.02`, `JOINT_DARK 0.35`, `luma_c = 1.0 + CONTRAST * (luma - 1.0)`, per-panel
   ±6 % brightness from a hash of `floor(u / joint_spacing_m)`, then re-tune `wash_energy` (≤ 1.0). Verify: soffit2 crop
   640×260 @ 250,0 luma 65–109, sd 6–15; in `x_soffit3` (1.5,6,−27 → 1,9.3,−31, fov 60) joint luma ≥ 65 % of the panel luma.

5. **The look-dev misplaces what it is supposed to prove (scale + splash zone).**
   (a) Every street lamp pole stands IN the carriageway: `lookdev_hero.gd:12-19` and `lookdev_street.gd:77` put poles and pools at
   x ±5.3, the edge lines are at ±5.6 and the kerb at ±6.4 (`r4_pools.jpg` decaltop: the lamp sits on the left edge line).
   (b) `base_y` has the wrong sign on every centred mesh: the shader computes `obj_y = VERTEX.y - base_y`
   (`concrete_stained.gdshader:71`) and the look-dev passes +half-height (pier 4.65, kerb 0.09, Bund block 11, cornice, pilasters)
   → obj_y ≤ 0 everywhere → the WHOLE object is splash zone (darker, wetter), no splash band. Probe `env4_basey_probe.gd`: pier
   crop 160×100 @ 720,300 **L63.5 shipped → L77.1** with base_y −4.65 (+21 %). Do: poles + pool decals at x ±7.2 (on the pavement,
   0.8 m behind the kerb) with the head on a 1.6 m arm over the kerb; base_y = −half-height (or move the mesh origin to the base);
   document the convention in README (instance uniforms table). Verify: decaltop shows the pole on the pavement; pier_base shows a
   darker band in the bottom 0.6 m (crop below 0.6 m ≥ 15 % darker than 1–2 m) and the pier mid-height L ≥ 70 in my probe view.

6. **The "staggered masonry courses" are mathematically broken.** `concrete_stained.gdshader:138-145`: `dy = abs(y − (row+0.5)·h)`
   draws the horizontal joint through the MIDDLE of each course, while the half-stone offset switches at `row·h` where no joint
   is drawn → every vertical joint crosses a horizontal one ("+" crossings) and jumps sideways halfway up a stone. With the flat
   (clamped, item 1) albedo the Bund reads as large porcelain tiles (`r4_detail3.jpg` top-left, `r4_crops_1to1.jpg` top-right) —
   not sh01 ashlar. Do: `dy = abs(y − round(y / h) · h)` (joint ON the row boundary), keep the offset per `row`; add 2–3 cm joint
   relief (darken + normal tilt), ±5 % per-stone tint from a hash of (row, stone index). Verify: 1:1 crop of `bund5` / `x_bund3`
   shows T-junctions only, no "+"; P50 of bund5 ≤ 0.30 once item 1 is fixed (now 0.345).

7. **Status claims that are false again (r3 rule: a claim without a capture or a test line is not done).**
   (a) "the new `detail_mean` uniform carries MEANS[granite_tile_03]" and README "tex_mean = the scan's measured mean" — null
   (item 1); (b) SHOULD-FIX 8 "the sky's radiance cross-fades to vignaioli_night" — `environment_controller.gd:100` sets `rain_mix`
   1.0/0.0, a pop (with `PROCESS_MODE_QUALITY` the radiance re-bakes once); (c) SHOULD-FIX 6 "masonry courses (0.42 × 1.8 m,
   staggered)" — item 6; (d) SHOULD-FIX 3 "the magic numbers are named constants" — many remain (`soffit_blue` 0.15/1.0, 0.12,
   0.08/1.5, 0.15/0.4, 0.5, 0.8, 0.85/0.1; `concrete_stained` 0.35/3.0, 0.045, 0.55/0.92, 0.2, 0.06, 0.012; `car_paint`
   0.05, 0.6, 0.8/0.5, 0.02, 0.45; `water_river` 1.37, 0.18, 0.06). Do: fix (b) with a real ramp (drive `rain_mix` from the
   weather's `rain_amount()` in 0.1 steps over the 8 s transition), finish (d), and correct the status.

## SHOULD-FIX
1. River: the water region 600×250 @ 900,600 of `r4h_river2` is **#555254 L83, R/B 1.01** — a milky grey floor, not the dark
   Huangpu (#0B1016, sh03); the lamp reflections are round glare blobs. Lower the river probe intensity / raise `wave_strength`
   anisotropy so lights stretch vertically; target water L ≤ 50 with coloured streaks (> 0.5 % saturated px in that crop, now 0).
2. Signs: 4 artworks repeated ~60× (billboard_ad, bus_ad, roadname_nanjing, neon_blade) and every panel is a flat colour field.
   Add 8–12 distinct real-word sign PNGs under `game/world/env/textures/`, a diffuser/LED-module micro texture and a 4 cm frame
   in `sign_panel.gdshader` (at 12 m the amber box in `fardecal` reads as a flat card).
3. Lamp poles / back plates / pole heads are untextured `StandardMaterial3D` (#2B2D31, #141416) — use a metal with roughness
   breakup + normal (ART §5 "no flat untextured surface"); the lamp head blows out to pure white (#FFFFFF) in `river2`.
4. Drips use world height (`concrete_stained.gdshader:127-130` `world_pos.y` 1.8–6 m): on deck parapets 8–12 m up they never
   appear — use `obj_y` (height above the object's base).
5. Process: `tmp/environment/runtests.sh`, `capture.sh`, `bench.sh` call `slots.py` + `/opt/homebrew/bin/godot` directly,
   bypassing `tools/godot.sh` (and its import) — worker rule "never launch godot directly"; scratch in `tmp/environment/` not cleaned.
6. `car_paint.gdshader:52` `CLEARCOAT_BASE = 0.0` is a dead constant; README says courses 0.45 m, recipe 0.42 m.
7. Paint: at `x_hero34` the body reads soft matte white, not "crisp reflections" — re-judge after item 2 (SSR on the clear coat).
8. Bench: my run (shared machine) medians low 44.2 / high 95.1 ms per 8 views (+6.4 ms/view, contended); the two quiet rounds
   give high +2.75 ms/view, 8.2 ms per 1080p view — plausible pass, but the GPU timer reads 0: report RenderingServer
   `get_frame_setup_time_cpu` + a vsync-off min-of-5 instead of the median.

## Verified OK
- `check --only=res://shaders/,res://world/env/` → `CHECK 56 files, 0 failed, 0 engine errors, 0 warnings`; `test_materials.gd`
  → 0 failed (incl. "every sampler bound", "look-dev uses all 69 materials"); `test_environment.gd` → 0 failed; the factory is
  deterministic (re-run → 21 .tres byte-identical to the shipped ones).
- r3 MUST-FIX 1 (a)(b)(c)(e): `Leaking004_opacity` in SH_concrete_pier/barrier/soffit_blue ✓; `SurfaceImperfections001_opacity`
  in all 4 SH_car_paint* ✓, sampled in object space with the 3-way weights ✓; missing texture fatal ✓. Drips visible at 1:1
  (`x_pier2`, pores + thin vertical stains) ✓.
- r3 MUST-FIX 2: light pools are soft white→black decals at energy 0.12, no rectangle in decaltop/street/road100, each has a pole ✓.
- r3 MUST-FIX 3: `sign_panel.gdshader`, lit panels; crush (luma < 0.02) pier5 0.00 %, pier_base 0.01 %, npc 0.37 %, road5m
  0.18 %; P5 0.069/0.080/0.047/0.040 ✓; ambient 1.0 ✓; glyphs glow and stay readable (`r4_detail3.jpg`).
- r3 MUST-FIX 4 / lead E1: wash 0.9, falloff 0.45, #6E6C68 × texture, strip #5A3DFF E4.5, metre-UV soffit quad; soffit2 crop
  **#2766C9 L96.1 sd 11.8** (sh05 #265FF9 L94.5); `underchase` PASS `--zone underdeck` ✓ (but see item 4).
- r3 MUST-FIX 5: far bank (6 towers 60–180 m, cyan crowns/edge strips, 22 riverside lights, 2 screens, promenade paving);
  river/river2/river_low PASS default (SAT 4.0/3.6/4.3 %, P50 .217/.215/.204); cyan edge strips streak in `river_low` ✓.
- r3 MUST-FIX 6: fresh captures; my numbers match the worker's table within ±0.01 (flicker).
- Lead notes 1 (road crop 400×40 @ 600,660 #201F27, B ≥ R), 3 (real SH_ materials) and 4 (chase cam 6 m back, 1.9 m up) ✓.
- Gold glass: canopy crop 300×150 @ 650,300 #382724 (R/B 1.55) dry, #4D403E rain; textured Roadster glb now loads ✓.
- Code: longest file 317 lines, static types, no `Variant` escapes; round-4 Write/Edit only in `game/shaders/**`,
  `game/world/env/**`, `status/environment.md`, `tmp/environment/` (log scan); moon 200 m / 4 splits; zone density test ✓.

## Evidence
```
tools/godot.sh check --only=res://shaders/,res://world/env/   -> CHECK 56 files, 0 failed, 0 engine errors, 0 warnings
tools/godot.sh test res://shaders/material_factory.gd          -> ERROR: Index (uint32_t)pos = 2 is out of bounds (points.size() = 2)
   at set_color (gradient.cpp:209) [0] hologram (recipes_light.gd:26) ... MATERIALS 21 written, 0 failed   (.tres unchanged)
tools/godot.sh test res://shaders/tests/test_materials.gd       -> TEST_MATERIALS 0 failed
tools/godot.sh test res://world/env/tests/test_environment.gd   -> TEST_ENVIRONMENT 0 failed
shots: --scene=res://world/env/lookdev.tscn --cams=res://world/env/lookdev_cams.json --warm=40 [--quality=high]
   --out=review_environment_r4 / r4h (+ _x: pole, pier2, bund3, soffit3, road20, hero34, far100, bank; + _rain --rain) errors=0
   main.tscn --skip-menu --env-only [--quality=high] --times=2,4 / --cams="spawn:-114.4,1.6,-250.9:-130,0.5,-193:62;
   spawnhi:-112,4.5,-256:-130,0,-190:62"  (other units' errors: world.gd:158 'spawns' on Nil, blocks_*.glb fail to load)
screenshot_stats (high): PASS chase rear3 road5 road5m kerb2 kerb5m npc tower100 far100 hero34r river river2 river_low
   rain_chase rain_river2; street P5 .104 SAT 17.0 (nanjing: P5 FAIL); shop20 SAT 24.6 (nanjing PASS); pier5 SAT 26.3
   (nanjing FAIL); underchase underdeck PASS; road100 SAT 15.1; canopy SAT .8 (exception); bund5 P50 .345 (inspection)
probes (runtime only, tmp/review/): env4_mean_probe (tex_mean Nil, uniform type Color), env4_mean_fix_probe (bund3 L90.3->76.3),
   env4_ssr_probe (road |dL| SSR on/off 1.73/1.66, probes+SSR vs none 2.94/3.45), env4_basey_probe (pier L63.5->77.1)
streaks (env4_streaks.py, road 1600x340 @ 0,560): street 158 cols / 95 px (r3 162/95); game2_spawn 0 sat cols, 33 bright <= 41 px
bench: tools/godot.sh run res://world/env/lookdev_bench.tscn 150 -> medians low 44.23 med 63.27 high 95.07 ultra 66.94 ms/8 views,
   rounds 3-4 high 65.8 vs low 43.6-44.0; gpu 0.00; settings.cfg after = "ultra" (restored to "low" from my backup)
```
Images viewed (13): `r4_main_sheet_s`, `r4_ref_cmp_s` (sh07|street|shop20, sh05|soffit2, cp04|chase, sh03|river2), `r4_game_sheet_s`,
`r4h_game_row_s`, `r4_crops_1to1`, `r4_pools_s`, `r4_hero_s`, `r4_crops2`, `r4h_game2_row_s`, `r4_ssr_ab`, `r4_river_s`,
`r4_detail3`, `r4_dist_s` (all in `captures/review/environment/`).
