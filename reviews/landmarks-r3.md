# landmarks review round 3 — VERDICT: FAIL

## Scores (0-10): function, visual, code
- **function 5** (r2: 4). All 10 glb load; check 12 files / 0 errors; test 63 PASS / 0 FAIL; colliders on every
  solid asset; manifest and preview agree. But the preview light rig makes 0.4°-wide pencil beams (unit bug), no
  aviation beacon blinks anywhere, the OPT LED dots do not chase, and 5 of the 7 mandatory lead notes fail (L-ART1 is only partly met).
- **visual 3.5** (r2: 3). Better: the OPT dot shell at 45 m (P95 0.613, SAT 7.6 %), the SWFC aperture outline, the
  Jin Mao gold setbacks, the three LED ads, the Waibaidu rivets at 5 m. Still failing:
  - the hero pillar still reads as bathroom tiles;
  - the skyline is dark from the Bund and from the air: bund P95 0.218 / SAT 0.000 %, trio_air P95 0.233 / SAT 0.000 %;
  - the Nanpu is a grey frame from the spiral, and the Lupu rainbow renders white.
- **code 5**. Files ≤ 370 lines, static typing, clean ownership. But:
  - the `spot_angle` unit bug, and the energies that were tuned around it;
  - the pillar ORM is wired as AO only, with constant roughness and metal (`pack=False`);
  - IMPORT-CHURN (a mandatory lead note) is violated;
  - a stale extracted texture, and scratch left in `/tmp`.

Lead notes: L-ART1 partly, **L-ART2 FAIL**, L-ART3 OK at close range, **L-NIGHT1 FAIL**, **L-NIGHT2 FAIL**,
**L-NIGHT3 FAIL**, **IMPORT-CHURN FAIL**. The ART-NIGHT notes (10:20) arrived after your round. They are
mandatory all the same; ART.md §11 is the spec.

Work order: 1 → 2 → 3 → 4, then 5-9. After each item:
1. Rebuild.
2. Run the test.
3. Capture with the cams in "Evidence".
4. Paste the real output into `status/landmarks.md`.

## MUST-FIX

1. **[L-ART2] The pillar relief still reads as tiles, not as a crafted bronze-on-steel relief.**
   Evidence: `captures/review/landmarks/r3_pillar_tex.jpg` (your own maps), `r3_sheet_pillar.jpg` (vs `c_pillar.jpg`), `review_landmarks_r3_g_pillar_2m.jpg` (in game).
   - **(a) The 雷纹 is a checkerboard printed on the steel.**
     - `tex_pillar.py:149-169 meander_field()` strokes a spiral into every 0.30 m cell of the whole 15.7 × 29.4 m surface and alternates the hand per cell.
     - It renders as alternating plain squares and nested squares: a tile grid. The dossier puts the fret *inside the bronze ground* of the relief.
     - Do:
       - Delete the full-surface grid.
       - Inside each relief panel, fill the space around the dragons with a recessed dark-bronze ground. Give that ground a continuous running fret: cell 0.15-0.20 m, line 0.02 m, groove 0.012 m.
       - Add angular cloud hooks (C/S hooks, 0.25-0.6 m, raised 0.04 m).
       - Keep plain brushed steel in 0.6-1.0 m bands at the deck levels (`PANEL_Y`), at the panel edges and in the gaps between cloud hooks.
       - Target: dark bronze covers **45-60 %** of each panel (`c_pillar.jpg` reads about 50 % dark).
   - **(b) The nine "dragons" are one staircase glyph copied in a 3 × 3 grid.**
     - Cause: `tex_pillar.py:245-249`, `rows = [...]`, `a0 = k * slot + slot * 0.12`. Every row has the same phase and the same shape.
     - They do not spiral, and at 15 m they read as thin black zig-zag cracks (`review_landmarks_r3_pillar_mid.jpg`).
     - Do: 9 dragons that **spiral up**:
       - Each spine climbs one panel diagonally (30-45°) across 120-160° of circumference, with S-bends.
       - Shift the phase 40° per panel and alternate the handedness per panel.
       - Length 6-8 m and body 0.45-0.60 m (dossier §1.2), with ±20 % variation per dragon: no two dragons identical.
       - No straight vertical or horizontal run longer than 0.8 m. Archaic 夔龙 are angular at the extremities, but the body flows.
   - **(c) Kui-dragon anatomy, so it reads as a dragon at 15 m:**
     - head 1.0-1.3 m long, with a crest or horn bent twice at right angles;
     - upper lip curled into a square hook;
     - round eye Ø 0.15 m with the 0.04 m socket;
     - 2 legs with 3 hooked claws;
     - dorsal hook fins every 0.4-0.5 m;
     - a tail that ends in a square spiral.
     - Keep the 0.025 m shoulder bevel and the 0.014 m chevron scales every 0.09 m.
   - **(d) No bronze/steel material split.**
     - `build_pillar.py:74` passes `pack=False`, so the glb has no `metallicRoughnessTexture`. `LM_PILLAR_Steel` is met 0.35 / rgh 0.42 everywhere, and `pillar_orm.png` B (metal) is a flat 0.349.
     - Do: `pack=True` with a real ORM:
       - G (roughness): steel 0.28-0.34 with vertical brushing (streaks 1-3 mm wide and 5-40 cm long, stretched noise); bronze 0.42-0.50; raised edges 0.32.
       - B (metal): 1.0 on steel and bronze, about 0.6 in patina cavities.
     - Base colour:
       - steel `#B9BCBE` with the brushing;
       - bronze `#3B2F25`, cavities `#241C16`;
       - raised edges `#8A6A3E` from a 2-4 cm curvature mask;
       - dust `#7A7468` on upward-facing ledges.
     - Glossy steel against a dark matte relief is what reads in `c_pillar.jpg`.
   - Verify:
     - `python3 tmp/review/lm_glbjson.py game/assets/landmarks/dragon_pillar.glb` shows BC + **MR** + N + AO on `LM_PILLAR_Steel`.
     - Dark bronze surviving a 0.30 m erosion covers ≥ 15 % of each panel (today 0 %).
     - Cams `pillar_2m` and `pillar_mid`, hstacked with `ref/shanghai/sheets/c_pillar.jpg`:
       - at 15 m: dragons with head, eye and claws;
       - at 2 m: fret and scales;
       - no visible repetition anywhere.

2. **[L-NIGHT3] The pillar uplights do not graze the column, the plinth is unlit, and the rig makes pencil beams.**
   - **Bug.**
     - `materials/landmark_lights.gd:89` does `light.spot_angle = deg_to_rad(angle)`, but `SpotLight3D.spot_angle` is in **degrees**.
     - My probe (`tmp/review/lm_r3_lights.gd`) prints `ang=0.2182` / `0.4363` on all 27 spots: beams of 0.44° and 0.87°.
     - The world pool (`world/build/light_pool.gd:247`) uses degrees correctly. So your 48 / 90 / 35 W were tuned against pencil beams, and they are wrong in game. Your note "at 12 W the pillar measured black" is this bug.
     - Pass the angle straight through.
   - **Aim.**
     - `Flood_Base_1..4` sit at (±4, 0.5, ±4) from the axis, 3.2 m off the surface, aimed 43° up.
     - A 25° beam therefore lights only y = 2.4-5.1 m of the 29.4 m column. In game you get two warm ovals at the base (`review_landmarks_r3_g_pillar_2m.jpg`, `_g_pillar_12.jpg`).
     - Move the four empties onto the plinth rim:
       - r = 3.1 m, y = 0.65 m, at 45°, 135°, 225° and 315°;
       - aimed 82-85° up, toward the column, so the beam rakes the relief;
       - `angle` 12.5 (a 25° beam), range 34 m;
       - re-tune the energy **in main.tscn**.
   - **Lit plinth** (lead).
     - Add 4 emissive uplight housings at the flood positions: lens 0.35 × 0.20 m, `#FFC98A` E3.
     - Add `LED_Pillar_Plinth`, a 3 cm warm line under the plinth lip, `#FFC98A` E1.5.
     - Plinth maps: `granite_tile_03` at 512² over 2 m is 256 px/m. Use 1024² (512 px/m, dossier §15 near-road).
   - Verify:
     - Test: assert that every spawned SpotLight3D has `spot_angle` equal to the manifest `angle` (degrees, 5-45), and that each `Flood_Base_*` axis meets the column between y = 8 and 25 m.
     - `pillar_mid`: column pixels P50 0.30-0.45, ≤ 2 % above 0.95, and warm silver from 1 m to 28 m.
     - In game (`main.tscn --skip-menu --env-only`, cam `g_pillar_12:-1310,1.7,679:-1299,9,687:62`): the relief is readable under the decks.

3. **[L-NIGHT1] The trio and the backdrop read dark from the Bund and from the air.**
   - Evidence:
     - Frame stats: bund P95 0.218 / SAT 0.000 %, trio_air 0.233 / 0.000 %, st_crown 0.253 / 0.000 %, jinmao_crown 0.272 / 0.000 %, swfc_ap 0.262 / 0.000 % (`r3_sheet_skyline.jpg`, `r3_sheet_towers.jpg`).
     - The Shanghai Tower has floor-band dots only, and its crown fins are grey metal (`LM_TOWER_Crown`, no emission).
     - Only the OPT has a beacon mesh: `LED_Aviation_Tip`, static, E8. Jin Mao, SWFC and Shanghai Tower carry bare `Aviation_*` empties. The 12 backdrop towers have none.
     - My test `tmp/review/lm_r3_fogtest.gd` set `disable_fog` on the 15 `LED_*` materials (`r3_fog_cmp.jpg`). SAT rose 0.000 → 0.392 % and P99 0.260 → 0.272. The OPT, the SWFC outline and the Jin Mao bands then read, but the lines are too thin to carry the frame.
   - Do:
     - (a) In every wrapper, set `disable_fog = true` on all emissive `LED_*` materials.
       - Generalise `lupu_fog.gd` into one `led_unfog.gd`.
       - Add wrappers for `oriental_pearl` and `nanpu_bridge`, and list them in the manifest.
       - Facade windows stay fogged (the env unit owns fog).
     - (b) Size for 1.3 km. At fov 50 and 1600 px, 1 px is 0.76 m, so every line meant to read from the Bund must be ≥ 1.6 m wide. Crowns are lit surfaces, not wires.
     - (c) Shanghai Tower:
       - 3 twisting LED lines on the rounded corners, following the 120° twist: 1.6 m, `#E6F2FF` E3.
       - The V-notch line: 2.0 m, E3.5.
       - Crown 546-632 m: emissive inner fin faces, `#DDEEFF` E2.5, plus a ring on the sloped top edge.
     - (d) Jin Mao: the lattice crown rings and the mast glow gold-white `#FFE6A8` E3.5. The banding is fine.
     - (e) SWFC: edges and aperture outline 2.4 m wide, blue-white `#CFE6FF` E3.5 (ART §11 says blue-white).
     - (f) Aviation beacons (ART §11):
       - `LED_Aviation_*`, red `#FF2A3A`, Ø 1.5 m, on every top above 100 m: OPT 468, Jin Mao 420.5, SWFC 492, Shanghai Tower 632, all 12 backdrop roofs and both Nanpu tower tops.
       - Blink at **1 Hz** (0.25 s on) from one `aviation_blink.gd` in the wrappers: toggle `emission_energy_multiplier` from `Time.get_ticks_msec()` with a per-tower phase.
     - (g) Backdrop: cool white edge or crown LED lines on ≥ 6 of the 12 towers (ART §11: 50 %).
   - Verify:
     - Bund cam, crop x 250-1050, y 150-650: P99 ≥ 0.55 and SAT ≥ 1.5 %.
     - trio_air: each tower is named by its signature at a glance.
     - Two shots 0.5 s apart (`--times`) differ at the beacons.

4. **[L-NIGHT2 + rest of L-ART1] OPT: no dot chasing, hidden small spheres, unlit columns, black bands.**
   - Evidence:
     - `LED_OPT_Spheres` is a plain StandardMaterial3D. The world's `led_cycle.gd` only lerps its colour over 40 s, so nothing chases.
     - `build_pearl.py:31` `SMALL_R = 5.0` gives Ø 10 m spheres; the dossier says Ø **12** m. They sit inside the tube triangle (the inner tube faces are 5.5 m from the axis) and stay hidden (`lead_view2_pearl.jpg`, `review_landmarks_r3_opt_400.jpg`).
     - The tubes render dark navy (`opt_out`, `opt_400`). In `opt_night_2014.jpg` they are the brightest part: a white-violet wash with horizontal light rings.
     - From the Bund the silver bands turn into broken black dashes across both spheres (`r3_fog_cmp.jpg`).
   - Do:
     - (a) New wrapper `oriental_pearl.tscn` (set it as the manifest `wrapper`), with a ShaderMaterial on `LED_Sphere_*`:
       - UV dot mask at 0.4 m pitch (alpha = dot);
       - chase: a brightness wave over the sphere at 0.5-1 Hz, e.g. `0.55 + 0.45 * sin(TAU * (0.75 * TIME - UV.y * 6.0))`;
       - a `led_color` uniform that the wrapper script cycles `#FF3FA4` → `#8A3CFF` → `#2E7BFF` over 40 s;
       - keep BLEND, `disable_fog`, E ≤ 4.
       - Tell the world unit in status that LedCycle skips ShaderMaterials (it casts to StandardMaterial3D).
     - (b) Small spheres Ø 12 m, with their own LED shell at E5, so five glowing beads read between the columns.
     - (c) Lit columns:
       - an emission mask on the tubes (a baked flood wash, `#FFF1E0` at the base → `#7A4CFF` up the shafts, E0.8-1.2);
       - light rings every 10 m between the spheres;
       - LED strips ≥ 1.2 m wide on the 3 outer edges, E3.
     - (d) Silver bands: an emissive edge line, `#E8ECFF` E2, so they do not read black at night.
   - Verify:
     - `opt_400` and the Bund crop, hstacked with `opt_night_2014.jpg`: bright columns, 5 beads, no black dashes.
     - `--times=1,1.5,2` shows the chase moving.

5. **The Nanpu reads as a grey frame from the spiral** (acceptance view c).
   - Evidence:
     - `spiral` P95 0.227 / SAT 0.000 %; `review_landmarks_r3_g_spiral.jpg`.
     - `nanpu_night_2026.jpg` shows white-washed towers, a blue deck LED line and an orange underside.
   - Why the real floods cannot do it:
     - They are 12.5° beams with a 70 m range, starting at deck level (44 m), so they never reach the 150 m tops.
     - The world flood pool (`world_builder.gd` `FLOOD_SPOTS` 12, `FLOOD_FADE_BEGIN` 500, `FLOOD_FADE_LENGTH` 400) is shared with the Bund, so from about 400 m these floods are seldom assigned.
   - Do:
     - Bake the flood wash into an emission mask on the legs and crossbeams: `#FFF4E6`, E0.6 at the base → E1.2 under the crossbeam, about 0.3 on faces turned away from the deck (ART §4: far lights glow through emissives).
     - `LED_Nanpu_DeckEdge`: a continuous 0.5 m `#2F7BFF` line on both sides, E3.
     - An orange under-deck strip, `#FF8A2A` E2.
     - `disable_fog` on these LEDs; the remaining real floods get ranges ≥ 110 m.
   - Verify: at the spiral cam the tower legs reach P95 ≥ 0.6 and the blue line runs the full span. Hstack with `nanpu_night_2026.jpg`.

6. **The Lupu rainbow renders white.**
   - Evidence: the arch pixels in `review_landmarks_r3_lupu.jpg` have saturation median **0.03** (p90 0.09).
   - Do:
     - Energy 1.2-1.6.
     - A fully saturated `rainbow.png` (S = 1, V = 1, 6-7 bands).
   - Verify: arch saturation median ≥ 0.45 at the `lupu` cam.

7. **Textures are still flat colour fields ("贴图纹理什么都要细化").**
   - Dossier §15: every material is albedo + normal + ORM + detail normal + a grime/variation mask.
   - Measured albedo std (0-1):

     | texture | mean | std | used on |
     |---|---|---|---|
     | `steel_paint_diff.png` | `#93999F` | **0.010** | Waibaidu |
     | `formwork_diff.png` | `#D4D4CE` | **0.017** | OPT tubes, Nanpu |
     | `honeycomb_diff.png` | — | 0.019 | OPT glass |
     | `metal_white_diff.png` | — | 0.031 | — |

     In `wb_side` the truss is clean grey paint with rivets only.
   - Do:
     - **Waibaidu steel** (dossier §15):
       - paint chipping on the edges: 1-5 cm flakes showing primer `#5E5A55`;
       - rust streaks 0.3-1.5 m long under joints and rivet rows: `#6B4A35`, 10-30 % opacity;
       - bird droppings on the top chords;
       - a grime gradient.
     - **Formwork concrete:**
       - vertical rain streaks 2-4 m long;
       - Ø 3 cm tie holes on a 1.2 × 2.4 m grid;
       - efflorescence at the joints;
       - a darker band at the base.
     - **OPT glass:** ±6 % per-panel tint and dirt at the panel seams.
     - Every set: a 0.5-1 m detail normal and a macro variation mask, so no two 30 m spans match.
   - Verify:
     - Albedo std ≥ 0.04 on each set.
     - Crops of `wb_side` and `opt_out` show wear readable at 5 m.

8. **[IMPORT-CHURN] The mandatory lead note is not satisfied.**
   - **(1) Identical bytes are rewritten.**
     - `texio.write_png` (`texio.py:15`) always writes. After your last rebuild all 42 `textures/*.png` carry 09:33.
     - Compare with the existing bytes and skip identical files:
       `if os.path.exists(path) and open(path, "rb").read() == blob: return path`.
     - Do the same in `lmmat.jpeg_copy` and for the glb export: export to `tmp/landmarks/`, compare the hash, replace only on change.
   - **(2) Blender-only inputs are imported by Godot.**
     - 40 of the 42 PNGs in `game/assets/landmarks/textures/` (22 MB, including `pillar_basecolor` 5.0 MB, `pillar_normal` 7.3 MB and `pillar_orm` 5.0 MB) are Blender inputs that Godot imports for nothing.
     - Only `metal_dark_diff.png` and `metal_dark_nor.png` are referenced, by `lujiazui_facade.tres`.
     - Move the 40 to `blender/landmarks/src_tex/`.
   - **(4) Report the texture count and MB in status.** It is missing. Today:
     - 118 images, 44 MB, in `game/assets/landmarks/`;
     - 52 of those images are byte-identical duplicates, because Godot extracts every embedded image once per glb;
     - plus 35 MB of glb.
   - **Stale file.** `dragon_pillar_pillar_rgh.png` (03:14) and its `.import` are in no glb. Delete them.
   - Verify:
     - Run the full build twice. `find game/assets/landmarks -newer <stamp>` lists 0 files after the second run.
     - Status quotes the count and the MB.

9. **Rules, hygiene and report accuracy.**
   - **Scratch outside `tmp/landmarks/`.** `/tmp/gd_sample.txt` (251 KB, from your `sample 31766 ... -f /tmp/gd_sample.txt`) breaks the lead rule. Delete it, and clear `tmp/landmarks/*.log`/`*.txt` when done.
   - **Contract names.** `LED_AdPlate_*` and `LED_AdBrackets_*` are non-emissive (`LM_Ad_Plate`) but carry the `LED_` prefix the world unit animates. Rename them `AdPlate_*` / `AdBrackets_*`.
   - **result.md claims that do not hold:**
     - "the 雷纹 is now a true square spiral … chained into one band": it renders as a checkerboard;
     - "dragons 0.45-0.60 m wide": they read as 3 × 3 copies of one staircase;
     - "Nanpu 4/tower … in the right places": the beams are 0.44° wide in your preview.
   - Next round, back each claim with the command output **and** a capture path.

## SHOULD-FIX
- **Backdrop.** The 12 towers total 1,596 render tris (about 133 each), so they read as plain boxes. ART §6 asks for setbacks, crown caps and antennas: ≤ 3k tris each, with the IFC twins recognisable.
- **Preview fps.** `preview_skyline.gd:15` sets `UPDATE_ALWAYS` on the 1000×700×1000 probe. The preview now runs at 50-64 fps at century/bund (r2: 121-191). Use `UPDATE_ONCE`.
- **OPT glass under the dots.** The dot shell covers the whole sphere at 45 m. Leave the silver-band zones (15-20 %) dot-free, so glass and bands show between LED rings (`opt_night_2014.jpg`).
- **Jin Mao spire.** The lattice mast reads like a power pylon. The real spire is a slim stepped needle (`swfc_jinmao_night_2009.jpg`).
- **Nanpu cables.** Within 30 m (`nanpu_w_main`) they are still bright planks. Fade the emission with distance, or use a thin emissive core.
- **Duplicate imports.** 52 duplicate extracted images. Ask the lead (status → Requests) whether shared external `.tres` materials or `.gltf` with shared textures are allowed, so each texture is imported once.
- **Missing test asserts:**
  - spot angle = manifest degrees;
  - the `Flood_Base_*` aim meets the column at 8-25 m;
  - `LED_Aviation_*` on every top above 100 m;
  - `disable_fog` on the `LED_*` materials in the wrappers;
  - `LM_PILLAR_Steel` has a metallicRoughness texture (parse the glb as `glbjson.py` does).

## Verified OK
- **Check:** `tools/godot.sh check --only=res://assets/landmarks/` → `CHECK 12 files, 0 failed, 0 engine errors, 0 warnings`.
- **Test:** `tools/godot.sh test res://assets/landmarks/tests/test_landmarks.gd` → 63 PASS, 0 FAIL, exit 0, `landmark_lights: 27 lights spawned`.
- **Polycounts** (my count from the glb accessors), all within budget; colliders ≤ 1,828 tris per asset:

  | asset | tris |
  |---|---|
  | pillar | 59,422 (≤ 60k) |
  | Shanghai Tower | 56,276 |
  | OPT | 45,388 |
  | Nanpu | 17,340 |
  | Jin Mao | 16,972 |
  | Lupu | 9,128 |
  | Waibaidu | 7,344 |
  | Pearl Ring | 5,216 |
  | SWFC | 1,880 |
  | backdrop | 1,740 |

- **Blender preview, pillar:** `PREVIEW objects=3 tris=59422`. The nodes are `Flood_Base_1..4`, `Flood_Under_Deck`, `Pillar_ColColumn-colonly`, `Pillar_Column` and `Pillar_Plinth`. Only the collider material is untextured.
- **Pillar maps (r2 item 1a fixed):** BC 2048×4096, N 4096×8192 and ORM 2048×4096 are shipped, with a real `occlusionTexture`.
- **OPT:**
  - glass `#AE2F69` (target `#B0306A`), roughness p50 0.16, metal 0.30;
  - the BLEND dot shell sits 0.6 m off the glass;
  - `opt_sphere20` P95 0.613 / SAT 7.6 %, the best frame of the unit;
  - the ground spheres exist (y 0.6-8.6), with 17 colliders.
- **Towers:**
  - windows are cool/neutral white (`tower100`, `jinmao_base`);
  - Jin Mao has gold setback bands and crown rings;
  - the SWFC aperture is symmetric and outlined on all 4 sides;
  - the Shanghai Tower needle is gone;
  - the three ads (东方霓虹 / 浦江电讯 / 申城快递) are well made: Chinese first, parody brands, pixel grid, E2.5.
  - **L-ART3 holds at close range.**
- **Bridges and ring:** 「南浦大桥」 reads from the deck; the Waibaidu truss and rivets read at 5 m; the Pearl Ring glass is BLEND.
- **r2 fixes:** data maps are linear (r2 item 5), the r2 stale textures are gone, and the masters are in `src_tex/`.
- **Bund order:** OPT front-left, trio behind, Shanghai Tower tallest and rightmost.
- **Ownership:** every Write/Edit in `jobs/landmarks/log.jsonl` is under `blender/landmarks/**`, `game/assets/landmarks/**`, `status/landmarks.md`, `jobs/landmarks/` or `tmp/landmarks/`. Files are ≤ 370 lines and tests extend Node.

## Evidence
- **Commands run** (from `~/m/skyrush`):
  - Lights probe: `python3 tools/slots.py light 6 -- godot --headless --path game -s tmp/review/lm_r3_lights.gd`.
    - Output: `Light_dragon_pillar_Flood_Base_1 SpotLight3D E=48.0 ang=0.2182 range=35.0 pos=(-1295.0, 0.5, 683.0) dir=(-0.52, 0.68, 0.52)`; every spot shows ang 0.2182 or 0.4363.
    - `animation_players=0`; the only aviation mesh is `LED_Aviation_Tip`; every `LED_*` material is a StandardMaterial3D.
  - Preview shots: `tools/godot.sh shot --scene=res://assets/landmarks/preview_skyline.tscn --out=review_landmarks_r3 --env-only --warm=40 --cams="<list below>"` → `errors=0`, fps 50 (century) to 142 (lupu).
  - In-game shots: `tools/godot.sh shot --scene=res://main.tscn --skip-menu --env-only --warm=120 --cams="g_bund:-105,5,-480:1000,230,-300:50;g_pillar_12:-1310,1.7,679:-1299,9,687:62;g_pillar_2m:-1294.5,1.7,687:-1299,4,687:60;g_opt:900,60,-700:637.5,200,-634.9:55;g_spiral:900,44,1180:1250,80,1390:62"`. The errors are other units' (blocks glb, booth shapes).
  - Fog test: windowed `tmp/review/lm_r3_fogtest.gd` → `led materials unfogged=15`.
  - `tools/blender.sh preview game/assets/landmarks/dragon_pillar.glb ../review/landmarks/bp_r3_pillar --views close_front34 --light night`.
  - `python3 tmp/review/lm_glbjson.py game/assets/landmarks/*.glb`.
  - PIL and md5 measurements (`pillar_orm` B flat 0.349, height p75 = 0, the albedo std table, Lupu saturation, 52 duplicates, 2 of 42 textures referenced).
- **Cams** (`name:pos:look:fov`):
  - bund `-105,5,-480:1000,230,-300:50`
  - century `830,2,-455:1180,260,-150:62`
  - spiral `900,44,1180:1250,80,1390:62`
  - pillar_2m `-1294.5,1.7,687:-1299,4,687:60`
  - pillar_mid `-1284,1.7,697:-1299,14,687:62`
  - pillar_15 `-1312,2,676:-1299,12,687:62`
  - opt_sphere20 `682.5,93,-634.9:637.5,93,-634.9:62`
  - opt_out `712.5,3,-634.9:637.5,60,-634.9:62`
  - opt_400 `250,140,-560:637.5,190,-634.9:45`
  - wb_side `-147.5,6.9,-967.1:-144.6,7.5,-976.8:62`
  - jinmao_base `1178,2,-179.8:1133,40,-199.8:62`
  - tower100 `1030,160,-160:1133,170,-199.8:60`
  - jinmao_crown `1240,385,-160:1133,375,-199.8:50`
  - st_crown `1372.8,600,57.5:1122.8,595,-42.5:40`
  - swfc_ap `1562.2,456,-136:1262.2,456,-136:40`
  - ring_street `798,1.5,-458.8:806,6.5,-508.8:62`
  - nanpu_w_main `1229.5,47,1381.6:1139.4,118,1338.2:50`
  - lupu `1330,47,1430:-300,60,2900:30`
  - trio_air `640,320,250:1180,300,-130:55`
- **Frame stats** (`screenshot_stats.py`; target P95 0.40-0.78, SAT 2-15 %):

  | frame | P50 | P95 | SAT % |
  |---|---|---|---|
  | bund | .110 | .218 | 0.000 |
  | century | .094 | .257 | 0.061 |
  | spiral | .114 | .227 | 0.000 |
  | trio_air | .120 | .233 | 0.000 |
  | opt_400 | .120 | .243 | 0.085 |
  | st_crown | .121 | .253 | 0.000 |
  | swfc_ap | .126 | .262 | 0.000 |
  | jinmao_crown | .122 | .272 | 0.000 |
  | lupu | .144 | .265 | 0.002 |
  | nanpu_w_main | .094 | .295 | 0.012 |
  | pillar_2m | .094 | .228 | 0.441 |
  | pillar_mid | .094 | .199 | 0.031 |
  | opt_out | .094 | .366 | 5.134 |
  | opt_sphere20 | .146 | .613 | 7.556 |
  | wb_side | .148 | .355 | 1.880 |
  | tower100 | .117 | .414 | 0.000 |
  | jinmao_base | .086 | .498 | 0.026 |

- **Captures** (`captures/review/landmarks/`):
  - shots: `review_landmarks_r3_<cam>.jpg` (19), `review_landmarks_r3_g_{bund,pillar_12,pillar_2m,opt,spiral}.jpg`;
  - sheets: `r3_lead_evidence.jpg`, `r3_sheet_{skyline,pillar,opt,towers,bridges,game,century}.jpg`, `r3_pillar_tex.jpg`;
  - fog test: `r3_fog_cmp.jpg` (`r3_fog_shipped.jpg` vs `r3_fog_led_off.jpg`);
  - Blender: `bp_r3_pillar*.jpg`.
