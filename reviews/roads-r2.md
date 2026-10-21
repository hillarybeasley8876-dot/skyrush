# roads review round 2 — VERDICT: FAIL

## Scores (0-10): function 3, visual 2, code 4

Summary: the structure got much better. Piers now stand on the ground, the soffit is blue only on the wings, the lane
graph links cleanly, and in main.tscn the wet asphalt reflects well. But in the game every Road_* material is flat
white: the textures are stripped, the UVs are dropped, and nothing binds the .tres files. So the planter pots are
white boxes, the foliage cards float as white quads, ivy is a white sleeve on the piers, and the tunnel and bridge
steel are untextured. The planter row is 2 pots, then a 4.8 m gap, repeated. The spawn junction has kerb arcs lying
on the carriageway and no zebra crossings. The tunnel ceiling is 3.1 m above the lanes. 131 garbage tiles are still
loaded by the world. The drive test still fails, and its tolerances were loosened. Lead notes R2, R-INT1 and TILE-TEX
are not met, and R3 and IMPORT-CHURN are only partly met. This does not yet meet "贴图纹理什么都要细化".

## MUST-FIX

1. **Every Road_* material renders flat white in Godot (lead TILE-TEX + R2, and the user's 细化 demand).**
   Evidence:
   - The glTF dump of `roads_-3_1.glb` has `images 0`. Every Road_* material has baseColorFactor [1,1,1,1], no
     roughnessFactor (so roughness is 1.0), and no texture.
   - Only the foliage and SH_soffit_blue primitives have TEXCOORD_0. Planter_White (522,848 tris in total),
     Tactile_Strip, Expansion_Joint, Ivy, Planter_Soil, Steel_Girder and Tunnel_* have no UVs, so even a bound
     texture would sample one texel.
   - None of the 194 `roads_*.glb.import` files contains `use_external`, so `tools/patch_imports.py` is not
     in effect.
   - `tools/blender.sh preview roads_-1_3.glb` reports every Road_* material as `UNTEXTURED`.
   - Captures:
     - `review_roads_r2b_pots_close.jpg`: white boxes, and white cards floating above them.
     - `review_roads_r2_pier_close.jpg` and `r2b_soffit_up.jpg`: pure-white sleeves on the pier bases. This is
       Road_Ivy.
     - `r2b_tunnel_wall.jpg`: a flat grey wall with no panels, joints or stripe.
     - `r2b_nanpu_side.jpg`: a flat girder.
   - Pure white also breaks ART §8 and competes with the white Roadster for the brightest value.
   **Do:**
   - Follow lead TILE-TEX. Keep the images in the Blender materials and export every tile with
     `export.export_glb(path, objs, shared_texture_dir="../_tex")`. This writes `.gltf` + `.bin`, one shared image
     copy goes to `game/assets/city/_tex/`, and TEXCOORD_0 and TANGENT are kept. The world loader already prefers
     `.gltf`.
   - Then delete the `.glb` tiles and their `.import` files, plus `patch_imports.py` and `materials/*.tres` if they
     become unused.
   - Every Road_* material gets a diffuse + nor_gl + rough map (+ ao). Use 1024² for big or hero surfaces and 512²
     for small parts (lead IMPORT-CHURN 2), all at ≥ 512 px/m in their UV scale:
     - Tunnel enamel #ECEFF0: 1.2 × 0.6 m panel joints in the normal map, and a #2C6BD8 stripe 0.3 m wide at
       Y 1.2 m.
     - Tunnel upper zone #3A3D42: its own concrete set (not the tinted enamel).
     - Steel #9AA4AE: bolt rows, chipped paint, rust streaks.
     - Expansion joint: finger teeth and a rubber strip.
     - Pots #EDEDE8: soil stains on the outer face.
     - Tactile strip: TactilePaving003 diff + nor + rough, tinted #E8C34A.
     - Ivy and foliage: alpha-mask atlases.
   - Put the real colour in the glTF factors too. No white defaults.
   **Verify:**
   - A glTF dump shows TEXCOORD_0 + TANGENT on every Road_* primitive, plus baseColor, normal and metallicRoughness
     textures.
   - `blender.sh preview` lists no UNTEXTURED Road_* material.
   - Captures at 3 m, 20 m and 100 m of pots, a pier with ivy, the tunnel wall and the bridge girder, in the preview
     AND in main.tscn.

2. **The planter row is not the "10+5" pot row.**
   Evidence (inner_ring near (−398, 11.0, 1690.9), `tmp/review/pots.py`):
   - Pots exist only at x ≈ −408/−407, −402/−401, −396/−395 and −390/−389: 2 pots, then a 4.8 m gap.
   - Foliage cards span y 11.44–11.86, but the pot tops are at 11.25, so the plants float 0.19 m above the pots.
   - About 31 tris per pot (r1 limit: ≤ 12).
   - `Road_Planter_Row` (the far strip) is generated but never built.
   - The 522,848 pot tris and 261,424 card tris draw at every distance.
   - Compare `ref/.../01_dragon_pillar_interchange/interchange_ground_2025.jpg`: a continuous white row with plants
     spilling over (side by side in `captures/review/roads/r2_refcompare.jpg`, row 1).
   **Do:**
   - A continuous row on BOTH parapets of every planter-styled deck: pitch 0.62 m (0.60 m pot + 2 cm gap), never
     thinned.
   - Rhythm: 10 bougainvillea pots (#C2185B bracts on #3E7D32 leaves), then 5 privet pots (#B5C534).
   - Cards rooted at soil level (pot top − 0.03 m), 0.45–0.6 m tall, overhanging the outer face by 0.15–0.25 m,
     jittered ±10 % in scale and ±15° in yaw.
   - Pots ≤ 12 tris: no bottom face; put the bevel in the normal map.
   - LOD:
     - Pots + cards in 64 m chunk nodes, with `extras.vis_end = 90`.
     - The strip as its own node, with `extras.vis_begin = 80`.
     - File a world request: today `asset_library.prepare_instance()` overwrites every visibility range with 0/0
       for roads, so it must honour these extras.
   **Verify:**
   - 161 ± 1 pots per 100 m of straight parapet.
   - Captures at 3 m and 20 m of an inner-ring parapet: white pots with magenta and green plants, nothing floating.
     Compare with interchange_ground_2025.jpg.

3. **Decks fly without piers (r1 item 1: shift, then portal; never drop).**
   - `status/roads.md` says "otherwise the pier is dropped". There are 14 internal gaps of more than 2 × the 30 m
     pier spacing (gaps measured from road_furniture.json piers projected on city.json paths):

     | road | gap | around |
     |---|---|---|
     | nanpu_pudong_loop | 308 m | (1793, 15, 1541) |
     | ns_elevated | 270 m (+ 4 more gaps > 60 m) | (−1412, 12, 60) |
     | ramp_l4_sb_eb | 252 m | (−1044, 16, 567) |
     | ramp_l4_nb_wb | 150 m | (−1652, 11, 699) |
     | yanan_elevated | 78 m | (−645, 10, 219) |

   - See `review_roads_r2_ns_gap.jpg`.
   **Do:**
   - Try in this order:
     1. Shift ±6 m along the road or sideways.
     2. A portal frame over the lower road: span = its asphalt width + 2 × 1.5 m, beam top = girder underside.
     3. For stacked decks, a tall pier in the lower deck's median or outside it, with a cantilever cap (dossier
        §1.2).
   - Maximum gap 45 m everywhere except the cable-stayed main span.
   - Ivy: patchy alpha leaf cards from 0 to 7.6 m with an organic top edge on 50 % of the piers, not a box sleeve.
   **Verify:** a script prints the maximum pier gap per road, all ≤ 45 m. Under-deck captures at
   (−1390, 1.7, 215)→(−1411, 9, 60) and under ramp_l4_sb_eb.

4. **Junctions are a mess (lead R-INT1 not met).**
   - My check `tmp/review/kerb_on_lane.py` (horizontal faces only) finds **5,503 ground lane samples** (2,460 lane +
     3,043 connector) sitting on a kerb, sidewalk or tactile top surface at road level (−0.05…+0.45 m). They are in
     **244 junctions**. Worst:

     | junction | at | samples |
     |---|---|---|
     | j_bund_zhongshan_e1_st_d0_ns_st_link_42 | (−133, −364) | 190 |
     | …_st_d0_ew_2_st_d0_ns_2_st_link_40 | (−137, −780) | 167 |
     | j_pudong_south_rd_st_d8_ew_st_d8_ns | (1621, 255) | 131 |
     | j_st_fujian_portal_…_yanan_rd_surface | (−459, 184) | 116 |

   - The spawn junction (`captures/review/roads/r2_junction_crop.jpg`):
     - About 10 grey kerb-return arcs lie on the carriageway, built by three overlapping junction records:
       (0.5, 0.5), (15.6, 3.4) and (37.6, −3.3).
     - The median islands run into the junction box.
     - No zebra crossing or stop line is visible.
   - Zebra bars are only 1.5 m long (`junctions.py:387`, `t * 1.5`). GB 5768 requires ≥ 3 m.
   **Do:**
   - Merge junction records closer than (sum of half-widths + 10 m) into one junction box before building.
   - Kerb returns (R 8–12 m, raised 0.15 m with a kerb face) only between adjacent arms' kerb lines.
   - Clip every kerb, sidewalk and island polygon against the union of the carriageway and junction polygons.
   - Median noses end 1 m before the crosswalk.
   - Zebra: 0.45 m bars with 0.60 m gaps, 5 m long on main roads and 4 m on minor roads.
   - Stop line 0.30 m wide, 1.5 m before the zebra.
   **Verify:**
   - kerb_on_lane.py reports 0.
   - Eye-level (1.1 m) and 28 m aerial captures of the spawn junction and of (−133, −364) in main.tscn: zebras on
     every arm and kerb returns only at the corners.

5. **The lane graph still dead-ends at junctions, and the test was loosened instead (r1 item 3).**
   - 772 lanes have `next == []`. 718 of them are flagged `terminus_kind: "junction"`, and 490 of those end within
     40 m of another road's lane start at the same level.
   - Example: all three middle lanes at the spawn junction have no movement: `bund_zhongshan_e1_0_back1`,
     `yanan_rd_surface_16_fwd1` and `zhongshan_e2_s_0_back1`. Traffic in a middle lane must stop at every junction.
   - `_check_termini` now passes as long as a dead end is "flagged".
   **Do:**
   - Every approach lane gets ≥ 1 movement:
     - middle lanes go straight;
     - with no straight arm, a middle lane takes the nearer turn;
     - a single-lane approach gets every plausible movement.
   - Merges skipped by `MIN_ARM_ANGLE` are linked as merges.
   - The test fails on any dead end whose `terminus_kind` is not `map_edge`, and prints the map-edge list.
   **Verify:** test_lanes prints `junction 0`.

6. **The drive test fails, and its settings were loosened (r1 item 5).**
   - 440 samples have no surface and 1,282 are blocked: yanan_elevated 345, ns_elevated 293, ramp_rt_eb_sb 93,
     yanan_rd_surface 79, nanpu_pudong_loop 75, ramp_rt_sb_wb 74.
   - `RAY_TOLERANCE` is 0.40 (r1: 0.15). At 0.40 a 0.15 m sidewalk slab counts as road.
   - The test skips the first and last 2–3 samples of every lane and casts on only every other step.
   - It loads the 131 garbage tiles (item 7), whose colliders can hide holes.
   - `surface-colonly` is still tagged `extras.surface = "concrete"` (r1: asphalt).
   **Do:**
   - Fix the elevated junction fills: per-vertex heights blended from each arm's end cross-section, or bring the
     arms to a common height over their last 20 m.
   - Restore tolerance 0.15 and test every sample.
   - Split the surface colliders by type and tag `extras.surface` on each:
     - `asphalt`: roads and junctions;
     - `steel`: bridge deck steel and joints;
     - `concrete`: kerbs, sidewalks, barriers, piers, tunnel walls.
   **Verify:** test_drive_collision reports 0 failures under the strict settings, after the garbage tiles are deleted.

7. **131 garbage tiles are loaded by the world.**
   - `game/assets/city/roads/` holds 194 `.glb` files: 63 current (12:06) and 131 from a 10:37 build (for example
     `roads_-106_-218.glb`, `roads_-10_2.glb`).
   - Each garbage tile is 2.5 KB of SH_wet_asphalt plus surface-colonly sliver triangles at y −0.01. They reach as
     far as (−80806, −166182): 650 triangles, 61 km² of asphalt.
   - `world_builder.gd:134` loads every `roads_*` file, and so does the drive test.
   - Current tiles also spill far past their 512 m square: roads_-2_0 asphalt spans x −1418…−500, z −79…1211 for a
     tile of x −1024…−512, z 0…512 (`tmp/review/tile_bounds.py`).
   **Do:**
   - Delete the 131 files and their `.import` now.
   - A full build deletes every `roads_*` tile it did not write (not with `--only`).
   - Add a build assertion: no triangle edge longer than 60 m, and every vertex inside its tile + 64 m. Clip road
     meshes at tile borders instead of assigning a piece whole.
   **Verify:** the tile count equals the built count, and the bounds script reports 0 out-of-tile primitives.

8. **Tunnel: the ceiling is 3.1 m above the lanes, the surfaces overlap, and the details are missing (r1 item 6).**
   - Rays from every yanan_tunnel lane centre hit the bore at 3.13 m (`tmp/review/tunnel_prof.py`). The crown is at
     4.52 m.
   - Dossier §4: Ø 11 m bores, roadway 7.5 m wide and 4.5 m high.
   - Road_Tunnel_Dark and Road_Tunnel_Enamel return identical hits (3.10, 3.28 and 4.19 m), so both meshes contain
     the same faces. They will z-fight once textured.
   - There are no `tunnel_light` records, jet fans, lane signals or exit signs.
   - In main.tscn, the camera at (139.7, −26.8, −127.6) sees the sky with no ceiling
     (`captures/review/roads/r2w_tunnel_1280.jpg`). The preview at the same spot shows the bore. Find out why.
   **Do:**
   - A Ø 11 m circular bore per carriageway, with clearance ≥ 4.5 m over the full 7.5 m roadway. A flat smoke-duct
     slab at 5.0 m is fine.
   - Enamel only from 0.5 to 3.2 m and dark concrete above it, with no shared faces.
   - LED luminaires 1.2 m long every 2.4 m at the ceiling corners.
   - Jet-fan pairs (Ø 1.2 × 5 m) every 250 m, lane signals every 150 m, exit signs every 80 m.
   - Portal U-trough with a yellow/black "限高 4.2m" gantry.
   - `tunnel_light` records every 12 m per bore, plus a request to the world unit.
   **Verify:**
   - tunnel_prof.py prints a ceiling ≥ 4.5 m.
   - A capture inside each bore in both the preview and main.tscn.

9. **road_furniture.json errors.**
   (a) 328 traffic lights and 906 road-name signs belong to elevated, ramp or tunnel roads at grade-separated
       crossings: the prop's y differs by more than 2 m from that road's height. Example: traffic_light
       `j_yanan_frontage_n_yanan_elevated` stands at (−1728, −0.47, 715), where yanan_elevated is at 9.03 m. Use the
       `levels.py` grade separation in `furniture.junction_furniture` as well.
   (b) 534 props are below ground (436 signs, 98 traffic lights; y as low as −1.39). Set y to the surface height.
   (c) 250 traffic lights and 266 signs still pass through a deck or pier above them (within height + 0.5 m;
       `tmp/review/furn_clear2.py`). Lamps are down to 21 and trees to 14; take those to 0 too.
   (d) Gantries (r1 9b not done):
       - 19 "direction" gantries print their own road's name: 延安高架路 at (−661, 231), 南北高架路 ×5, 内环高架路 ×4.
       - Exit gantries name the ramp, including on-ramps: "西藏路上匝道 出口 300m", "重庆路上匝道 出口 100m".
       - Exit gantries carry dev tokens such as "南北高架左转匝道 SB>EB".
       - There is no 500 m gantry.
       - 19 of 52 gantries have `text_en` equal to the Chinese text.
       **Do:**
       - Exit gantries only before off-ramps: "<destination road> 出口 500m / 300m / 100m" with an English line
         such as "Xizang Rd Exit 500 m".
       - Direction gantries every ~500 m, naming the next two destinations with arrows (dossier §2.6; ref
         `02_elevated_roads/yanan_elev_east_of_xizang_2025.jpg`).
       - No internal codes.

10. **Ramp attaches are still not done (r1 item 4; status known issue 8).**
    - The gore still uses the parent's `at` point.
    - Chevrons are not confined to the gore wedge.
    - There is no 1:25 taper or 150 m acceleration lane.
    - The parent's parapet and planters are not removed up to the gore nose.
    **Do:** exactly as r1 item 4 says: project the ramp end onto the parent; widen the parent deck; build one girder
    and one soffit under the widened stretch; 45° chevrons with 45 cm bars inside the wedge only; a crash cushion at
    the nose.
    **Verify:** 30 m aerial captures of ramp_xizang_off, ramp_chongqing_on and ramp_rt_nb_eb show no barrier or
    chevron across a lane, and the drive test passes along both roads.

11. **Budgets (brief + lead IMPORT-PERF).**
    - `roads_-3_1` has 438,596 visible tris (plus colliders), over the 400 k limit.
    - Two tiles exceed the lead's 15 MB per tile: roads_-3_1 is 29.8 MB and roads_-2_0 is 19.2 MB.
    - The status has no draw-call estimate.
    **Do:**
    - Pots ≤ 12 tris (item 2), and drop the hidden faces (pot bottoms, kerb and deck undersides that face the slab).
    - Report per tile: tris, MB and draw calls (meshes × visible tiles from the deck and from the interchange).

12. **Code rules and cleanup.**
    - Two files are over the 400-line limit:
      - `lanes.py` (546): split it, e.g. into lane sampling, junction links and attach links.
      - `junctions.py` (448): split it, e.g. into fill, kerb returns and markings.
    - Dead code (defined, never called): `deck.girder_profile`, `lanes._link_segments`, `materials._carrier`,
      `meshkit.uv_from_attributes`, `meshkit.quad_strip_poly`, `collision._barrier_box`, `junctions._cap_distance`,
      `levels.arm_sign`, `levels.offset_point`, `profiles._gutter`. The `PLANTS`/Road_Planter_Row strip is also
      unused unless item 2 uses it.
    - Magic numbers r1 asked to name are still inline: `attaches.py` 12 / 0.2 / 0.4 (lines 41, 95–101);
      `tunnel.py` (63 literals, e.g. 0.6, 3.55, 3.68); `piers.py` (33); `deck.py` (33); `furniture.py` 2.5 / 9.0 /
      11.0. Give each a named constant with its source.
    - IMPORT-CHURN (1): `textures.save()` rewrites all 13 images on every build (every mtime is 12:20). Write an
      image only when its bytes change, as the tiles already do.
    - Scratch files `/tmp/dbg6.py` and `/tmp/dbg7.py` were written this round (02:05 and 02:07). Delete them; use
      `tmp/roads/` only.
    - status/roads.md is wrong:
      - it claims 36,597 props, 256 anchors, 635 piers and 22 images (2.5 MB); the files hold 35,901 props,
        156 anchors, 602 piers and 13 images (0.99 MB);
      - it still lists the import-churn fix as a request;
      - it claims "every triangle of the fill goes into its tile", but road meshes spill 700 m.

13. **Lead R3 is not complete.**
    - Captures must be at 1.1 m (the status uses 1.7 m).
    - The status must list the verified tiles.
    - Cover each district: Bund, Yan'an deck and under it, the 龙柱 interchange, Lujiazui / Century Ave, the Nanpu
      deck and spiral, inside the tunnel, the expressway and toll.
    - My main.tscn captures show two more problems:
      - `review_roads_r2w_w_pots.jpg` at (−403, 11.6, 1688): a building facade stands against the inner-ring parapet.
        File this with buildings / city_layout.
      - `w_tunnel`: no tunnel (item 8).

## SHOULD-FIX
- 4,254 of 9,216 road-name signs read placeholder names ("D4 街 / D4 street", "D6 街", "D3b 街", "D7 街"…). ART §7
  wants real words. Request real Huangpu/Pudong street names from city_layout, or map them in furniture.py.
- Static typing: the loop variables are untyped in the tests and the preview (`for file in`, `for entry in`,
  `for i in`, `for id in`). Use `for entry: Variant in lanes`, etc.
- `FILL_DROP = 0.01` still leaves a 1 cm step under the junction fill. Join the cut road ends with shared vertices.
- No road in city.json is styled with bus lanes, so 公交专用 is never drawn. Ask city_layout to style 2–3 surface roads
  with bus lanes. Also add straight-left arrows, Ø 0.7 m manholes and skid-mark quads.
- `preview_roads.tscn` should use `res://world/env/environment.tscn`. In the preview the puddles read as opaque black
  splats at 20–100 m (`review_roads_r2_aerial100.jpg`, `junction_high`); in main.tscn they read correctly.
- From r1, still open: a 2 cm kerb top chamfer; a safety-shape inner face on the parapet with a coping; delineators
  every 4 m; `textures.save` should honour `--out`.

## Verified OK
- `check` is clean. `test_lanes` passes 10/0: links meet within 0.000 m, coverage is ≥ 95 %, all 31 ramp attaches are
  linked, and no end point is shared. The dynamic shots pass 20/20 with no tunnelling.
- Piers stand on the ground with the T cap under the girder; pier records have y = 0 and a `deck_y` field. Pier
  colliders are trimesh.
- Lead R1 is met. SH_soffit_blue is on the wing undersides only, and the girder bottom reads as dark concrete.
  Underdeck SAT is 3.8–7.4 % in the preview and 18.9 % in main.tscn (zone target 5–26 %).
- The LED energies are 4.5 (soffit and bridge, tier E3) and 6 (tunnel).
- Cable anchors: 156 on nanpu_bridge, every 9.6 m, unique `_L/_R` names, none on waibaidu.
- Lamps through decks are down from 76 to 21, and trees from 208 to 14.
- Tiles are written only when their bytes change, and the lead's `generate_lods=false` lines are kept in the 63 tile
  .import files.
- Wet road in main.tscn: reflections and puddles read well (`review_roads_r2w_w_junction_eye.jpg`). The full build
  takes 4.5 min.
- Performance: the preview runs at 51–155 fps at 1600×900. In main.tscn on the Yan'an deck, Roads costs 140 draws and
  42.9 k prims of a 738-draw frame.
- The worker log shows no Write/Edit outside the owned paths and no background Godot/Blender runs this round.

## Evidence
- `tools/godot.sh check --only=res://assets/city/roads/` → `CHECK 18 files, 0 failed, 0 engine errors, 0 warnings`.
- `tools/godot.sh test res://assets/city/roads/tests/test_lanes.gd` → `10 checks, 0 failures`, but `every dead end is
  flagged (junction 718, map edge 54)`.
- `tools/godot.sh test res://assets/city/roads/tests/test_drive_collision.gd` → `FAIL ... (440 bad samples)`,
  `FAIL ... blocked (1282 bad)`, `TEST drive_collision: 4 checks, 2 failures`.
- `tools/blender.sh preview game/assets/city/roads/roads_-1_3.glb review_roads_r2_tile --views top,close_side` →
  `tris=62516`, all Road_* `<-- UNTEXTURED`.
- `tools/godot.sh perf --skip-menu --spawn=-1249,10.2,691,90` → `PERF Main/World/Roads draws=140 ... prims=42914`.
- Captures:
  - Preview scene: `captures/review_roads_r2_{deck_eye,parapet_close,deck_eye2,gore,nanpu_deck,aerial100,underdeck,`
    `pier_close,ns_gap,tunnel,surface_eye,kerb_close,junction_eye,junction_high}.jpg` and
    `review_roads_r2b_{pots_close,pots_row,pots_outside,soffit_up,tunnel_wall,gore_top,nanpu_side}.jpg`.
  - main.tscn: `review_roads_r2w_w_{junction_eye,junction_high,deck,pots,under,tunnel}.jpg`.
  - Sheets: `captures/review/roads/r2_sheet{A,B,C,D,E,W}.jpg`, `r2_refcompare.jpg` (interchange_ground_2025,
    yanan_elev_east_of_xizang_2025, bund_tunnel_interior_2012 and under_elevated_2009 next to ours),
    `r2_junction_crop.jpg`.
- Scripts in `tmp/review/` (run with Blender's bundled python3.13 for numpy): `glb_tris.py`, `cur_tiles.py` (tris,
  UVs and long edges per material), `tile_bounds.py`, `stray.py`, `kerb_on_lane.py`, `furn_clear2.py`, `pots.py`,
  `tunnel_prof.py`, `tunnel_hit.py`, `zebra.py`, `roads_r2_cams.py`; the pier-gap and dead-end numbers come from
  python over lanes.json, road_furniture.json and city.json.
