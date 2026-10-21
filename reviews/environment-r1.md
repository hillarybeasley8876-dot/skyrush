# environment review round 1 — VERDICT: FAIL

Reviewer: art director (Opus). Brief: `briefs/environment.md`. Lead notes `reviews/environment-lead.md` (E1, 1–4) are mandatory.
User demand for this project: **贴图纹理什么都要细化** — every texture/material must be refined. Captures I made:
`captures/review_environment_r1_{chase,car34,road5m,pier,soffit,facade20,far100,river,close,canopy,road100}.jpg`,
`captures/review_environment_r1_rain_chase.jpg`, sheets in `captures/review/environment/`.

## Scores (0-10)
- function: **5** — check/tests green, weather + presets wired; but 4 acceptance items fail (SH_car_paint_npc not in the
  lookdev, Roadster light bar not glowing, preset cost unmeasured, lead notes E1 + 1 unsatisfied) and other units' SH_
  colours/textures are thrown away by the shared shaders.
- visual: **4** — wet asphalt at 5 m is good; everything else reads grey-box: solid blue soffit, black piers, warm brown
  haze, gold-foil river, flat kerbs/pavement/lightboxes, two white hot-spots on the car's tail. Not a store screenshot.
- code: **6** — typed, small files, clean check; but several shader maths bugs (texture-mean normalisation, object-space
  height on centred meshes, UV-scale assumptions) and dead uniforms.

## MUST-FIX

1. **Lead E1 — soffit reads as a solid blue ceiling (NOT fixed).** Measured in my drive-under view
   (`--cams="soffit:-1,1.6,-20:0,9.3,-31:80"`): `screenshot_stats --zone underdeck` → P50 **0.315** (max 0.30), P95 0.797
   (max 0.78), SAT **32.8 %** (max 26 %); soffit mean #386ED0 (sh05 reference #2357F3). Cause in
   `game/shaders/soffit_blue.gdshader`: EMISSION is a flat `wash_color*wash*wash_energy` that ignores the concrete, ALBEDO is
   the raw texture ×0.55 (brown), strip colour #5AA3FF + white core, strip half-width 0.012 v (= 18 cm on a 15.4 m soffit).
   Do: (a) `wash_falloff` 0.55 → **0.45** (100 % outer edge → 55 % at the girder; roads' soffit UV v = 0,1/3,2/3,1 across the
   wing–flat–wing profile, `blender/city/roads/deck.py:60-84`); (b) ALBEDO = **#6E6C68 × (texture / its measured mean)**;
   (c) modulate the wash by the concrete: `EMISSION = wash * mix(1.0, tex_luma / tex_mean_luma, 0.45) * (1.0 - 0.35 * grime)`
   so formwork joints, stains and the 4 m panel grooves show through; grime noise less stretched (`vec2(0.15, 0.4)`, not
   `vec2(0.06, 0.5)`); (d) LED strip: colour **#5A3DFF**, energy 4–5 (E3–E5), *thin*: new uniform `strip_width_m = 0.05`
   + `soffit_width_m` (default 15.4) so the strip is 5 cm, core whitening ≤ 0.3×. Verify: the drive-under camera above
   (add it to `lookdev_cams.json` as `soffit_under`) passes `--zone underdeck`, and a 1:1 crop shows concrete texture
   inside the blue wash.

2. **Lead note 1 — haze is still warm brown (NOT fixed).** Mean colour at the street vanishing point (chase cam crop
   760,330,80×50) **#694F3B**; ground haze under the deck (pier cam crop 300,520,200×60) **#6E5340**; your own number
   #4E3C38 is warm too (R/B 1.4). Target: haze B ≥ R, roughly #34304A–#4A4458; warm only in local halos around lamps.
   The street volume is lit warm by six #FFCEA6 lamps with `light_volumetric_fog_energy 0.1` + ambient inject of the warm
   HDRI. Try in this order and re-measure each step: `volumetric_fog_ambient_inject` 0.15 → **0.03**; street lamps
   `light_volumetric_fog_energy` 0.1 → **0.04**; colour spills 0.08 → 0.03; `volumetric_fog_emission` **#14122A** with
   `volumetric_fog_emission_energy` ~1.0 as the cool base; cool the sky radiance (item 3c). Verify with
   the mean-colour crop command in Evidence on the chase and drive-under views; list before/after hex in status.

3. **Gold-foil Huangpu (DOSSIER 1.4 Don't #6) — and the status claim "the river camera is framed to avoid it" is false:**
   your own `captures/lookdev_river.jpg` shows a golden sheet; my river view water crop (1150,650,350×150) = **#55433A**.
   The only probe covers x −17…17; the water is x 17…63, so it mirrors the HDRI's gold Bund. Do: (a) a second
   ReflectionProbe over the river (size ≈ 50×30×200, capture 2 m above the water, box projection, UPDATE_ONCE);
   (b) `SH_water` roughness 0.22 → **0.08** (DOSSIER 4.9; keep crest +0.1); `flow_b` (−0.07, 0.07) is 135° from flow_a and
   0.43 m/s — set **(0.044, 0.037)** (= 0.25 m/s at 40° after the ×1.37 / 6 m scale); delete unused `foam_amount` or use it;
   (c) in `sky_night_city.gdshader` AT_CUBEMAP_PASS add `radiance_tint` (#7E86A8) and `radiance_saturation` (0.35) so any
   reflection that misses a probe is cool and never gold. Verify: add `river_low:18,1.2,-40:40,-0.5,-95:60` to the cams;
   water crop B ≥ R, no gold sheet. Also move the residential slab at (30, 12, −74) (spans x 17–43) out of the river.

4. **Hero shot / acceptance "Roadster: white clear-coat, gold glass, glowing red bar" — FAIL.** `lookdev_builder.gd:191`
   puts the "player headlights" at **z = +2.6**, i.e. 0.5 m *behind* the rear bumper (Roadster Body z −2.29 front … +2.09
   rear, faces −Z), shining forward into the car's own tail: two blown white hot-spots (mean RGB 177,174,175, max 255) on
   the rear, while the reddest light-bar pixels are only (130,65,67). Move them to **z = −2.40**, y 0.7, x ±0.75, pointing −Z.
   Then measure the bar again: it must be the brightest saturated accent of the chase frame; if it still renders as a dim
   1–2 px strip, file a request to car_model in your status (M_LightBarRear, emissive 10) with the crop as proof.
   **Acceptance "all SH_ materials appear in the lookdev" — FAIL:** `build_hero()` returns early when the Roadster glb exists
   (line 307), so the `SH_car_paint_npc` car (line 322) is never built; your status claims it is in the capture. Build the NPC car
   unconditionally (blue #1F3A5F via `set_instance_shader_parameter`), and also a silver (#9DA3A8) one.

5. **Imported SH_ colours and textures are discarded — every other unit loses its detail.** MaterialLibrary forwards only
   `albedo_texture/normal_texture/roughness_texture/emission_texture`, and only if the shader declares them:
   - `neon_tube`: colour/energy are instance uniforms with a pink default → every prop/building neon exported as `SH_neon`
     (`blender/props/materials.py:146-151`, per-sign emission colours; `blender/city/buildings/kit.py:47`) renders the
     same #FF2A8A. Add plain `uniform vec4 emission_color` + `uniform float emission_energy` as the per-material default and
     make the instance `neon_color` an override only when its alpha > 0 (instance default `vec4(0.0)`); also declare
     `emission_texture` (white default, multiplies the tube colour: glyph/colour mask for channel letters).
   - `hologram_billboard`: rename `content` → **`emission_texture`** so the props' ad artwork is forwarded per asset.
   - `car_paint`: add `albedo_texture` (× base colour, default white) and `roughness_texture` (× roughness) — the Roadster's
     4096² `body_panel_base` and npc_cars' `npc_paint_rough.png` are dropped today; base colour: same plain-uniform +
     instance-override pattern (`albedo_color` default, instance `base_color` alpha > 0 overrides) so SH_car_paint_npc
     traffic is not all Ano White when the traffic unit forgets a car.
   - `glass_tinted` / `glass_gold`: add `albedo_texture` (dirt/grime from the import, e.g. `npc_glass_grime.png`).
   - Add **`SH_car_paint_police`** (#F2F4F5, metallic 0, rough 0.35, clear coat 1.0/0.06, grime 0.35) and
     **`SH_car_paint_taxi`** (teal #1E8C8A) with the livery from the imported albedo on UV2 — npc_cars already exports
     these names (`blender/npc_cars/palette.py:34-37`), today they fall back to plain imported materials.
   - Status *Requests → lead/core*: `MaterialLibrary._with_textures` should also copy `albedo_color` → `albedo_color`,
     `emission` → `emission_color`, `emission_energy_multiplier` → `emission_energy` when the shader declares them.
   Verify: new test in `test_materials.gd` — a StandardMaterial3D named `SH_neon.001` with emission #19E6FF and an albedo
   texture, after `MaterialLibrary.apply()`, yields a ShaderMaterial whose forwarded texture/colour match (the colour part
   passes once core lands; the texture part must pass now).

6. **Shared texture library is imported without mipmaps or compression (48 / 48 `.import` files):**
   `mipmaps/generate=false`, `compress/mode=0`, `"vram_texture": false` for asphalt_02, aerial_asphalt_01, concrete,
   concrete_wall_008, rough_concrete, granite_*, concrete_pavement, Asphalt031. Without mips the road, granite and concrete
   alias/sparkle at 20–100 m and anisotropic filtering does nothing (DOSSIER 5.4: "VRAM Compressed, mipmaps on").
   Set for every texture your SH_ materials use: `compress/mode=2`, `mipmaps/generate=true`, `*_nor_gl`:
   `compress/normal_map=1` + `compress/high_quality=true`; run `tools/godot.sh import`; note the change for the lead in
   status (it is the shared library: no deletions). Verify: `grep -c "mipmaps/generate=true"` = number of files and
   `"vram_texture": true` in each; a moving 100 m road view (`--times=1,2 --press=accelerate`) shows no shimmer.
   **Deliverable 4 incomplete:** only 4 texture sets + 1 HDRI fetched; DOSSIER §5.1 lists ~45. Fetch at least what the
   shared materials need and wire it in: `polyhaven clean_asphalt`, `ambientcg Asphalt025C`, `ambientcg Concrete046`,
   `ambientcg Leaking004`, `ambientcg Leaking016A`, `ambientcg SurfaceImperfections001`, `ambientcg PavingStones144`,
   `ambientcg TactilePaving003`, `ambientcg Facade009`, `hdri vignaioli_night`, `hdri kloppenheim_07_puresky`.

7. **`concrete_stained.gdshader` maths bugs (piers render black #0D0A11, barriers brown):**
   - `col = base_color * (alb / 0.5)` (line 63) assumes a texture mean of 0.5 linear; measured means are concrete **#73695B**,
     concrete_wall_008 **#8D8571** → resulting albedo ≈ **#494136** (pier) / **#5B5444** (barrier) instead of the cool grey
     **#7A7874** (ART §5 "cooler grey"). Add `uniform vec3 tex_mean` (linear, per material, set by `material_factory.gd`
     from a measured mean) and use `base_color * alb / tex_mean` — per-channel, so the warm scan is neutralised.
     Same bug in `facade_windows.gdshader:97` (`/ 0.5`: residential wall ≈ #6A5E4A instead of #8E877C).
   - Splash zone uses object-space `VERTEX.y` (lines 34, 67): every centred primitive (lookdev piers h 9.3 m, deck box,
     kerbs) gets the **whole lower half** darkened + wet. Add `instance uniform float base_y = 0.0` (object-space height of
     the object's base; 0 = origin at the base, the Blender export convention) and use `VERTEX.y - base_y`; set it in the
     lookdev for centred meshes. Verify: pier close-up shows a dark band exactly 0–0.6 m.
   - Triplanar normal maps are fed to NORMAL_MAP in the mesh's own tangent space — wrong for 2 of 3 projections. Do a
     world-space whiteout blend per axis and write `NORMAL = (VIEW_MATRIX * vec4(n_world, 0.0)).xyz`.
   - DOSSIER 4.3 detail layer missing: concrete_wall_008 diffuse ×3 MUL with a stretched noise mask, AO from `*_ao.jpg`,
     drips from the `Leaking*` opacity maps instead of pure noise (`world_pos.y * 0.045` → uniform).

8. **`car_paint.gdshader`:**
   - Grime uses panel-local `VERTEX.y`. Roadster panels are separate nodes with their own origins: Hood (origin y 0.69,
     local −0.04…+0.02), Door_L (0.66, −0.38…+0.22), Bumper_F (0.25, −0.13…+0.16) → the **whole hood and front bumper and
     2/3 of each door** get 15 % #2E2A26 grime, roughness 0.12 → 0.22 and clear coat ×0.85, while the Body next to them is
     clean — a visible step at every panel gap. Add `instance uniform float panel_offset_y` (height of the mesh origin in
     car space) and use `VERTEX.y + panel_offset_y`; request core (MaterialLibrary) or vehicle to set it; until then base
     the grime on downward-facing normals only.
   - `peel_normal` and `flake_normal` are the **same** texture (`_noise(0.9, 5, 256, true)`, material_factory.gd:170-173);
     frequency 0.9 ≈ 1 px period = white noise; sampled at `UV*45` / `UV*420` although the Roadster UV0 is ≈ 1 unit per mm
     (0…5467) → fully mip-averaged, no orange peel exists on screen. Sample both in **object space** (metres, triplanar):
     peel cells 8–12 mm, soft noise (freq ≈ 0.06, bump ≈ 2), flake a different seed, strength ≤ 0.03.
   - Declared `skyrush_wetness` is unused: wet grime must be darker and glossier when wet (brief: "wet grime").

9. **`glass_gold.gdshader` assumes 0…1 UVs.** The canopy UV0 is in metres (u −0.84…+0.84, v −0.61…+2.75), so
   `interior(glass_uv)` (lines 30-33) brightens only the square u,v ∈ [0,1] — the pale off-centre blob in
   `review_environment_r1_canopy.jpg`. Drive the interior read-through by view angle / real alpha, and the rain streaks by
   object-space position (metres, running toward the rear). Verify with a canopy close-up camera in the lookdev.

10. **`facade_windows.gdshader`:** (a) the MultiMesh seed the lead added to the verified shader is missing — copy
   `varying float mm_seed; mm_seed = INSTANCE_CUSTOM.x;` and `seed = (building_seed + mm_seed * 997.0) * 17.31 …` from
   `ref/art/lookdev/shaders/facade_windows.gdshader` (DOSSIER 4.4); (b) the cladding normal map is applied on the glass:
   `NORMAL_MAP = mix(nrm, vec3(0.5, 0.5, 1.0), glass)`; (c) lit-window area: office 0.30 × 0.82 × 0.533 = **13 %**,
   residential 0.55 × 0.95 × 0.3025 = **16 %** of the façade; ART §2 (binding over the dossier) says 2–8 %, §5 "~6 % lit":
   office `lit_ratio` → **0.15**, residential → **0.22** (≈ 6–7 %); (d) `/ 0.5` normalisation → `tex_mean` (item 7).

11. **`road_wet.gdshader` — the road is the most-seen surface and has no close-up detail layer.** DOSSIER 5.3 #4 "detail
   normal at ×4 frequency" is absent and `asphalt_02_ao.jpg` is unused. Add a detail normal (same normal map at
   `uv * 4.0`, whiteout blend 0.5, faded by `fwidth` so it never sparkles far away) and AO (`ao_texture`,
   `AO = mix(1.0, ao, 0.8)`). Verify: 1:1 crop at 5 m shows grit + micro relief; no sparkle at 100 m.

12. **Flat untextured surfaces beside the road (ART §5 rule 1, DOSSIER 1.4 DO #6).** In `road5m`/`pier` views the
   pavement is a flat slab (crop 1000,750,400×120: mean #231C23, luma stdev **2.2**), kerbs are flat, shopfront walls are
   black below 7.8 m, the lightboxes (`lookdev_builder.gd:259, 269`) are blank cream quads, piers are black.
   Do: shared `SH_sidewalk` (concrete_pavement 1.8 m or PavingStones144, joint normal, wet darkening, tactile strip
   TactilePaving003 30 cm) and `SH_kerb` (granite_bund darkened #8E8C86, DOSSIER 4.9); lightboxes with real content
   (reuse a sign PNG from `game/assets/props/textures/`, E2 2–3); 2 shadowless OmniLights #2357F3 (energy ≈ 1.2,
   range 12) under the deck so piers read blue-lit grey like sh05, not black. Verify: pavement crop stdev ≥ 6, pier
   mid-height mean ≥ #2E3448, new cams `kerb5m` and `pier_base` in `lookdev_cams.json`.

13. **Weather `--rain` at boot ramps for 4.8 s.** `_ready()` pushes rain 0, then `set_rain(true)` only sets the target
   (`weather_controller.gd:30-37`, 0.125/s) → a capture with the default warm of 60 frames sees rain ≈ 0.12. Snap
   `_rain/_wetness` to the targets when the option is present at boot; keep the smooth ramp for runtime toggles. Verify in
   `test_environment.gd` that after `set_rain(true)` at boot the global reads 0.6 on the next frame.

14. **Acceptance "preset costs within tech dossier §5 budget" — unverified.** Your table (low 109/79, medium 80/105 fps)
   is noise, and 2.46 ms is copied from the dossier, not measured. Build the 8-view method (tech dossier §3.1:
   7 × 1920×1080 SubViewports sharing World3D + camera, `ref/tech/probe/scripts/bench.gd` as the model) as
   `game/world/env/lookdev_bench.gd`, interleave low/medium/high/ultra × 3 on the `hero` and `soffit_under` cams, report
   ms/view per preset; pass = high ≤ 10 ms GPU/view and the high−low post delta ≤ 3.0 ms.

15. **Re-capture everything and re-run `screenshot_stats` on ALL cams incl. the new ones** (`soffit_under`,
   `river_low`, `kerb5m`, `pier_base`, `car_close`, `canopy`): default zone, soffit cams with `--zone underdeck`.
   My non-cherry-picked views fail today: soffit (above), `road100` P50 0.252 (warm haze), `facade20` SAT 23.8 % (default) and HUES80 1 with `--zone nanjing` (target 2–4).

## SHOULD-FIX
1. Per-zone environment overrides (DOSSIER 3.1): `set_zone(&"default"|&"nanjing"|&"underdeck"|&"flight")` on the
   environment node with a 2 s blend (Nanjing volumetric 0.009, underdeck 0.008, flight fog 0.0015 + aerial 0.5).
2. Rain look: cross-fade the sky radiance to `vignaioli_night` with `skyrush_rain`; rain ripples on `SH_water`.
3. Dead code: `environment_controller.gd` `_weather` (never used), `road_marking.gdshader` `skyrush_rain` (declared,
   unused), `water_river` `foam_amount` (unused).
4. Docs/tests drift: README says the HDRI radiance is 0.25 (code 0.18); `test_environment.gd` prints "is not 0.25" for a
   0.18 check; the env test asserts your own tuned numbers, so it cannot catch a regression against the dossier — name
   the deviation and its reason in a comment next to each changed value.
5. Lookdev: bake one GB straight arrow + 公交 text with `ref/art/lookdev/tools/bake_road_glyphs.py` into
   `game/world/env/lookdev_tex/` and place it, so `road_marking` `use_mask` is exercised; add back-plates #141416 and
   brackets to the neon (DOSSIER 4.5); one CJK channel-letter sign; a real 1024×576 ad on the hologram.
6. Bund block: uplights every 5 m along the whole face, 1 m from the wall, 40° (DOSSIER 3.4), plus cornice/pilaster boxes,
   so the 2500 K wash climbs the façade as in sh01 instead of a scalloped band at the base of a plain box.
7. `car_paint` / `glass_gold` use `cull_back` but the Roadster glb materials are double-sided: check the wheel arches and
   the underside for see-through holes in a close-up; switch to `cull_disabled` if any.
8. Use a real exported road tile (`game/assets/city/roads/roads_-1_-1.glb` + `MaterialLibrary.apply`) next to the
   primitives, so the shared materials are judged on real UVs, vertex colours and mesh origins.
9. `lookdev_builder.gd` is 355 lines and these fixes will push it over 400: split it first (street / structures / city /
   hero), as a separate step. Type the loop variables and arrays (`for x: float in […]`, `var cols: Array[Color]`).
10. Scratch hygiene: `/tmp/t.gd` is still on disk — delete it; scratch belongs in `tmp/environment/`.

## Notes for the lead (other units, not this worker)
- car_model: the Roadster UV0 on `SH_car_paint` spans 0…5467 × −3789…1 (≈ 1 UV unit per mm) with no
  KHR_texture_transform, so the 4096² `body_panel_nor` tiles every millimetre — the baked panel gaps cannot show with any
  shader. Body shading is faceted (flat normals) in every close-up. The rear light bar renders as a dim 1–2 px strip.
- CONTRACTS §2 still names `SH_facade_lit` as an example; the library has `SH_facade_office` / `SH_facade_residential`.
- npc_cars builds liveries with a Blender Mix node (`blender/npc_cars/materials.py:139-163`); check that the glTF export
  carries the livery image at all before the shaders unit wires `SH_car_paint_police/taxi`.

## Verified OK
- `tools/godot.sh check --only=res://shaders/,res://world/env/` → `CHECK 40 files, 0 failed, 0 engine errors, 0 warnings`.
- `test_materials.gd` → `TEST_MATERIALS 0 failed` (16 materials, 7 weather shaders, 5 instance-uniform sets, library lookup);
  `test_environment.gd` → `TEST_ENVIRONMENT 0 failed`. Tests are `extends Node` via the test host (lead rule) ✓.
- All 12 shaders and 16 `SH_*.tres` exist and compile; files ≤ 355 lines; GDScript typed; factory regenerates the set.
- Recipe: AgX (exp 1.0, white 10, contrast 1.3), glow levels 0/0.5/0.7/0.4/0.15/0/0 thr 1.2, fog #2A2638, volumetric
  albedo #9AA0B8, SSR/SSAO/volumetric per `Settings` preset and re-applied on `Settings.changed`; SSIL/SDFGI off.
- Moon #9FB4FF 0.06 shadowless, flight mode 0.12 + 4-split shadows. Globals registered in `project.godot`; wetness
  default 0.85, rain 0.6; `weather` group API (`set_rain`, `rain_amount`).
- Conditioned granite mean measured **#ABAAA3** ✓; the street ReflectionProbe works: street puddles mirror our lamps and
  neon, no gold in street puddles (lead note 2, street part) ✓; asphalt at 5 m: grit, cracks, pink neon streaks ✓.
- Hero camera = chase distance (0, 1.9, 6) → (0, 0.85, −1), 55° (lead note 4, camera part) ✓.
- Ownership: Write/Edit only in `game/shaders/**`, `game/world/env/**`, `status/environment.md`, plus additive writes to
  the shared texture library / manifest (no deletions). The `ref/art/*` diffs (22:01–22:02) are the lead's, not the worker's.

## Evidence
```
tools/godot.sh check --only=res://shaders/,res://world/env/   -> CHECK 40 files, 0 failed, 0 engine errors, 0 warnings
tools/godot.sh test res://shaders/tests/test_materials.gd      -> TEST_MATERIALS 0 failed
tools/godot.sh test res://world/env/tests/test_environment.gd  -> TEST_ENVIRONMENT 0 failed
tools/godot.sh shot --scene=res://world/env/lookdev.tscn --out=review_environment_r1 --cams="chase:0,1.9,6:0,0.85,-1:55;
  car34:3.4,1.25,-4.6:0,0.6,-0.6:50;road5m:3.2,1.5,-3:5.6,0.0,-9.5:62;pier:3.5,1.7,-21:9,2.6,-30:60;
  soffit:-1,1.6,-20:0,9.3,-31:80;facade20:-3,2.2,-18:10.8,6.5,-33:62;far100:-2,3,15:22,35,-110:55;
  river:16.5,1.4,-40:40,-0.4,-90:60"            -> errors=0, fps 35–86 (machine shared with other jobs)
tools/godot.sh shot ... --cams="close:1.9,1.15,-1.2:0.3,0.75,-1.4:50;canopy:1.2,2.1,1.8:0,0.9,-0.6:45;
  road100:0.8,1.3,10:0,0.0,-110:35"; and --rain --warm=420 --cams="chase:..."   -> errors=0
screenshot_stats.py (worker's 9 lookdev_*.jpg)          -> all PASS (re-run, matches status)
screenshot_stats.py (mine): chase PASS, far100 PASS, pier PASS, rain_chase PASS; road100 FAIL P50 0.252;
  road5m FAIL P95 0.795; soffit --zone underdeck FAIL P50 0.315 / P95 0.797 / SAT 32.8 %; facade20 FAIL SAT 23.8 %
mean colours (ffmpeg crop -> 1x1): haze chase #694F3B, haze under deck #6E5340, soffit #386ED0 (sh05 #2357F3),
  river water #55433A, pier mid-height #0D0A11, pavement #231C23 (luma stdev 2.2), road at 5 m #251C1B
light bar vs hot-spots (chase): reddest bar pixels (130,65,67); lamp blob mean (177,174,175), max (255,254,255)
texture means: concrete #73695B, concrete_wall_008 #8D8571, asphalt_02 #5B5955, granite_bund #ABAAA3
grep game/assets/textures/*/*.import: 48/48 mipmaps/generate=false, "vram_texture": false
glb (python, roadster.glb): Hood T y 0.69 local y −0.04…0.02; Door_L T y 0.66 local −0.38…0.22; Bumper_F T y 0.25;
  Glass UV0 u −0.84…0.84 v −0.61…2.75; Body UV0 0…5467 (≈ 1/mm); SH_car_paint has baseColor + normal textures
```
Sheets viewed: `captures/review/environment/{sheetA,sheetB,cropsA,cropsB,sheetC,ref_cmp,worker_sheet}.jpg`
(ref_cmp = sh05 vs my soffit view, cp06 vs my chase view).

Measurement one-liners used above (run from `captures/`):
```
# mean sRGB of a crop:   ffmpeg -v error -i IMG -vf "crop=W:H:X:Y,scale=1:1:flags=area" -f rawvideo -pix_fmt rgb24 - | xxd -p
# luma stdev at 1/4 res: ffmpeg -v error -i IMG -vf "crop=W:H:X:Y,scale=iw/4:ih/4:flags=area,format=gray" -f rawvideo - \
#                          | python3 -I -c "import sys,statistics as s;v=list(sys.stdin.buffer.read());print(s.mean(v),s.pstdev(v))"
```
