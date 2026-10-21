# landmarks review round 1 — VERDICT: FAIL

## Scores (0-10): function, visual, code
- **function 4** — all 10 glb load, anchors/heights/contract names are right and the test passes, but there are
  gameplay-relevant geometry bugs: Nanpu cables in the carriageway, a cable on the road centreline, the Pearl Ring
  girder at 5.3 m with a 0.3 m collider, a pier in the Waibaidu carriageway, floating stairs, open meshes, a mirrored sign.
- **visual 2** — at night the skyline is black slabs and white balls (frame stats below: P99 0.11, SAT 0.0 % from the
  Bund). The OPT is white, the pillar looks like wallpaper with a brown worm on it, the facades tile in a 4 x 4 lattice,
  the bridges are dark, and 10 materials have no texture at all. The user asked for textures refined everywhere
  ("贴图纹理什么都要细化"). This round is far from that.
- **code 5** — the scripts are deterministic, split by job and all under 400 lines (good). There are real bugs:
  `dot_grid` draws lines instead of dots, `tex_mat` silently drops the tint colour, open caps, a test that masks its
  own failures, magic numbers in bridge logic, and a re-implemented `lib/mats.py`.

Work order: items 1-3 are the lead's mandatory notes (L-ART1..3). Do them first, then 4-12. After every item,
rebuild (`tools/blender.sh run blender/landmarks/build_all.py`), re-run the test, and re-capture with the cams given.
The cams are in Godot map coordinates for `preview_skyline.tscn` (`--cams="name:x,y,z:lx,ly,lz:fov"`).

## MUST-FIX

1. **[L-ART1] The Oriental Pearl spheres render WHITE. They must be glossy pink-magenta glass with fine LED dots.**
   - Bug: `blender/landmarks/texgen.py:174` uses `np.minimum(|cu-.5|, |cv-.5|) < duty/2`, which draws a grid of
     thick LINES. `led_dots_pink.png` is **79.5 % lit**, measured: white with dark-pink square holes. See
     `captures/review/landmarks/r1_opt_sphere20.jpg`.
   - Do:
     - (a) Draw round dots: `d = hypot(cu-.5, cv-.5)`, radius 0.20 of the cell (about 12 % coverage) with a 1-px soft edge.
     - (b) Dot pitch **0.4 m** (dossier §15). Use a small tileable cell texture (256² holding 8 x 8 dots = 3.2 m) and
       set the per-sphere UV tiling to circumference / 3.2 m. Today the pitch is 3.3 m (48 cells around 157 m).
     - (c) Make the LED shell see-through between the dots. Use alpha-scissor (glTF alphaMode MASK, cutoff 0.5) with
       the dot mask in the base-colour alpha. Set the default emission colour to **#FF3FA4** at energy 2.0-2.5,
       never white, so the asset is pink in any scene. The world unit still animates the hue. Keep the `LED_Sphere_*` names.
     - (d) `LM_PEARL_Glass`: base **#B0306A**, metallic 0.3, roughness 0.15, plus a **honeycomb/triangulated panel
       grid at 1.2 m pitch** (normal + roughness + ±6 % albedo per panel, dossier §15).
     - (e) Silver bands `LM_PEARL_Alu` **#C8CCD0**: brushed normal + roughness 0.25-0.4 breakup. Today they render
       black because they are untextured and have no reflection probe.
     - (f) Tubes: the `#7A4CFF` vertical strips must be visible from the Bund (≥ 2 m wide, E3). Light the tubes from
       `Flood_Base_*` in the preview (item 6).
   - Verify:
     - Cam `opt_sphere20:682.5,93,-634.9:637.5,93,-634.9:62`.
     - Cam `bund:-105,5,-480:1000,230,-300:50`.
     - hstack the result with `ref/shanghai/img/06_lujiazui/opt_night_2014.jpg`. The OPT must be the most colourful
       object in the Bund frame.

2. **[L-ART2] The dragon pillar is a flat brown worm on cream wallpaper, not crafted bronze relief.**
   See `captures/review/landmarks/sbs_pillar.jpg` next to `ref/shanghai/sheets/c_pillar.jpg`.
   - Measured:
     - `tex_pillar.py:249-254` lays the dragons out as a **3 x 3 grid of vertical sine-wave capsules**. They do not
       spiral. Body radius is up to 0.82 m, so bodies are up to 1.64 m wide; the dossier says 0.45-0.6 m.
     - The 雷纹 is isolated glyphs in a perfect 0.38 m grid on bare steel.
     - The raster is 4096 x 2048 over 15.7 x 29.4 m: **260.8 px/m around but only 69.7 px/m up**.
     - The glb material has only basecolor + normal, at metallic 0.35. Roughness, AO and height are generated but not wired.
     - The plinth renders light concrete because the #3A3A3C tint is dropped (see item 5).
   - Do:
     - (a) Raster **4096 x 8192** (dossier §15, about 260 px/m both ways) for height, normal, AO, curvature,
       roughness and albedo. If the glb gets too big, ship albedo/ORM at 2048 x 4096.
     - (b) 9 archaic **kui** dragons, each a band 0.45-0.6 m wide and 6-8 m long, **climbing helically** (one turn per
       12-15 m) and interlacing between the deck-level panel grooves (9.0 / 16.5 / 24.0 m).
       - Spines are polylines with 90°/45° turns. Head, tail and limb ends end in square-spiral curls with hooks.
       - Dorsal flanges (扉棱) run along the backs.
       - Fill each body with **scales as repeated chevrons** 8-10 cm; drill the eyes deep.
       - Sun disc Ø 1.2 m on the east, crescent moon on the west.
     - (c) 雷纹 as a **continuous interlocking square-spiral band** (0.25-0.35 m cells, alternate the rotation, linked
       ends) that fills ALL gaps at 0.03-0.04 m depth. Target dark-relief coverage **55-65 %**, like c_pillar.jpg.
       Bare steel should show only as narrow ridges and fields.
     - (d) Materials (dossier §1.2):
       - Steel **#B9BCBE**: metallic ≥ 0.9, roughness 0.30, with **vertical brushing** (stretched noise about
         2 mm x 300 mm in the roughness map plus a fine detail normal).
       - Bronze **#3B2F25**: metallic 1, roughness 0.45. Raised edges **#8A6A3E** from the curvature map.
       - Darkened cavities; dust on up-facing ledges.
       - Wire roughness/metallic (glTF metallicRoughness) and occlusion into the glb.
     - (e) Use the 60k budget. Build a 192 x 150-quad cylinder (about 57.6k tris), add a Displace modifier with
       `pillar_height` at 0.12 m, and apply it before export. The silhouette must show the relief; the normal map
       carries the fine detail.
     - (f) Plinth: dark granite **#3A3A3C**, roughness 0.6. Use the library `granite_tile_03` via `mats.pbr(..., tint=)`.
     - (g) Preview lights: replace the four OmniLight3D at energy 80 with **SpotLight3D** at the `Flood_Base_*`
       empties.
       - `light_color #FFC98A`, `spot_angle 12.5` (25° beam), energy 8-15, range 35 m.
       - Aim at the column at y ≈ 12 m. A spot shines along its local −Z, so `rotation_degrees.x = 90` points it straight up.
       - Add the `Flood_Under_Deck` light.
       - Grazing light is what makes relief read.
   - Verify:
     - 2 m close-up cam `pillar_2m:-1294.5,1.7,687:-1299,4,687:60` (4.5 m from the axis = 2 m from the surface).
     - 15 m cam `pillar_mid:-1284,1.7,697:-1299,14,687:62`.
     - hstack both with `sheets/c_pillar.jpg`. Dark relief must dominate, silver must show between it, edges must
       catch the uplight, and the silhouette must be bumpy.

3. **[L-ART3] The Lujiazui towers read as black slabs with sparse orange dots, and the windows tile every 4 bays x 4 floors.**
   - Measured: `facade_night_emit.png` has exactly **2 colours**, black and one orange. `facade_maps(bays=4)` plus
     `lit = r0 < 0.13` means the same 1-2 windows repeat across every tower; see `crops_sign_jinmao.jpg`, bottom.
     `facade_night_diff.png` has 4 flat colours.
   - The brief's reading list points to the facade shader (ref/art/DOSSIER.md §4.4); it was not used.
   - Do:
     - (a) Tower glass on Jin Mao, SWFC, Shanghai Tower and the backdrop uses `res://shaders/facade_windows.gdshader`
       with the office preset: object-space projection (no UV needed), per-window random, grime, LOD fade.
       - Lead: **~35-40 % lit** windows in cool/neutral whites (#DEE8FF / #FFC18D, little warm), `window_energy` ≤ 1.0.
       - The shared `SH_facade_office.tres` has lit_ratio 0.30 and is owned by the shaders unit. Own a ShaderMaterial
         at `game/assets/landmarks/materials/lujiazui_facade.tres` with lit_ratio 0.38.
       - Apply it in thin wrapper scenes `game/assets/landmarks/<tower>.tscn` (glb + override + `building_seed`
         instance uniform, a different seed per tower). List the wrappers in the manifest.
     - (b) Lit crowns, sized for where they are seen from. ART dossier §4.5 says stroke ≥ 0.0026 x distance, so about
       **3.4 m at 1.3 km** from the Bund. Today's gold and white lines vanish from the Bund.
       - Jin Mao: gold **#FFD27A** wash bands 2-4 m tall on every setback, plus a floodlit crown at E3-E4
         (`swfc_jinmao_night_2009.jpg`).
       - SWFC: **#DDEEFF** edge strips ≥ 1.5 m wide along both arcs and around the aperture.
       - Shanghai Tower: **#E6F2FF** dotted floor bands (keep them) plus a **brighter continuous notch line** along the
         V-notch at E3 (missing today).
     - (c) Give 2-3 backdrop towers (for example IFC_C, CMB, Aurora) **giant LED ad facades**, about 60 x 120 m each.
       - Use `SH_hologram` mode 0 with `led_grid` = screen metres x 6 and energy ≤ 2.5.
       - Content: your own 1024 x 576 ads with ART.md §7 parody brands (东方霓虹, 浦江电讯 ...), Chinese first.
   - Verify:
     - Cams `bund` (above), `century:830,2,-455:1180,260,-150:62` and `jinmao_base:1178,2,-179.8:1133,40,-199.8:62`.
     - No repeating lattice at 20 m.
     - Jin Mao gold, SWFC outline and Shanghai Tower bands must read from the Bund.
     - Frame stats (ref/art/DOSSIER.md §2.4) on the Bund shot: P95 ≥ 0.40, SAT 2-15 %.

4. **The backdrop blocks the OPT, and the backdrop towers are near-identical boxes.**
   - In `r1_bund.jpg` a backdrop box overlaps the OPT's lower sphere and tubes. `Tower_Mirae` (566, −566) and
     `Tower_StdCh` (704, −686) stand in the OPT sightline from the promenade.
   - All 12 towers are the same two-stage box with the same facade (ART.md §8: "repeated identical buildings").
   - Do:
     - Keep a clear corridor of ±60 m around the OPT. Nothing taller than 60 m may overlap the OPT silhouette from
       promenade points x −110, z −250…−900.
     - Vary the plans: chamfered and rounded corners for the IFC twins, an L-plan, a cylinder, stepped setbacks, a
       podium. Give every tower its own crown.
   - Verify: Bund cam. The OPT stands free and no two backdrop towers read alike.

5. **No-texture and flat-texture surfaces everywhere (SPEC pillar 4, ART.md §5, dossier §15).**
   - The Blender stats (`tmp/review/lm_stats.txt`) flag these as UNTEXTURED:
     - `LM_PEARL_Alu` (12,276 tris), `LM_JINMAO_Fin` (12,864), `LM_JINMAO_Crown`, `LM_SWFC_Beam`
     - `LM_TOWER_Core`, `LM_TOWER_Crown`
     - **`LM_RING_Steel`, `LM_RING_Glass`**: the whole Pearl Ring
     - **`LM_WAIBAIDU_Timber`**: the sidewalk next to the road
     - `LM_LUPU_Steel`
   - The "textured" glass uses flat 2-4-colour images: `glass_bands_diff.png` has 2 colours, `facade_night_diff.png` has 4.
   - Bug: `lmmat.tex_mat` sets `Base Color.default_value` (lmmat.py:111) and then links the texture, so the colour is
     silently dropped. Lost tints: Jin Mao #3E4A52, OPT concrete #D2D2D0, Nanpu concrete #D8D8D2, plinth #3A3A3C.
   - CONTRACTS §2 says to use `blender/lib/mats.py`; do not copy it. Its `pbr(name, tex=, tint=, tile_m=)` wires
     library diffuse, rough and normal maps and the baseColorFactor tint. Use it for library textures, and give
     `lmmat` a multiply tint for unit textures.
   - Every non-LED material needs: albedo with variation + normal + roughness/ORM + grime or edge wear.
     - **Metals** (OPT bands, Jin Mao fins/crown, SWFC beam, Shanghai Tower crown, Pearl Ring, Lupu): a generated
       1024² brushed/painted-metal set. Panel seams every 1.2-1.5 m, roughness 0.25-0.4 breakup, rain streaks from
       the library `Leaking004` / `Leaking016A`.
     - **Pearl Ring glass**: panel joints every 1.5 m, dirt along the bottom edge.
     - **Waibaidu timber**: **512 px/m**. Planks 0.20 m wide (9 cm thick), staggered butt joints, grain, gaps, a worn
       foot path, normal + roughness.
     - **Shanghai Tower core and crown**: panel/fin trim textures.
   - Verify:
     - Extend `test_landmarks.gd` so it FAILS when any surface whose material name does not start with `LED_`
       (colliders excepted) lacks `albedo_texture` or `normal_texture`.
     - My `tmp/review/lm_stats.py` must list 0 UNTEXTURED apart from LED_ materials.

6. **Night lighting: the floodlit landmarks render black.**
   - Frame stats: Bund P95 0.075 / P99 0.108 / SAT 0.0 %; spiral P99 0.114; Century Ave P99 0.222.
     Targets (ref/art/DOSSIER.md §2.4): P95 0.40-0.78, SAT 2-15 %.
   - Do. Export enough `Flood_*` empties, give each a light spec in the manifest (type, colour, energy, angle,
     range), and attach real SpotLight3D at those empties in `preview_skyline.tscn` so the captures prove the look.
     The dossier forbids emission on bare concrete (§15).
     - **Nanpu**: 4 per tower (2 per leg at deck level, aimed up), 4000 K **#FFCEA6** (ART dossier §2.2), white wash
       like `img/03_nanpu_lupu_bridges/nanpu_night_2026.jpg`. Add `Flood_Nanpu_Under_*` **#FF8A2A** under the deck
       (dossier §3.2).
     - **Waibaidu**: warm **#FFC24D** floods along both trusses (`img/05_bund/waibaidu_bridge_night_2019.jpg`).
     - **OPT**: tube and base floods.
     - **Lupu**: the rainbow arch is **invisible from the Nanpu deck** (`r1b_lupu_from_nanpu.jpg`). At 2.2 km a stroke
       must be ≥ 5.7 m (stroke rule above), so put the rainbow on the full 9 m outer face of each rib at E3.
   - Verify:
     - Cam `spiral:900,44,1180:1250,80,1390:62`.
     - Cam `nanpu_deck:1082.7,45.2,1317.6:1139.4,70,1338.2:62`.
     - Cam `lupu_from_nanpu:1330,47,1430:-300,60,2900:30`. The rainbow must read.
     - hstack with nanpu_2019_01.jpg and lupu_night.jpg.

7. **Nanpu geometry bugs** (`build_bridges.py`).
   - (a) Cable planes at **x = ±11.0 m** (lines 78-79). At the deck they land **inside the carriageway**: lanes reach
     ±11.25 m, so cars drive through cables. At the tower they anchor in mid-air 6 m inboard of the legs, which stand at
     ±17.2 m, and form ghost "columns" (`crops_sign_jinmao.jpg`, top).
     - Fix: deck anchors on the edge girders at |x| ≈ 14.9 m; tower anchors inside the leg section at |x| ≈ 15.6 m.
       Use named constants.
   - (b) The **centre vertical cable** (lines 80-83) hangs at x = 0 from nothing above the upper crossbeam and lands on
     the road centreline.
     - Fix: delete it. The dossier's "1 vertical cable at each tower" means one per cable plane at the leg.
   - (c) The **W sign 「南浦大桥」 reads mirrored** from the main span. It sits on the +Y face but faces −Y (line 102).
     - Fix: rotate the W sign 180° about Z, `rotation_euler = (90°, 0, 180°)`.
     - It renders salmon-pink, not **#D9161C**. Use E2.5-3 and add a dark back-plate #141416 (ART dossier §4.5).
   - (d) The legs are 8-sided tubes. Dossier §3.2 asks for **rectangular legs, 6.0 x 4.5 m at the base tapering to
     4.0 x 3.5 m**.
     - Fix: chamfer the corners (0.3 m) and the crossbeams; add cable-anchor blocks and tower caps. Bevel the edges so
       they catch light (ART.md §10.8).
   - (e) Concrete: the crossbeam shows stretched vertical streaks and the legs show moiré (`r1_nanpu_deck.jpg`).
     - Fix: per-face box UVs at a 4 m tile plus a detail normal; formwork grid 1.2 x 2.4 m with Ø 3 cm tie holes; rain
       streaks under the crossbeams (dossier §15, concrete row).
   - Verify:
     - Test: no cable vertex with |x| < 12.0 m below local Y 50; both signs' normals face the main span.
     - Cam `nanpu_w_main:1229.5,47,1381.6:1139.4,118,1338.2:50`: the sign reads 南浦大桥 left to right.

8. **Waibaidu geometry is wrong** (`build_bridges.py:211-266`).
   - (a) `Waibaidu_Pier` (line 253) is a 2.6 x 3.2 m steel-textured post at x = 0 whose top is at Y 0. It stands in the
     middle of the 11.2 m carriageway (the grey block on the road in `r1_waibaidu.jpg`), while the trusses at
     x = ±6.096 rest on nothing mid-creek.
     - Fix: a granite pier across the full width (x −9.5…+9.5), top below the bottom chord (Y ≈ −1.2), with bearings
       under each truss.
   - (b) Members are round 5-6-sided tubes. The real bridge (`waibaidu_bridge_day_2019.jpg`) has riveted built-up
     box/I sections with lacing.
     - Fix: rectangular chords about 0.6 x 0.5 m with flanges; laced verticals and diagonals (lacing as
       alpha-scissor texture or thin geometry); gusset plates at every node; rivet rows along the plate edges,
       Ø 2.5 cm @ 10 cm. Today it is a uniform 16 x 16 rivet field.
   - (c) Add the **overhead X-bracing and portal frames** between the top chords (12.192 m apart) and the outer
     sidewalk railings.
   - Verify: cam `waibaidu:-144.4,5.5,-936.3:-137.1,9,-985.8:62` hstacked with waibaidu_bridge_night_2019.jpg.

9. **The Pearl Ring is the closest landmark to the player, and it is grey-box quality with a clearance bug** (`build_lujiazui.py:93-145`).
   - (a) The girder underside is at **Y 5.30** (measured, `DECK_Y - 1.2`), but the brief requires **5.5 m clearance**.
     The collider is only 0.3 m thick (Y 6.2-6.5), so a Big Hop (apex 7.8 m, SPEC §5) flies through the visible girder.
     - Fix: girder 1.0 m deep, or deck top at 6.7 m. Make the collider cover the full girder volume.
   - (b) The columns are **Λ pairs**: two 10-sided faceted tubes converging upward. The reference
     (`img/06_lujiazui/lujiazui_intersection_ring_2014.jpg`) shows single stout columns with flared Y heads.
     - Fix: 8 smooth-shaded Y columns, painted **#F0F0EE**, with texture.
   - (c) The stairs are two plain boxes and **float 1.57 m above the ground** (min Z 1.57, measured).
     - Fix: model real stairs with treads, an escalator truss with glass sides, handrails and a canopy at the 4
       points, all touching the ground.
   - (d) Rounded fascia and soffit, under-deck downlights (emissive spots), textures per item 5.
   - Verify:
     - Cams `ring_street:798,1.5,-458.8:806,6.5,-508.8:62` and `ring_over:868,25,-398.8:748,4,-488.8:60`.
     - Test: min Y of the ring deck mesh ≥ 5.5; collider bottom = girder bottom.

10. **Open meshes and an unreadable SWFC aperture.**
    - Boundary-edge counts (`tmp/review/lm_open.py`): **JinMao_Body 208** (each tier is lofted with `cap_end=False`,
      `build_towers.py:48-57`, so every setback ledge is a hole you see from the sky lanes) and **SWFC_Body 30** (the
      lower shaft is open at 440 m and the top beam is open at 472 m, lines 125/145, so the aperture looks into a
      hollow tower).
      - Fix: cap the ledges, the aperture floor and the aperture ceiling, and add the inner reveal faces.
    - The SWFC aperture must read as a crisp **inverted trapezoid on both broad faces**: 30 m wide at 440 m, 50 m at
      472 m. In `towers_strip.jpg` it reads as a one-sided notch.
      - Make the broad faces the two sweeping arcs (curved, not planar).
      - Add the 4-floor, 15.8 m podium (dossier §6.2).
    - Verify:
      - lm_open shows 0 open edges on the bodies.
      - Cam `swfc_top:1512,450,-236:1262.2,455,-136:50` shows the sky through the aperture, outlined in white.

11. **Missing acceptance evidence.** The brief wants, per asset, Blender previews (night + studio) plus a
    side-by-side with a reference photo.
    - Today only the OPT has a studio sheet, and only 5 of 10 have side-by-sides. Missing: Pearl Ring, backdrop, Lupu,
      and Jin Mao / SWFC / Shanghai Tower as separate sheets.
    - Fix: run `tools/blender.sh preview <glb> <name> --light both` for all 10 and hstack each with its named reference
      photo in `captures/landmarks/`.

12. **Rules and hygiene** (the lead's project-wide rules).
    - Scratch went to system `/tmp`: `/tmp/dbg.gd` is still there, and `/tmp/probe*.py` were used. Delete them. Use
      `tmp/landmarks/` only, and clean it up.
    - Delete the orphan `game/assets/landmarks/textures/pillar_ao.jpg.import` and `pillar_rough.jpg.import`.
    - `test_landmarks.gd:69` and `:72` do `ok = _find(...) != null`, which overwrites the accumulated `ok` and masks an
      earlier height FAIL. Write `ok = ok and ...` instead.
    - Static typing: `:37` `var data = ...` → `var data: Variant`. The loop variable `name` (`:54`) shadows
      `Node.name`; rename it `asset_name`.
    - Verify: `tools/godot.sh test res://assets/landmarks/tests/test_landmarks.gd` exits 1 when you temporarily break
      one expected height.

## SHOULD-FIX
- **Manifest.**
  - Add anchor **Y** to every entry. The preview puts Lupu at Y 25 and Waibaidu at Y 4, but the manifest has only (x, z).
  - Lupu `rotation_y` −1.5708 disagrees with the preview basis (+90°). Make them agree.
  - Fix the heights: Waibaidu says 23.5 m against 9.4 m measured; Pearl Ring 8.5 against 8.1.
- **Unused PNG masters.** About 18 MB of pillar PNGs plus the other masters sit under
  `game/assets/landmarks/textures/`. Godot imports them, but the glb files embed the JPEG copies. Move the masters to
  `blender/landmarks/src_tex/`, or put them in a subfolder with a `.gdignore`.
- **Magic numbers** in `build_bridges.py` (11.0, 95.0, 2.3, 9.6, 131.0, 3.1/2.4/2.2/1.8, 40.5 …) and the Pearl Ring
  stair numbers: move them to named constants with dossier references. The cable bug came from one of them.
- **Cable shimmer.** The Ø 0.18 m cables are sub-pixel beyond about 70 m and shimmer, causing the moiré on the legs.
  Use camera-facing emissive ribbons with a minimum pixel width, or a far LOD of flat strips.
- **Preview scene.**
  - Instance `res://world/env/environment.tscn` (the environment unit) instead of a home-made Environment.
  - Add a ReflectionProbe at Lujiazui and one at the pillar so metals do not render black.
  - Call `MaterialLibrary.apply(self)` on load.
- **Jin Mao crown.** The real crown is stacked octagonal lattice rings; today it is a cone plus spire.
- **OPT podium.** Check the podium (Ø 100 m x 12 m) and the three Ø 8 m ground spheres (dossier §6.1) and texture them.
- **For the lead, not the worker.** With the dossier anchors, the OPT subtends 30.9° and Shanghai Tower 26.2° from
  promenade point (−110, −400). Acceptance item (a), "Shanghai Tower tallest", cannot hold from the Bund. Order and
  "rightmost" are correct.

## Verified OK
- All 10 glb files exist in `game/assets/landmarks/`, load in Godot and follow the contract names:
  - `LED_*` emissive meshes
  - `Flood_*` and `Aviation_*` empties
  - `PearlRing_ColDeck-colonly` and `Waibaidu_ColDeck-colonly`
  - origins at the anchor on the ground
- The `preview_skyline.tscn` placements match the dossier anchors; the test checks all 10.
- Heights match the dossier: OPT 468, Jin Mao 420.5, SWFC 492, Shanghai Tower 632, pillar 29.4, Nanpu tower 150
  (from −3).
- Polycounts are within budget:

  | asset | tris |
  |---|---|
  | OPT | 42,036 |
  | Jin Mao | 13,834 |
  | SWFC | 1,360 |
  | Shanghai Tower | 56,008 |
  | backdrop | 758 |
  | Pearl Ring | 2,656 |
  | Nanpu | 16,620 |
  | Lupu | 8,424 |
  | Waibaidu | 4,048 |
  | pillar | 526 (budget 60k; use it, see item 2e) |

- Preview fps is 73-245 at 1600 x 900.
- Silhouettes that already work:
  - Shanghai Tower: 120 rings twisting to 120°, taper, V-notch, crown fins.
  - Jin Mao: 13 octagonal tiers with gold setback lines.
  - OPT proportions: 3 tubes, braces, 5 small spheres.
- Code layout: deterministic builders, one `build_all.py` (27 s), all files ≤ 371 lines, numpy texture generators.
- Ownership: the job log shows every Write/Edit under `blender/landmarks/**` and `game/assets/landmarks/**`.
  `tools/city/city_landmarks.py` was changed by another unit. No landmarks Godot or Blender process is left running.

## Evidence
- `tools/godot.sh check --only=res://assets/landmarks/` → `CHECK 2 files, 0 failed, 0 engine errors, 0 warnings`.
- `tools/godot.sh test res://assets/landmarks/tests/test_landmarks.gd` → 25 PASS lines, 0 FAIL. Note the masking bug in item 12.
- `tools/blender.sh run tmp/review/lm_stats.py` → per-material texture wiring in `tmp/review/lm_stats.txt` (10 UNTEXTURED
  non-LED materials, item 5).
- `tools/blender.sh run tmp/review/lm_open.py` →
  - open edges: JinMao_Body 208, SWFC_Body 30
  - Pearl Ring: deck min Z 5.30, stairs min Z 1.57
  - Waibaidu: pier top 0.0, at x = 0
- `tools/blender.sh preview game/assets/landmarks/{swfc,jin_mao,shanghai_tower,nanpu_bridge}.glb ../review/landmarks/bp_<n>
  --views front34,side --light studio` → `captures/review/landmarks/bp_*` and `towers_strip.jpg`.
- Texture measurements with PIL:
  - `led_dots_pink.png` 79.5 % lit
  - `facade_night_emit.png` 2 unique colours
  - `facade_night_diff.png` 4
  - `glass_bands_diff.png` 2
  - pillar raster 4096 x 2048 = 260.8 x 69.7 px/m
- Godot captures, `tools/godot.sh shot --scene=res://assets/landmarks/preview_skyline.tscn --env-only --warm=40`, in
  `captures/review/landmarks/`:
  - Batch 1: `r1_{bund,century,spiral,nanpu_deck,pillar_close,pillar_mid,opt_sphere20,opt_base,jinmao_base,tower100,swfc_top,ring_street,waibaidu}.jpg`
  - Batch 2: `r1b_{nanpu_w_main,nanpu_w_back,opt_full,ring_over,lupu_from_nanpu}.jpg`
  - Sheets: `sheetA-D.jpg`, `sbs_bund_waibaidu.jpg` (vs lujiazui_from_bund_night_2016_01 / waibaidu_bridge_night_2019),
    `sbs_pillar.jpg` (vs sheets/c_pillar.jpg), `sbs_bridges.jpg` (vs lupu_night / nanpu_2019_01), `crops_sign_jinmao.jpg`.
- Frame stats (luminance P5/P50/P95/P99, SAT %; targets ref/art/DOSSIER.md §2.4):

  | frame | P5 | P50 | P95 | P99 | SAT |
  |---|---|---|---|---|---|
  | bund | .000 | .075 | .075 | .108 | 0.0 % |
  | century | .004 | .075 | .075 | .222 | 0.5 % |
  | spiral | .002 | .075 | .075 | .114 | 0.0 % |
  | waibaidu | .000 | .075 | .180 | .835 | 0.3 % |

- Lead notes `reviews/landmarks-lead.md` L-ART1, L-ART2 and L-ART3 are **not satisfied**; they are MUST-FIX 1-3.
