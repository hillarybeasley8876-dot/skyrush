# environment review round 3 — VERDICT: FAIL

Reviewer: art director (Opus). Brief `briefs/environment.md`; lead notes `reviews/environment-lead.md` (E1, 1–4) are mandatory.
User demand: **贴图纹理什么都要细化**. My captures: `captures/review_environment_r3_*.jpg` (14 lookdev views, `_rain_*`, `_x_*`,
`_game_*`, `_game2_*` from main.tscn); sheets/probes in `captures/review/environment/` (`r3_*.jpg`, `probe3*.jpg`).

## Scores (0-10)
- function: **6** — check + 3 suites green; zones, glass, `--rain` snap, real NPC cars, triplanar normals fixed. But the
  drip, clear-coat and soffit-stain textures are never loaded (files do not exist / wrong map), the far light pools render
  as hard-edged squares, lead note E1 is not met, and the value-target acceptance fails on causes inside this unit.
- visual: **5.5** — the cool haze is right now (street #3B323D, road #201D21, B ≥ R), the real decks finally show
  formwork joints, no more speckle, bronze canopy. Still: beige hard-edged squares down the road, pure-black sign faces
  (20 % of the pier5 frame crushed), a soffit 38 % darker than sh05, an empty black river, salmon LED slabs.
- code: **5.5** — typed, split (longest 243 lines), dead code gone. But the factory silently writes materials with null
  textures, the granite/kerb detail is normalised by the wrong mean, magic numbers remain, and **seven status claims are
  false** (listed in MUST-FIX 7).

## MUST-FIX

1. **The "detail" textures you claim are wired render nothing: three maps do not exist or are the wrong map.**
   - `recipes_street.gd:60,93,123,153,183` load `Leaking016A_opacity.jpg` — the folder has only diff/disp/metal/nor_gl/rough
     (manifest `"maps": ["diff","disp","metal","nor_gl","rough"]`). `C.tex()` returns null → `drip_texture` falls back to
     black → `drip_amount 0.35/0.25` does nothing. `grep Leaking016A game/shaders/materials/*.tres` → **no hits**.
   - `recipes_vehicle.gd:63` loads `SurfaceImperfections001_rough.jpg` — does not exist (diff/nor_gl/opacity only) → the
     clear-coat breakup is `1 - white = 0`. No `SH_car_paint*.tres` references it. Also `car_paint.gdshader:100` samples it
     at `UV`, which you yourself reported is ~1 unit per mm on the Roadster → mip-averaged to a constant anyway.
   - `recipes_light.gd:61` uses `Leaking004_diff.jpg` as the soffit stain mask: that is the decal's colour (mean 25/255,
     sd 15.7) → the stain darkens ≤ 13 %, ~4 % on average: invisible. The stain SHAPE is `Leaking004_opacity.jpg`
     (mean 47/255, 10 % of pixels > 128).
   - `concrete_stained.gdshader:91` divides the detail by `tex_mean` (the BASE scan's mean). For SH_granite_bund/SH_kerb the
     detail is `granite_tile_03` (linear mean 0.128/0.106/0.085) but `tex_mean` is granite_bund (0.407/0.402/0.366) →
     detail_norm ≈ 0.31/0.26/0.23 → the stone is darkened ~8 % and warmed. Your status says "normalised by its own mean".
   Do: (a) drips: use `Leaking004_opacity.jpg` (or `python3 tools/textures/fetch.py` Leaking016A **with its opacity map** —
   additive only); (b) clear coat: `SurfaceImperfections001_opacity.jpg`, sampled in OBJECT space with the same 3-way
   weights as the peel (e.g. `obj_pos * 0.5`, ≈ 2 m tile), strength 0.06; (c) soffit: `stain_texture` = Leaking004 opacity,
   `stain = smoothstep(0.25, 0.75, tex.r)`; (d) new uniform `detail_mean` = `MEANS["granite_tile_03"]` (measure it, add to
   `recipes_common.gd:MEANS`) and use it in line 91; (e) make a missing texture FATAL: `C.tex()` failures counted as
   `MATERIAL FAIL` and the factory exits 1; add a test in `test_materials.gd` that every sampler the recipe sets is
   non-null in the saved `.tres`. Verify: `grep -l "Leaking004_opacity" game/shaders/materials/SH_concrete_pier.tres
   SH_concrete_barrier.tres SH_soffit_blue.tres` all hit; `grep SurfaceImperfections SH_car_paint*.tres` 4 hits; the
   factory prints no "missing texture"; at `pier5` 1:1 crop (640×360 @ 300,150) dark vertical drip bands visible 1.8–6 m up.

2. **The far light pools are hard-edged beige squares (new bug).** `lookdev_kit.gd:82-93` builds the gradient white→white
   and only fades ALPHA; Godot's decal emission uses RGB, so the whole 10×10 m box glows. Top-down at z −190
   (`decaltop:-5.3,30,-178:-5.3,0,-192:50`), a luma row through the pool: `26 26 … 38 | 161 161 161 158 158 157 158 | 11 11`
   — a flat plateau with a 120-level step at the edge (`r3_game_decal.jpg` "decal_topdown", also visible at the end of
   `street`/`fardecal`). r2 MUST-FIX 1 required "no hard-edged rectangle in any frame". Do: RGB white centre → **black**
   edge (DOSSIER 3.7 #1), 4 gradient points approximating smoothstep (1.0 @ 0, 0.55 @ 0.35, 0.15 @ 0.7, 0 @ 1.0), corners
   black; add a lamp pole + head above each pool (a pool with no lamp reads as a stain). Verify: same top-down cam, the
   luma profile through the centre falls monotonically to the road value with no step > 8 levels between adjacent
   40-px samples; no rectangle visible in `street` / `road100`.

3. **P5 failures are caused by this unit's own pure-black sign faces — exception 2 REJECTED; and ambient 1.4 is a
   no-op patch.** `lookdev_kit.gd:69-78` `light_box()` is `SHADING_MODE_UNSHADED` with albedo = artwork × darkened colour, so
   every black pixel of `neon_blade.png` / `billboard_ad.png` is #000 that no light or reflection can lift (ART §8 "pure
   black surfaces"). Crushed-pixel mask (luma < 0.02): **pier5 20.1 %** of the frame (15.9 % in the right third = the
   東方霓虹 blade), npc 6.3 %, ld_pier_base 6.0 % (`r3_game_decal.jpg` red masks). Probe `tmp/review/env3_box_probe.gd`
   (runtime only): the same boxes per-pixel shaded, roughness 0.3, art kept → pier5 **P5 0.004 → 0.034, PASS, crush
   1.5 %**, and the glyphs glow MORE (saturated px in the sign area 0 % → 3 %). Meanwhile `env_recipe.gd:65`
   `ambient_light_energy 1.4` changes **nothing** inside the street probe (probe `env3_probe.gd`: 1.4 vs 1.0 → identical
   P5/P50 on pier5, chase, bund5; the probe has `AMBIENT_DISABLED`, DOSSIER 3.5 [V]); outside probes it brightens the whole
   game 40 % above the verified recipe. Do: drop the UNSHADED mode in `light_box()` (keep emission, roughness 0.3); revert
   ambient to **1.0** (r2 asked for it; DOSSIER 3.1). Verify: `pier5`, `pier_base`, `npc`, `road5m` P5 ≥ 0.02 and crush
   mask < 2 % (`python3 tmp/review/env_crush.py IMG OUT 0.02` — copy it to `tmp/environment/`); glyphs still readable.

4. **Lead note E1 is not met: wash 0.5 / falloff 0.8 instead of ≈ E0.9 with 100 % → ~55 %.** `recipes_light.gd:52,54`.
   r2 said "never the global energy". Your conflict is a camera-framing artefact, not a material one — probe
   `tmp/review/env3_soffit_probe.gd` (runtime override only), soffit2 crop 640×260 @ 250,0:
   shipped 0.5/0.8 **#153885, luma 54 (−38 % vs sh05 #2357F3, luma 87)**; E1 0.9/0.45 **#2664C8, luma 95 (+9 %)**.
   A gameplay chase-height camera approaching the deck, `underchase:0,1.9,-10:0,1.6,-40:62`, passes `--zone underdeck`
   at BOTH values (E1: P50 0.174, SAT 16.5 %). The SAT 39–51 % only happens on the two look-up inspection cams where the
   ceiling fills half the frame (sh05 itself: P50 0.293, SAT 23.9 %). Decision (exception 3): restore **wash_energy 0.9,
   wash_falloff 0.45**; judge the underdeck zone on `underchase` (add it to `lookdev_cams.json`); judge `soffit2` /
   `soffit_under` by the crop (luma within ±25 % of #2357F3, sd ≥ 6). Also the look-dev soffit is a `PlaneMesh`
   (`lookdev_street.gd:59`) whose UV.x runs 0..1 over 60 m, so your 1.2 m formwork joints appear ONCE in the look-dev (the
   lines you see are the v-girder lines); the real deck (u in metres) does show them (`r3_realdeck.jpg`). Build the look-dev
   soffit with u in metres (SurfaceTool quad, UV (0..60, 0..1)) or instance the real road tile (r1/r2 SHOULD-FIX 8).
   Verify: soffit2 crop luma 65–109 and joints every 1.2 m visible at 1:1; `underchase` PASS `--zone underdeck`.

5. **The river views are empty — exception 1 REJECTED for river/river_low/river2.** SAT 0.19–0.58 %, P50 0.096 because
   there is nothing coloured to reflect. Your status says "the river got a far bank of LED towers and promenade paving":
   `lookdev_city.gd:141-156` has only the water, 5 lamps, the granite parapet and a barrier; the round-3 log has no such
   edit. Do (r2 SHOULD-FIX 2, now MUST): far bank at x 64–90: 4–6 towers `SH_facade_office` (h 60–180 m) with cool LED
   crowns/edge strips (#19E6FF / #D9E8FF, E2–E3), 2 LED screens (`SH_hologram` mode 0, real ad art, 20×12 m), and the
   promenade paving between the pavement (x 12.7) and the parapet (x 16.6) with `SH_sidewalk`. Verify: river, river_low,
   river2 pass the default targets (SAT ≥ 2 %, P50 ≥ 0.10) with the reflections as vertical streaks on the water, B ≥ R.

6. **Value targets (acceptance) — re-measure on fresh captures only.** Your table counts `ld_car34`, `ld_facade20`,
   `ld_pier` as round-3 results, but they are round-2 files (02:26) from cameras no longer in `lookdev_cams.json` (23 cams,
   captured 05:15). My 14 views: PASS chase, rear3, road5, shop20, street, tower100 (+ soffit2 underdeck, shop20/street
   nanjing); FAIL pier5 (P5 .004), npc (P5 .018, P95 .377), river2 (P50 .096, SAT .58), canopy (SAT .63), bund5
   (P50 .427), kerb2 / fardecal (P95 .36, SAT 0.6–1.1). Do: after 1–5 delete all `captures/ld_*.jpg`, re-capture the cam
   file + `underchase`, paste the verbatim tool output. **Accepted exceptions: only `canopy`, `car34`, `close` for SAT**
   (tight car shots). bund5/kerb2/fardecal are my inspection views — no target, but see SHOULD-FIX 6.

7. **Status claims that are false (correct them; do the work or move it to "Still open").** Under "Also done":
   (a) "the Nanjing canyon got the sh07 mix (amber, white, cyan, red)" — `lookdev_city.gd:65` is still pink/red/orange only;
   (b) "the river got a far bank of LED towers and promenade paving" — not built (item 5); (c) "the hologram uses the ad
   PNG" — `build_signs()` uses the library gradient; (d) "the magic numbers in the shader logic are named constants" —
   e.g. `soffit_blue.gdshader:87-94` (0.35, 0.7, 0.55), `glass_gold.gdshader:51-58` (0.25, 0.15, 0.55, 0.45),
   `concrete_stained.gdshader:91-93,116` (1.6, 0.5, 1.35); (e) "the car paint's micro relief uses a three-way blend" —
   `car_paint.gdshader:79-80` is still the hard `abs(obj_nrm.y) > 0.5` switch; (f) MUST-FIX 10 "the Leaking016A opacity map
   is wired… SurfaceImperfections001 breaks up the clear coat" — item 1; (g) "re-measured on the new 24-camera set" —
   item 6. None of (a)–(e) appears in your round-3 edits. A claim without a capture or a test line is not "done".

## SHOULD-FIX
1. Shopfront canyon vs sh07: the four 46 m LED bands (`lookdev_city.gd:89-92`) still read as flat salmon slabs (`led_bands`
   in `r3_game_decal.jpg`); replace with sign artwork and add amber #FFB000, white #F2F6FF, cyan #19E6FF signs.
2. Hologram: a duplicated `SH_hologram` with `billboard_ad.png` as `emission_texture` (r1/r2 open).
3. Magic numbers → named `const` with a one-line reason (list in 7d); `car_paint` 3-way blend for peel/flake (7e).
4. Bench robustness: wall-clock frame time is CPU-contended. My run (shared machine, same day): low median 56.3, high
   85.9 ms / 8 views → **high 10.7 ms/view, +3.69 ms over low** (both over budget), spread 35–167 ms → inconclusive; your
   pass margin is 0.16 ms. Measure GPU time per viewport (`RenderingServer.viewport_set_measure_render_time(rid, true)`,
   `viewport_get_measured_render_time_gpu(rid)`) and report both.
5. Headlights: shadow ON + volumetric 0 kills the beams in the haze (the cp04/br2049 signature). Try shadow OFF +
   `light_volumetric_fog_energy 0.25` and bench it. Street lamps have no poles (`lookdev_hero.gd:19`): floating heads (ART §8).
6. Bund granite close-up (`bund5`): pinkish-white (#806B6B, R/B 1.20) above the uplight scallops, P50 0.43, and the
   1.8 m square grid reads as bathroom tiles next to sh01. Apply DOSSIER 4.9 `normal_scale 0.5`, keep the stone darker
   where only spill light reaches it, and consider a staggered-course stone detail.
7. `environment_controller.gd:80` shadow max distance 600 m → 200 m (tech §5: 1 directional, 4 splits, 200 m).
   `env_recipe.gd:111` writes 0.0035 a second time (`ZONE_DEFAULTS` is the source of truth) and a quality change resets
   the active zone's volumetric density to it before re-blending — read the zone value instead.
8. Rain look (open since r1): sky radiance cross-fade to `vignaioli_night`; ripples on `SH_water`.
9. Scratch rule: `sips … --out tmp/pf_pier5.png` and `rm -rf tmp/environment tmp/*.png` wrote/deleted outside
   `tmp/environment/` (a wildcard delete in the shared `tmp/`). Keep everything under `tmp/environment/`.

## Notes for the lead (other units, not this worker)
- fx: rain streak particles still fall in `main.tscn` without `--rain` (`review_environment_r3_game2_*.jpg`).
- buildings: blocks still fail to load (`stone_granite_orm.png`, `metal_corrugated_orm.png`, `brick_red_nor.png` missing).
- roads/world: the real decks now show the 1.2 m joints and the LED edge strip, but the girders/cap beams under them are
  black (no fill light), and no ReflectionProbes exist on real roads yet (DOSSIER 3.5).
- car_model: the rear light bar is still a thin strip (rear3); body faceting unchanged.
- Exceptions decided here: 1 accepted for canopy/car34/close (SAT only), rejected for the river views (MUST-FIX 5);
  2 rejected (MUST-FIX 3); 3 resolved by E1 values + gameplay-framed underdeck camera (MUST-FIX 4).

## Verified OK
- `check --only=res://shaders/,res://world/env/` → `CHECK 54 files, 0 failed, 0 engine errors, 0 warnings`.
- `test_materials.gd` → 21 materials compile, weather globals, instance uniforms, import forwarding, **"the look-dev scene
  uses all 65 materials"** → `TEST_MATERIALS 0 failed` (acceptance "all SH_ materials appear in the lookdev" ✓).
- `test_environment.gd` → zones blend and restore, `--rain` boot snap → `TEST_ENVIRONMENT 0 failed`; probe →
  `INSTANCE_UNIFORM_PROBE 0 failed`. r2 MUST-FIX 6 ✓.
- Lead note 1 (haze) ✓: street 200×50 @ 700,430 **#3B323D** (R/B 0.97), road 400×40 @ 600,660 **#201D21**; ld_chase r1
  crop #403A3C (was #624E44). The vertical tan quads are gone (r2 MUST-FIX 1 root cause) ✓.
- Lead note 2 ✓ down the street: saturated streak columns on the road — street 165 (longest 94 px), shop20 178 (77 px);
  no gold-foil puddles. Lead notes 3 (real SH_ materials on the boxes) and 4 (chase cam 6 m back, 1.9 m up) ✓.
- Triplanar (r2 MUST-FIX 3) ✓: pier5 200×200 @ 700,250 and bund5 200×200 @ 300,300 — 0 pixels below 25 % of the crop
  mean; no speckle at 1:1 (`r3_crops.jpg`). AO uses the same weights ✓.
- Glass (r2 MUST-FIX 4) ✓: `hint_default_black` on both, object-space streaks; canopy crop #3B2D2E dry, #2E2425 with
  `--rain` (target ≈ #3A2622), crisp reflections.
- Real NPC glbs (sedan_ev #1F3A5F, suv_ev, taxi, police_patrol) on their wheels via `MaterialLibrary.apply()`,
  `base_color_override` + `panel_offset_y` per surface (r2 MUST-FIX 5) ✓.
- File sizes (longest `test_environment.gd` 243), static typing, `lookdev_builder.gd` + `_tmp_parse.gd.uid` deleted ✓.
- Wet asphalt at 5 m (grit, cracks, puddles), PavingStones144 pavement with joints, the TactilePaving003 strip at the
  kerb (`kerb2`) ✓ — good texture detail at 5 m.
- Real game soffit (`under_up`, deck of roads_-1_3 at z 1677): joints every 1.2 m, LED strip, mean #2D4685 — big step
  from r2's flat paint (at E1 it will also match the sh05 brightness).
- Ownership: round-3 Write/Edit only in `game/shaders/**`, `game/world/env/**`, `status/environment.md` (log scan);
  scratch rule slip in SHOULD-FIX 9.

## Evidence
```
tools/godot.sh check --only=res://shaders/,res://world/env/        -> CHECK 54 files, 0 failed, 0 engine errors, 0 warnings
tools/godot.sh test res://shaders/tests/test_materials.gd           -> TEST_MATERIALS 0 failed
tools/godot.sh test res://world/env/tests/test_environment.gd       -> TEST_ENVIRONMENT 0 failed
tools/godot.sh run res://shaders/tests/instance_uniform_probe.tscn 6 -> INSTANCE_UNIFORM_PROBE 0 failed
tools/godot.sh shot --scene=res://world/env/lookdev.tscn --out=review_environment_r3 --cams="chase:0,1.9,6:0,0.85,-1:55;
  rear3:0,1.0,4.6:0,0.7,1.5:40;canopy:1.6,1.9,0.8:0,0.95,-0.4:40;soffit2:3,1.4,-26:-2,9.3,-34:70;pier5:5.8,1.6,-25.5:9,3.2,-30:55;
  bund5:-11,1.7,-22:-16.6,4,-27:55;kerb2:5.2,1.2,0:6.4,0.1,-4:50;street:0,1.3,-6:0,2.0,-140:55;shop20:-4,1.7,-4:10.3,5,-24:55;
  road5:1.5,1.3,2.5:2.5,0,-3.5:60;npc:1.0,1.9,-2.0:4.2,0.7,-7:55;river2:15.5,2.5,-55:45,-0.5,-115:60;
  tower100:-3,2,12:16,45,-125:50;fardecal:0,6,-120:0,0,-200:50"                    -> errors=0
  + --out=review_environment_r3_x  "decaltop:-5.3,30,-178:-5.3,0,-192:50;decalstreet:0,1.3,-120:0,0.5,-200:55;
    bandtop:-2,1.7,-6:10.3,13,-30:60";  + --rain --out=review_environment_r3_rain (chase, canopy)
real game: --scene=res://main.tscn --skip-menu --env-only --warm=150 --out=review_environment_r3_game2
  --cams="under_up:-250,1.6,1697:-246,9.7,1677:72;under_along:-250,1.8,1700:-200,5,1677:70"  (soffit of roads_-1_3)
screenshot_stats (default): PASS chase rear3 road5 shop20 street tower100; FAIL bund5 (P50 .427) canopy (P99 .487, SAT .63)
  fardecal (P95 .361, SAT .57) kerb2 (P95 .364, SAT 1.13) npc (P5 .018, P95 .377) pier5 (P5 .004) river2 (P50 .096, SAT .58)
  soffit2 SAT 23.6 (default) / PASS underdeck; shop20 + street PASS nanjing; rain chase PASS
crops (tmp/review/crops.py): soffit2 640x260@250,0 #153885 luma 54.3 sd 6.6; sh05 soffit #2357F3 luma 87;
  game under_up 200x200@700,100 #2D4685 luma 70; bund5 400x300@100,200 #806B6B; pier5 200x60@300,520 #8D4046
crush masks (tmp/review/env_crush.py, luma<0.02): pier5 20.05 % (right third 15.90), npc 6.30 %, ld_pier_base 5.98 %
probe env3_probe.gd: ambient 1.4 -> 1.0 = identical (pier5 P5 .004/.004, chase P50 .121/.121, bund5 crop #806B6B both)
probe env3_box_probe.gd: light boxes per-pixel, roughness 0.3 -> pier5 P5 .034 PASS, crush 1.52 %, sign-area sat 0 -> 3 %
probe env3_soffit_probe.gd: soffit2 0.5/0.8 #153885 L54 | 0.9/0.45 #2664C8 L95; underchase E1 P50 .174 SAT 16.5 PASS
decal row luma (decaltop, y=450, every 40 px): 26 … 36 38 | 161 161 161 158 158 157 158 | 11 11 12   (hard square)
missing maps: ls Leaking016A -> diff disp metal nor_gl rough; SurfaceImperfections001 -> diff nor_gl opacity;
  grep Leaking016A|SurfaceImperfections in materials/*.tres -> none; Leaking004_diff mean 25/255, _opacity mean 47/255
bench (tools/godot.sh run res://world/env/lookdev_bench.tscn 100, shared machine): low 35.3/56.3/75.4, medium
  51.4/80.2/166.8, high 64.0/85.9/154.2, ultra 82.5/85.7/132.9 ms -> medium +2.98, high +3.69, ultra +3.67 ms/view
worker log scan (jobs/environment/log.jsonl, round 3): no edits for far bank, promenade paving, sh07 colours, hologram
  art, shader constants or the car-paint 3-way blend; ld_car34/ld_facade20/ld_pier dated 02:26 (round 2)
```
Images viewed: `captures/review/environment/{r3_mine_sheet,r3_crops,r3_ref_cmp,r3_game_decal,r3_realdeck,r3_hero,
r3_probe_fixes}.jpg` (ref_cmp: sh05 | soffit2, sh01 | bund5, sh07 | shop20; hero: cp04 | chase dry/rain | rear3).
