# environment review round 2 — VERDICT: FAIL

Reviewer: art director (Opus). Brief `briefs/environment.md`; lead notes `reviews/environment-lead.md` (E1, 1–4) are mandatory.
User demand: **贴图纹理什么都要细化**. My captures: `captures/review_environment_r2_*.jpg` (10 lookdev views + `_med_*`
+ `_game_realdeck/_realroad` from main.tscn); sheets/probes in `captures/review/environment/` (`r2_*.jpg`, `probe_*.jpg`).

## Scores (0-10)
- function: **4.5** — check/tests green, `--rain` snap works, river probe works; but zones are broken, the glass shaders
  are max-grimy by default, the triplanar normals are wrong on every concrete surface, the preset budget fails, and 4
  acceptance items fail (value targets, SH_ materials in lookdev, budget, lead notes E1 + 1).
- visual: **4** — street dressing improved (pavers, granite kerb, CJK signs, back plates), but the lead's two complaints are
  unchanged: tan "haze" (a geometry bug, below) and a flat blue soffit; new black speckle on all concrete in the real game;
  milky canopy; floating ellipsoid traffic cars. Not a store screenshot.
- code: **4.5** — typed, small files, clean check; but `material_factory.gd` 469 lines (> 400), a 355-line dead file,
  two maths bugs (triplanar normal, detail ×2) and several status claims that the evidence contradicts.

## MUST-FIX

1. **Lead note 1 (warm haze): root cause is the light-pool quads standing VERTICALLY.** `lookdev_street.gd:66-70` adds six
   `QuadMesh` 10×10 m at y 0.02 with no rotation; a QuadMesh faces +Z, so these are six translucent tan WALLS across the
   street every 30 m, half below ground (same bug in r1: old `lookdev_builder.gd:285-286`, rotation (0,0,0)). Proof
   (runtime probe `tmp/review/haze_probe.gd`, street view `0,1.3,-6 → 0,2,-140`, fov 55): hiding only those six quads moves
   the horizon band **#695146 → #403337** (R/B 1.51 → 1.16) and the mid-road **#514036 → #201D1F**; turning volumetric fog
   off (#745B4C), radiance saturation 0 or a cool ambient did NOT change it. See `r2_pools_ab.jpg` (left shipped, right
   without the quads: a hard-edged tan rectangle disappears). Your status values are not supported: the r1 crop on your
   own `ld_chase.jpg` (80×50 at 760,330) is **#624E44** (R/B 1.44), `ld_pier.jpg` ground (200×60 at 300,520) **#735748**;
   and "#332829 cool" has R > B. Do: delete the quads; implement DOSSIER 3.7 #1 exactly — a `Decal` (size 10,6,10,
   `texture_emission` radial gradient 256 px, `emission_energy 0.6`, `modulate` = lamp colour, `upper_fade/lower_fade 0.3`,
   `distance_fade` 200/50) and only for lamps farther than 60 m (in the lookdev add 3–4 far lamps at z −190…−260 to prove
   it; the six near lamps are real OmniLights and need no pool). Then re-tune from the verified recipe, one change at a
   time with a before/after crop: `ambient_light_energy` 1.45 → 1.0, `fog_density` 0.0055 → 0.0035,
   `volumetric_fog_emission_energy` 0.25 → 0.5–1.0 (lead asked ~1.0; it washed out only because of the walls).
   Verify: both crops above and the street-view crop (200×50 at 700,430) have **B ≥ R** (target #34304A–#4A4458);
   street-view P50 ≤ 0.24; no hard-edged rectangle in any frame.

2. **Lead E1 (soffit) still a solid blue ceiling — and the deliverable violates "≈ E0.9".** `material_factory.gd:304`
   writes `wash_energy 0.26` (DOSSIER 3.7 #2 [V] and E1 say 0.9). My drive-under view
   (`soffit2:3,1.4,-26:-2,9.3,-34:70`), 1:1 crop 640×260 at 250,0: mean **#05276B, luma sd 1.8** (flat; your
   soffit_under: #043488, sd 4.8). sh05 shows a bright #2357F3 soffit with longitudinal ribs, joints and edge highlights
   (`r2_ref_cmp.jpg` top row). In the real game (deck of `roads_-1_-1` at x −390, z −4) it renders as flat blue paint
   (`r2_game.jpg` left). `soffit_blue.gdshader:55` `concrete *= 0.40` breaks "albedo #6E6C68 × texture". Do:
   (a) `wash_energy` 0.9; (b) delete the ×0.40; (c) put STRUCTURE into the wash (it is the only thing visible):
   formwork joints = dark 2–3 cm lines every 1.2 m along u (u is metres) and at v = 0.25/0.5/0.75, longitudinal ribs /
   drip-edge brightening near v = 0 and 1, water stains from the fetched-but-unused `Leaking004`/`Leaking016A`
   (wash × mix(1, 0.55, stain)), concrete AO map; (d) concrete modulation `mix(1.0, luma, 0.45)` → 0.8; (e) if under-deck
   P50 then exceeds 0.30, deepen `wash_falloff` toward the centre line, never the global energy. Verify: same crop
   **luma sd ≥ 6** with joints/stains visible at 1:1; soffit mean within ±25 % luma of #2357F3;
   `screenshot_stats --zone underdeck` passes on `soffit_under` and on `soffit2`; and a real-deck capture:
   `tools/godot.sh shot --scene=res://main.tscn --skip-menu --env-only --out=env_realdeck --cams="realdeck:-392,1.6,8:-389,6.8,-14:72"`.

3. **Triplanar normal reconstruction is wrong → black/white speckle on every concrete, granite, kerb and paving surface,
   including the real road decks and piers.** `concrete_stained.gdshader:74-76`: `nx * w.x * vec3(sign(n.x), 0, 0)` keeps
   only `nx.x` — the RED perturbation (random sign) — as the whole X normal; Y faces keep only `ny.y` (green perturbation),
   Z faces keep `nz.z` (no detail at all); near-flat texels give a near-zero vector (NaN at exactly 0). X/Y faces flip in and out per
   texel: see `r2_triplanar.jpg` (real deck underside, Bund pilasters, pier edge). Also `AO` samples `p.xz` only (line 118),
   so walls get vertically stretched AO stripes. Do the standard whiteout triplanar (Golus):
   ```glsl
   vec3 n = world_nrm;
   vec3 tx = texture(normal_texture, p.zy).rgb * 2.0 - 1.0;
   vec3 ty = texture(normal_texture, p.xz).rgb * 2.0 - 1.0;
   vec3 tz = texture(normal_texture, p.xy).rgb * 2.0 - 1.0;
   tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
   ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
   tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
   vec3 n_world = normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
   NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
   ```
   and blend AO with the same `w`. Verify: 1:1 crops of the real deck underside (cam above), the pier (`pier5:5.8,1.6,-25.5:
   9,3.2,-30:55`) and the Bund pilasters: no isolated black texels (in a lit 200×200 crop no pixel < 25 % of the crop mean);
   Z-facing walls show normal relief.

4. **Both glass shaders are max-grimy by default (Godot's unset sampler is WHITE).** `glass_gold.gdshader:24` declares
   `albedo_texture : source_color`; the Roadster's `SH_glass_gold` has no base-colour texture, so `grime = 1.0`
   everywhere → roughness 0.05 → **0.27**, alpha −0.15: a milky beige canopy. Probe `tmp/review/glass_probe.gd` (only sets a
   black texture): canopy crop **#43312C sd 25.7 → #372221** with crisp neon/specular reflections (`r2_glass_ab.jpg`).
   The map is also sampled at `world_pos.xz * 2.0` and the streaks at `world_pos` (r1 #9 said OBJECT space): both slide
   over the glass as the car moves — at 250 km/h ≈ 200 streak periods/s → flicker. `glass_tinted.gdshader:29`
   `max(noise, texture(albedo_texture, glass_uv * 2.0))` → white default saturates to 1 (the procedural grime is dead) and
   the imported `npc_glass_grime` is tiled 2× off its authored UVs. Do: `hint_default_black` on both glass `albedo_texture`;
   sample the imported map at `UV` ×1; glass_gold grime + streaks in object space (`obj_pos = VERTEX` in vertex(), streaks
   flowing toward +Z/−Y of the car); glass_tinted keeps `max(noise, imported)`, which works once the default is black. Verify: canopy cam crop
   dark bronze (≈ #3A2622) with a sharp reflection; `--scene=res://main.tscn --skip-menu --rain --press=accelerate
   --times=2,2.1` → identical streak pattern relative to the car in both frames.

5. **Acceptance "all SH_ materials appear in the lookdev" — FAIL; the traffic cars are floating ellipsoids.**
   `lookdev_hero.gd:85-91` builds SphereMesh blobs (r 0.85, height 0.7, scale y 0.72) centred at y 0.7 → their bottom is
   **0.45 m above the road** (floating, ART §8 / §10.9) with a UFO silhouette (`review_environment_r2_npc.jpg`);
   `SH_car_paint_police` and `SH_car_paint_taxi` are not in the scene at all. The real glbs exist:
   `game/assets/cars/npc/{sedan_ev,suv_ev,taxi,police_patrol}.glb` (SH_car_paint_npc / _taxi / _police + SH_glass_tinted).
   Do: instance sedan_ev (blue #1F3A5F) and suv_ev (silver #9DA3A8) — `set_instance_shader_parameter("base_color_override",
   …)` on every SH_car_paint_npc surface — plus taxi and police_patrol, standing on their wheels (y 0), each through
   `MaterialLibrary.apply()`; add cams `npc:1.8,1.7,-2.5:4.2,0.7,-7:45` and one framing taxi + police. For the Roadster set
   `panel_offset_y` on every SH_car_paint mesh = its y relative to the car root (proves no grime step at the Hood /
   Door_L / Bumper_F gaps). Verify: a test that walks `lookdev.tscn` and finds all 20 `SH_*.tres` in use; captures show
   4 real cars with wheel contact.

6. **Zone overrides are broken.** Probe `tmp/review/zone_probe.gd` (run through `res://tools/test_host.gd`):
   `set_zone(&"flight")` then `set_zone(&"default")` → `fog_density` stays **0.00150** and `fog_aerial_perspective`
   **0.500** forever (expected 0.0055 / 0.0); `nanjing → underdeck` first frame: volumetric density jumps **0.0090 → 0.0036**
   (a pop). Causes (`environment_controller.gd:42-75`): `_apply_zone()` loops over `_zone_to`, which is `{}` for default;
   `_zone_from = _zone_values()` returns hard-coded defaults instead of the current values; those defaults duplicate
   `env_recipe.gd` numbers (two sources of truth). Do: one DEFAULTS dictionary owned by the recipe; `_zone_to =
   DEFAULTS.merged(ZONES[zone], true)`; `_zone_from` = the Environment's current values of those keys. Verify in
   `test_environment.gd`: flight→default restores 0.0055 / 0.0 within 2.1 s; nanjing→underdeck first frame within 5 % of
   0.009; also the `--rain` boot-snap test r1 #13 asked for (it works — probe frame 1: rain 0.600, wet 1.000 — but is untested).

7. **Preset costs: over budget and misreported.** Status: "high 9.7 ms/view ✓, high−low 2.4 ms ✓". Your own table
   (low 45.8, high 77.5 ms per 8 views) gives (77.5 − 45.8) / 8 = **3.96 ms > 3.0**. My run
   (`tools/godot.sh run res://world/env/lookdev_bench.tscn 90`): medians low 50.45, medium 69.74, high 88.12, ultra 69.25 ms
   → high **11.0 ms/view > 10**, high−low **4.71 ms > 3.0**; ultra < high means the method is noise. Method gaps vs tech
   dossier 3.1: vsync is ON (`project.godot` vsync_mode=1; the dossier ran vsync off); the comment says "base, preset,
   base, preset" but the code runs low, medium, high, ultra; the `< 15 ms` filter throws away real samples. Do: disable
   vsync in the bench (`DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)`, restore after), interleave
   low between every preset, 5 rounds, cost = (X − mean of the neighbouring lows) / 8, print min/median/max. Then cut the
   high step: high−medium (volumetric fog + shadows) measured ≈ 2.3 ms/view vs the dossier's 0.60 — set
   `light_volumetric_fog_energy = 0` on the 9 spill lights and 5 river lamps, no volumetric on the two SHADOWED headlights
   (shadowed spot × froxels is the expensive pair), try `volumetric_fog_length` 96 → 64. Verify: two consecutive bench runs
   agree within 15 % and both meet high ≤ 10 ms/view and high−low ≤ 3.0 ms; paste the raw BENCH lines in status.

8. **Value targets (acceptance): 6 of your 15 cameras pass, not "9 of 15".** `screenshot_stats.py captures/ld_*.jpg`:
   PASS chase, facade20, far100, kerb5m, road100, soffit; FAIL canopy, car34, close, pier, pier_base, river, river_low,
   road5m, soffit_under. Mine: 3 of 10 pass (street P50 0.249, shop20 P50 0.263 — the tan walls; pier5 P5 0.004; soffit2
   HUES80 4). Do: after items 1–5 re-capture all cams, mine included (`--cams` strings in Evidence); lift crushed blacks
   (P5 0.004–0.012) with the ambient once the walls are gone; list any camera you believe is a legitimate exception (car
   close-ups with no neon in frame) under "Exceptions — needs lead approval", never as PASS. Verify: the table in
   status is the verbatim tool output.

9. **File-size and dead-code rules.** `shaders/material_factory.gd` is **469 lines** (CONTRACTS §3: ≤ 400): split it first,
   as its own step (e.g. `material_factory.gd` driver + `recipes_street.gd` road/marking/concrete family +
   `recipes_vehicle.gd` paint/glass + `recipes_light.gd` neon/hologram/soffit/water/facade). Delete the dead
   `world/env/lookdev_builder.gd` (+ `.uid`, 355 lines, referenced nowhere since the split) and the orphan
   `shaders/_tmp_parse.gd.uid`. Verify: `wc -l game/shaders/*.gd game/world/env/*.gd` all ≤ 400;
   `grep -rn lookdev_builder game --include='*.gd' --include='*.tscn'` empty.

10. **concrete_stained: the detail layer re-introduces the r1 #7 bug, and the "drip maps" are not wired.** Line 82
   `alb *= mix(vec3(1.0), detail * 2.0, detail_amount * 0.5)` assumes a 0.5 mean: with the concrete mean
   (0.171, 0.141, 0.105) it darkens **−12 %** and re-warms the colour (R/B +3 %). DOSSIER 4.3 wants `concrete_wall_008`
   ×3 MUL with a 128×1024 stretched noise mask (missing). `drip_texture` is never assigned and `drip_amount` is 0 in every
   material, so the status claim "adds … the drip maps" is false; `Leaking004`, `Leaking016A`, `TactilePaving003`,
   `SurfaceImperfections001`, `Concrete046`, `Facade009`, `Asphalt025C`, `clean_asphalt` were fetched and never used (r1 #6:
   "fetch … and wire it in"). Do: normalise the detail by its own measured mean (add it to `MEANS`), add the stretched mask;
   `Leaking016A` as drips on SH_concrete_pier (0.35) and SH_concrete_barrier (0.25) between 2–6 m; the 30 cm
   `TactilePaving003` strip at the kerb edge (r1 #12: new `SH_tactile` or a band in SH_sidewalk); `SurfaceImperfections001`
   as roughness breakup on the car paint clear coat (very low strength) and the glass grime. Verify: the pier mid-height
   mean changes < 5 % when `detail_amount` goes 0 → 0.35; drips visible at 5 m on the pier.

## SHOULD-FIX
1. **Shopfront street vs sh07 (Nanjing Rd).** The four continuous LED bands (`lookdev_city.gd:90-92`, 0.1×2.2×46 m at E3)
   read as pastel-salmon slabs under AgX (ART §10.6 "no blown-out areas"), and the street was cut down to one pink hue to
   pass the DEFAULT zone. The canyon is the Nanjing set piece: judge it with `--zone nanjing` (HUES80 2–4, SAT 8–26 %),
   replace the bands with real sign artwork (props light boxes, CJK channel letters) and add the sh07 mix: amber #FFB000,
   white, cyan #19E6FF, red. Light-box energy 3.5 on a mostly black PNG reads dark — give the art a lit background.
2. **River lookdev.** The river views are a black slab (SAT 0.17–0.5 %, P50 0.098): add a far-bank strip of cool LED towers
   (SH_facade_office + 2 LED screens) so the reflections can be judged; fill the 4 m void between the pavement (x 12.7)
   and the parapet (x 16.6) with promenade paving — `river`, `river_low` and my `river2` look into that hole (missing
   ground shows the below-horizon sky).
3. **Hologram** in the lookdev still shows the factory gradient: give it real ad art (`res://assets/props/textures/
   billboard_ad.png`) on a duplicated material, as asked in r1 SHOULD-FIX 5.
4. **README drift:** office `lit_ratio 0.30` (is 0.15), residential 0.55 (0.22), `puddle_amount 0.20` (0.24), office wall
   #2E2F32 (#383A3E); the concrete row lists 2 of 5 materials, the car_paint row 2 of 4.
5. **Magic numbers in shader logic:** promote the tuning literals to named `const`s or uniforms with a one-line reason
   (soffit 0.35 / 0.45 / 0.85, glass_gold 0.25 / 0.15 / 0.55 / 0.45, concrete 0.045 / 0.06 / 0.25, car_paint 0.35 / 0.6).
6. `car_paint` micro-relief switches projection axis hard at `abs(obj_nrm.y) > 0.5` → seams on curved panels: use a
   3-way blend (two extra taps of the 256² peel map are cheap).
7. Rain look (open since r1): sky radiance cross-fade to `vignaioli_night` with `skyrush_rain`; rain ripples on SH_water.
8. Put one real road tile (`roads_-1_-1.glb` via `MaterialLibrary.apply`) into the lookdev (r1 SHOULD-FIX 8): it would
   have shown the speckle (MUST-FIX 3) and the flat soffit (MUST-FIX 2) on real UVs at once.

## Notes for the lead (other units, not this worker)
- car_model: the rear light bar is still a 2–3 px strip (rear view 3 m: max pixel (242,98,97); hero chase: 128 reddish
  pixels on the whole car); `M_LightBarRear` (E10, texture mean #DE0111) is the car's own material. Under AgX an E10 red
  desaturates to salmon — a wider bar at E3–4 with glow carrying the brightness will read as #FF1A2E. Body still faceted.
- buildings: during my `main.tscn` capture (03:01) blocks failed to load: `res://assets/city/blocks/textures/
  windows_far_emit.jpg` missing (`blocks_3_1.glb`, `blocks_-1_-1_far.glb`).
- Rain streak particles were visible in `main.tscn` without `--rain` (`review_environment_r2_game_*.jpg`) — fx/world
  should read `weather.rain_amount()`.

## Verified OK
- `tools/godot.sh check --only=res://shaders/,res://world/env/` → `CHECK 50 files, 0 failed, 0 engine errors, 0 warnings`.
- `test_materials.gd` → `TEST_MATERIALS 0 failed` (20 materials, weather globals, instance uniforms, the import-forwarding
  test); `test_environment.gd` → `TEST_ENVIRONMENT 0 failed`. Tests are `extends Node` via the test host ✓.
- `--rain` at boot snaps (probe: frame 1 rain 0.600, wetness 1.000) — r1 #13 ✓ (untested, see MUST-FIX 6).
- Texture library: 90/90 `.import` with mipmaps + VRAM compression, normal maps flagged — r1 #6 ✓; manifest grew
  additively 4 → 21 entries, nothing deleted ✓.
- River: a second probe, water roughness 0.08, `flow_b (0.044, 0.037)`, slab moved out of the river; no uniform gold
  sheet any more (river_low water #676670, R/B 0.93; warm only at the promenade lamps) — r1 #3 ✓.
- Headlights at z −2.40 pointing −Z, no tail hot-spots ✓; NPC paint built unconditionally (but see MUST-FIX 5).
- SH_sidewalk (PavingStones144) and SH_kerb (granite #8E8C86), #141416 back plates, CJK signs with real words
  (东方霓虹, 南京东路 Nanjing Rd. E), two blue under-deck lights ✓.
- car_paint: object-space peel (≈ 11 mm cells) and flake on different seeds, downward-face grime, wetness ✓;
  facade: `mm_seed`, no cladding normal on glass, `lit_ratio` 0.15 / 0.22, `tex_mean` ✓; road: ×4 detail normal faded by
  distance + AO; asphalt at 5 m shows grit, cracks and puddles ✓.
- Real roads: `SH_soffit_blue` UV v ∈ {0, 0.5, 1}, u in metres — the shader's edge-strip logic matches; asphalt, pier and
  marking meshes have no UVs and the shaders are world-space ✓.
- Hero chase camera (6 m back, 1.9 m up) ✓ (lead note 4). Lead note 3 (real SH_ materials on the boxes) ✓.
  Lead note 2 (neon streaks on the wet road): ✓ within the probe; re-check after MUST-FIX 1.
- Ownership: Write/Edit only in `game/shaders/**`, `game/world/env/**`, `status/environment.md` + additive texture
  library writes; `roadster.glb` was only read; `tmp/environment/` and `/tmp/t.gd` cleaned ✓.

## Evidence
```
check / tests                     -> as above (CHECK 50 files 0 failed; TEST_MATERIALS 0 failed; TEST_ENVIRONMENT 0 failed)
tools/godot.sh shot --scene=res://world/env/lookdev.tscn --out=review_environment_r2 --cams="hero34r:2.4,1.5,6.2:0,0.75,-0.5:50;
  rear:0,1.0,4.6:0,0.7,1.5:40;soffit2:3,1.4,-26:-2,9.3,-34:70;road5:1.5,1.3,2.5:2.5,0,-3.5:60;pier5:5.8,1.6,-25.5:9,3.2,-30:55;
  shop20:-4,1.7,-4:10.3,5,-24:55;street:0,1.3,-6:0,2.0,-140:55;npc:1.8,1.7,-2.5:4.2,0.7,-7:45;river2:15.5,2.5,-55:45,-0.5,-115:60;
  tower100:-3,2,12:16,45,-125:50"                     -> errors=0; fps 45-116 (shared machine)
  same with --quality=medium --out=review_environment_r2_med (street, soffitm)   -> street haze #745B4C (vol fog off: unchanged)
screenshot_stats (mine): PASS hero34r, rear, tower100; FAIL npc (P5 .012, P95 .362, SAT 1.73), pier5 (P5 .004),
  river2 (P50 .098, SAT .51), road5 (SAT 1.91), shop20 (P50 .263), soffit2 (HUES80 4; underdeck: SAT 3.9, HUES80 4),
  street (P50 .249).  Worker ld_*: 6/15 PASS (list in MUST-FIX 8); ld_soffit_under --zone underdeck: HUES80 4 FAIL
haze probe (tmp/review/haze_probe.gd, windowed via tools/slots.py heavy):  horizon 400x40@600,460 / road 400x40@600,660
  A shipped #695146 / #514036 | radiance_saturation 0 #695146 / #513F35 | cool ambient #2A2638 #62493D / #4F3D33
  quads hidden #403337 / #201D1F | + street lamps hidden #3D3136 / #1A181E | + Bund uplights / glow off: unchanged
crops (tmp/review/crops.py): ld_chase 80x50@760,330 #624E44 R/B 1.44; ld_pier 200x60@300,520 #735748;
  soffit2 640x260@250,0 #05276B sd 1.8; ld_soffit_under 300x100@600,60 #043488 sd 4.8; sh05 soffit 200x80@800,100 #35487E;
  ld_river 350x150@1150,650 #4F413B (warm lamp reflections); ld_river_low 400x150@900,650 #676670
glass probe: canopy 360x200@520,330  shipped #43312C sd 25.7 -> albedo_texture black #372221 sd 16.3
zone probe: after flight fog .00150 aerial .500; after default .00150 / .500; nanjing->underdeck first frame vol .00362
bench (90 s): low 37.07/61.64/50.45, medium 60.50/83.99/69.74, high 88.12/88.87/67.79, ultra 93.04/69.25/67.98 ms
glb: roadster SH_glass_gold has NO baseColorTexture; M_LightBarRear E10 tex mean #DE0111; body_panel_base mean #FEFEFE;
  roads_-1_-1 SH_soffit_blue v {0,0.5,1}; npc glbs: sedan_ev/suv_ev SH_car_paint_npc, taxi _taxi, police_patrol _police
real game: tools/godot.sh shot --scene=res://main.tscn --out=review_environment_r2_game --skip-menu --env-only --warm=120
  --cams="realdeck:-392,1.6,8:-389,6.8,-14:72;realroad:-430,1.5,-110:-470,1.0,-160:62"  (buildings load errors, see notes)
```
Images viewed: `captures/review/environment/{r2_worker_sheet_s,r2_mine_sheet_s,r2_pools_ab,r2_crops,r2_ref_cmp,r2_game,
r2_triplanar,r2_glass_ab}.jpg` (ref_cmp: sh05 | soffit2, sh07 | shop20, cp04 | ld_chase).
