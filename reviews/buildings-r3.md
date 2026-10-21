# buildings review round 3 — VERDICT: FAIL

Reviewer: lead art director (Opus). User demand: 「贴图纹理什么都要细化」 — every texture refined.
The pipeline work is real (gltf + shared `_tex`, write-if-changed, colliders 1653/1653, checker and
test green, far-atlas bands, lit shop fronts with legible signs). But two silent geometry bugs undo
most of the art: **every face normal in the unit is (0,0,0) when it is read**, so (a) all extruded
masses are INSIDE OUT (the facade shader culls the street side of every building) and (b) **84 % of
the textured area has collapsed UVs** (the paving, brick, roof, tile, granite you generated are drawn
as streaks). Plus **164 of 556 building blocks are empty** (18 % of the area, incl. Nanjing E Rd).
None of this is in your status. Lead notes BL-ART2, BL-ART3, B-NIGHT1, TILE-TEX budget are open.

## Scores (0-10): function 4, visual 3, code 5

## MUST-FIX

1. **Face normals are never computed → inside-out buildings AND smeared textures (one root cause).**
   - Blender 5.2 check (`tmp/review/b3_bm.py`): a face made by `bm.faces.new()` has normal
     (0, 0, 0) until `normal_update()`; the unit never calls it (`grep normal_update` → nothing).
   - (a) `shapes.ensure_normal` (`shapes.py:22-27`) reads that zero normal, so it never flips; the
     prism sides keep their creation winding, which comes out inward for the lots (measured below).
     The intended test is inverted as well: `shapes.py:57`
     `if (cx-mx)*nx + (cz-mz)*nz < 0.0: flip` makes n point TO the centroid. Measured:
     `python3 -I tmp/review/b3_inout.py game/assets/city/blocks SH_facade_residential,SH_facade_office`
     → **INWARD 74 % of the facade area, outward 0 % (8 tris)**, the rest party walls; far boxes
     (`b3_inout_far.py … Window_Far_Office,Window_Far_Resi`) → **INWARD 63 %, outward 0 %**.
     In-engine (`tmp/review/gd/b3_wind.gd`): the street wall of `b_d3b_061_49` (z = 1487, building at
     z < 1487) has its front faces toward −z. `facade_windows.gdshader` is `cull_back` and the far
     material is single-sided, so from the street you see the inner faces of the BACK walls, the roof
     underside as a dark ceiling and the AC units floating in air: `captures/review/buildings/
     pc3_mid20.jpg`, `p3_crops.jpg` (bottom right), `pb3_air_pudong.jpg` (hollow towers),
     `p3_ref_compare.jpg` (dark plane over the neon street).
   - (b) `kit._face_uv` (`kit.py:96-112`) picks the projection axis from `face.normal`; with (0,0,0)
     it always takes axis 0 → U = Blender y on y-facing walls (constant) and V = height on horizontal
     faces (constant). `python3 -I tmp/review/b3_zerouv.py game/assets/city/blocks` → **84 % of
     21.8 km² textured area has zero-area UVs**: Paving 100 %, Grass 99 %, Awning 95 %, Tile_White
     87 %, Stone_Granite 82 %, Metal_Corrugated 78 %, Render 76 %, Stone_Pale 74 %, Roof_Tile 61 %,
     Wood_Lacquer 57 %, Brick_Red 54 %, Brick_Grey 50 %. Example: paving quad (−67,−50)…(−70.5,−48)
     in `blocks_-2_1.gltf` has UVs (910, 0.94), (912, 0.94), (912, 0.94), (910, 0.94). This is the
     "plank" ground and the "siding" walls in `pb3_shik_lane.jpg`, `pe3_door3.jpg`, `pc3_shik7.jpg`.
   - Do: call `bm.normal_update()` before every read of `face.normal` (in `ensure_normal`, in
     `Bag._split` before `_face_uv`, in `openings.py` and `far.py`); derive the outward direction of
     prism sides from the polygon's signed area (works for concave/L footprints), not the centroid;
     keep `doubleSided` only for cards (cloth, leaves, signs, glass) — opaque solids single-sided.
     Add a build assertion: every side face of a mass has `centre + 0.3 m · normal` outside its
     footprint, and every tiling-material face has UV area > 0. Port my two probes into
     `test_blocks.gd` (front-face normal of each `SH_facade_*` / `Window_Far_*` triangle points away
     from its building; zero-UV area < 1 % per tiling material).
   - Verify: `b3_inout.py` and `b3_inout_far.py` → outward ≥ 95 %, INWARD 0 %; `b3_zerouv.py` → every
     tiling material ≤ 1 %; recapture `--cams="mid20:-1243.8,1.7,1507.0:-1243.8,7,1487.0:70"` in
     `preview_blocks.tscn`: a solid facade, AC units on the wall, no dark ceiling.

2. **164 of 556 building blocks have NO building (18 % of the block area); Nanjing E Rd is empty.**
   - `python3 -I tmp/review/b3_empty.py data/city/city.json game/assets/city/blocks` → office_tower 40,
     midrise 61, heritage 20, neon_street 4 of 9, residential_slab 36, industrial 3; empty area share:
     residential 60 %, heritage 49 %, office 25 %, midrise 11 %. Largest: `b_d7_003` office 106 800 m²
     (Pudong east), `b_d3_001` midrise 101 200 m², `b_d5_001` 76 500 m², `b_d7b_009` 61 800 m²,
     `b_d5_008` 47 300 m², `b_d7_053`, `b_d7_002`, `b_d0_025`, `b_d0_010`. Small ones too: `b_d2_009`
     (neon, 40 × 30 m, on Nanjing E Rd), `b_d2_005`, `b_d2_003`, `b_d0_013` → nothing but paving and two
     benches. The r2 cam `nanjing:-330,1.7,-538:-200,9,-540:70` (`pb3_nanjing.jpg`) shows an empty dark
     street: r2 MUST-FIX 12 is still open (within 60 m of `st_nanjing_e_rd`: 7 plazas + 1 heritage).
   - Cause (likely): the map blocks are 10 m raster outlines (staircases, 8–114 vertices, fill
     0.29–0.70); `plan.Frame` takes the longest edge as the frontage and `plan.fits` needs a whole
     rectangle inside the polygon and off the corridors → nothing fits, and the planner gives up silently.
   - Do: split every polygon into axis-aligned rectangles (merge the 10 m raster cells into maximal
     rectangles) and plan each rectangle with a frontage on every edge that faces a road; fall back to
     smaller lots (frontage ≥ 6 m, depth ≥ 8 m) before giving up; lots > 20 000 m² get an internal
     service lane/plaza and several buildings. Print "blocks without building: N" per style and make
     `check_blocks.py` AND `test_blocks.gd` fail when a non-park block has no building or its built
     coverage (footprint / block area) is < 30 %.
   - Verify: `b3_empty.py` → "EMPTY blocks (no building): 0", empty area share ≤ 2 %; the nanjing cam
     shows ≥ 12 blades on both sides (hstack with `nanjing_road_night_2009.jpg`).

3. **The textures themselves are still not refined (the user's demand) — measured on the files.**
   - `brick_grey_diff.jpg`: luminance std **0.017** (p5–p95 0.361–0.420) → at 1:1 no brick or mortar is
     visible (`p3_tex.jpg` top left); `roof_tile_diff` std 0.026, no tile courses at 1:1 (`p3_tex.jpg`
     row 2 right, `pe3_roof.jpg`); `render_grey` 1024² over 4 m = **256 px/m** on midrise ground
     floors (blurry cloud); `tile_white` flat beige squares, uniform grout, and its albedo is linear
     0.257 (not white) after `NIGHT_VALUE` 0.44; `stone_granite` a regular grid of identical blocks
     (`pc3_her7.jpg` reads as bathroom tile). `Prop_Sheet` is 1024² (256 px cells): measured texel
     density median **386 px/m** (ART §5: props ≥ 512), a 3 m roller shutter gets ~85 px/m, and the
     material has **no normal and no ORM map** (gltf: no normalTexture/metallicRoughnessTexture); the
     cells are flat clip-art and one cell is empty black. `shop_interiors` / `interiors` are flat
     vector clip-art with the **same orange ring lamp in almost every cell** (`p3_tex.jpg` row 2,
     `p3_crops.jpg` top left) and are stretched: Shop_Interior median **174 px/m** (status claims 256).
     `Plaque_Atlas` and `Cloth_Atlas` have no normal map.
   - Do (albedo + normal + ORM each; the numbers are acceptance values):
     a. 青砖 brick: brick `#59626B` ±10 % per brick, lime mortar `#A8A398` recessed 4 mm (normal),
        10 mm joints, Flemish bond 240 × 53 mm, chipped arrises, soot under sills; albedo std ≥ 0.06.
        Same for `brick_red` (bricks `#8A3B2E`).
     b. 小青瓦 roof: pan + cover tile rows at 0.18–0.20 m pitch visible in albedo (std ≥ 0.06) and
        normal, ridge tiles, moss/soot; ≥ 512 px/m.
     c. render: ≥ 512 px/m (1024² over 2 m), trowel marks, hairline cracks, rain streaks from
        `Leaking004/016A`, dirt band 0–0.6 m.
     d. white tile: per-tile tint ±4 %, glaze roughness 0.15–0.35 in ORM.G, darker dirty grout, streaks
        under every sill; keep the albedo light (linear ≈ 0.5) — make night with light, not albedo.
     e. granite: per-block tone ±8 %, chamfered rustication joints in the normal, darker base 0–1 m.
     f. props: atlas 2048² (512 px cells → ≥ 512 px/m), + normal + ORM, wear/rust drips/dirt; roller
        shutters as their own tileable (75 mm ribs in the normal, 1024 px/m, stickers as decals).
     g. interiors: shaded rooms (lamp falloff, AO in corners, floor/wall materials, products with
        highlights), ≥ 6 lamp types, no lamp/ceiling repeated between cells; one cell per ≤ 2.5 m of
        window (split wider shop windows into 2–3 cells) so shops reach ≥ 256 px/m.
   - Verify: status table texture → px, m per repeat, px/m, albedo std; a 1:1 crop sheet (brick,
     roof, render, tile, granite, prop cell, shop cell); 5 m captures of a shikumen wall, a shop
     front and an AC unit, AFTER MUST-FIX 1.

4. **BL-ART2 (lead, mandatory) — knockers, pediments, lane gates, roofs.**
   - `shikumen.py:75-77` the knockers are 0.14 × 0.14 m flat brass squares (`pe3_door3.jpg`: two tiny
     squares), not rings; `shikumen.py:87-90` the "pediment" is 3 stacked slabs (1.10/0.80/0.50 m ×
     0.16/0.14/0.12 m), no carved relief; `shikumen.py:243-262` the lane gate is two brick piers + a
     `brick_red` beam + a flat plaque quad without a normal map (`pe3_plaque.jpg`); the roof shows no
     tile courses (item 3b). Compare `ref/shanghai/img/09_street_details/shikumen_xintiandi_2012.jpg`
     (`p3_shik_ref.jpg`): arched/triangular carved pediments, stone gate frames, visible brick courses.
   - Do: ring knocker = torus Ø 0.12 m, section 12 mm, 16 × 6 segments, hanging from a Ø 0.10 m
     backplate at 1.10 m on each leaf; pediment = triangular or segmental-arch stone pediment 0.9–1.2 m
     tall over the lintel with a relief panel from a carved-stone atlas (scrolls/flowers, 3+ variants,
     normal map readable at 5 m); lane gate = granite gate frame with a carved lintel and the 「xx里」
     plaque carved in (plaque normal), a 过街楼 bay over 30 % of lane mouths; door leaves black
     lacquer `#1E1A17` with plank seams in the normal.
   - Verify: 3 m capture of a door (both rings, the pediment relief catching a lamp) and 10 m capture
     of a lane gate, hstacked with `shikumen_xintiandi_2012.jpg`.

5. **BL-ART3 (lead, mandatory) — the lanes are bare, the commercial templates repeat.**
   - `blocks_-2_1` (310 shikumen houses): `Prop_Sheet` **0 tris** → no AC units, wall lamps, plants,
     dishes; `pb3_shik_lane.jpg` is a bare corridor, the right-hand wall has no back doors or
     windows at all. Every fascia uses one template (white square-in-circle logo + name: 沪上书屋,
     恒丰烟酒, 光明眼镜, 四季水果 … `pc3_mid7.jpg`, `pc3_mid7b.jpg`); the same LED ad 飞驰申城/申城夜赛
     appears in `pc3_neon20.jpg` and `pc3_off20.jpg`; the planters along the shops are black boxes.
   - Do: per shikumen house 0–2 AC units under back/side windows, a warm wall lamp beside every door
     (E 0.8 + a light-pool decal), 1–3 potted plants on the step, a dish on 20 %, drain pipes, back
     doors and kitchen windows on the lane side of the back row, laundry across the lane on 30 % of
     house pairs, streaks under every sill. Shops: ≥ 5 fascia templates (lightbox + logo, red board
     with gold characters, 3D channel letters on a rail, LED-strip text, painted board), ≥ 8 LED ads;
     run the `NeighbourGuard` on the template too. Planters with plants and a textured concrete box.
   - Verify: `shik_lane:-206.75,1.6,806:-206.75,3.2,770:70` shows lamps, AC units, plants and laundry
     on both walls; mid7/neon20 cams: no two neighbouring fascias share a template.

6. **ART-NIGHT (lead, mandatory): B-NIGHT1 near LOD still a polka dot; the aerial is as dark as r2.**
   - `pb3_air_pudong.jpg`, `pc3_off20.jpg`: per-window dots, no floor bands (the near shader is the
     shaders unit's; your request is only in your status). The far LOD has bands (`check_night.py`
     PASS: offices 24.1 % in 2-floor bands, flats 18.6 %) but is barely visible at 1 km
     (`pb3_air2.jpg`). `screenshot_stats.py`: air P95 0.225, P99 0.264, SAT 0.000, HUES80 0 and air2
     the same — **identical to r2** (target P95 ≥ 0.40, SAT 2–15 %).
   - Do: (a) send the band/cool-white shader change and `SH_beacon.tres` to the lead as a cross-unit
     request (not only in status) and ship per-building parameters in the glTF extras now
     (`lit_ratio`, `band_ratio`, `cool_mix` next to `building_seed`) so the world can set instance
     uniforms; (b) far LOD: it is only drawn beyond 350 m where the depth fog removes ≥ 34 % → raise the
     lit-cell emission to 1.6 (fog-compensated: 1.6 × 0.87 × 0.66 ≈ 0.92 at 350 m, under the 1.1 glow threshold); (c) re-check the LED
     crowns after MUST-FIX 1 — today they read as hollow wireframe boxes.
   - Verify: preview_blocks.tscn cams `air:-1150,170,820:-350,0,50:60`,
     `air2:450,220,650:1250,40,-350:60`, `air_pudong:650,120,-150:1150,30,-520:60` → P95 ≥ 0.35 without
     street lamps (≥ 0.40 in game with lamps), lit floor bands visible at 120 m.

7. **TILE-TEX / IMPORT-PERF size budgets (lead, mandatory) are not met.**
   - `tile_stats.py` → blocks **371.7 MB** (roads 180 MB more; the lead's target is ≤ 250 MB for ALL
     city tiles); 5 tiles > 15 MB: `blocks_-2_1` 18.5, `-2_-1` 18.4, `-2_2` 17.6, `-3_-1` 16.2,
     `-2_3` 15.9 MB.
   - Measured cuts on `blocks_-2_1`: **10.8 %** of the triangles are ground-level bottom faces that are
     never visible (32 690 of 302 648; `add_prism` caps every prism); city-wide 26 % of the facade
     area has a building on both sides (party walls); Wood_Lacquer (casements + doors) is 27 % of the tris.
   - Do: `add_prism(..., cap_bottom=False)` for every mass standing on the ground or on another mass;
     drop faces that touch another building; the casement as one alpha-tested quad with a frame/muntin
     cell; repeated modules (windows, doors, AC units) as one mesh + transforms in the sidecar for a
     MultiMesh (write the world request). Your share: blocks ≤ 170 MB, every tile ≤ 15 MB.
   - Verify: `tile_stats.py` → "5 tiles over" becomes 0; total ≤ 170 MB.

8. **Street frontage — the r2 request to city_layout was never filed (r2 MUST-FIX 10).**
   - `tmp/review/b3_setback.py`: street-facing buildings stand **median 12–17 m** behind the sidewalk
     edge (midrise 16.0, shikumen 16.8, neon_street 12.0, office 13.2 m); the block polygons start
     9.3–9.8 m behind it (`b3_blockgap.py`; city_layout cuts lots from a 10 m raster). On Shanghai
     shopping streets the shop fronts are at the back of the sidewalk; `pc3_mid20.jpg` has a 20 m dark
     band of paving and black boxes between the road and the shops.
   - Do: write the request in status AND to the lead: commercial blocks start 0–1 m from the sidewalk
     back edge; until then put real street life in the strip (kiosks, bike rows, planters with plants,
     a newspaper stand) instead of empty paving.
   - Verify: request visible in `status/buildings.md` Requests and in the lead's notes.

9. **Honest status.** "build_city.py is 301 lines" → 354; "the style modules use named constants
   instead of magic numbers" → `shikumen.py` still has 106 float literals in logic (`_door`: 0.34,
   `DOOR_H + 0.42`, `+ 0.78`, (1.10, 0.16)…, knocker 0.12/0.07); "every MUST-FIX of r2 is addressed" →
   r2 #10 (request), #12 (Nanjing), #3 (occlusion export) are not; "17 neon_street blocks" → 9 in the
   map, 4 of them empty; the empty blocks and the inside-out walls are not reported. Report only what a
   command printed; list open items as open.

## Cross-unit blockers (for the lead — not counted against this unit)
Do NOT edit these files (world/shaders own them); only write the requests in your status.
- **world**: `game/world/loader/asset_library.gd:107-108` `_is_imported` checks
  `FileAccess.file_exists(line.substr(5).strip_edges())` on `path="res://…"` — the quotes stay, so
  every tile is reported "not imported yet": `tmp/review/b3_shot.log` → 118 block and 194 road tiles
  skipped; `main.tscn` shows only the fallback prisms (`rb3_*.jpg`). All my captures therefore use
  `preview_blocks.tscn`. Strip the quotes (`.trim_prefix("\"").trim_suffix("\"")`).
- **shaders**: clustered lit floors + cool-white office mix in `facade_windows.gdshader`;
  `SH_beacon.tres` (1 Hz) does not exist; unlit windows of `SH_facade_residential` still near #000.

## SHOULD-FIX
- `doubleSided: true` on 23 of 25 tile materials (fill rate, mirrored normal maps on back faces) —
  after MUST-FIX 1 keep it only for cards.
- `NIGHT_VALUE` in `gen_textures.py:56-60` bakes night into the albedo (paving linear 0.088, white
  tile 0.257): keep physical albedos; night is the environment's exposure and lights.
- AO is baked into the albedo and `occlusionTexture` is still not exported (r2 #3 asked for it).
- Ground cover over at-grade ramps (`tmp/review/b3_ramps.py`): `plaza_poi_toll_west_6` ×
  `yanan_elevated`, `plaza_poi_charge_bund_174` × `ramp_xizang_off` → clip against ramp corridors
  where the deck is < 3 m (z-fight with the ramp surface).
- `tmp/buildings/` holds 71 MB of scratch (3 build logs, a 3 MB city snapshot, demo jpgs) — delete
  when done (project rule).
- `test_blocks.gd` loops are untyped (`for rec in data.get("buildings", [])`) — `for rec: Dictionary in`.
- Occluders are still the AABB of rotated footprints (r2 SHOULD-FIX).

## Verified OK
- `tools/godot.sh check --only=res://assets/city/blocks/` → CHECK 3 files, 0 failed, 0 engine errors.
- `tools/godot.sh test res://assets/city/blocks/tests/test_blocks.gd` → PASS 59 tiles, 2222 buildings,
  1653 near-road, 1653 colliders (extends Node; ANDed checks).
- `check_blocks.py --city data/city/city.json` → 0 violations, 0 stale tiles (sidecar sha256
  533727ecb46c0466… = the map on disk); `--self-test` PASS 157 426 corridor points.
- Independent: `b2_overlap.py` → 0 footprints on a road/sidewalk corridor, 0 closer than 1 m, 0 in
  water; `b2_decks.py` → 0 buildings piercing a deck.
- Budgets: near max 302 648 tris (`blocks_-2_1`) ≤ 600 k; far max 24 392 ≤ 40 k; max 29 materials ≤ 40.
- Import pipeline: `.gltf + .bin`, one shared `_tex` (70 files, 28 MB), no `.glb` tiles left, all 118
  `.import` carry `generate_lods=false` + `create_shadow_meshes=false`, write-if-changed + mtime
  restore (`gen_textures.py:107-123`, `tile_io.py:74-96`).
- Real openings: heritage windows in a reveal with frames (`pc3_her7.jpg`), shikumen doors recessed in
  stone frames (`pe3_door3.jpg`); the pane ray-cast assertion exists.
- Signs: real Chinese parody names, complete, legible; dense blades on the neon blocks
  (`pc3_neon20.jpg`), a lit shop front + fascia on every midrise unit (B-NIGHT3 met where buildings
  exist). Far-atlas bands and `SH_beacon` on roofs > 100 m present.
- `tools/blender.sh preview game/assets/city/blocks/blocks_-2_1.gltf rb3_prev_m21`: only
  `SH_facade_office` UNTEXTURED (runtime replaced); sheets in `captures/review/buildings/blender/`.
- Ownership: every Write/Edit of the worker is inside owned paths; nothing left in `game/` outside them.

## Lead notes status
IMPORT-CHURN done; TILE-TEX format done, budget open (#7); IMPORT-PERF options done, 15 MB open (#7);
BL-ART1 partly (interiors exist but flat clip-art #3g; near windows polka dot #6); BL-ART2 open (#4);
BL-ART3 open (#5); BL-ART4 ground cover present, frontage request open (#8); ART-NIGHT B-NIGHT1 open
(#6), B-NIGHT2 partly (crowns hollow until #1; beacons steady, shaders), B-NIGHT3 met where buildings
exist; atomic swap done. Project rules: tests extends Node OK, runs end by themselves OK, scratch NOT
cleaned (`tmp/buildings`, 71 MB).

## Acceptance (brief)
Street level looks like Shanghai at night — FAIL (#1 inside-out + streaked textures, #3, #5, #8);
shopfront depth / signs / AC units / varied lit windows / no repetition — partly (signs and lit shops
good; templates repeat, lanes bare); aerial dense varied skyline with lit crowns — FAIL (#1, #2, #6);
budgets — tris/materials PASS, MB FAIL (#7); colliders near roads — PASS; no footprint on
roads/sidewalks/water — PASS.

ART §10: 1 value — street frames dark, aerial P95 0.225; 2 palette — neon far below the reference's
saturation (`p3_ref_compare.jpg`); 3 texture 5/20/100 m — FAIL at 5 m (streaks, std 0.017 brick, flat
clip-art) and 20 m (siding walls, plank ground), 100 m polka dot; 4 tiling — collapsed UVs instead;
5 scale — floors/doors OK, frontage 12–17 m back; 6 emissives — no blow-outs, too weak at distance;
7 Shanghai — signs yes, shikumen/heritage only in outline; 8 edges — raw boxes; 9 floating —
FAIL (inside-out walls, floating AC units); 10 store shot — no; 11 lit density at 120 m — FAIL.

## Evidence
All from `~/m/skyrush`; captures in `captures/review/buildings/`; scripts in `tmp/review/b3_*.py`
(run with `python3 -I`), Godot probe `tmp/review/gd/b3_wind.gd`.
- `tools/godot.sh check …` / `test …` / `check_blocks.py` / `--self-test` / `check_night.py` /
  `tile_stats.py`: outputs quoted in Verified OK, #6, #7.
- `b3_inout.py … SH_facade_residential,SH_facade_office` → INWARD 6 986 tris 74 %, party/ambiguous
  2 766 tris 26 %, outward 8 tris 0 %; `b3_inout_far.py … Window_Far_*` → INWARD 63 %, outward 0 %.
- `godot --headless --path game -s tmp/review/gd/b3_wind.gd` → `{ "front_faces_toward_+z": 0,
  "front_faces_toward_-z": 2 }` for the street wall z = 1487 of `b_d3b_061_49`.
- `tools/blender.sh run tmp/review/b3_bm.py` → new-face normal (0, 0, 0), after normal_update (0, 0, 1).
- `b3_zerouv.py` → total textured area 21.82 km², zero-UV 84 % (per material in #1).
- `b3_empty.py` → 164 empty blocks, 18 % of 5.71 km²; `b3_setback.py`, `b3_blockgap.py` (#8);
  `b3_texel.py` → Shop_Interior median 174 px/m, Prop_Sheet 386 px/m; texture std via PIL (#3).
- `b3_ramps.py` → 2 plazas over at-grade ramps; `b2_overlap.py`, `b2_decks.py` → 0.
- `screenshot_stats.py pb3_air.jpg pb3_air2.jpg pb3_air_pudong.jpg` → P95 0.225, SAT 0.000, 4 FAIL each;
  `pb3_shik_lane.jpg` 5 FAIL (P95 0.162).
- Game run `tools/godot.sh shot --scene=res://main.tscn --skip-menu --env-only` → `rb3_*.jpg` show the
  world's fallback prisms (tiles skipped, see blockers); the review captures are
  `tools/godot.sh shot --scene=res://assets/city/blocks/preview_blocks.tscn --env-only --warm=90`:
  `pb3_*` (shik_lane, shik_gate, her_s20, nanjing, neon_c5, resi_s20, office_s20, air_pudong, air_puxi,
  air, air2), `pc3_*` (mid7, mid7b, neon7, her7, mid20, neon20, off20, resi20, ind20, shik7, shik20,
  mid100), `pd3_*` (mid20 top/side), `pe3_*` (door3, plaque, roof). Sheets: `p3_close.jpg`,
  `p3_s20.jpg`, `p3_misc.jpg`, `p3_crops.jpg`, `p3_tex.jpg`, `p3_shik_ref.jpg`, `p3_ref_compare.jpg`,
  `p3_sheet_air.jpg`, `r3_worker_sheet.jpg` (your captures).
- Preview fps 113–154 at street level (no roads/props); the in-game frame budget could not be
  measured because the world loader skips the tiles.

## Order of work
#1 first (it changes every capture and every other measurement), then #2, rebuild, then #3–#5 on the
rebuilt city, #6–#7, and re-run every Verify line above with the numbers in status.
