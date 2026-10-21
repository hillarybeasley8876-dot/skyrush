# landmarks review round 2 — VERDICT: FAIL

## Scores (0-10): function, visual, code
- **function 4**
  - Good: all 10 glb load, anchors and heights are right, the test passes 37/37, and the Pearl Ring soffit and Waibaidu pier are fixed.
  - Bad: the preview light rig spawns **zero** lights. The pillar glb is built from stale textures. No solid landmark has a collider: towers, OPT legs, Waibaidu trusses, ring columns, pillar, Nanpu legs.
- **visual 3** (r1: 2)
  - Better: towers at close range and the Waibaidu truss.
  - Still wrong:
    - The OPT is an opaque pastel-pink lamp that z-fights at distance.
    - The pillar reads as a white waffle grid.
    - Nanpu and Lupu are dark.
    - The Bund frame is unchanged: P95 0.219, SAT 0.000 %.
  - All three lead notes still fail.
- **code 4**
  - Good: every file is ≤ 400 lines and the builders are split sensibly.
  - Real bugs:
    - the light rig is dead;
    - normal and roughness maps are written as sRGB;
    - a stale JPEG cache feeds the pillar;
    - the dragon scales are unioned into the body, so they are invisible;
    - the OPT tube strips are triplicated;
    - the reflection probes are 20 m boxes.
  - Hygiene: 20.8 MB of stale extracted textures, orphan .import files, scratch files left in `tmp/`.
  - Several claims in `jobs/landmarks/result.md` are false (see item 9).

Work order: items 1-3 are the lead's mandatory notes L-ART1..3; do them first, then 4-9. After each item:
1. Rebuild.
2. Run the test.
3. Re-capture with the cams below (`tools/godot.sh shot --scene=res://assets/landmarks/preview_skyline.tscn --env-only --warm=40 --cams="..."`).
4. Quote the real command output in `status/landmarks.md`.

## MUST-FIX

1. **[L-ART2] Dragon pillar: the shipped relief is a low-res waffle grid that does not match its own displacement.**
   - Evidence (`captures/review/landmarks/`):
     - `r2_pillar_tex_compare_s.jpg` (shipped | current master | `sheets/c_pillar.jpg`)
     - `r2_pillar_master_1to1.jpg`
     - `r2_bp_pillar_close_s.jpg` (Blender studio + night)
     - `review_landmarks_r2_pillar_2m.jpg`
   - **(a) Pipeline.**
     - The glb embeds `pillar_bc.jpg` 512×1024 (**32.6 px/m**), `pillar_rgh.jpg` 512×1024 and `pillar_nor.jpg` 1024×2048 (65 px/m).
     - It has **no occlusionTexture**. The brief asks for normal + height + AO + curvature.
     - Those JPEGs date from 03:14, but the 4096×8192 masters were rebuilt at 06:02. Correlation of shipped vs current master: basecolor **0.10**, normal **0.07**. So colour and normal come from an older design, while the Displace modifier reads the new `pillar_height.png`.
     - Cause: `lmmat.jpeg_copy` (`lmmat.py:78`) skips the conversion whenever the output file already exists.
     - Do:
       - Regenerate whenever the source is newer (or always).
       - Ship the normal at **4096×8192** and basecolor/ORM at **≥ 2048×4096** (dossier §15: ≈ 260 px/m).
       - Pack AO into the R channel of an ORM texture so glTF exports `occlusionTexture`.
   - **(b) The 雷纹 collapses into squares.**
     - In `tex_pillar.py`, MEANDER_CELL 0.18 and MEANDER_TURNS 3 give a spiral step L = 0.18/9 = **0.020 m**, but MEANDER_W = **0.032 m**, wider than the step.
     - Every spiral therefore fills into a solid square with a dot. The column reads as bathroom tiles.
     - Do:
       - Cell **0.30 m**, 2.5 turns (step ≈ 0.05 m), line 0.020-0.022 m.
       - Link each cell's outer end to its neighbour so the pattern is one continuous band.
       - Alternate the rotation per cell; depth 0.035 m.
   - **(c) The scales are invisible.**
     - `scale_prims` capsules go into the same `min` distance field as the body (`draw_dragon`), so the body swallows them. The bodies are flat: the normal map is uniform inside them.
     - Do:
       - **Carve** V-shaped chevrons 0.012-0.015 m deep, every 0.09 m, apex toward the head, inside the body mask.
       - Eyes: 0.04 m deep holes.
       - End horn, claw and tail tips in square hooks.
   - **(d) Bodies are too wide and too soft.**
     - Width is 0.72-0.84 m; dossier §1.2 says **0.45-0.6 m**.
     - BEVEL 0.075 m makes soft blobs. Use 0.02-0.03 m so the edges are crisp and the raised edge #8A6A3E (from curvature) catches the uplight.
   - **(e) The displacement aliases.**
     - It displaces the full height map, including the 0.18 m grid, on 0.196 m mesh rows. The result is the wobbly surface in `pillar_2m`.
     - Do: displace with a blurred copy (Gaussian σ ≈ 0.15 m) containing the dragons and the sun/moon only. Leave the 雷纹 and the scales to the normal map.
   - Target look (`ref/shanghai/sheets/c_pillar.jpg`):
     - large interlaced dark-bronze #3B2F25 dragons dominate;
     - fine spirals sit inside the bronze;
     - brushed steel #B9BCBE (vertical brushing) shows between them.
   - Verify:
     - `python3 tmp/review/lm_glbjson.py game/assets/landmarks/dragon_pillar.glb` shows N 4096×8192, BC/ORM ≥ 2048×4096 and an AO entry.
     - Shipped vs master correlation ≥ 0.95.
     - Cams `pillar_2m:-1294.5,1.7,687:-1299,4,687:60` and `pillar_mid:-1284,1.7,697:-1299,14,687:62`, hstacked with c_pillar.jpg: dragons read as dragons at 15 m, and spirals and scales read at 2 m.

2. **[L-ART1] OPT: the spheres are opaque pastel-pink lamps, the glass is hidden, and three shells z-fight.**
   - Evidence:
     - `review_landmarks_r2_opt_sphere20.jpg`: P50 **0.415**, P95 0.785 — the frame is flooded.
     - `r2_sbs_bund_opt.jpg` vs `img/06_lujiazui/opt_night_2014.jpg`.
     - `r2_fog_cmp.jpg`: dark blotches on both spheres from the Bund.
   - Cause: `build_pearl.py:78-93` stacks three shells per sphere:
     - `Sphere_*` at r;
     - `LED_Sphere_Glow_*` at r + 0.08 m, **OPAQUE** #FF3FA4 at E2.6, which completely covers `LM_PEARL_Glass`;
     - `LED_Sphere_*` at r + 0.16 m, MASK.
     - 8 cm separations z-fight at 0.5-1.3 km.
   - Do:
     - **Delete `LED_Sphere_Glow_*`.**
     - Keep the separate dot shell (lead note):
       - offset **r + 0.6 m**;
       - alphaMode **BLEND**, not MASK (MASK dots vanish and shimmer past 40 m);
       - dot radius 0.28 of the 0.4 m pitch (about 25 % coverage);
       - dots emissive #FF3FA4 at E4.
     - Alternative from the brief: name the shell material `SH_hologram` (LED mode) and call `MaterialLibrary.apply()` in the preview.
     - The glass must show: #B0306A, metallic 0.3, roughness 0.15 (reachable only after item 5), 1.2 m honeycomb panels. Silver bands #C8CCD0, brushed.
   - **Shaft: the silhouette is wrong.**
     - `TUBE_TOP = 100`: the three Ø 9 m tubes end inside the lower sphere. Above it the shaft is a single Ø 11.2 m core (`build_pearl.py:58`).
     - In opt_night_2014.jpg the section between the spheres is the three tubes, about 27 m across and lit violet over their full length.
     - Do: run the three tubes up to the upper sphere (≈ 252 m) with the 5 small spheres nested between them.
   - **Tube strips (`build_pearl.py:100-108`).**
     - Today: 9 vertical boxes at only **3 distinct angles** (each one triplicated and coplanar), z 0-100 m. The tubes splay out below 55 m and the lower sphere covers 68-118 m, so only about 13 m of each strip is visible (`review_landmarks_r2b_opt_out.jpg`).
     - Do: strips on the outward face of each tube, no duplicates, following the splayed legs (12-55 m), then 118-250 m and 295-335 m. Colour #7A4CFF at **E3 = energy 5**; today it is 8, not the "E3" in the report.
   - Verify:
     - `opt_sphere20:682.5,93,-634.9:637.5,93,-634.9:62`: glossy glass with visible honeycomb and dots, P50 ≤ 0.30.
     - `bund:-105,5,-480:1000,230,-300:50`: no blotches; violet tubes between the spheres.
     - hstack with opt_night_2014.jpg.

3. **[L-ART3] Towers: warm windows, clipped walls, no LED ads, a needle on Shanghai Tower, a half-open SWFC aperture.**
   - **(a) Windows are orange-dominated** (`review_landmarks_r2_jinmao_base.jpg`, `_century.jpg`).
     - `facade_windows.gdshader:79` picks `light_warm` #FFA757 for 42 % of the lit windows, and `materials/lujiazui_facade.tres` does not override it. The lead asked for cool/neutral whites.
     - Set `light_warm = #FFE0C2` and `light_neutral = #F4F1EA`; keep `light_cool = #DEE8FF`.
   - **(b) `tex_mean` is wrong, so every wall texel clips.**
     - `lujiazui_facade.tres` sets `tex_mean = Color(0.28, 0.28, 0.28)`, but `textures/metal_dark_diff.png` measures sRGB mean **(0.542, 0.564, 0.587)**.
     - The shader divides by `tex_mean` and clamps at 1.6 (`:100`), so every wall texel clips: the walls are flat. With fog off, the backdrop reads as flat beige boxes at 0.8-1.3 km (`r2_fog_cmp.jpg`, bottom).
     - Set `tex_mean` to the measured mean.
   - **(c) The 2-3 giant LED ad facades are missing entirely.**
     - Nothing named hologram or ad exists in the unit, and result.md does not mention them.
     - Add them on IFC_C, CMB and Aurora:
       - about 60 × 120 m each;
       - LED dot grid with `led_grid` = metres × 6, energy ≤ 2.5;
       - your own 1024×576 ads using ART.md §7 parody brands (东方霓虹, 浦江电讯 …), Chinese first;
       - on a dark #141416 back-plate.
   - **(d) Shanghai Tower ends in a needle.**
     - `build_shanghai_tower.py:123` shrinks the crown to s = 0.06 at 632 m.
     - The real crown continues the twisted skin at about 0.5 scale, with a sloped top edge rising toward the notch and a ring of fins (`lujiazui_skyline_day_2023.jpg`, `lujiazui_night_2023.jpg`).
     - Keep s ≥ 0.42 to the top, cut the top with a plane sloping about 25 m across, and arrange the fins as a ring.
   - **(e) The SWFC aperture is only half open.**
     - Seen along its own axis (`swfc_ap:1562.2,456,-136:1262.2,456,-136:40`), only the left part of the slot is open and only its horizontal edges are outlined (`r2_crops_swfc_sign_lupu.jpg`, left).
     - Make it a symmetric through-opening, 30 → 50 m wide on both broad faces, and outline all 4 sides (including the sloped ones) with 1.6 m strips.
   - Verify:
     - Cams `century:830,2,-455:1180,260,-150:62`, `jinmao_base:1178,2,-179.8:1133,40,-199.8:62`, `st_crown:1372.8,600,57.5:1122.8,595,-42.5:40`, `swfc_ap` and `bund`.
     - Expected: mostly white windows, readable ad screens, no needle, sky visible through the aperture.

4. **The night light rig spawns zero lights, and the specs would blow out once it works.**
   - **The rig finds nothing.** `materials/landmark_lights.gd:34` calls `_collect(self, ...)` on the `Lights` node, which has no children.
     - My probe (`tmp/review/lm_count_lights.gd`) prints `lights=1 flood_empties=40`: the only light is the Moon.
     - So every night capture is lit by the moon and emissives alone. The claimed "SpotLight3D at the Flood_Base_* empties" never existed.
   - **The `asset` field is never used.** A scene-wide search would attach every `Flood_Crown_` spec to all 21 crown empties of all four towers. There are 4 such specs, and `lujiazui_backdrop` is listed twice.
   - **Energies and ranges are far too high:** 180 for the pillar, 5200-14000 for the crowns, ranges up to 220 m. Replace them:
     - Pillar spots: energy 8-15, range 35, `spot_angle` **12.5**. Godot's spot_angle is the half-angle, so today's 22 gives a 44° beam; the dossier asks for 25°.
     - Bridge and OPT floods: energy 4-16, range ≤ 80 m.
     - Crowns: keep them emissive.
   - **Placement is wrong.**
     - `build_bridges.py:172-174` puts `Flood_Nanpu_Leg_*` on the leg axis (inside the concrete), aimed straight up, 2 per tower. The report says 8.
     - Nanpu: 4 per tower, 3 m outboard of each leg face at deck level, aimed up the leg at 75-80°.
     - `build_bridges.py:355-357` places 2 Waibaidu floods at 5.5 m aimed at the sky. Use 8 (4 per truss) on the sidewalks, aimed at the truss.
     - Also make empty names unique per asset (`Flood_SWFC_Crown_1`, not `Flood_Crown_1_001`).
   - Fix the rig: search under `get_parent()` for the node whose `scene_file_path` (or wrapper `Model`) matches `entry.asset`, then collect its `Flood_*` children.
   - Verify:
     - Test: the preview spawns exactly the expected number of lights, and no light sits inside a mesh AABB of its asset.
     - `pillar_2m` / `pillar_mid`: 4 warm grazing pools.
     - `nanpu_w_main:1229.5,47,1381.6:1139.4,118,1338.2:50`: white-washed legs (cf. `img/03_nanpu_lupu_bridges/nanpu_night_2026.jpg`).
     - `wb_side:-147.5,6.9,-967.1:-144.6,7.5,-976.8:62`: lit members (cf. `img/05_bund/waibaidu_bridge_night_2019.jpg`).

5. **Every generated normal and roughness map is gamma-encoded.**
   - Cause: `texsets.py:172` and `texgen.py:276, 281, 292-296` write data maps through `srgb_to_bytes`.
   - Measured:
     - The flat normal in `honeycomb/formwork/timber/metal_*/rivets_nor.png` is **(188, 188, 255)** instead of (128, 128, 255). Every surface is shaded as if tilted about 34°.
     - Roughness 0.22 is stored as 0.51, so glass and metals read matte, and `LM_PEARL_Glass` can never reach 0.15.
   - Do:
     - Write normal/roughness/metal/AO linearly: `np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8)`. Only albedo and emission get the sRGB curve.
     - Regenerate every set and rebuild every glb.
   - Verify: an assertion in texgen/texsets that the median R and G of every `*_nor.png` are 126-130.

6. **The Nanpu name sign and the Lupu rainbow do not read.**
   - **Sign.**
     - 「南浦大桥」 measures about 5.4 × 1.3 m (characters about 1.3 m) on a 30 × 7.2 m plate (`r2_crops_swfc_sign_lupu.jpg`, top right).
     - Dossier §3.2 asks for **4 m characters** (16 m² each). `NP_SIGN_H = 4.0` does not reach the mesh.
     - Make the glyphs 4.0 m tall (a line of about 17-18 m), #FF2020 at E3 (energy 5), on a #141416 plate 1 m larger than the text on all sides.
     - Verify: the sign mesh AABB height is ≥ 3.8 m, and it is readable in `nanpu_w_main`.
   - **Lupu.**
     - Two causes (`r2_crops_swfc_sign_lupu.jpg`, bottom right):
       - the LED band sits on the rib extrados (`build_bridges.py:228-230`), facing the sky;
       - at 2.2 km the env fog (`FOG_DENSITY 0.0035`, about 99.9 %) erases emission.
     - Do:
       - Put the rainbow on both 9 m outer side faces of each rib.
       - Add a wrapper `lupu_bridge_far.tscn` that sets `disable_fog = true` on the `LED_Lupu_*` materials. The property exists in 4.7.2; I checked.
       - Energy 8: it is the one far hero.
     - Verify: `lupu:1330,47,1430:-300,60,2900:30` shows the rainbow.

7. **No colliders on solid landmarks.**
   - CONTRACTS §2 says buildings get simplified `-colonly` meshes. Only `PearlRing_ColDeck` and `Waibaidu_ColDeck` exist (probe `tmp/review/lm_probe3.gd`).
   - Today the car can:
     - drive through the OPT podium, legs and braces;
     - drive through the 8 ring columns and the stairs;
     - drive through the Waibaidu trusses and portals, and the pillar;
     - fly (sky lanes, Big Hop) through every tower and Nanpu leg.
   - Do (everything except Lupu):
     - `-convcolonly` hulls: one per OPT leg, tube, brace and sphere, ≤ 200 tris each.
     - `-colonly` low-poly lofts for the towers, ≤ 2k tris each.
     - The pillar as a 24-sided cylinder.
     - Waibaidu: two 0.6 m truss walls 0-9 m, plus the portals.
   - Verify: extend the test so every asset except `lupu_bridge_far` has ≥ 1 collider and no collider exceeds 20k tris.

8. **Texture refinement is left undone ("贴图纹理什么都要细化").**
   - **Pearl Ring glass.** `LM_RING_Glass` uses the opaque `metal_white` set; r1 item 5 is still open.
     - Make it glass: alphaMode BLEND, #CFE6F0 at alpha 0.3, roughness 0.05.
     - Add 1.5 m panels with 4 cm frames and a 10 cm dirt band at the bottom.
   - **Near-road texel density** (dossier §15: 512 px/m).
     - Waibaidu steel is 512² per 2 m = **256 px/m**. Make it 1024² per 2 m.
     - Nanpu formwork is 1024² per 4 m = **256 px/m** on the legs beside the deck. Use a 2 m tile plus a detail normal.
   - **Raw tower glb fallback.**
     - The tower glass in the raw glb still uses the flat 4-colour `facade_night_*` (9 KB). A world unit that places the glb instead of the wrapper gets the round-1 look.
     - Either bake a decent fallback, or add a test that fails when a manifest `wrapper` is not used.
   - Verify: `python3 tmp/review/lm_glbjson.py game/assets/landmarks/*.glb`.

9. **Hygiene and report accuracy.**
   - Delete the **12 stale Godot-extracted textures** (20.8 MB) in `game/assets/landmarks/`:
     - `dragon_pillar_granite_tile_03_diff.jpg` (4.0 MB), `_nor_gl.jpg` (3.1 MB), `_rough.png` (3.0 MB);
     - `dragon_pillar_pillar_normal.jpg` (2.5 MB), `dragon_pillar_pillar_basecolor.jpg` (1.5 MB);
     - `dragon_pillar_concrete_1k.jpg`, `dragon_pillar_concrete_nor_1k.jpg`;
     - `nanpu_bridge_concrete_diff.jpg`, `nanpu_bridge_concrete_nor_gl.jpg`;
     - `oriental_pearl_concrete_diff.jpg`, `oriental_pearl_concrete_nor_gl.jpg`, `oriental_pearl_glass_rough.png`.
   - Delete the orphans `textures/pillar_{ao,basecolor,normal,rough}.jpg.import` (r1 item 12 asked for this).
   - Move the **66 MB** of texture masters out of the Godot project (e.g. `blender/landmarks/src_tex/`) or into a `.gdignore`d folder.
   - `tmp/pillar_check.jpg` and `tmp/texsets_check.jpg` are scratch outside `tmp/landmarks/`: delete them.
   - `landmark_lights.gd:23`: change `var data = ...` to `var data: Variant`. Round 1 asked for exactly this in the test.
   - `preview_skyline.tscn`: both ReflectionProbes keep the default 20 m `size`, so `ProbeLujiazui` at (900, 120, -430) covers nothing. Set `size`, e.g. 1000×700×1000 and 12×32×12.
   - result.md claims things that are not true:
     - AO and curvature in the glb;
     - a 4096×8192 raster shipped;
     - SpotLight3D at the `Flood_Base_*` empties;
     - 8 Nanpu leg floods;
     - strips at E3;
     - all round-1 items addressed.
   - Next round, quote the command output behind every claim.

## SHOULD-FIX
- **Manifest vs preview.**
  - Let the test build each transform from `anchor` + `rotation_y` and compare it with the preview node. Lupu is −1.5708 in the manifest; check the sign against the preview basis.
  - Waibaidu `height_m` is 12.4 in the manifest but 9.5 in the test. Pick one.
- **OPT podium.** The Ø 100 × 12 m podium is a plain grey drum (`review_landmarks_r2b_opt_out.jpg`). Add glazing bands, entrances and the three Ø 8 m ground spheres (dossier §6.1).
- **Jin Mao crown.** Build stacked octagonal lattice rings instead of a cone plus spire (r1).
- **Nanpu cables.** Within about 30 m of the camera they read as roughly 0.5 m white planks (`review_landmarks_r2_lupu.jpg`, top). Check `NP_CABLE_R` against the rendered width. A minimum-pixel-width approach avoids both planks and shimmer.
- **Preview materials.** Call `MaterialLibrary.apply(self)` in `materials/preview_skyline.gd` so `SH_*` materials look as they will in game.
- **For the lead (fog).**
  - The env fog density (`world/env/env_recipe.gd:9`, `FOG_DENSITY 0.0035`; ART.md §4 says 0.0012) leaves about 1 % of the skyline visible at 1.3 km (Bund to trio) and about 0.05 % at 2.2 km (Nanpu to Lupu).
  - Bund frame, fog on: P95 0.219 / P99 0.260 / SAT 0.000 %. Fog off: P95 0.313 / P99 0.439 / SAT 0.052 %.
  - So the assets need more light (items 2-4), and a skyline fog decision (an exemption, or a lower density for far emissives) is cross-unit.

## Verified OK
- **Check:** `tools/godot.sh check --only=res://assets/landmarks/` → `CHECK 10 files, 0 failed, 0 engine errors, 0 warnings`.
- **Test:** `tools/godot.sh test res://assets/landmarks/tests/test_landmarks.gd` → 37 PASS, 0 FAIL, exit 0. The test now accumulates `ok = ok and ...` correctly.
- **Polycounts** (Blender import), all within budget:

  | asset | tris |
  |---|---|
  | OPT | 56,036 |
  | Jin Mao | 14,146 |
  | SWFC | 1,400 |
  | Shanghai Tower | 56,088 |
  | backdrop | 1,338 |
  | Pearl Ring | 4,944 |
  | Nanpu | 17,228 |
  | Lupu | 8,424 |
  | Waibaidu | 7,032 |
  | pillar | 59,326 (≤ 60k) |

- **Anchors:** the Nanpu towers sit at (1139.4, 1338.4) / (1520.6, 1521.6) with the deck at 44.0. Waibaidu spans z −1019…−913 along (0.145, −0.989). Both match dossier §3.2 / §5.5.
- **Pearl Ring:** girder 5.70-6.70 m, collider 5.70-6.70 m (= the girder). Columns stand on the ground; the stairs reach the ground.
- **Waibaidu**, the best asset this round (`review_landmarks_r2_wb_side.jpg`):
  - full-width granite pier (19.0 m, top −1.2) with bearings;
  - box chords, lacing and rivet rows readable at 3 m;
  - overhead X-bracing and portals;
  - warm #FFC24D LED line.
- **Nanpu:** the cables are off the carriageway, the centre cable is gone, and 「南浦大桥」 reads left to right with a back-plate.
- **Towers:**
  - Facade wrappers carry per-tower seeds, lit_ratio 0.38.
  - Jin Mao's gold setback bands, SWFC's white arrises and Shanghai Tower's floor bands + notch line read at 100-400 m (`review_landmarks_r2_tower100.jpg`, `r2_sheet_details.jpg`).
- **Bund order:** OPT front-left, the trio behind, Shanghai Tower tallest and rightmost.
- **Ownership:** all 37 Write/Edit targets in `jobs/landmarks/log.jsonl` are under `blender/landmarks/**`, `game/assets/landmarks/**` or `status/landmarks.md`. There is no landmarks scratch in /tmp; today's `/tmp/dbg.gd` (04:53) loads core/sandbox and belongs to another unit.
- **Code:** all .py and .gd files are ≤ 391 lines. Night + studio Blender sheets exist for all 10 assets, plus `captures/landmarks/side_*.jpg`.
- **Performance:** the preview runs at 121-191 fps at 1600×900, but with zero real lights (item 4).

## Evidence
- **Commands run** (from `~/m/skyrush`). Scratch scripts are in `tmp/review/`.
  - `tools/godot.sh check --only=res://assets/landmarks/` and `tools/godot.sh test res://assets/landmarks/tests/test_landmarks.gd` (outputs above).
  - `tools/blender.sh run tmp/review/lm_stats.py > tmp/review/lm_stats_r2.txt`: per-material images. Only LED_* and LM_RING_Collider are untextured. The pillar images are 512×1024 / 1024×2048.
  - `python3 tmp/review/lm_glbjson.py <glb>`: embedded image sizes, alphaMode and emissive.
    - pillar: no AO.
    - `LED_OPT_SphereGlow`: OPAQUE, E2.6.
    - `LED_OPT_Spheres`: MASK, E4.
    - `LED_OPT_Tubes`: E8.
    - `LM_RING_Glass`: opaque metal_white.
  - `tools/blender.sh preview game/assets/landmarks/dragon_pillar.glb ../review/landmarks/bp_r2_pillar --views close_front34,front34 --light both` → tris 59,326, `LM_PILLAR_Steel` images 512×1024 / 1024×2048.
  - Headless probes, run with `python3 tools/slots.py light 6 -- godot --headless --path game -s tmp/review/<probe>.gd`:
    - `lm_count_lights.gd` → `REVIEW lights=1 flood_empties=40 aviation_empties=4`.
    - `lm_probe2.gd` → `Flood_Nanpu_Leg_W1 pos=(1146.8, 44.0, 1322.9) aim=(0,1,0)` (on the leg axis) and `Flood_Waibaidu_E pos=(-132.8, 9.5, -964.9) aim=(0,1,0)`.
    - `lm_probe3.gd` → `PearlRing_ColDeck y 5.70..6.70`, `Waibaidu_ColDeck` (12 faces); no other colliders.
    - `lm_api.gd` → `disable_fog=true probe_size_default=(20, 20, 20)`.
  - Windowed probe `lm_fogtest.gd` (Bund view, fog on vs off) → `r2_fog_on.jpg`, `r2_fog_off.jpg`, `r2_fog_cmp.jpg`.
  - PIL measurements:
    - shipped vs master pillar correlation: basecolor 0.101, normal 0.067, rough 0.176;
    - flat normal (188, 188, 255) in every texsets/texgen `*_nor.png`;
    - `metal_dark_diff.png` sRGB mean (0.542, 0.564, 0.587);
    - 12 stale extracted textures (20.8 MB) and 4 orphan .import files.
- **Captures** in `captures/review/landmarks/`:
  - `review_landmarks_r2_{bund,century,spiral,nanpu_deck,nanpu_leg,lupu,opt_sphere20,opt_base,jinmao_base,tower100,swfc_top,ring_street,ring_over,waibaidu,wb_side,pillar_2m,pillar_mid}.jpg`
  - `review_landmarks_r2b_{swfc_ap,st_crown,jinmao_crown,nanpu_w_main,opt_out,ring_col}.jpg`
  - Sheets: `r2_sheet_{overview,lujiazui1,lujiazui2,pillar_wb,details}.jpg`, `r2_sbs_bund_opt.jpg` (vs lujiazui_from_bund_night_2016_01 / opt_night_2014), `r2_sbs_ring_waibaidu.jpg` (vs lujiazui_intersection_ring_2014 / waibaidu_bridge_night_2019), `r2_crops_swfc_sign_lupu.jpg`, `r2_pillar_tex_compare_s.jpg`, `r2_pillar_master_1to1.jpg`, `r2_bp_pillar_close_s.jpg`.
  - Note: `opt_base` puts the camera inside the podium; use `opt_out:712.5,3,-634.9:637.5,60,-634.9:62` instead.
- **Frame stats** (`ref/art/lookdev/tools/screenshot_stats.py`; targets P95 0.40-0.78, SAT 2-15 %):

  | frame | P5 | P50 | P95 | P99 | SAT |
  |---|---|---|---|---|---|
  | bund | .080 | .110 | .219 | .260 | 0.000 % |
  | bund, fog off | — | .106 | .313 | .439 | 0.052 % |
  | century | .078 | .098 | .244 | .315 | 0.003 % |
  | spiral | .085 | .114 | .232 | .271 | 0.000 % |
  | nanpu_deck | .085 | .122 | .349 | .565 | 0.012 % |
  | opt_sphere20 | .093 | .415 | .785 | .800 | 1.108 % |
  | pillar_2m | .012 | .089 | .226 | .269 | 0.000 % |
  | waibaidu | .068 | .141 | .295 | .592 | 0.556 % |
  | ring_street | .076 | .142 | .426 | .502 | 0.533 % |

- **Lead notes:** `reviews/landmarks-lead.md` L-ART1, L-ART2 and L-ART3 are **not satisfied** (MUST-FIX 2, 1, 3).
