# bund review round 1 — VERDICT: FAIL

Reviewer: lead / art director, 2026-10-20. Judged against briefs/bund.md, reviews/bund-lead.md (B-ART1..4 are
mandatory), SPEC/ART/CONTRACTS, SHANGHAI_DOSSIER §5/§12/§15, art DOSSIER §1.2/§3.4/§4.9/§5, and my own captures
(captures/review/bund/). The user asked "贴图纹理什么都要细化" — every texture refined. Today: every generated map is
≤ 512² (roof 256², flood wash 64×256), none of the normal maps reaches the glb, 7 materials are flat colours, and
the facades are lit by a flat emission. Round 2 is a rebuild of the look, not a tweak.

## Scores (0-10)
- function: 3 — glbs load, 25 nodes at the right z, sidecar + Empties exported, colliders present; BUT the whole
  promenade/flood wall is built on the wrong side of the road (inside the buildings), its south 228 m is missing,
  the preview uplights are 1° beams, 4 meshes have no material, no normal map is exported.
- visual: 1.5 — every capture shows flat tan boxes with square black or beige windows; none of B-ART1..4 is met
  (sheet_b.jpg puts my river view next to hsbc_customs_night_2026.jpg: gold row + blue cascades vs grey boxes).
- code: 4.5 — clean module split, deterministic, all files ≤ 288 lines; but the test is `extends SceneTree` (lead
  rule), the core lib is monkey-patched, and there are logic bugs (offset side, flute aliasing, Material-as-role,
  deg_to_rad).

## MUST-FIX

1. **Promenade + flood wall are on the WEST side of the road, inside the building row; south 228 m missing; plazas
   misplaced.**
   - Evidence: glb AABB `Bund_Promenade_flood` x −202.8…−159.9, z −978…−240; `Bund_Promenade_lantern` x −201.5…
     −135.7. It must be ≈ x −73 near z −330 (centreline x −121.6 + 49 m EAST). `r1c_stone2m.jpg`: the bull, the
     steps and the deck wall poke out of HSBC's south corner. `prom`, `flood`, `top` captures: no deck, balustrade,
     lantern or blue wall anywhere east of the road. Your `captures/bund_promenade.jpg` shows none of them either.
   - Cause: `promenade.base_path()` reverses the centreline to north→south; in Blender coords (x, −z) the tangent
     is then −Y and `offset_path()`'s right vector (ty, −tx) points WEST (the docstring "right vector is east" is
     wrong). `base_path` also drops (4.2, −10.2) via z0 = −18 and never inserts a start point, so the path begins
     at z −245.7. `promplazas`: bull target −118 and Chen Yi −150 get clamped to the path end (≈ −242); the
     Signal Tower uses `len(base) − 6` (≈ z −236).
   - Do: build the path south→north (or negate the offset) so +offset = east; insert the interpolated start point
     (0.4, −18); rebuild deck, wall, wash, balustrade, 32 balconies, 64 lanterns, 8 lamp columns, planters, stairs
     and the `-colonly` collider on the east side. Place with `_index_at(base, z)`: Meteorological Signal Tower
     plaza z ≈ −25 (Yan'an Rd end), Bund Financial Plaza + bull z ≈ −222 (Fuzhou Rd gap between No. 9 and No. 12),
     Chen Yi Square z ≈ −540 (opposite Nanjing E Rd) — all on the deck, east of the road.
   - Verify: test asserts the flood AABB x within −110…−40 and z covering −25…−960, river face x = −73 ± 1.5 at
     z ≈ −330; captures `top` and `prom` (cams in Evidence) show the lantern line + balustrade east of the road.

2. **The preview's 144 lights light nothing: `spot_angle` is set in radians.** (B-ART1)
   - `game/assets/bund/preview_bund.gd` `_make_light`: `light.spot_angle = deg_to_rad(55.0)` = 0.96°. Godot's
     `SpotLight3D.spot_angle` is in DEGREES → every uplight and crown light is a 1° pencil beam. This is why every
     facade in every capture is flat.
   - Do: `light.spot_angle = float(rec["angle"])`. Set the sidecar to the verified art-dossier values (§3.4):
     angle 40°, energy 25, range 30, pitch 80°, BUND_2500K #FF9F46 (now 55°/120/34 — tuned against the bug);
     crowns ≈ energy 40–60, range 45, #FFCF87 — tune on screenshots, no clipped stone. Add
     `distance_fade_enabled = true` (begin 60, length 20) and keep only the 32 lights nearest the camera active
     (re-pick every 0.25 s), i.e. the world unit's budget (≤ 32 visible).
   - Verify: in `road_n` and `prom` the bottom 6 m of each facade has ≥ 2× the luma of mid-height, crowns are lit,
     no stone pixel is 255; the preview prints the active light count (≤ 32).

3. **Remove the warm emission from the stone; neutral albedo; bake AO + variation so cornices draw dark lines.**
   (B-ART1, brief Build §4)
   - All 13 `Bund_Stone_*` materials carry emissiveFactor [0.18, 0.099, 0.032] (`mats.STONE_WASH` × 0.18) and
     `Bund_Dome_Stone` 0.22: a uniform glow that erases the base→crown gradient, fills every shadow and even turns
     the coffee-brown Broadway Mansions (#7A4A32) tan. Stone diffuse means are #C1BAAE…#DDD8CE — 15–30 % brighter
     than the brief's neutral #ABAAA3. The art dossier: "uplights on granite (lights, not emission)".
   - Do: emission 0 on all stone. ONE neutral granite texture (mean ≈ #ABAAA3); the per-building hue from the
     dossier table goes into COLOR_0 (≤ ±8 % value). Bake per building: AO (Blender bake AO → Color Attribute,
     distance 1.5 m; dice large facade faces to ≤ 0.75 m so the bake has vertices — the 1.2 M budget allows it)
     × ±8 % world-space macro noise (12–30 m) × dirt gradient (−15 % at 0–0.6 m) × hue. Wire Color Attribute ×
     base texture (Mix Multiply → Base Color) so the exporter writes COLOR_0 and Godot multiplies it in. The brick
     (No. 6/9/33), glazed-tile (No. 15/19) and coffee-tile (No. 0) buildings keep their own maps (MF5) + the same AO.
   - Verify: the `*_stone` primitives in the glb JSON have `attributes.COLOR_0`; on `hsbc_front` the 1 m band
     under the main cornice is ≥ 40 % darker than the wall 3 m below; in greyscale the base and crown are the
     brightest parts of each facade, exactly like hsbc_customs_night_2026.jpg.

4. **No normal map reaches the glb.** Every one of the 30 materials in both glbs has no `normalTexture` (glb JSON).
   - Cause: core `lib/mats.py` looks up `<id>_nor_gl.*`; `texgen.save_set` writes `<id>_nor.jpg`, so the lookup
     silently fails. Also `normal_from_height` uses ny = −gy (DirectX, Y-down); the pipeline (Blender/glTF/Godot)
     is OpenGL.
   - Do: write `<id>_nor_gl.jpg` with ny = +gy·strength; regenerate; rebuild; delete the old `_nor.jpg`.
   - Verify: glb JSON lists a normalTexture for every textured material; test checks
     `normal_texture != null` on every Bund_* StandardMaterial3D that has an albedo texture; on the 5 m capture the
     top edge of a block just BELOW a horizontal joint is lit from above (green > 128 there in the map).

5. **Texture detail — "贴图纹理什么都要细化" (SHANGHAI_DOSSIER §15, ART §5, art DOSSIER §5.2–5.3).**
   - Now: every generated map is ≤ 512² (granite 512 px / 1.8 m = 284 px/m; flood wall 190 px/m) vs the required
     512 px/m on Bund ground floors (0–8 m) and 256 px/m above; all 9 stone tints use the SAME seed (identical
     blotches on every building); no per-block tone, no soot, no edge wear, no AO/ORM, no macro variation.
     `r1c_stone2m.jpg` (2 m) is a smooth tan plane; `r1b_mid20.jpg` (20 m) shows no joints at all.
   - Do (a) granite ashlar set 2048² covering 2.4 × 2.4 m (≈ 850 px/m): 1.2 × 0.6 m blocks, 1 cm joints (8 px),
     per-block albedo ±5 % and per-block grain seed, chipped arrises (1.5 cm bevel in the normal, +8 % lighter
     edge), soot in joints (×0.55), rain streaks 0.3–1.5 m under every sill/cornice drip line, dirt 0–0.5 m at the
     base, ORM (AO from height; roughness 0.45–0.8 per block). Max 3 seed variants, buildings pick one.
   - (b) the brief's shared trim sheet (2048², one for the district): egg-and-dart, dentils, bead-and-reel,
     acanthus band, flutes, balusters, carved keystone, brass door frame — UV-mapped onto the cornice, capital,
     surround and door geometry (geometry stays; the trim gives it texture). The brief asked for it; "mouldings
     are geometry" does not replace it.
   - (c) every remaining flat material gets maps: `Bund_Copper_Lit` (standing seams every 0.45 m, verdigris
     streaks, emission mask), `Bund_Clock_Face` (1024² dial: Roman numerals, minute ring, hands — dark marks on
     #FFF6E0, E2), `Bund_Flag_Red` (weave + fold normal), `Bund_Bronze` (patina, polished nose/horns; the bull
     must be a sculpted ≥ 3 k-tri charging bull, not 148 tris of boxes), `Bund_Lantern_Paper` (palace-lantern
     panels, red/gold ribs, tassels, emission mask), `Bund_Foliage` (alpha-card leaf atlas), `Bund_Cove_Gold`
     (LED diffuser strip). Paving (sawn granite slabs, gum spots, stains, a tactile strip) and the flood wall
     (formwork 1.2 × 2.4 m, tie holes Ø 3 cm, efflorescence, rain streaks) at 2048².
   - Verify: `tools/blender.sh preview` prints no `UNTEXTURED`; stone/paving/wall maps ≥ 2048, others ≥ 1024;
     captures at 2 m / 5 m show joints, grain, soot and chipped edges; at 20 m no 2.4 m repeat is visible.

6. **Flood wall river face: blue light curtains every ~6 m, reflected in the river (B-ART3).**
   - Now: `Bund_Flood_Wash` is a continuous 64×256 gradient ribbon (flat), and it sits on the wrong side (MF1).
     Reference: hsbc_customs_night_2026.jpg, bottom band (separate bright cascades, dark wall between, a lit lip).
   - Do: an emission texture per 6.0 m module (1024×512): a 3.6 m wide curtain of fine vertical streaks (1–3 cm,
     random brightness along x), a bright lip under the coping (#29D3FF) fading downward to #1E8BFF and to 20 % at
     the water line; 2.4 m of unlit wall (concrete maps) between curtains; curtain E2.5–3.5, gap 0; ribbon 5 cm in
     front of the wall face. Give the preview water SSR/a ReflectionProbe so the cascades mirror as vertical streaks.
   - Verify: the `flood` cam shows ≥ 6 separate cascades with reflections; saturated neon ≤ 15 % of the frame;
     side-by-side `compare_floodwall.jpg` with hsbc_customs_night_2026.jpg.

7. **Windows: proportions, depth, interiors, never black holes (B-ART4, dossier §15).**
   - Now (`facade.front_wall`/`_window`): `win_w = min(pitch*0.52, 2.0)` and height 0.52 × floor → ≈ 2.0 × 2.1 m
     SQUARE windows (see `hsbc_front.jpg` vs hsbc_customs_day_2015.jpg — real ones are tall, ≈ 1:2); unlit glass
     renders as black holes (no reflection source); lit = 30 % flat untextured panes at linear (0.8, 0.496, 0.2)
     ≈ #E7BA7C beige, not amber #FF9F40.
   - Do: classical windows w 1.3–1.5 m × h 2.4–2.8 m, sill 0.9 m above the floor, glass 0.30 m behind the wall
     face, 6 cm dark-bronze mullion/transom bars (2 × 3 panes). A 2048² interior atlas (16 cells: curtains,
     blinds, ceiling lamps, shelves, office desks), one cell per window by UV offset. Lit ≈ 25 %: #FF9F40
     (linear 1.0, 0.346, 0.051) at E1 0.8 × per-window 0.6–1.0; unlit cells at E0 0.03–0.06 behind glass with
     roughness 0.06. Add a ReflectionProbe to preview_bund.tscn covering the row (≈ 900 × 90 × 140 m).
   - Verify: on `road_n` and `mid20` no window is pure black (min window luma > 12); lit windows read amber.

8. **Relief depth (B-ART2) — measured on `close_b18`, `close_hsbc` and in code.**
   - (a) rustication: `facade.shell` alternates course projection 0.45/0.36 m = 0.09 m steps, horizontal only.
     Need V-grooves 0.15 m deep both ways, blocks 1.2 × 0.6 m with 45° chamfers, voussoirs over openings.
   - (b) fluting is aliased away: `columns.column` uses flutes=20 with segments=20, so cos(20·2πi/20) = 1 at every
     vertex → every "fluted" shaft is a smooth 20-gon. Use 24 flutes and ≥ 96 segments.
   - (c) proportions: `r = height / 8.2` → H/D 4.1 (HSBC's portico shafts come out 3.6 m thick). Ionic H/D 9
     (r = h/18), Doric 8, Corinthian 10; real Ionic volutes (swept scrolls) and two rows of Corinthian leaves.
   - (d) HSBC (`trim.portico`): 6 columns evenly spaced, free-standing 3.2 m out, from the ground. Build what
     hsbc_customs_day_2015.jpg shows: 2-storey rusticated base with 3 arched entrances; above it 6 giant Ionic
     columns single-double-double-single spanning floors 3–5 in front of a wall recessed 0.8–1.0 m; entablature
     + triangular pediment; end pavilions; balustraded attic.
   - (e) window surrounds: alternating triangular/segmental pediments 0.25 m proud on the piano nobile,
     keystones, consoles under balconettes (today one head box per window). (f) dentils under every main cornice
     (0.15 × 0.20 × 0.15 m at 0.30 m pitch), modillions on HSBC, Customs House, Yokohama Specie.
   - Verify: `close_hsbc` (5 m) shows the grooves, pediments and flutes in raking light; tri total ≤ 1.2 M.

9. **Landmarks must be unmistakable (brief acceptance).** In `river_mid`/`hsbc_front`/`customs_front`: the HSBC dome
   is a smooth grey hemisphere, the clock faces are blank blown-out white discs, the Peace Hotel pyramid is a dull
   flat teal cap at E0.55 (dossier: E2), the Bank of China roof is black roofing felt (`Bund_Roof_Tar`), Broadway
   Mansions' setback stages are windowless boxes.
   - Do: HSBC dome with 16 ribs, drum of paired Ionic columns, lantern with oculi + finial; Customs House with the
     4-column Doric portico in the base, tower stages with corner piers + recessed bays, dials (MF5), bell stage
     arches, stepped crown, mast + flag; Peace Hotel pyramid steep, copper seams, E2–3 #21C08B over a gold-lit
     stone drum; Bank of China hipped roof in blue-green glazed cylinder tile (albedo ≈ #2E6E6A, tile normal),
     edge-lit; Broadway Mansions: windows on every setback, vertical brick piers, #7A4A32 brown.
   - Verify: Godot compare sheets at the reference photo's angle: compare_12 / compare_13 vs
     hsbc_customs_night_2026.jpg, compare_20 / compare_23 vs peace_hotel_boc_night_2026.jpg, compare_0 vs a photo
     that actually shows Broadway Mansions (check waibaidu_bridge_*_2019.jpg; bund_night_2023.jpg used now does
     not show it).

10. **Material objects used as role names → 4 meshes without material + garbage node names.**
    - `buildings.roles_for` stores a Material in `roles["band"]`; `facade.front_wall` calls `asm.box(band, …)` with
      it, so the bucket key is the Material: glb nodes `Bund_19_PalaceHotel_<bpy_struct, Material("Bund_Brick_Red")
      at 0x7b11f2de08>` (also Bund_6, Bund_9, Bund_33) export with NO material (Godot default white) and break the
      ASCII PascalCase naming contract (CONTRACTS §1). The Palace Hotel's signature red-brick bands (#9C4A3A on
      white tile #EDE9E0) and the white bands of No. 6/9/33 are effectively missing (12–72 tris).
    - Do: pass the role name `"band"` and map it to the material in `roles`; give the Palace Hotel a 0.5 m red-brick
      band at every floor line + the corner piers in brick, per peace_hotel_day_2019.jpg.
    - Verify: test fails on any primitive without material and on node names outside `[A-Za-z0-9_-]`.

11. **Tests + lead project rules.** `game/assets/bund/tests/test_bund.gd` is `extends SceneTree`; the lead rule
    requires `extends Node` (pattern: `res://core/tests/test_core_smoke.gd`, run by test_host). It also leaks the
    instanced scenes (487 resources/388 meshes reported at exit) — `free()` them. Add the checks from MF1, MF2
    (sidecar angle ≤ 60°, energy ≤ 40), MF4, MF10. The status says heights are "within 3 m" but the tolerance is
    6.0 (Asia measures 36 m vs 31 m): use 3 m and fix the models, or report the truth. Lead rule "scratch files
    are deleted when done": `tmp/bund/` (photo copies + shots.sh) is still there and status "How to test" depends
    on it — move the shot script into `blender/bund/`, update the status, delete `tmp/bund/`.

12. **Evidence must show what it claims.** False today: (a) `bund_promenade.jpg` "the lanterns and the balustrade
    in the foreground" — there are none (MF1); (b) "the capture tool's static-camera mode did not move the camera"
    — it works, every capture of this review used `--cams`; (c) compare sheets are Blender renders with
    `--boost=4` light at angles unlike the photos; compare_0's photo has no Broadway Mansions; the labels render
    CJK as tofu. Redo all evidence in Godot (`tools/godot.sh shot --scene=res://assets/bund/preview_bund.tscn
    --cams=…`), downscale, look at every image yourself, and describe only what is visible.

## SHOULD-FIX
1. `mats.py` monkey-patches `lib.mats.tex_path` at import (a patch around core code). Build the unit's materials
   with explicit paths in `blender/bund/mats.py`, or put a request for a `tex_dirs` option in status/bund.md.
2. All materials export `doubleSided: true` (Blender's default). Set `use_backface_culling = True` on every opaque
   material (halves fragment cost on 250 k+ tris, exposes flipped faces); keep two-sided only for flags/leaf cards.
3. Magic numbers in logic → named constants in `data.py`: lit fractions 0.30 / 0.20 (facade.py, trim.attic),
   course heights/projections 0.85 / 0.45 / 0.36, column ratio 8.2, jamb 0.26, portico offset 3.2, …
4. Delete stale Godot-extracted files from older exports (≈ 15 MB, unused): `game/assets/bund/bund_buildings_
   concrete_*`, `bund_promenade_concrete_*`, `bund_promenade_concrete_pavement_*`, `bund_promenade_concrete_wall_
   008_*` (+ `.import`).
5. Drop the self-flying camera in `preview_bund.gd` (one default view is enough); review shots come from `--cams`.
6. `texgen.py` OUT = "~/m/skyrush/…" hard-coded → derive from `__file__`. `preview_bund.gd` `_process(delta)` →
   `_delta`. `lights.py` UPLIGHT_STEP duplicates UPLIGHT_EVERY.
7. Crown lights exist for only 5 buildings; add Broadway Mansions, North China Daily News (two towers), Peninsula,
   Great Northern corner dome, Asia attic/pediment, Bank of Taiwan.
8. Side elevations: the 6 cm window panels stuck on the wall read as paint from the side streets; give them
   0.15 m reveals (cheap boxes) and the same interior atlas.
9. Keep the fog request to the environment unit open, but do not depend on it: once MF2/MF3 are done the row must
   read gold at ~300 m with today's fog.

## Verified OK
- Ownership: the worker log shows writes only in `blender/bund/**`, `game/assets/bund/**`, `status/bund.md`
  (+ scratch in `tmp/bund/`); no core/other-unit files touched.
- `tools/godot.sh check --only=res://assets/bund/` → 3 files, 0 failed, 0 engine errors, 0 warnings.
- `tools/godot.sh test res://assets/bund/tests/test_bund.gd` → 32 PASS, 0 FAIL (but see MF11).
- 25 nodes `Bund_<No>_<short_name>` at the dossier z (±1 m); Customs 79.2 m, Sassoon/BoC ≈ 77–80 m, HSBC dome 50 m.
- One 12-tri `-convcolonly` box per building (25); promenade `-colonly` exists (wrong side, MF1).
- Sidecar `bund_lights.json`: 144 records in game axes (139 `Uplight_*` at 1 m, 80° up; 5 `Crown_*`), and the
  same 144 Empties are exported in bund_buildings.glb.
- Budget: 250,692 + 44,194 = 294,886 tris of 1.2 M (HSBC 47 k, Customs only 9.4 k — room to add MF8/MF9 detail).
- Cornice projection 0.75–1.25 m and window surrounds 0.18 m proud meet B-ART2; window recess 0.25 m (needs 0.30).
- Files ≤ 288 lines; seeded/deterministic build; preview runs 155–177 fps at 1600×900 (lights broken, re-measure).

## Evidence
- `python3 -I tmp/review/bund/glbinfo.py <both glb>` → 30 materials, `nor=-` on every one; Bund_Stone_* emissive
  [0.18, 0.099, 0.032]; Bund_Flood_Wash emis=flood_grad_diff; Copper_Lit/Clock/Flag/Bronze/Lantern/Foliage/Cove
  have no textures.
- `tools/blender.sh preview game/assets/bund/bund_promenade.glb …` → `tris=47162`, UNTEXTURED: Bund_Bronze,
  Bund_Foliage, Bund_Lantern_Paper; `…bund_buildings.glb …` → `tris=250692`, UNTEXTURED: Clock_Face, Copper_Lit,
  Cove_Gold, Flag_Red; every image 512×512 (roof 256, flood 64×256).
- Promenade AABBs (glb accessors): flood x −202.8…−159.9 z −978.5…−239.8; lantern x −201.5…−135.7; bronze bull
  x −142.5…−138.7 z −243.2…−241.3 (inside HSBC). Meshes without material: 4 (node names quoted in MF10).
- Texture means (ffmpeg 1×1): granite #A4A29C, stone_grey #C1BAAE, stone_cream #DAD3C6, stone_white #DDD8CE,
  tile_coffee #774832.
- Godot captures (all `--scene=res://assets/bund/preview_bund.tscn --warm=45`, in captures/review/bund/):
  `review_bund_r1_*.jpg` cams `road_n:-101,1.3,-230:-126,5,-330:70; road_s:-139,1.3,-640:-150,10,-545:70;
  close5:-124.5,1.7,-252:-130,6,-272:70; prom:-82,4.2,-385:-130,18,-300:62; flood:-40,-1.2,-385:-73,0.5,-335:60;
  river_mid:60,8,-360:-130,26,-330:50; river_far:230,10,-380:-130,28,-330:40`;
  `r1b_*.jpg` cams `top:-120,260,-330:-120,0,-331:60; close_b18:-152,1.7,-478:-157.5,6,-494:70;
  close_hsbc:-125,1.7,-236:-130.5,7,-252:70; mid20:-137,1.6,-462:-157,11,-490:62; far100:-60,6,-520:-157,35,-569:55`;
  `r1c_*.jpg` cams `hsbc_front:-88,10,-268:-130,22,-268:62; customs_front:-90,14,-322:-137,38,-328:66;
  stone2m:-128,1.6,-240.5:-130.6,1.2,-243:60`. Contact sheets: sheet_a (road/5 m/prom), sheet_b (flood/river +
  hsbc_customs_night_2026.jpg), sheet_c (5 m/20 m/100 m), sheet_d (fronts + hsbc_customs_day_2015.jpg + 2 m),
  worker_4views.jpg, worker_compares.jpg. Reuse these cams for round 2 (prom lands on the deck once MF1 is fixed).
- ART §10 on these frames: 1 value structure FAIL (uniform tan, no gradient) · 2 palette FAIL (tan, no gold, no
  blue wash) · 3 detail 5/20/100 m FAIL · 4 tiling n/a (too faint) · 5 scale FAIL (stubby columns, square
  windows) · 6 emissives FAIL (blown clock discs, beige panes) · 7 recognisable weak · 8 edges FAIL (no bevels/
  normals) · 9 FAIL (promenade inside buildings, material-less meshes) · 10 store shot: no.
