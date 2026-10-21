# world review round 3 — VERDICT: FAIL

## Scores (0-10): function 3, visual 2, code 4
- function 3: the loader rejects every imported tile, so the real buildings, the Bund and the road tiles
  never load (#1). The fallback prisms have no collision: in the lead's smoke drive the car ends up inside
  a building at t=14 s. Street furniture has no collision at all (#2). Racing lines are still broken, and
  the cause is in the world, not only in the data (#8). The build takes 44-63 s against a 10 s target, and
  test_world_api is killed by the 300 s slot limit (#9).
- visual 2: what the player sees is a grey-box city. There are no Bund façades and no gold floods. The
  street grid is black from 120 m (no lamp dots). Every shop sign and the inner-ring gantry show the wrong
  text ("延安高架路"). A tree grows through a bus shelter. The police station is a black box. Neon is ≤ 2 %
  in 26 of my 30 frames; the maximum is 13.6 %, the blue deck soffit at vp_dragon.
- code 4: every file is ≤ 400 lines and the work is split into modules. But one quote character broke the
  whole loader, and there is no test that would catch it. Other problems: a bitmask bug that a test
  confirms instead of catching, 18 untyped parameters, ≥ 20 dead functions, orphan comments, and magic
  numbers that the status says are gone. Four status claims are false (#16).

## Lead notes (reviews/world-lead.md) — every one is mandatory
| note | state |
|---|---|
| TILE-TEX (.glb or .gltf, .gltf wins) | **NOT satisfied**: `find_glbs` prefers .gltf, then `_is_imported` rejects every tile (#1) |
| W-INT1 spawn on a lane | OK (lead drive: 0 → 300 km/h by t=7 s) |
| W-INT2 lenses / W-INT3 gas reparent | OK (0 errors) |
| W-INT4 / W-INT5 perf table, ≤ 600 draws / ≤ 2,000 objects | **NOT satisfied**: no table; my probe gives 2,006 draws / 2,871 objects at yanan_deck (#10) |
| W-INT6 0 world errors in the lead drive | OK (0 ERROR lines with a res://world frame) |
| W-INT7 masts off the carriageway + test | **NOT satisfied**: test_world_quality FAILs (2 masts, 1 prop), masts have no collision shape (#2, #13) |
| W-INT8 API safe before build / build ≤ 10 s | API OK; build **44-63 s** (#9) |
| W-NIGHT1 dark textured ground | partly: dark, but ≈ #0E0E0D, one material, no detail (#14) |
| W-NIGHT2 lamp dots from 120 m | **NOT satisfied**; the status claim is false (#3) |
| project rules: tests extend Node, scratch deleted | tests OK; 20 scratch logs (17 MB) left in tmp/world (#16) |

## MUST-FIX
1. **The loader skips every imported tile, so the real city never loads (critical).**
   `game/world/loader/asset_library.gd:101-109` `_is_imported()` takes the line
   `path="res://.godot/imported/<file>.scn"` from the `.import` file and calls
   `FileAccess.file_exists(line.substr(5).strip_edges())`. The string still contains the double quotes, so
   the check is false for every imported file.

   My probe (`tmp/review/world/probe_r3_import.gd`, log `r3_probe_import.log`) prints
   `blocks_0_0.gltf | exists(raw)=false | exists(unquoted)=true | _is_imported=false | load_ok=true`.
   `bund_buildings.glb` and `bund_promenade.glb` give the same result. In my capture run C, **183 of 183**
   tiles were skipped as "not imported yet" (63 roads .gltf, 118 blocks .gltf, 2 Bund glb), although every
   imported `.scn` is on disk (roads_0_0 was imported at 13:56:08). Every worker log since 11:01 shows the
   same skips.

   Consequences:
   - `Blocks` holds 618/618 fallback `Block_*` prisms and `Roads` holds 303/303 fallback `Road_*` ribbons
     (`r3_probe.log`).
   - test_world_quality reports "0 occlusion boxes". That is this bug, not "the tiles aren't imported on
     this machine".
   - The Bund is missing: no heritage façades and no gold floods. Compare
     `review_world_r3a_vp_bund.jpg` and `_bund_from_river.jpg` with
     `ref/shanghai/img/05_bund/bund_night_2023.jpg` (sheet `captures/review/world/r3_ref_compare.jpg`).
   - The fallback prisms have no collision. The lead's smoke drive ends inside a grey prism
     (`review_world_r3_drive_t14_0.jpg`, `air=true` from t=14.0 to 15.0 s).

   Do:
   - (a) Read the remap path properly. Either `ConfigFile.load(path + ".import")` and
     `get_value("remap", "path", "")` (texture imports use `path.s3tc` / `path.etc2`, so accept any
     `path*` key of `[remap]`), or drop the check and rely on `ResourceLoader.exists()` + `load()`.
   - (b) Never build the fallback when tiles exist. If some tiles are missing, print "N of M tiles loaded"
     once.
   - (c) If the fallback stays (for test_city), give each prism a box/convex collision and skip `park` and
     `plaza` lots.
   - (d) New checks in test_world_quality:
     - roads / blocks / bund: "N of N tiles instantiated, 0 skipped" whenever their `.import` target exists;
     - no `Block_*` or `Road_*` node when the tiles exist;
     - occlusion boxes > 0 (r2 had 1,966).

   Verify:
   - Re-shoot my cams `tmp/review/world/cams_r3a.json`. The Bund must be gold, #E9C98F on #C9B79A, in
     vp_bund and bund_from_river.
   - The lead smoke drive must never enter a building.
2. **No street furniture has collision.** Only ground, water, fallback roads, sites, toll, breakers and sky
   lanes create bodies (`grep -rln CollisionShape3D game/world`). These have none:
   - 4,965 lamps, 18,878 trees and the traffic-light masts;
   - gantry and VMS posts, 466 bus stops, the noise walls;
   - 4,380 bollards and the hydrants.

   The car passes straight through all of them. That breaks SPEC pillar 5, and W-INT7's test is about
   "mast/pole collision shapes".

   Do: one StaticBody3D per 512 m tile, on layer 3 (prop) with mask 0. Add the shapes with
   `PhysicsServer3D.body_add_shape`, using the same transforms as the MultiMesh, so there are no nodes per
   prop:

   | prop | shape |
   |---|---|
   | lamp pole | cylinder r 0.15 m × height_m |
   | tree trunk | r 0.25 × 3 m |
   | mast | pole r 0.2 + arm box |
   | gantry / VMS posts | 0.5 × 7 m |
   | bus stop | box 8 × 2.6 × 1.8 m |
   | noise wall | box per segment |
   | bollard | r 0.1 × 0.95 m |

   Test: a 1,900 kg probe body at 60 km/h aimed at a lamp, a mast and a tree reports a contact and ends
   with speed < 30 km/h.
3. **W-NIGHT2 is not implemented, and the status claim is false.** `prop_library.gd:111` splits off a
   "head" only when a MeshInstance3D is named `Light*`. In `lamp_street.glb`, `lamp_heritage.glb`,
   `lamp_magnolia.glb` and `lamp_deck_double.glb`:
   - the head is the second **material surface** of the single mesh (surface 1, material `Prop_Opal`,
     emissive strength 2.4; surface 0 is `Prop_Metal`);
   - `Light`, `Light_1` and `Light_2` are empties.

   So no glow batch exists. The probe lists only `Furniture_lamp_lamp` (4,965) and `…lamp_heritage` (57),
   both with vis_end 600 m. From 120 m the grid is black:
   - `review_world_r3a_vp_flight120.jpg`: luminance 0.070, 0 % neon;
   - `_flight120_obl.jpg` against `ref/shanghai/img/05_bund/bund_aerial_night_2023.jpg`.

   Do:
   - Split the merged lamp by material. The emissive `Prop_Opal` surface (the head) becomes the glow part. Draw it per
     tile with `visibility_range_end` ≥ 1,500 m and shadows off.
   - Beyond 600 m add a far dot: an additive 2 × 2 m billboard, sodium #FFB46B / LED #D9E8FF, so the dot
     never shrinks below one pixel.

   Test: glow instances ≥ 95 % of the lamp instances, and vis_end ≥ 1,500.

   Capture: flight120_obl, camera (-250, 120, 250) looking at (-1000, 0, 650). Yan'an Rd and the side
   streets must read as lines of dots.
4. **The lamp glb is not chosen from the road style (r2 #6d, not done).** `_road_styles` only sets the
   panel colours (`furniture_builder.gd:227`). The data asks for three variants:
   - 395 lamps with `mount: median, arms: 2` → `lamp_deck_double.glb`;
   - roads with `style.lamps = "magnolia"` (yanan_rd_surface, st_nanjing_e_rd, …) → `lamp_magnolia.glb`;
   - "heritage" → `lamp_heritage.glb`.

   Today the probe finds 4,965 `lamp_street`, 57 heritage, 0 magnolia and 0 deck_double. Today's double
   lamps draw one arm and register two lights.

   Verify:
   - Print the placements per glb.
   - Capture from (-1615, 2, 737) looking at (-1500, 3, 730): magnolia lamps and a plane-tree row. Compare
     `ref/shanghai/img/02_elevated_roads/yanan_elev_east_of_henan_2025.jpg`.
5. **The gantry panels show the props unit's baked text, not the data.** `sign_props.gd:54-61` instantiates
   every part of `guide_gantry_27.glb`, including its own panel with the baked text "延安高架路 Yan'an
   Elevated Rd / 南北高架路 N-S Elevated Rd". It then adds `PanelBox_i` + `SignPanel_i` (`:80-95`). At the
   inner-ring gantry (-191.27, 10.0, 1678.58), whose data says "内环高架路", the visible panel reads
   延安高架路 / 南北高架路 (`review_world_r3c_gantry18.jpg`).

   Do:
   - Drop the glb's panel surfaces (materials `Prop_Sign` / `Prop_SignLit`) from the gantry parts.
   - Put the generated panels in the glb panel's plane, facing the oncoming traffic: one panel per
     direction.
   - Colour: green #00704A on elevated roads, blue #1F57C3 on surface roads. Text: white #FFFFFF, ≥ 0.45 m
     cap height.

   Verify with captures 18 m before each gantry, eye 1.6 m above the deck:

   | gantry | must read |
   |---|---|
   | (-191.27, 10.0, 1678.58) | 内环高架路 |
   | (-1461.16, 12.0, -225.03) | 南北高架路 |
   | (-661.31, 9.99, 231.16) | 延安高架路 |

   No baked text may remain anywhere. Compare `ref/shanghai/img/02_elevated_roads/inner_ring_2048.jpg`.
6. **All 1,187 shop signs are "延安高架路 ↑" road guide signs.** `prop_library.gd:47` maps
   `SIGN_MESH["shop_sign"] = "SignFace"`. But `guide_sign.glb` has a single mesh (materials `Prop_Sign`,
   `Prop_Metal`) and no `SignFace` node. So `face` stays null in `sign_props.gd:160-179`, and the generated
   shop name is never applied. Every shop sign shows the props unit's default guide panel:
   - `review_world_r3b_nanjing5.jpg`: a green "延安高架 Yan'an Elevated Rd ↑" board on Nanjing E Rd;
   - `review_world_r3c_sidewalk5.jpg`.

   A guide sign is traffic signage, not a shop board, and ART §7 asks for real words in context.

   Do:
   - Use a real shop-board prop. Ask props for a `shop_sign` glb with a `SignFace` mesh, or reuse
     `neon_blade_frame`.
   - Find the face by material name, not by node name.
   - Give the boards per-instance text from a per-tile atlas (UV offset in `INSTANCE_CUSTOM`), so they
     stay one MultiMesh instead of 1,187 nodes. Use parody names: 东方霓虹, 浦江电讯, 申城快递, 量子奶茶,
     老城隍面馆 …

   Verify:
   - A 5 m capture on st_nanjing_e_rd shows readable shop names.
   - Your own text list contains 0 road names on shop boards.
   - Compare `ref/shanghai/img/09_street_details/nanjing_road_night_2009.jpg`.
7. **Props stand inside each other.** `furniture_filter.gd:185 _is_free()` checks only lanes, junctions,
   sites and decks. There is no check between props, and the 23,778 relocated props all land on the same
   kerb line. Evidence:
   - a plane-tree trunk grows through the roof and back panel of a bus shelter, with a road sign inside the
     same shelter (`review_world_r3b_nanjing5.jpg`, `review_world_r3c_sidewalk5.jpg`);
   - compare `ref/shanghai/img/09_street_details/bus_shelter_2026.jpg`.

   Do: an occupancy grid with 0.5 m cells and a footprint per kind. Place the big props first (bus stops,
   masts, gantry posts, trees), then the small ones, and make `_is_free` reject occupied cells.

   | prop | footprint |
   |---|---|
   | bus stop | 8.4 × 2.0 m oriented box |
   | tree | r 1.2 m |
   | lamp | r 0.5 m |
   | mast | r 0.6 m |
   | bin / hydrant / bollard | r 0.4 m |
   | bike rack | 2.0 × 1.0 m |

   Test: no two placed props are closer than the sum of their radii; print the 5 worst pairs.
8. **Racing lines: the router drives lanes backwards, and the lane graph is not connected forward.** The
   status calls this "a data problem, not a line problem". For bund_sprint that is false:
   - all 10 of its gates are ≤ 0.1 m from a lane whose direction matches the gate (dot 1.00, my check
     `tmp/review/world/py/route_check.py`);
   - your build prints no bad leg for it;
   - yet the line is 6,213 m for 3,351 m of gates, with 32 reversals and 66.0 % on a lane.

   The cause: the route's roads have no forward connection in the lane graph (`tmp/review/world/py/seg_links.py`).
   With the 13:46 data it listed 34 such transitions over the 5 routes. With the roads unit's 14:07 data it
   lists 26, and bund_sprint's gates still match the lanes (all ≤ 0.1 m, dot 1.00). For bund_sprint, the
   13:46 data lacked:
   - bund_zhongshan_e1(−1) → st_nanjing_e_rd(−1)
   - st_nanjing_e_rd(−1) → st_henan_rd(−1)
   - st_henan_rd(−1) → st_henan_portal(−1)
   - st_henan_portal(−1) → yanan_tunnel(+1)
   - yanan_tunnel(+1) → century_ave(+1)

   The 14:07 data still lacks the first, the second and the last of these. A full Dijkstra over the 14:07
   links finds no forward path for leg 6, and the forward path is 5,773 m for 3,351 m of gates.

   `lane_path_finder` then "follows the lanes in both directions".

   Do:
   - (a) Never traverse a lane against its direction. A leg without a forward path is reported, not drawn
     backwards.
   - (b) `LaneLinks` (yours) synthesizes the missing turn connectors at every city.json junction:
     - from every lane end within the junction radius (≥ 15 m) to every lane start of another road within
       that radius;
     - only for a heading change ≤ 135° (no U-turns);
     - each connector is a Hermite Curve3D at lane height.
   - (c) bund_sprint and lujiazui_ring must then pass the test: ≥ 95 % of samples within 2 m of a lane and
     0 reversals.
   - (d) Only after (a) and (b), send the legs that still fail to city_layout, with gate coordinates.
     Today's list is grand_loop 5, 6, 18, 19 and river_loop 5, 6, 11, 12, 19, 20. Send the missing
     lanes.json links to roads with junction ids.
   - (e) test_city's `test_loop` also fails: legs [1, 3] run "against traffic", leg [2] is unreachable,
     75.6 % on a lane, 6 reversals. test_city.json is core-owned, so after (a) and (b) give the remaining
     legs to the lead.
9. **The build takes 44-63 s against ≤ 10 s (W-INT8), and test_world_api is killed by the slot limit.**
   Build times of my runs:

   | run | build |
   |---|---|
   | test_world_api | 62.8 s |
   | test_drive_lanes | 59.1 s |
   | test_world_quality | 62.6 s |
   | runtime probe | 63.2 s |
   | captures | 52.7 s, 50.9 s |
   | lead drive | 44.0 s |

   The phases of the api run: lanes 13.7 s, furniture 20.0 s (of which sorting 9.2 s), routes 14.9 s,
   terrain 3.7 s. test_world_api builds the city twice and was killed at 304 s
   (`[slots] TIMEOUT after 300 s`, `r3_test_world_api.log`).

   Do:
   - (a) Cache the lane graph, links, routes and furniture placements (position, kind, variant) in a
     binary `.res`, keyed by the SHA-256 of city.json + lanes.json + road_furniture.json (for example
     `user://world_cache/<sha>.res`). Rebuild only when a hash changes.
   - (b) Build furniture, signs and sites for the 3 × 3 tiles around the spawn first, then set
     `loading_fraction = 1.0`. Stream the other tiles afterwards, ≤ 4 ms per frame.
   - (c) Print a per-phase table.

   Verify:
   - warm cache at machine load < 10: `[world] built in ≤ 10 s`;
   - cold cache: ≤ 20 s;
   - test_world_api finishes in < 200 s at load 30.
10. **The performance table (W-INT4 / W-INT5, mandatory) is still missing.** My probe
    (`tmp/review/world/perf_r3.gd`, log `r3_perf.log`): environment + world only, fixed cameras at
    1920×1080, with fallback roads and blocks because of #1.

    | view | draws | objects | prims | largest groups (draws) |
    |---|---|---|---|---|
    | bund | 529 | 604 | 0.23 M | Roads 330, Blocks 93 |
    | yanan_deck | **2,006** | **2,871** | 0.56 M | Roads 968, Blocks 638, Landmarks 135, Sites 105 |
    | dragon | **1,840** | **2,658** | 0.40 M | Roads 1,116, Blocks 474, Furniture 101 (854 objects) |
    | lujiazui | **1,248** | 1,690 | 0.40 M | Roads 572, Blocks 387 |
    | nanpu_spiral | 406 | 519 | 0.21 M | Roads 223 |
    | flight120 | 199 | 201 | 0.21 M | Roads 131 |

    Do:
    - (a) After #1, measure the 6 viewpoints with the real tiles (`tools/godot.sh perf` or this probe) and
      put a per-group table in status.
    - (b) Nodes built one by one have no visibility range (`grep visibility_range build/sign_props.gd` → 0):
      1,187 shop signs, the gantries, the VMS boards and the sites are drawn out to the far plane. Set
      ranges: shop signs 150 m, gantries and VMS 800 m, sites 1,200 m.
    - (c) The 56 mast batch nodes are direct children of the world root (`signal_controller.gd:97`
      `_batch.build(parent, …)` with parent = world). Put them under `TrafficSignals`.
    - (d) If a fallback stays, merge it per tile.

    Target: ≤ 600 draws and ≤ 2,000 objects at every viewpoint.
11. **The police station is still a dark untextured box (r2 #15).** At 30 m (`review_world_r3b_police_lj.jpg`:
    luminance 0.096, 23 % near-black) and at 15 m (`review_world_r3c_police15.jpg`), the Lujiazui station
    is a near-black tiled box:
    - the band is black and glossy;
    - 陆家嘴警察局 cannot be read;
    - no lit window is visible.

    ART §8 says "no grey-box shapes".

    Do:
    - Ask props for a `police_station.glb` (their brief's police kit) and use it.
    - Until it exists, build the station like this:
      - walls in white tile ≈ #D8D6D0, with a grout normal for 0.6 × 0.3 m tiles (triplanar, 1 m);
      - band #1E4FB8 with white letters ≥ 1.2 m high (readable from 30 m);
      - 15-30 % of the front windows lit #FFD7A0;
      - a 警 emblem and the red/blue light bar;
      - the front facing the road.

    Verify: captures at 5, 15 and 30 m. Take the colours from
    `ref/shanghai/img/09_street_details/police_lightbars_2011.jpg`.
12. **A broken toll arm is on the wrong physics layer.** `toll_plaza.gd:350` sets
    `arm.collision_layer = 5`. That is a bitmask: layers 1 (world) + 3 (prop), not layer 5 (debris =
    `1 << 4` = 16). `test_gameplay_sites.gd:175` asserts `== 5`, so the test confirms the bug. Every
    wheel ShapeCast and every AI ray on layer 1 will hit the debris.

    Do: use `1 << 4`, and make the test assert `collision_layer == 1 << 4`.
13. **W-INT7 still fails, and the spawn junction shows conflicting heads.**
    - test_world_quality reports "2 of 1380 traffic-light masts stand in the carriageway" and "1 of 49548
      furniture props stand on the carriageway" (FAIL 3 of 17). The lead's gate is 0. The masts also need
      their collision shapes (#2).
    - At the spawn junction, camera (0, 1.5, −13), a red head and a green head face the same approach
      (`review_world_r3b_spawn_junction.jpg`). The cause: city.json has two signalised junctions 15.4 m
      apart, `j_bund_zhongshan_e1_st_d6_ns_yanan_rd_surface_zhongshan_e2_s` at (0.5, 0.5) and
      `j_bund_zhongshan_e1_st_d0_ns_st_d6_ns_yanan_rd_surface_zhongshan_e2_s` at (15.6, 3.4). Both carry
      the Bund and Yan'an roads, and their phase splits differ (4 roads vs 5 roads).

    Do:
    - Merge the junctions that are closer than 20 m into one controller with one cycle and one mast set
      per approach.
    - Add a test: all heads that face one approach always show the same state.
14. **W-NIGHT1 ground: too dark to carry texture, one material for every lot, no detail.** The ground uses
    `road_wet.gdshader` with `albedo_mul 0.15` (≈ #0E0E0D from asphalt_02's #5B5955) and `tile_m` 6.
    - At 5 m the asphalt grain and the puddles read well (`review_world_r3c_ground5.jpg`).
    - From 120 m the ground is a void: vp_flight120 luminance 0.070.
    - There is no value step between road and lot, and no detail at 20 m.

    ART §2 says "never pure #000 — keep detail in the darks". The user demands refined textures
    everywhere ("贴图纹理什么都要细化").

    Do:
    - Lots ≈ #1F1F22 (`albedo_mul` ≈ 0.35).
    - A 4-8 m concrete paving apron (`PavingStones144` or `concrete_pavement`, ≈ #2A2A2E, 0.5 m tiles) at
      the site forecourts and along the block edges.
    - Keep the macro variation (`aerial_asphalt_01`, 37 m).
    - Scatter decals per tile from the shared textures: manholes, drain grates, oil stains and puddles, one
      per 15-25 m², with no z-fighting.

    Verify: captures of the lot at (-560, 1.7, -632) looking at (-560, 0, -645) at 5, 20 and 100 m. Grain
    must read at 5 m, decals at 20 m, and the value step lot vs road at 100 m.
15. **Code rules (CONTRACTS §3, global rules).**
    - **Untyped parameters**, against "static typing everywhere". `grid`, `graph` and `data` are untyped in
      18 functions, among them:
      - `route_builder.gd:37,47`;
      - `lane_links.gd:16,25,42,93,122,127`;
      - `start_grid.gd:112`;
      - `gameplay_sites.gd:69,257`;
      - `signal_controller.gd:212` and `setup(…, grid = null)`;
      - `lane_probe.gd:23`;
      - `tests/water_probe.gd:13`.

      Type them with the preloaded scripts (`grid: LaneSpatial = null`, `graph: LaneGraph`).
    - **Dead code**: delete these functions or use them.
      - `light_pool.gd:99-151`: source_count, active_lights, active_spots, active_decals, decal_positions,
        source_grounds, active_source_kinds;
      - `lane_path_finder.gd`: start_lane (18), junction_point (113);
      - `ribbon_builder.gd`: poly_faces (133);
      - `gameplay_sites.gd`: pursuit_breakers (65);
      - `heading.gd`: transform_from_heading (25);
      - `prop_library.gd`: has_prop (70);
      - `lane_spatial.gd`: segment_count, lane_count (53, 75);
      - `probe_placer.gd`: probe_count, active_probe_count (133, 137);
      - `test_world_api.gd`: _reachable, _follows_the_road, _distance_to_lane (137, 306, 335).
    - **Orphan doc comments** with no code under them: `world.gd:31-41` and 43 (seven `##` lines left over
      from moved constants).
    - **Magic numbers**, which the status says are gone:
      - `toll_plaza.gd:163`: −78.0;
      - `street_dresser.gd:163,168,169,218,248`: 0.75, 0.7, 0.6, 2.2, [3, 6, 9, 13];
      - `gas_station.gd:23-25,47,53`: 80, 70, 0.6, 1.4;
      - `city_sites.gd:87,104,124,130,144`: 6.6, −7.2 / 3.6 / 2.2 / 3.4, 9.7, 7.6;
      - `furniture_filter.gd:210`: 3.0.
    - **A dangerous default**: `proc_meshes.gd:90` returns a white glow (energy 3.0) for an unknown material
      name, so a typo becomes a blown-out white object. Use `push_error` and return a textured neutral
      concrete instead.

    Verify: check reports 0 warnings, and `grep -rnE "func .*[(,] *(grid|graph|data)( = null)?[,)]"
    game/world` finds 0 hits.
16. **Status honesty and scratch files.** Four claims of this round are false:
    - "0 occlusion boxes because the buildings unit's tiles aren't imported on this machine" (see #1);
    - "the heads are batched with a visibility range of 1,800 m" (#3);
    - "the magic numbers are named constants" (#15);
    - "the racing lines … a data problem, not a line problem" (#8).

    Correct them, and quote only numbers you measured in this round. Delete the 20 scratch logs in
    `tmp/world/` (17 MB: api3.log, capture2.log at 12.7 MB, q4-q9.log, grid_test*.log, …). The lead's rule
    is that scratch is deleted when done; keep the evidence in status.

## SHOULD-FIX
1. `mesh_merger.gd:38` calls `generate_lods(0.0, LOD_EPSILON, [])`. Those arguments are the normal
   merge / split angles in degrees, not a screen-space error. Use the importer defaults (60, 25) and fix
   the comment at :9.
2. There are 1,049 `ReflectionProbe` nodes for ≤ 4 enabled ones. Keep about 16 pooled probes and move them
   along the grid; measure the cost (brief §4).
3. `signal_controller._process` updates every mast on every frame. Throttle it to 10 Hz.
4. The river reads as a pale flat plane from the Bund (`review_world_r3a_lujiazui_from_bund.jpg`), while
   `ref/shanghai/img/06_lujiazui/lujiazui_from_bund_night_2016_01.jpg` shows dark water with long
   reflections. Check your water mesh (normals up, UVs in metres) against the environment lookdev. If the
   shader is the cause, request a fix from the environment unit.
5. The toll canopy underside is blown out (`review_world_r3b_toll_w.jpg`). The props glb's `Prop_Soffit`
   has an emissive strength of 2.0. Request ≤ 0.8 plus a troffer texture from props (ART §10.6).
6. The roads unit's ids are now consistent (0 unknown junctions in the 13:47 data). Still, the fallback
   that placed masts at unknown junctions, always green, should map them to the nearest city.json
   junction (≤ 25 m) instead.

## Verified OK
- `tools/godot.sh check --only=res://world/` → `CHECK 63 files, 0 failed, 0 engine errors, 0 warnings`.
- Tests:
  - test_drive_lanes: `PASS all 18 checks` (on the fallback roads, see #1);
  - test_gameplay_sites: `PASS all 24 checks` (but see #12).
- W-INT1: the lead's smoke drive starts on a lane and accelerates 0 → 300 km/h by t = 7 s.
- W-INT2 / W-INT3: no lens or reparent errors.
- W-INT6: the lead's drive has 0 ERROR lines with a res://world frame. Its 55 × `Parameter "uniform_set"
  is null` come from the renderer, with no script frame.
- W-INT8 (API): before the build, every API method returns its documented fallback, with one warning and
  no script error:
  `pre spawn=(0,1,0) nearest=(10,1,10) lanes=0 routes=0 route=<null> minimap=0 pois=0 roadblocks=0 signal=2`.
- Landmarks: the manifest anchors are read as [x, y, z] and all 10 landmarks are placed. The Nanpu H-tower
  stands ahead at vp_nanpu_spiral, and the OPT is north-east of the Bund.
- The VMS boards cycle pre-rendered amber dot-matrix messages (`review_world_r3c_vms18.jpg`).
- Furniture:
  - batched per 512 m tile with per-type ranges: lamps 600, trees 350, bus stops 250, signs 200,
    bins/bollards 120;
  - LODs through ImporterMesh;
  - masts batched per tile (14 batches, 400 / 600 m);
  - sky-lane rings as a MultiMesh (98 instances).
- Light pools: 32 omni + 12 spot street lights plus 12 flood spots (56 lights) and 48 decals.
- Files: all ≤ 400 lines (max 397, world.gd 229); the work is split into loader/, build/, api/ and tests/.
- TILE-TEX: `find_glbs` accepts .glb and .gltf and prefers .gltf. It is defeated by #1.
- Ownership: the job log shows Write/Edit only under `game/world/**` and `status/world.md`, and Bash writes
  only to game/world, tmp/world and captures.

## ART §10 checklist (my captures)
1. Value: grey prisms on a near-black ground. The car stands out only because the city is dull.
2. Palette: neon ≤ 3.1 % in 29 of 30 frames; the exception is vp_dragon at 13.6 % (blue deck soffit).
   There is no gold Bund and no cyan Pudong at street level.
3. Detail at 5 / 20 / 100 m:
   - the ground asphalt is good at 5 m;
   - the fallback walls are flat grey at 5-20 m (`review_world_r3b_nanjing20.jpg`, `_r3c_ground5.jpg` left
     half);
   - the police box is black;
   - the sign texts are wrong.
4. Tiling: not visible on the ground.
5. Scale: the props stand inside each other (#7).
6. Emissives: the toll canopy is blown out (props, SHOULD-FIX 5).
7. Shanghai is recognisable only from the Lujiazui skyline and the Nanpu tower; the Bund is missing.
8. Edges and bevels: n/a on the fallback boxes.
9. A tree passes through a bus shelter, and the car enters a building at t = 14 s.
10. Store screenshot: none of my 30 frames.
11. Lit density at 120 m: no lamp dots (#3).

## Evidence
All runs were made with the machine at load 23-59 (other units running). Logs are in `tmp/review/world/`.
The roads unit deleted and re-exported its tiles and data during my runs (13:34-14:05: 8,640 → 7,075 →
8,501 lanes). Because of #1, every run drew the fallback roads either way.
- `r3_check.log`: CHECK 63 files, 0 failed.
- `r3_test_world_api.log`:
  - built in 62.82 s (8,640 lanes);
  - FAIL lines for every route: bund_sprint 6213 m vs 3351 m, 32 reversals, 66.0 %; test_loop 75.6 %, 6
    reversals;
  - killed by `[slots] TIMEOUT after 300 s` (EXIT 124).
- `r3_test_drive_lanes.log`: PASS 18, built in 59.09 s. `r3_test_gameplay_sites.log`: PASS 24.
- `r3_test_world_quality.log`: FAIL 3 of 17 (1 prop, 2 masts, 0 occlusion boxes), built in 62.56 s.
- `r3_probe_import.log`: the import probe for #1. `r3_probe.log` (`tmp/review/world/probe_r3.gd`):
  - group sizes;
  - fallback roads 303/303, blocks 618/618;
  - the MultiMesh list, with no glow batch;
  - the ground material (`albedo_mul 0.15`);
  - 342 masts.
- `r3_perf.log` (`perf_r3.gd`): the table in #10.
- `r3_drive.log`: the lead's smoke drive. Shots `captures/review_world_r3_drive_t{2_0,6_0,10_0,14_0}.jpg`,
  sheet `captures/review/world/r3_sheet_drive.jpg`.
- Data checks (python, `tmp/review/world/py/`): `route_check.py` and `seg_links.py` (#8).
- Captures, made with `tools/godot.sh shot --scene=res://main.tscn --skip-menu --env-only
  --stub=player_car,camera,menu,hud,police,traffic,rivals,audio[,modes] --warm=45`:
  - `review_world_r3a_*` (cams `cams_r3a.json`): vp_bund, vp_yanan_deck, vp_dragon, vp_lujiazui,
    vp_nanpu_spiral, vp_flight120, flight120_obl, bund_from_river, lujiazui_from_bund. Sheet
    `r3_sheet_vp_1280.jpg`.
  - `review_world_r3b_*` (`cams_r3b.json`): gantry_yanan, gantry_ns, vms_yanan, nanjing5, nanjing20,
    lot100, spawn_junction, police_lj, charge_nj, gas_pc, toll_w. Sheets `r3_sheet_street.jpg` and
    `r3_sheet_sites.jpg`.
  - `review_world_r3c_*` (`cams_r3c.json`): gantry18, vms18, ground5, sidewalk5, police15, shopsign5. Sheet
    `r3_sheet_close.jpg`.
  - Reference comparison `captures/review/world/r3_ref_compare.jpg`:
    - `05_bund/bund_night_2023.jpg` vs vp_bund;
    - `05_bund/bund_aerial_night_2023.jpg` vs flight120_obl;
    - `09_street_details/nanjing_road_night_2009.jpg` vs drive t2;
    - `06_lujiazui/lujiazui_from_bund_night_2016_01.jpg` vs lujiazui_from_bund.
  - Your own captures `r3_*.jpg` / `r4_*.jpg` (sheet `r3_worker_sheet.jpg`) show the same fallback city.
- Frame statistics (`py/stats.py`; neon = s > 0.5 and v > 0.45):

  | capture | luminance | near-black | neon |
  |---|---|---|---|
  | vp_flight120 | 0.070 | | 0 % |
  | vp_bund | 0.094 | 19.8 % | |
  | police_lj | 0.096 | 23.1 % | |
  | spawn_junction | 0.089 | 30.4 % | |
  | vp_dragon | | | 13.6 % |
  | all others | | | ≤ 3.1 % |

## Not world's (for the lead)
- rivals: `rival_brain.gd:164` parse error (`elapsed`), which breaks `modes/mode_director.gd`.
- props: the toll canopy `Prop_Soffit` emission is 2.0; `guide_sign.glb` has no separate face for text.
- roads: lanes.json lacks forward links on 34 route transitions (#8d); the tiles were re-exported during
  this review.
