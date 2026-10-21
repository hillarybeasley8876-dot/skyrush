# world review round 2 — VERDICT: FAIL

## Scores (0-10): function 4, visual 3, code 4
- function 4: the spawn, the signals, the toll and charge triggers and the water now work, and three tests
  pass. But every landmark is misplaced. 23 of 30 gantries and 12 of 18 VMS boards are deleted. All 5 racing
  lines fall back to straight lines through buildings. Every route has a 1-slot grid. test_drive_lanes FAILS.
  The world build takes 38-52 s against a 15 s target.
- visual 3: up close the Bund and one junction read well (`review_world_r2_junction.jpg`). Everywhere else
  the city fails: the Lujiazui skyline is grey and unrecognisable, the dragon pillar is black, the Nanpu
  bridge is missing from its own viewpoint, the gantry panels are blank white, the 派出所 is a black box, and
  about 95 % of the lamps and 99 % of the trees are gone. The dragon view is 62 % near-black.
- code 4: typing is static and every file is ≤ 400 lines. But there is dead code in 5 files, 6 copies of
  `_centerline`, and a shared material that gets mutated. Five tests cannot fail. Several status claims are
  false (see MUST-FIX 19).

## Lead notes (reviews/world-lead.md)
- W-INT1 spawn: **OK**. The player is on the lane (0.00 m), faces the lane, and the 60 m ray ahead is
  free. The car drives (`captures/review_world_r2c_t6_0.jpg`).
- W-INT2 lenses: **OK**. W-INT3 gas reparenting: **OK** (0 errors; canopy visible in `review_world_r2_gas30.jpg`).
- W-INT4 / W-INT5 perf: **NOT satisfied**, see MUST-FIX 9:
  - there are no per-type visibility ranges;
  - the masts are not chunked per tile;
  - the per-subsystem table at the 6 viewpoints is missing (the status table is one view of main.tscn with
    negative rows).

## MUST-FIX
1. **Every landmark is misplaced, the wrappers are ignored, the floods are missing.**
   `game/world/loader/landmark_manifest.gd:36-38` reads `anchor` as `[x, z]`. Since 05:48 the manifest is
   `[x, y, z]` ("anchor = the node's world position"), so z gets the y value:

   | landmark | manifest anchor | placed at |
   |---|---|---|
   | oriental_pearl | (637.5, 0, -634.9) | (637.5, 0, **0**) |
   | dragon_pillar | (-1299, 0, 687) | (-1299, 0, **0**) |
   | nanpu_bridge | (1330, 0, 1430) | (1330, 0, **0**) |
   | waibaidu_bridge | (-140, 4, -966) | (-140, 0, **4**), on the Bund road |
   | lupu_bridge_far | (-300, 25, 2900) | lost y 25 |

   Evidence:
   - `review_world_r2_vp_nanpu_spiral.jpg` shows no H-tower, although Tower W (1139, 147, 1338) is 172 m dead ahead.
   - In `review_world_r2c_t6_0.jpg` the OPT stands south-east of the car instead of north-east.
   - `review_world_r2_lujiazui_from_bund.jpg` shows a grey generic skyline. Compare it with
     `ref/shanghai/img/06_lujiazui/lujiazui_from_bund_night_2016_01.jpg` in `captures/review/world/r2_ref_compare.jpg`.

   Do:
   - (a) For `size() >= 3` use `Vector3(a[0], a[1], a[2])`; keep `[x, z]` as the fallback.
   - (b) Instantiate `wrapper` when it is set (`jin_mao.tscn`, `swfc.tscn`, `shanghai_tower.tscn`,
     `lujiazui_backdrop.tscn`). The wrapper applies `lujiazui_facade.tres` with each tower's seed.
   - (c) Read the manifest `lights` list (11 entries): find each `empty` prefix (`Flood_Base_`,
     `Flood_Under_Deck`, `Flood_Nanpu_Leg_`, `Flood_Nanpu_Under_`, ...) inside the instance and register
     spots with that colour (#FFC98A, #FFCEA6, #FF8A2A), energy, angle and range.
   - (d) Delete the hard-coded `_dragon_pillar_uplights` (`world_builder.gd:200-206`, literals 16/18/34/72).

   Verify:
   - A test asserts every landmark root is at its manifest anchor (±0.1 m) and that ≥ 11 flood sources exist.
   - Recapture vp_dragon, vp_nanpu_spiral and lujiazui_from_bund (cams in Evidence). Compare them with
     `interchange_night_6658.jpg`, `nanpu_night_2026.jpg` and `lujiazui_from_bund_night_2016_01.jpg`.
2. **The Bund and landmark floods die beyond 60 m.** `light_pool.gd:112` gives spots a real light only
   within `DECAL_DISTANCE` 60 m, so:
   - the Bund is unlit from the river and from Pudong;
   - the dragon pillar uplights are off at the brief's dragon viewpoint (73 m away);
   - `bund_gold.jpg` shows uplight cones only on the 2 lower floors, while `hsbc_customs_night_2026.jpg`
     is gold to the crown.

   Do: give Bund and landmark floods a separate pool (≤ 12 SpotLights, chosen within 600 m, distance_fade
   begin 500 m, length 100 m). Street lamps keep the 60 m rule.

   Verify, in the test:
   - a camera at (-1299, 3, 760) gives ≥ 2 active pillar floods;
   - a camera at (600, 25, -600) gives ≥ 8 active Bund spots.

   Capture from (300, 30, -450) looking at (-160, 30, -450): the Bund façades are gold #E9C98F on #C9B79A.
3. **The furniture filter deletes the gantries and the VMS boards.** `furniture_builder.gd:62` runs
   `_accepts()` before the `INDIVIDUAL_TYPES` branch (:65). A gantry spans the road by definition, so the
   filter rejects:
   - `gantry (on the carriageway) x16` and `(in a junction) x7`, leaving **7 of 30** gantries;
   - `vms x12`, leaving **6 of 18** boards.

   The "外滩 The Bund" gantry at (-661.31, 9.99, 231.16) no longer exists (`review_world_r2_gantry30.jpg`).

   Do:
   - Skip the carriageway and junction tests for gantry and vms.
   - Test only the two posts (±span/2 along the local X axis). If a post is on a lane, slide the gantry
     ≤ 20 m along the road.
   - Two data entries at the same spot get one panel per direction, not two coplanar panels. Example:
     (-1410.92, 12, 70.06) carries both "延安高架右转匝道 WB>NB" and "南北高架右转匝道 NB>EB".

   Verify: print "gantries 30/30, vms 18/18".
4. **The gantry panels are blank white** (`review_world_r2b_gantry_ring.jpg`, `_gantry_ns.jpg`). Five causes:
   - a) **A shared material is mutated.**
     - `_gantry_panel` uses the cached static `ProcMeshes.material("sign_green")` (`furniture_builder.gd:117`).
     - city_sites uses `sign_blue` for both the band and the sign (`city_sites.gd:85,142`) and `sign_green`
       for the carport (:62).
     - `SignFactory._apply` (`sign_factory.gd:51`) writes each texture into that one cached material. Every
       panel shows the last rendered text, and the police band carries the sign texture.

     Fix: create a new StandardMaterial3D per generated texture.
   - b) **BoxMesh UVs are a 3×2 atlas**, so the front face shows 1/3 × 1/2 of the texture. Fix: put a
     QuadMesh face (UV 0..1) 2 cm in front of a plain box.
   - c) **The text is split on spaces** (`sign_factory.gd:87-97`). "延安高架路 Yan'an Elevated Rd" becomes
     the Chinese line "延安高架路 Yan'an Elevated" and the English line "Rd". "外滩 The Bund" becomes
     "外滩 The" / "Bund". Fix: pass the data's `text_en` through. It is dropped by `_build_individual`, and
     `normalise()` also drops `style`.
   - d) **Colour and layout.** Elevated, bridge and ramp roads get green #00704A; surface roads get blue
     #1F57C3. Draw lane arrows, as asked in r1 #15. Give the panel the texture's aspect: the panel is
     13.4 × 2.2 m (6.1:1) but the texture is 2048 × 256 (8:1).
   - e) **Emission.** Emission 0.55 on the whole texture makes the green glow, but GB signs are
     retroreflective. Fix: emission only through the white text and border mask, or ≤ 0.25 overall.

   Verify: captures 30 m before (-1574.7, 12, -709.4), (-191.3, 10, 1678.6) and (-661.3, 10, 231.2).
   Each panel shows its own readable 中文 + English text.
5. **The VMS boards never show a message.** The data has no VMS `text`, and `_generate` skips an empty text
   (`sign_factory.gd:41`), so `_add_vms` never runs (`review_world_r2b_vms_ring.jpg` shows the props' default
   screen).

   Do:
   - Start each board on `VMS_MESSAGES[i % n]`.
   - Draw amber #FFB000 dot-matrix text (a 4 px dot mask) on #101418.
   - Pre-render the 5 messages once and cycle the cached textures; do not create a SubViewport every 8 s.
   - Keep one interval constant: `VmsCycle.INTERVAL` and `SignFactory.VMS_INTERVAL` duplicate each other.

   Verify: timed captures at (-419, 14, 1681) 8 s apart show two different messages.
6. **The streets are stripped bare, and no request was filed with roads** (r1 #18 asked for one).
   test_world_quality's log shows what the filter rejects:
   - lamps: 5,202 + 427 + 22 of 5,950 (≈ 300 placed);
   - trees: 20,180 + 1,385 + 42 of 21,908 (≈ 300 placed);
   - noise walls: 37 of 40.

   My own check (each prop against lanes.json, same level): 20,089 trees and 1,668 lamps sit inside a lane
   (closer than width/2 to its centre), and 3,558 lamps sit within 0.75 m outside the lane edge, on the kerb.
   `LANE_CLEARANCE` 2.2 m rejects those kerb lamps too. Examples:
   - yanan_rd_surface trees at ±7.8 m from the centre ((-1615.85, 745.23), (-1610.21, 729.65)), where the
     carriageway half-width is 0.5 + 3 × 3.75 = 11.75 m;
   - g50_west lamps at z 720.38 / 735.62.

   Result: `review_world_r2_street_trees.jpg` and `_vp_bund.jpg` show no tree rows and almost no lit lamps.

   Do:
   - (a) Add the request to roads in `status/world.md` with these numbers.
   - (b) Relocate instead of deleting. Push a sidewalk prop that falls on its own road's carriageway out to
     the half-width + shoulder + 1.0 m on its side. Drop it only when the new spot is on another lane, a
     junction, a site or under a deck.
   - (c) Accept a lamp whose distance to the lane centre is ≥ width/2 + 0.3 m.
   - (d) Pick the glb from the data:
     - `mount: median, arms: 2` (702 lamps) → `lamp_deck_double.glb` (today 1 arm is drawn but 2 lights are registered);
     - road `style.lamps` "magnolia" (yanan_rd_surface and 7 more roads) → `lamp_magnolia.glb`;
     - "heritage" → `lamp_heritage.glb`.

   Verify: ≥ 90 % of the lamps and trees are placed, the check "0 on the carriageway" still passes, and the
   placements are printed per glb. Capture (-1615, 2, 737) looking at (-1500, 3, 730): a tree row with
   magnolia lamps. Compare `yanan_elev_east_of_henan_2025.jpg`.
7. **No street dressing.** Brief §3 asks for "planters, lamps, trees, bins, bollards", and ART §6 asks for
   scale cues. The props unit ships `bin`, `bollard`, `bike_share`, `e_scooter`, `hydrant`,
   `planter_pot_privet/bougainvillea`, `cone`, `crowd_barrier`, `metro_entrance`, `neon_blade_frame`,
   `hologram_projector` and `guide_sign`. None of them is placed.

   Do: a seeded sidewalk dresser for surface roads with a sidewalk ≥ 2.5 m, using these rates:

   | prop | rate |
   |---|---|
   | bins | 2 per 100 m |
   | bollards | 4-6 per junction corner |
   | bike-share rack or e-scooter group | 1 per 150 m |
   | hydrant | 1 per 120 m |
   | planter pots | on the Bund promenade and Nanjing Rd |
   | metro entrance | 3-4 near POIs |
   | neon_blade_frame | 1 per 25-40 m on `st_*` shop streets, Chinese parody names (ART §7) |

   All of them as MultiMesh per type per 512 m tile, culled by visibility range.

   Verify: counts per type are printed. 5 m and 20 m captures on st_nanjing_e_rd show bins, bikes, bollards
   and blade signs, with neon ≤ 15 % of the frame.
8. **The build takes 38-52 s against a 15 s target.** The status says the world's own work is "under a
   second"; that is false. The cumulative phase prints of my test_world_quality run give these durations:

   | phase | s |
   |---|---|
   | terrain | 2.6 |
   | roads | 9.7 |
   | blocks + landmarks | 3.5 |
   | lights + lanes + furniture | **15.1** |
   | signals | 1.0 |
   | probes + sites + sky lanes | **5.2** |

   The full test_world_api build was 51.9 s.

   Do:
   - Profile `_build_lanes` (LaneGraph + LaneLinks over 8,397 lanes) and FurnitureFilter, which calls
     `curve.get_closest_offset` per candidate lane per prop. Replace that with a 4 m grid of 2D segments.
   - Print per-phase durations, not cumulative ones.
   - Build in phases with `await get_tree().process_frame` and emit `Events.loading_progress` per phase.
     It is still synchronous in `_ready` (r1 SHOULD-FIX 5).

   Verify: the world-owned phases take ≤ 3 s together on this machine; print the table.
9. **Performance (lead W-INT4/W-INT5, mandatory).** My probe, environment + world only, fixed cameras at
   1920×1080 (`tmp/review/world/perf_r2.gd`, log `r2_perf2.log`):

   | view | draws | objects | prims |
   |---|---|---|---|
   | bund | 208 | 208 | 0.99 M |
   | yanan_deck | 551 | **1,710** | 0.94 M |
   | dragon | **605** | 632 | **1.44 M** |
   | lujiazui | 307 | 748 | 0.58 M |
   | nanpu | 178 | 297 | 0.67 M |
   | flight120 | 72 | 72 | 0.51 M |

   Fps was 54-107 with the machine at load 25-30. Do:
   - a) `furniture_builder.gd:13` `TILE := 1024.0` → 512 (r1 #18a; the file header already says 512).
   - b) `:15` uses one `VISIBILITY_END` of 500 m. Use per type: lamps 600, trees 350, bus stops 250,
     bins/bollards 120, signs 200 (W-INT5).
   - c) `mesh_merger.gd:23/41` `add_surface_from_arrays` drops the imported LODs; the status claim "the
     imported LODs stay" is false. Furniture costs 0.05-0.21 M prims at LOD0 out to 500 m. Merge through
     `ImporterMesh` + `generate_lods()`, then `get_mesh()`.
   - d) The masts are one city-wide MultiMesh: MastBodies 147,960 prims + 3 × 28,080 lens prims, i.e.
     0.23 M prims and 8 draws at every view, Nanpu and Lujiazui included. Chunk per 512 m tile with
     visibility ranges of 400 m (bodies) and 600 m (lenses).
   - e) SkyLanes holds 1,790 MeshInstance3D (each ring gate is a full glb), which is 1,225 objects and
     88 draws at yanan_deck. Make them a MultiMesh per gate part per lane.
   - f) `probe_placer.gd:85-90` hides all 1,106 probes and then shows 4, every 0.5 s. Toggle only the
     probes whose state changes, look them up through a grid, and measure the probe cost (brief §4).
   - g) Replace the status perf table: it has negative rows (Terrain −80, Landmarks −55) and covers one
     main.tscn view with moving traffic. Give a per-group table at the 6 brief viewpoints from fixed
     cameras, the way perf_r2.gd does.

   Verify: at every viewpoint the world stays ≤ 450 draws, ≤ 1,200 objects and ≤ 1.0 M prims.
10. **All 5 racing lines are unusable.** My probe sampled every 10 m and counted samples > 4 m from any lane:

    | route | off lane | reversals |
    |---|---|---|
    | bund_sprint | 111/167 | 1 |
    | elevated_sprint | 385/519 | 1 |
    | grand_loop | 1,437/2,159 | 8 |
    | lujiazui_ring | 101/257 | 0 |
    | river_loop | 1,073/1,533 | 3 |

    The rivals would drive through buildings. Causes:
    - one failing leg returns `_gate_line` for the whole route (`route_builder.gd:116`);
    - the start lane must match the gate −Z;
    - a leg that doubles back on a lane is dropped.

    Do:
    - Fall back per leg only.
    - Run a multi-source / multi-target Dijkstra: candidates are all lanes within 8 m of a gate with
      tangent·(gate −Z) > 0.3.
    - When the gate projection lies past the exit, start the leg on the next lane.
    - Report the unroutable legs, with gate indices, as a request to city_layout.

    Verify: test_world_api FAILS (not INFO, see #14) when a route has < 95 % of samples within 2 m of a
    lane or any reversal. The per-route numbers are printed.
11. **Every route has a one-slot start grid.** city.json gives one `grid` anchor `[x, y, z, h]` and
    `_grid()` (`route_builder.gd:63`) keeps exactly one slot, so `get_spawn_transform(&"rival", i)` puts all
    5 rivals on one spot. `_on_road` (:91) also keeps the raw transform (y 0, bund_sprint heading 90° on a
    N-S road) unless it is more than 6 m off a lane.

    Do:
    - Expand the anchor to ≥ 6 slots: 2 columns on adjacent same-direction lanes × 3 rows, 8 m apart,
      behind the start line.
    - Snap every slot to a lane centre + 0.6 m, facing the tangent, with a 6 m clear check.

    Verify: a test asserts ≥ 6 slots per route, ≥ 5 m apart, ≤ 0.3 m from a lane, heading error ≤ 5°.
12. **test_drive_lanes FAILS 1 of 17.** The failing check is "lane ramp_rt_sb_wb: a dropped body rests on
    the road (y 21.66 vs 19.71)" (`tmp/review/world/r2_test_drive_lanes.log`). The status says PASS all 17.

    Do:
    - Print the collider the body lands on, so you can tell a world-owned body (sky lane gate, gantry,
      sign) from the roads deck.
    - Fix a world-owned cause. File a roads cause as a request with the lane id and the 1.95 m offset.
    - Make `_lane_transform` and the spawns robust to this: ray down from lane y + 4 m to y − 4 m (mask 1)
      and place the car at hit + 0.6 m. "Never trust raw coordinates" applies to heights too.

    Verify: the test passes. A new check takes 200 random lane points and finds every
    `nearest_road_transform` 0.4-0.8 m above the collision.
13. **The world's own engine errors go uncounted.** In test_drive_lanes the engine logs 13 × `Parameter "t"
    is null` (`texture_2d_get`, called from `sign_factory.gd:122` `get_image()` on the headless renderer),
    and 2 more in test_gameplay_sites. Both tests still print "no engine errors during the run (0)".
    `world_error_counter.gd:13` counts an error only when `file` starts with res://world/.

    Do:
    - Count an error when `file` OR any frame of `_script_backtraces` is under res://world/.
    - Skip the SubViewport render when `DisplayServer.get_name() == "headless"`.

    Verify: `grep -c 'Parameter "t"'` prints 0 for all 4 test logs.
14. **Five tests cannot fail.** These are the r1 verification steps that are still missing:
    - Racing lines: INFO + return (`test_world_api.gd:320-328`), so the line checks run for 0 of 5 routes.
      Also `var circuit := String(route.id) != ""` is always true.
    - Light pools: "0 of 0 active light pools float". Put the camera 60-130 m from lamps, wait 0.3 s and
      require ≥ 10 active decals, all touching the ground.
    - Probes: "0 reflection probes are enabled". Add a camera, wait 0.6 s, and require 1-4 enabled within 400 m.
    - Breaker: only "pursuit breaker built". Drive a VehicleBase into a `Support_*` at 70 km/h and assert:
      the collapse completes within 1.2 s of the hit, a police car in the 25 × 12 m zone gets `wreck()`,
      and `Events.stunt(&"breaker", 500, ...)` fires (r1 #13).
    - Toll: one pass only. Run two passes 6 s apart and expect 2 infractions; a hit arm on layer 5 rests
      at y ≥ 0 within 3 s (r1 #14).

    Verify: each check prints its numbers. Disable each feature once and see its check fail.
15. **The procedural sites are grey boxes with stretched textures.** The 派出所 is an 18 × 9 × 12 m BoxMesh
    with concrete_wall_008 tinted "tile_white". BoxMesh UVs give it ≈ 38 px/m; ART §5 asks ≥ 512 px/m.

    Captures:
    - In `review_world_r2_vp_bund.jpg` (left) it reads as a black box with a white band.
    - `_police6.jpg` shows a flat brown wall and a blown-out white area.

    Other problems:
    - `proc_meshes.gd`: "glass_dark", "metal" and "sign_*" use the concrete albedo; "foliage" has no albedo.
    - The parking bays emit light (glow 0.25).
    - Both stations say 外滩派出所; police_lujiazui should read 陆家嘴派出所 (use the POI label).
    - The carport sign says 地下车库, but the carport is open.
    - The Bund station at (-160, 0, -520) sits inside the Bund building row.

    Do:
    - Use world-space triplanar UVs in `ProcMeshes._pbr` (`uv1_triplanar`, `uv1_world_triplanar`,
      `uv1_scale = 1 / tile_m`) with matched library sets:
      - walls: granite_tile_03 or Facade009 + Leaking004 streaks;
      - metal: albedo #2B2E33, metallic 1, Plastic006 / SurfaceImperfections001 roughness;
      - glass: albedo #0B0F14, roughness 0.05 + SurfaceImperfections001.
    - Paint the bays with non-emissive #E8E8E0.
    - Shape-query each site against the blocks and the Bund (layer 1). Shift it out of overlaps, or file
      the POI with city_layout.

    Verify: 5 m and 20 m captures of each station show the texture grain and readable text, with no
    blown-out area.
16. **The breakers are badly placed, and the roadblock stunt gates are missing.**
    - `breaker_sites.gd` sets no yaw. Billboards and scaffolds stand 16 m from the centreline whatever the
      road width, with no check against blocks or junctions. The 25 × 12 m police zone points in a fixed
      world direction.
    - `_build_breakers` (:62-93) is a dead copy of `build()`.
    - Brief §5 asks for StuntGates over the roadblock sites (飞跃路障); there are none.
    - The roadblock transforms come raw from city.json.

    Do:
    - Face each breaker to the road, at half-width + sidewalk + 1 m, and reject spots inside blocks.
    - Delete the dead copy.
    - Add a StuntGate per roadblock site, snapped to the lane.

    Verify: a test counts 1 gate per roadblock site. Capture 2 breakers.
17. **Code rules (CONTRACTS §3, global rules).**
    - Dead code:
      - `furniture_builder.gd` `_centerline/_point_at/_index_at`;
      - `world_builder.gd` `_color`;
      - `gameplay_sites.gd` `BILLBOARD_GLB/SCAFFOLD_GLB/BREAKER_*/MAX_*`, `PropLibrary`, `_centerline`;
      - `world.gd` `LOOK_AHEAD`, unused while `_lane_transform` uses the literals 4.0 and 0.6.
    - `_centerline` is copied in 6 files (breaker_sites, furniture_builder, gameplay_sites, road_furniture,
      signal_controller, probe_placer) and `_point_at` in 3. Move them into `api/spline_util.gd`.
    - Magic numbers remain in logic:
      - toll_plaza.gd: mass 12.0, −78°, 18.0;
      - world_builder.gd: 16/18/34/72;
      - route_builder.gd: `gate_width 24.0`;
      - gameplay_sites.gd: toll gate `Vector3(20, 4, 56)`;
      - world.gd: `for step in 64`.
    - Stale comments: the prop_library.gd header ("each part becomes one MultiMesh"), furniture_filter.gd
      ("1,527 of the 11,247 trees"), and the duplicated comment block at asset_library.gd:86-90.
    - `KIND_ALIASES` still overlaps `GLB_FOR_KIND`.

    Verify: `grep -rn "func _centerline" game/world` finds 1 hit; check reports 0 warnings.
18. **Roads still disappear beyond 400 m** (r1 #8b, not fixed). Roads have 63 glbs and 0 `_far`, but
    `asset_library.gd:84` sets `visibility_range_end = 400` on every near tile.

    Do: set the 400 m end only on tiles that have a `_far` sibling.

    Verify: a capture from (150, 120, -350) looking at (900, 0, -500) shows the road network out to ≥ 1.5 km.
19. **The status claims numbers that are false today.** Re-measure every number in `status/world.md`
    from this round's runs. False claims:
    - "the imported LODs stay";
    - "world unit's own work … under a second";
    - "the landmark glbs are at the anchors of the manifest";
    - "test_drive_lanes PASS all 17";
    - "0 engine errors";
    - "268 probes" (now 1,106).

    Add the requests:
    - roads: #6, and #12 if the cause is theirs;
    - city_layout: the gates (#10), the overlapping police POI (#15), and the duplicate junctions at one
      point, e.g. `j_st_beijing_e_rd_bund_zhongshan_e1` and `j_bund_zhongshan_e1_st_beijing_e_rd` at
      (-128, -703), which give two sets of masts.

## SHOULD-FIX
1. Breaker collapse:
   - today it waits 1.2 s, tweens for another 1.2 s, and checks for police once;
   - the brief means a 1.2 s collapse after the hit;
   - SPEC pillar 5 asks for rigid-body pieces, not a tween.
2. Reflection probes: 1,106 nodes for ≤ 4 active. Keep them in a grid; consider capping at 1 per 300 m on
   surface streets.
3. The ground uses SH_wet_asphalt (albedo_mul 0.42) for all land, so land and road share one value. Use
   concrete_pavement or PavingStones144 for the land around roads (ART §2: a mid-value step).
4. Lens shader (`mast_batch.gd`): a flat ALBEDO. Add a Fresnel-lens texture and a darker hood for close range.
5. Decal search radius 130 m (`light_pool.gd:22`) against the dossier's 200 + 50 m fade (§3.7.1).
6. The scratch logs `tmp/world/{cap.log,cap2.log,perf.log}` are left behind. Lead rule: delete scratch
   when done, and keep evidence in status.

## Verified OK
- `tools/godot.sh check --only=res://world/` → `CHECK 55 files, 0 failed, 0 engine errors, 0 warnings`.
- Tests: test_world_api `PASS all 497 checks`, test_gameplay_sites `PASS all 18`, test_world_quality
  `PASS all 12`. Caveat: several of these checks are vacuous (#14).
- W-INT1 spawn (reviewer probe):
  - player at (-126.8, 0.6, -309.8), fwd (0.17, 0, 0.99) along Zhongshan E1, 0.00 m from the lane, no hit
    in 60 m ahead;
  - police on the lane (0.02 m);
  - the car accelerates away at t = 6 s.
- W-INT2: 3 lens batches, ≤ 1 lit lens per mast. The junction capture shows one red lens per head.
- W-INT3: 0 reparent errors; the gas glb canopy, pumps and store are visible.
- Water: 50/50 rays hit −3.0 m and 40 land rays hit land (0 wrong). The kill floor exists.
- `nearest_road_transform` takes 0.46-0.55 ms (spatial index) and picks the deck at (-1299, 20, 700) → y 21.8.
- Light pool: 32 omni + 12 spot + 48 decals; reassignment 0.00 ms (spatial hash). Bund lights are read in
  Godot axes.
- 1,966 occluders from the block sidecars. Charge trigger 40 × 18 m from the glb extras.
- The toll plaza is built from the props glb, with ETC / 人工 booths and red X lane lights (`review_world_r2b_ground5.jpg`).
- 35 POIs, 274 minimap polylines, 4 roadblocks; headings go through `api/heading.gd`.
- Files ≤ 400 lines (max world.gd 370); static typing throughout.
- Ownership: the job log (`jobs/world/log.jsonl`) shows Write/Edit only under game/world/** and
  status/world.md. Bash writes go only to game/world/**, tmp/world/** and captures/; the `_probe_*` scratch
  tests were deleted.
- 0 world errors in my 4 runs of main.tscn (`grep -c res://world` = 0).

## Evidence
Machine load was 20-32 during all runs (other units busy). Logs are in `tmp/review/world/`.
- `tools/godot.sh check --only=res://world/` → 0 failed (r2_check.log).
- Tests:

  | test | result | time | notes |
  |---|---|---|---|
  | test_world_api | PASS 497 | real 80 s | `[world] built in 21.66 s (19 lanes)` (test_city) and `built in 51.92 s (8397 lanes, 5 routes)`; 5 × `INFO route … falls back` |
  | test_drive_lanes | `FAIL 1 of 17` | real 130 s | `FAIL lane ramp_rt_sb_wb: a dropped body rests on the road (y 21.66 vs 19.71)`; 13 × `Parameter "t" is null` at sign_factory.gd:122 |
  | test_gameplay_sites | PASS 18 | real 64 s | |
  | test_world_quality | PASS 12 | real 195 s | furniture-rejected counts (#6); phases terrain 2.61 / roads 12.31 / blocks 15.81 / furniture 30.91 / signals 31.94 / sites 37.18 s |

- Reviewer probe: `tools/godot.sh test /Users/minimax/m/skyrush/tmp/review/world/probe_r2.gd`, log
  `r2_probe.log`. It gives the spawns, nearest-road timings, the racing-line table (#10), `ReflectionProbe
  1106, MultiMeshInstance3D 81, MeshInstance3D 7362, OccluderInstance3D 1966` and `furniture 7070 placed`.
- Perf: `python3 tools/slots.py heavy 4 -- godot --path game --windowed --resolution 1920x1080 -s
  tmp/review/world/perf_r2.gd`; logs `r2_perf.log` and `r2_perf2.log` (table in #9).
- Independent data checks (python over lanes.json, road_furniture.json and city.json):
  - furniture inside lanes (#6);
  - gates without an aligned lane;
  - a near-duplicate junction id;
  - the manifest anchor format (#1).
- Captures were run through the heavy slot directly, because `tools/godot.sh shot` waited 20+ min on the
  import queue. Options: `--skip-menu --stub=vehicle,camera,menu,police,hud`. The menu title stage
  overrides static cams unless menu is stubbed; my first attempt gave 6 identical frames.
  - `captures/review_world_r2_vp_{bund,yanan_deck,dragon,lujiazui,nanpu_spiral,flight120}.jpg`; sheet `review/world/r2_sheet_vp.jpg`.
  - Six viewpoints (cams):

    | name | camera | look-at |
    |---|---|---|
    | bund | -140,3,-500 | -120,3,-700 |
    | yanan_deck | -500,16,190 | -300,11,200 |
    | dragon | -1299,3,760 | -1299,14,687 |
    | lujiazui | 600,25,-600 | 900,60,-400 |
    | nanpu_spiral | 981,46,1271 | 1330,40,1420 |
    | flight120 | 150,120,-350 | 100,0,-400 |

  - Details:
    - `captures/review_world_r2_{gantry30,police22,police6,charge30,gas30,toll40}.jpg` (`r2_sheet_sites.jpg`);
    - `..._{hide20,junction,street5,bund_gold,lujiazui_from_bund,street_trees}.jpg` (`r2_sheet_street.jpg`);
    - `captures/review_world_r2b_{gantry_ring,gantry_ns,vms_ring,ground5,ground20,bund_lamps}.jpg` (`r2_sheet_signs.jpg`).
  - In-game run with real car and camera, `--times=1.5,6 --press=accelerate`: `review_world_r2c_t1_5.jpg`,
    `_t6_0.jpg` (`r2_sheet_ingame.jpg`).
  - Reference comparison `captures/review/world/r2_ref_compare.jpg`, reference | ours:
    - `hsbc_customs_night_2026.jpg` | bund_gold;
    - `lujiazui_from_bund_night_2016_01.jpg` | lujiazui_from_bund;
    - `interchange_night_6658.jpg` | vp_dragon.
- Frame statistics (PIL; neon = s > 0.5 and v > 0.45):

  | capture | neon | mean luminance | near-black |
  |---|---|---|---|
  | bund | 1.1 % | 0.140 | |
  | yanan_deck | 0.8 % | 0.154 | |
  | dragon | 1.7 % | **0.047** | **62 %** |
  | lujiazui | 0.6 % | 0.121 | |
  | flight120 | 0.1 % | 0.085 | |
  | bund_gold | 8.9 % | 0.208 | |

**ART §10 checklist** (these captures):
1. Value: the dragon and flight frames are near-void; the car stands out only because the street is empty.
2. Palette: neon ≤ 2 % in 5 of 6 views, so there is no cyberpunk layer; the Pudong skyline is grey, not cyan.
3. Detail at 5/20/100 m: the roads unit's asphalt reads well at 5-20 m. The world's own boxes are ≈ 38 px/m,
   the signs are blank, and the far skyline is generic.
4. Tiling is not visible on the roads.
5. Scale: the 派出所 sits inside the Bund row; billboards are not oriented.
6. Emissives: blown-out white at police6; the toll lane strips are near clipping.
7. Shanghai is recognisable only at the Bund up close; the skyline, dragon pillar and Nanpu bridge are
   misplaced or missing (#1).
8. Bevels: n/a.
9. The Nanpu bridge is missing at its viewpoint; landmarks are displaced.
10. Store screenshot: only `review_world_r2_junction.jpg` comes close.

**Not world's (for the lead):**
- traffic: `res://ai/traffic/traffic_car.gd` parse error (`_stopped`), 1,222 × `rp_child` null.
- police: `police_drone.glb` misses its webp textures.
- hud: `minimap_panel.gd:309` "Icons" is not declared.
- shaders: `concrete_stained.gdshader` had `const float X := …`, fixed while I ran.
- buildings: the faceted blob trees (`Foliage_Dark`); a tower intersects the inner-ring deck
  (`review_world_r2b_gantry_ring.jpg`).
- roads: lanes.json and road_furniture.json disagree (#6).
