# buildings review round 1 — VERDICT: FAIL

Reviewer: lead art director (Opus). The user asked for "贴图纹理什么都要细化" — every texture refined.
Right now the in-game city is broken (all tiles stacked at the origin) and the art is far from
Shanghai street level or the reference photos. Fix in the order below; numbers are binding.

## Scores (0-10): function 3, visual 2, code 4

## MUST-FIX

1. **Tiles are exported in tile-local coordinates — in the game all 50 tiles pile up at the origin.**
   - Evidence: `blocks_-1_1.glb` node `b_d4_141_0-convcolonly` sits at local (78, 4.2, −40); the
     roads unit's `roads_-1_1.glb` spans x −513…−3, z 511…1020 (WORLD coordinates). The world
     loader (`world/loader/asset_library.gd`, `world_builder.gd:100-108`) adds your tiles
     without a position, exactly like the roads. `captures/review/buildings/rb1_game_mid.jpg`:
     Fuzhou Rd (−660, 1.7, −224) has no buildings at all; `rb1_game_origin.jpg`: every tile
     overlaps inside x, z ∈ [0, 512] (over Lujiazui and the river). Only your preview hides this
     (`preview_blocks.gd` offsets each tile by 512 m).
   - Do: export near, far and colliders in WORLD coordinates (same convention as roads): drop
     `translate_objects()` / the `−origin` shifts in `build_city.py` (lines ~156, 165-190, 277);
     for every exported mesh put the node translation at its cell centre (world) and the vertices
     relative to it (see item 6 — the visibility range is measured to the instance centre);
     keep `origin` in the sidecar only as metadata; delete the per-tile offset in
     `preview_blocks.gd`.
   - Verify: glb bounds of `blocks_-1_1.glb` (node translation + accessor min/max) lie in
     x −512…0, z 512…1024 (+ block spill); `tools/godot.sh shot --scene=res://main.tscn
     --stub=menu --env-only --cams="mid:-660,1.7,-224:-560,8,-232:70"` shows the midrise row
     on the right side of Fuzhou Rd. Put that capture in status.

2. **AC units, cages, balconies, residential balcony bands and stair cores are placed on the tile
   border lines, not on the buildings.**
   - Cause: `grid.point_at_u()` returns `(origin[0], …)` or `(…, origin[1])` — it throws away the
     wall's own across-wall coordinate. Callers: `styles/midrise.py:49,69`,
     `styles/residential.py:25,26,42,56`.
   - Evidence: in `blocks_-2_-1.glb` 89 % of the `Metal_Galv` vertices and 81 % of the
     `Metal_Dark` vertices lie within 1 m of the tile lines x = 0 / z = 0
     (`python3 -I tmp/review/glbverts.py <glb> Metal_Galv`). `bl_mid2_border.jpg`: curtains of
     AC units floating over a park; `bl_mid_upper.jpg`: the midrise facade itself is bare.
   - Do: map the shader-grid parameter back onto THIS wall: `s = (u − u0) / (u1 − u0) * fc["w"]`,
     `p = fc["a"] + fc["t"] * s` (u0/u1 = `wall_u` at `fc["a"]`/`fc["b"]`; u is linear along the
     wall), then offset outward by the part depth. Add a Python assertion in the builder:
     every clutter part centre is ≤ 0.6 m from its own building's facade plane, else raise.
   - Verify: the assertion runs on the whole city; no clutter vertices along the 512 m tile
     border lines; a capture at 15 m of a midrise facade shows AC units under ~30 % of the
     windows, cages on ~5 %, balconies on the street side.

3. **Neon street: zero blade signs are ever built, and the blade geometry is wrong.**
   - `styles/neon.py:_signage`: `h = 5.0`, `bh = uniform(3, 7)`, `if h − bh < 3.4: break` →
     always breaks → 0 blades (your `captures/demo_neon.jpg` shows none). `parts2.add_blade_sign`
     builds the blade box parallel to the wall and puts the two sign faces flush with the wall,
     one facing into it. `add_led_screen(ctx, fc["a"], …)` hangs a 0–4 m screen over the shop
     at the corner. The blades are also centred on the corner (`u = step*(i+0.5) − w/2`), so
     half of them hang past the building edge.
   - Do (dossier §9 + art §4.5, ref `nanjing_road_night_2009.jpg`): blades PERPENDICULAR to the
     facade, faces pointing ±tangent (read up/down the street), 1.0–1.5 m wide × 3–8 m tall,
     bottom ≥ 3.6 m, stacked upward to the 4th–6th floor, 2–4 per 10 m of frontage, both sides
     of the street, 0.3 m stand-off, steel brackets, a black anodised back plate `#141416`
     8 cm behind each face; characters in coloured neon (red `#FF2A3A`, magenta `#FF3FD8`,
     cyan `#29D3FF`, yellow `#FFD23F`, green `#39FF88`) with a white-hot core — not white text
     with a coloured rim; 1 in 12 with a dead letter. LED screens 6–20 m high, 8–20 m wide.
   - city.json has no `neon_street` block (no D2). Until city_layout adds it, give every block
     that touches the dossier D2 rectangle (x −900…−170, z −560…−520) the neon frontage on the
     edge facing `st_nanjing_e_rd` (keep its style for the rest).
   - Verify: capture `--cams="nanjing:-330,1.7,-540:-450,9,-540:70"` (game, after item 1)
     shows ≥ 12 blades on both sides; ffmpeg `hstack` it next to
     `ref/shanghai/img/09_street_details/nanjing_road_night_2009.jpg` in status.

4. **Heritage windows: half of each facade's windows float in mid-air past the corner, and
   the panes are coplanar with the wall.**
   - `styles/heritage.py:_windows`: `u = step*(i+0.5) − fc["w"]*0.5` is measured from the corner
     `fc["a"]`, so u < 0 lands outside the building; `add_wall_quad` puts the pane exactly on
     the wall plane (z-fight). Evidence: your `demo_heritage2.jpg` (white squares sticking out
     beyond the facade), `rb1_prev_her.jpg`, `bl_her_close.jpg` (window crosses on a blank wall).
   - Do: u in [0, w]; real openings with a 0.25–0.35 m reveal (build the wall as piers +
     spandrels, or inset frames + reveal quads), glass 0.25 m inside, granite architrave +0.08 m
     proud with sill and keystone; 30 % lit (dossier §15 Bund granite), warm `#FFA757` /
     `#FFC18D` at E1 (0.6–1.0); mullion/transom inside the reveal, never floating.
   - Verify: 5 m capture of a heritage facade — every window inside the wall outline, visible
     reveal shadow, no flicker while orbiting.

5. **Ground floors: no walls on three sides, no depth, flat emissive "shop interiors"
   (midrise, residential_slab, neon_street — most of the city).**
   - The facade prism starts at `GROUND_H` 3.4 m and shopfronts are added on the front edge
     only, so the sides and back are open from 0 to 3.4 m: `bl_mid2_side.jpg` shows the void
     under the row. `parts.add_shopfront` (docstring "recessed") puts the `Shop_Glow` quad ON the
     building line — recess 0 m; the "door" is a box 0.30 m in FRONT of the facade. The office
     podium lobby glass (`office.py:_podium`) is coplanar with the `SH_facade_office` prism and
     the granite plinth → z-fighting. Brief: "Ground floor (0–8 m) is hand-built geometry with
     real depth".
   - Do: close all four sides from 0 m (wall material + side shops on corners, roller shutters
     卷帘门 with their housing box, service doors, louvres, pipes on the back); shop glazing
     recessed 0.5–0.8 m with soffit and side reveals, stall riser, mullions, a recessed door;
     behind the glass an interior card from an interior atlas (shelves/fridges/tables per shop
     type, see BL-ART1) instead of a flat emissive plane; the 3.4–8 m band hand-built too
     (fascia, 2nd-floor signs, AC units, canopy); podium lobby glass recessed ≥ 0.6 m behind
     columns.
   - Verify: orbit capture of one midrise from the side street (no void, nothing coplanar);
     5 m capture of a shopfront showing depth and an interior.

6. **Far LOD and HLOD: blown-out checkerboard, wrong granularity, preview shows near + far
   together.**
   - `windows_far_*`: 16 × 16 full-bleed window cells (no wall, no mullions, ~55 % of the area
     lit), used as BOTH albedo and emission at strength 2.0 (E2). Result: 3 m bright squares
     over the whole facade (`rb1_prev_mid.jpg`, `rb1_prev_office.jpg`). ART §2/§5 and art
     dossier §2.3/§4.4: windows E1 (0.6–1.0), never bloom, lit 2–8 % of a facade.
   - Do: rebuild the atlas: per cell a wall/spandrel frame (≥ 35 % of the cell) + mullions;
     10–30 % of cells lit; residential warm `#FFA757`/`#FFC18D` + 5 % TV blue, office cool
     `#DEE8FF`; albedo = dark wall/glass (`#2E2F32`/`#0B0E13` office, `#8E877C` residential),
     emission E1 0.8; cell size equal to the near shader presets (office 1.5 × 3.9 m,
     residential 3.3 × 2.95 m) so the hand-off does not pop; set outward normals explicitly
     (`far._wall_quad` ignores `n`); roof cap must use a dark roof cell, not UV (0.5, 0.5).
   - Granularity: Godot measures the visibility range to the instance centre (docs
     "Visibility ranges (HLOD)"); the world unit uses near end 400 m / far begin 350 m per
     GeometryInstance. A 512 m tile's centre is up to 362 m from its nearest corner, so
     buildings ~40 m from the camera can switch to the far box. Split near AND far into 128 m
     cells (`blocks_<tx>_<tz>_c<i>_<j>_<mat>`, node translation = cell centre), shared
     materials; stay ≤ 600 draw calls per view (GODOT.md §5) — report the count from
     `tools/godot.sh perf` after item 1.
   - `preview_blocks.gd` loads near and far at the same time with no visibility ranges: use
     the same ranges as `AssetLibrary.prepare_instance` so your captures show what the game
     shows.

7. **Textures and materials are not refined (user: "贴图纹理什么都要细化").**
   - Reused generic maps: `Wood_Lacquer`, `Roof_Tile`, `Awning_Fabric`, `Foliage_Dark` and
     `Grass_Lawn` are the grey `render_grey` noise tinted; `Metal_Dark`/`Metal_Galv` (AC units,
     cages, door leaves, brackets, laundry poles) are the corrugated-steel ribs at 2.7 m with
     rust specks. `Glass_Dark`, `Shop_Glow`, `Emissive_*` are flat colours with no map
     (ART §5: no flat untextured surface anywhere the camera can see).
   - All tileables are 1024²; `Render_Grey` is 256 px/m but is used at 0–3.4 m (ART §5:
     street-level tiling ≥ 512 px/m). No trim sheet at all (brief: trim sheets 2048²; GODOT.md
     §5: 2048² facade trim sheets per style; art dossier §5.2: one 2048 trim sheet per district —
     cornice, sill, frame, pipe, AC unit, sign-frame strips). No detail normal and no grime /
     variation mask (SHANGHAI_DOSSIER §15: REQUIRED on every material). `matsb.pbr_tex`
     multiplies albedo by the ORM rgb in Blender (tints albedo by roughness/metal) and the AO
     never reaches glTF `occlusionTexture`.
   - Brick is a perfect stretcher bond with identical bricks (§15: 240 × 53 mm Flemish bond,
     10 mm lime mortar, per-brick tone, chipped arrises, soot); `stone_granite` is a beige
     speckle `#BAAD9D` with no blocks (art §4.9: Bund granite conditioned to `#ABAAA3`;
     §15: rusticated blocks 0.6 × 1.2 m with 1 cm joints); `stone_pale` is cloud noise.
   - Do: (a) dedicated 2048² sets (albedo + normal + ORM): grey clay roof tiles 小青瓦 with
     tile rows and ridge, black lacquer wood `#1E1A17` with grain and worn edges, powder-coated
     / galvanised steel with scratches and rust streaks, AC-unit casing (grille, fan disc,
     brand plate) on a 512 px/m prop sheet, awning canvas, glass with dirt/streak mask, cloth
     for laundry; (b) use the CC0 library the dossier names where it fits: `granite_tile_03` /
     `granite_bund` (already in `game/assets/textures/`), `dark_brick_wall`, `church_bricks_03`,
     ambientCG `CorrugatedSteel007A`, `LeafSet027`; (c) one 2048² trim sheet per family
     (shikumen, midrise/residential, heritage, office podium) and UV the trims to it; (d) detail
     normal (0.5–1 m) + world-space grime: rain streaks under sills, AC units and cornices,
     ground-up dirt 0–0.6 m, ±5 % per-block tint; (e) export ORM occlusion properly.
   - Verify: `tools/blender.sh preview` on a tile prints no UNTEXTURED; a table in status
     (material → maps, size, px/m; ≥ 512 px/m for everything at 0–8 m); 2 m close-ups of a
     shikumen door, a midrise shopfront and a heritage base.

8. **Signs: blurred, truncated, blank plaques, real brand names.**
   - Resolution: `neon_horizontal.jpg` 2048 × 1024 holds 26 signs (~512 × 128 px → ~110 px/m on a
     4.7 m fascia); blades ~192 × 576 px (~160 px/m). SHANGHAI_DOSSIER §15: "vector-sharp text at
     ≥ 2048 px per sign face"; ART §5: props ≥ 512 px/m. The 5 m capture `rb1_prev_close_mid.jpg`
     is visibly soft.
   - Broken slots (signs.json): `blade_30…34` (茶楼, 眼镜行, 钟表修理, 裁缝店, 刻印社) have
     v0 = −0.125 → 12 % of the face samples outside the atlas (wraps into other glyphs);
     `blade_09` 老弄堂小笼 renders as 「老弄堂小」 and `blade_12` 永福大药房 as 「永福大药」.
     Brief: real words, never gibberish.
   - `plaques.jpg` is almost white — the 「xx里」 lane names are invisible.
   - 「益丰药房」 is a real pharmacy chain (益丰大药房) and 「新亚旅社」 borrows a real Shanghai
     hotel brand (新亚) — ART §7: parody brands only. Replace both.
   - Every lightbox is the same template (dark board, coloured rim, white glowing text). Real
     Shanghai lightboxes are printed backlit panels: coloured grounds, red/yellow/blue/white,
     a small logo, an English sub-line, a fictional phone number.
   - Do: ≥ 1024 px tall per blade face and ≥ 2048 px wide per fascia sign (several 2048²/4096²
     atlases; fit the text to the cell, never crop; assert every slot uv is inside 0…1 in
     `texgen`); fonts per shop type from art dossier §7.2 (Smiley Sans, ZCOOL KuaiLe, Ma Shan
     Zheng, Noto Serif SC); plaques = dark incised characters `#2A2622` on stone `#CFC8B8` with
     a normal map for the carving.
   - Verify: 3 m captures of a fascia sign, a blade and a lane plaque — all strokes sharp.

9. **Shikumen is not recognisable (ref `shikumen_xintiandi_2012.jpg`, lead note BL-ART2).**
   - Door frame = two jamb boxes + lintel + a 1.1 × 0.3 m block in cloud-noise `Stone_Pale`; the
     door is one flat quad in `render_grey`; windows are solid wood slabs with the pane coplanar
     on the slab's front face (z-fight), no recess, no muntins; roofs are a flat 0.12 m slab in
     `render_grey`. `ref_compare.jpg` (top row) shows the gap.
   - Do (BL-ART2, dossier §9, art §4.9): granite frame 0.25 m deep around a 1.4 × 2.6 m opening,
     triangular or segmental pediment with carved relief (geometry + trim-sheet normal), black
     lacquer double doors `#1E1A17` roughness 0.3 recessed 0.3 m with brass ring knockers
     `#B08D57` (metallic 1, roughness 0.35), 1–2 stone steps; timber casement windows recessed
     0.15 m with 2 × 3 muntins and panes, some shutters; pitched roofs with real tile courses,
     ridge tiles and 老虎窗 dormers; Flemish-bond grey brick with red courses every 9–12
     courses; lane gate arch with a legible 「xx里」 plaque. Remove sliver houses (`b_d4_199_32`
     is 1.38 m wide; minimum 3.6 m).
   - Verify: game capture `shik:-950,1.7,1033:-953,3,1038:60` hstacked with the reference photo.

10. **From the air the city is black (brief: "dense, varied skyline with lit crowns").**
    - `rb1_prev_air.jpg` / `rb1_prev_air2.jpg`: `screenshot_stats.py` → 5 FAIL (P95 0.224,
      P99 0.263, SAT 0 %). Crown strips are 0.25–0.5 m (sub-pixel beyond ~300 m) in random
      cyan/warm/red; one plain box tower per office block.
    - Do: crowns per district (brief "white/cyan/magenta per district palette"): D7 Lujiazui
      `#DDEEFF`/`#19E6FF`, D5 Jing'an warm `#FFD27A`, D3 magenta `#FF2BD6` accents; strips
      ≥ 0.8 m (art dossier §4.5: 300 m viewing) at E3–E4 on about 1 tower in 3; lit rooftop
      billboard frames (E2) on ~20 % of midrises; red aviation lights `#FF2A3A` E4 on every
      roof > 60 m; vary tower plans (chamfers, notches, stepped crowns, a few cylinders/
      twisted tops); 2–3 towers per office block when the block is > 80 m.
    - Verify: the same two air cams pass `screenshot_stats.py` (P95 ≥ 0.40, SAT 2–15 %).

11. **The road-distance code is wrong — invalid check and a false request to city_layout.**
    - `citydata.road_segments()` reads `a[0], a[1]`, but road points are `[x, y, z]`: every one of
      the 46 843 segments gets z = 0.0 (the road height). Hence the status claims "blocks are
      100–700 m from the nearest road (median 767 m)" and "only 10 of 2 389 buildings within
      25 m" — both false. `water_polygons()` ignores the Suzhou Creek (centerline + width).
      My independent check (catmull-sampled surface roads, correct z, creek included): 0 on a
      road/sidewalk, 0 in water, **1 918 of 2 389 buildings within 25 m of a road edge**; block
      edges are 2.3–61 m (median 4 m) from road edges.
    - Do: use `a[0], a[2]`; sample catmull roads; add the creek; apply the brief's 25 m collider
      rule (`COLLIDER_RANGE`); make `check_blocks.py` fail below 1 m clearance and add a negative
      case (a fake footprint on a road must be reported). **Retract** the two city_layout
      requests in `status/buildings.md` ("100–700 m from the nearest road", "cut the blocks
      against the road corridors").
    - Verify: the build log / status reports ~1 900 colliders kept (25 m rule); check_blocks
      0 violations and the negative case caught.

12. **`tests/test_blocks.gd` cannot fail on its own checks and misses the brief's checks.**
    - `buildings_check()` prints FAIL but returns `void`, so duplicate ids, unknown styles and
      empty footprints still end in "PASS 50 tiles". No budget or placement assertion.
    - Do: return `bool` and AND it into `ok`; per tile assert near tris ≤ 600 000, far
      ≤ 40 000, materials ≤ 40, every non-park building within 25 m of a road has a
      `-convcolonly` collider (read the sidecar), and the instanced tile's world AABB lies
      within its 512 m cell ± 150 m (this would have caught item 1). Keep `extends Node`.
    - Verify: temporarily corrupt one sidecar id in tmp/buildings and show the FAIL line.

13. **Lead note BL-ART1 — glazing is flat cream rectangles (not satisfied).**
    - Shikumen/heritage windows are flat `Emissive_Warm` quads (linear (1.0, 0.66, 0.34) ×
      0.55 ≈ cream `#FFD49F`, all the same tone), shop interiors are flat `Shop_Glow`, the far
      atlas is gradient squares.
    - Do exactly what BL-ART1 says: dark reflective glass for most panes; lit panes show an
      interior with depth (interior-mapping/parallax card or an interior atlas: curtains,
      ceiling lamps, shelves, TVs), a warm `#FFA757` / neutral `#FFC18D` / cool `#DEE8FF` /
      TV-blue mix, emission ≤ 1.0 (never blooms); shikumen windows = wooden frames + panes.
      If you need a glass/interior shader, write the request to shaders with the exact
      uniforms (interior atlas, depth, tint, lit flag via vertex colour) and ship a baked
      interior-card fallback now.
    - Verify: 5 m and 20 m night captures: no two adjacent lit windows identical, nothing blooms.

14. **Lead note BL-ART3 — repetition (not satisfied).**
    - `bl_mid_street.jpg`: one shopfront module repeated along the whole block (same riser,
      same glow, same sign frame); shikumen rows differ only in storey count (same door, same
      windows, same red band); all laundry is the same red `Awning_Fabric`.
    - Do: per house/shop variation from the seed: laundry poles with 3–6 cloths from a cloth
      atlas (8+ colours/patterns), AC units (0–3, two casing types), potted plants, satellite
      dishes, shop signs from different templates, wall lamps, open/half/closed shutters and
      roller doors, weathering streaks; enforce "no two neighbouring modules identical" with
      a check in the builder (hash of the module's choices ≠ neighbour's).
    - Verify: street capture of a shikumen row and a midrise row with no visible repeat.

15. **Lead note BL-ART4 — black void around the buildings (not satisfied).**
    - Inside blocks there is no ground cover: `Paving_Concrete` is 12 triangles in
      `blocks_-2_-1.glb`; the 3 m setbacks, the 4 m gaps between rows and the 弄堂 lanes show
      the bare ground plane (`rb1_game_mid.jpg`, `bl_mid2_side.jpg`).
    - Do: fill every block to its polygon edge (which is ≥ 1 m from the kerb): sidewalk-style
      paving with a kerb-height step, lane paving (granite setts / concrete with drains) in
      弄堂, small plazas, planters, bike racks, bins; textured (≥ 512 px/m) with grime at
      the walls.
    - Verify: aerial capture at 40 m over a block: no unpaved ground visible.

16. **Lead project rule — scratch outside tmp/buildings.** Your log shows scratch files in
    `/tmp` (`dbg.py`, `dbg2.py`, `gltfprops.py`, `uvtest.py`, `probe.gd`; three are still
    there) and `game/tests_tmp_inspect.gd` (outside your owned paths; you deleted it later).
    Use `tmp/buildings/` only and delete it when done; remove your leftovers in `/tmp`.

## SHOULD-FIX
- Per-building variety of `SH_facade_*` is lost in the merged meshes (one seed per tile; midrise
  "tile vs render" choice invisible above 3.4 m). Bake seed + wall tint into vertex colour
  (COLOR_0) and request shaders to read it (keep your INSTANCE_CUSTOM request too).
- Floor ranges differ from the brief: midrise clamps 4–14 (brief 6–12), residential 14–32
  (18–30), office 18–60 (20–60).
- `kit.Bag.tris()` counts faces, not triangles: status says max 181 k per tile, the real max is
  252 472 (`blocks_-1_-1.glb`). Report real triangle counts. In `blocks_-2_-1.glb` 176 k of
  204 k tris are the misplaced clutter of item 2.
- `Bag.emit()` runs `remove_doubles` over a whole merged material group, welding unrelated
  parts that touch (shading seams); weld per part before merging.
- Magic numbers in logic (`0.45`, `3.6`, `0.30`, `5.0`, …) — move per-style parameters into a
  named constants table at the top of each style module; no imports inside functions
  (`residential.py`, `midrise.py`, `office.py`).
- Park trees are lollipops in `render_grey`; use the dossier's bark + `LeafSet027` cards, or
  agree with props/roads to instance their plane trees.
- Orphan `textures/*.png.import` files (no `.png` beside them) — delete.
- 47 far files for 50 near tiles — list in status which tiles have no far LOD and why.
- `check_blocks.py` is brute force (every sample × 46 843 segments): it ran > 5 min without
  finishing here. Bucket the segments in a 40 m grid (my `tmp/review/overlap.py` does the full
  city in 35 s).

## Verified OK
- `tools/godot.sh check --only=res://assets/city/blocks/` → "CHECK 3 files, 0 failed, 0 engine
  errors, 0 warnings"; `tools/godot.sh test res://assets/city/blocks/tests/test_blocks.gd` →
  "PASS 50 tiles, 2389 buildings" (test is `extends Node`, as the lead requires).
- Budgets (real triangles = indices / 3): near max 252 472 (`blocks_-1_-1.glb`) ≤ 600 k; far max
  4 950 (`blocks_-1_1_far.glb`) ≤ 40 k; ≤ 17 materials per tile; 2.6 M tris total; textures are
  shared by relative URI (not embedded, 9.5 MB).
- Footprints (independent check, correct road z, catmull roads, creek included): 0 buildings on
  a road or sidewalk, 0 in water.
- One `-convcolonly` box per building with `building_seed` / `style` / `block_id` extras; Jolt
  printed no collider errors in my game run. Sidecar JSON per tile with occluder boxes.
- Module split is sensible (one generator per style, texgen separate); all Python files
  ≤ 300 lines; GDScript typed; no Write/Edit outside your owned paths in the log.
- Most sign texts are real words / dossier parody brands (except item 8).

## Evidence
Commands (run from ~/m/skyrush; my scratch scripts are in `tmp/review/`):
- `python3 -I tmp/review/glbtris.py "game/assets/city/blocks/blocks_*[0-9].glb" 5 per` →
  `blocks_-1_-1.glb tris=252472 mats=15`; far files: 47, max 4 950.
- `python3 -I tmp/review/overlap.py data/city/city.json game/assets/city/blocks` →
  "buildings 2389 on a road/sidewalk: 0 in water: 0 within 25 m of a road edge: 1918".
- `citydata.road_segments(city.json)` → 46 843 segments, distinct z values `[0.0]`;
  `water_polygons()` → 1 of 2 water entries.
- `python3 -I tmp/review/glbverts.py game/assets/city/blocks/blocks_-2_-1.glb Metal_Galv` →
  "on x=0 line: 46 % on z=0 line: 43 %" (Metal_Dark 41 % / 40 %).
- Game: `tools/godot.sh shot --scene=res://main.tscn --stub=menu --env-only --out=rb1_game
  --outdir=$HOME/m/skyrush/captures/review/buildings --warm=90 --cams="mid:-660,1.7,-224:-560,8,-232:70;
  air:-1150,170,820:-350,0,50:60;origin:300,90,380:250,0,250:60"` → no buildings at Fuzhou Rd,
  black Puxi from the air, every tile stacked at the origin. (Its 22 errors are other units'
  shaders: `soffit_blue`/`glass_tinted` `maxf`, `concrete_stained`, `INSTANCE_CUSTOM`.)
- Preview: `tools/godot.sh shot --scene=res://assets/city/blocks/preview_blocks.tscn --out=rb1_prev
  … --cams="mid:-660,1.7,-224:-560,8,-232:70;close_mid:-655,1.7,-213:-659,3.5,-207:60;
  shik:-960,1.7,1026:-880,6,1030:70;close_shik:-950,1.7,1033:-953,3,1038:60;
  her:-300,1.7,-536:-200,10,-545:70;office:1290,1.7,79:1400,20,79:70;air:-1150,170,820:-350,0,50:60;
  air2:450,220,650:1250,40,-350:60"` → 0 errors; far-LOD checkerboard over every street view.
- Blender (near geometry only, neutral light): `tools/blender.sh run tmp/review/bl/street_render.py
  -- <tile.glb> <out> "<cams>"` → `bl_mid_close/street/upper`, `bl_shik_close/street`,
  `bl_her_close/street`, `bl_mid2_side` (void under the row), `bl_mid2_border` (AC curtains).
- `python3 -I ref/art/lookdev/tools/screenshot_stats.py captures/review/buildings/rb1_prev_air.jpg`
  → 5 FAIL (P5 0.101, P95 0.224, P99 0.263, SAT 0 %, HUES80 0); `rb1_prev_mid.jpg` passes the
  numbers only because the far checkerboard is bright.
- Contact sheets in `captures/review/buildings/`: `worker_sheet.jpg` (your 8 captures),
  `sheet_game.jpg`, `sheet_prev1.jpg`, `sheet_prev2.jpg`, `sheet_blender.jpg`, `sheet_bugs.jpg`,
  `atlases.jpg`, `textures.jpg`, `ref_compare.jpg` (refs `shikumen_xintiandi_2012.jpg`,
  `nanjing_road_night_2009.jpg` vs our captures).

Acceptance (brief):
- Street level looks like Shanghai at night, not grey boxes — **FAIL** (items 1, 3, 5, 9, 13–15).
- Shopfront depth, signs, AC units, varied lit windows, no repetition — **FAIL** (2, 5, 8, 13, 14).
- Aerial: dense varied skyline with lit crowns — **FAIL** (6, 10).
- Budgets met — PASS. Colliders near roads — PASS (one per building; 25 m rule pending, 11).
- No footprint on roads/sidewalks/water — PASS (but the unit's own check is invalid, 11).

ART §10 checklist (on my captures): 1 value structure — fail from the air; 2 palette/neon —
far LOD floods warm/white, neon blades absent; 3 texture at 5/20/100 m — fail (flat quads,
blurred signs at 5 m, checkerboard at 20–100 m); 4 tiling — brick/tile uniform, visible;
5 scale — floors and lane widths OK, sliver houses; 6 emissives — far windows bloom; 7 Shanghai
recognisable — no; 8 edges/bevels — none (raw boxes); 9 floating/z-fighting/missing faces —
fail (items 2, 4, 5, 9); 10 store screenshot — no.
