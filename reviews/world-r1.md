# world review round 1 — VERDICT: FAIL

## Scores (0-10): function 3, visual 2, code 5
- function 3: every subsystem exists and the 3 tests pass, but the race lines are unusable, all city.json headings
  are mirrored, the river has an invisible floor, gas stations are missing, the signals light the wrong lenses, and
  the toll infraction fires once per session.
- visual 2: from the Bund you see no Lujiazui skyline (culled at 400 m), the Bund has no gold floodlight (all 144
  Bund lights are placed underground), there are no light pools, gantries carry no text and stand along the road,
  trees stand in the middle of junctions, the police station is a grey box, and the ground reads as a black void.
- code 5: typed and modular, but furniture_builder.gd has 414 lines (limit 400), there are hundreds of engine
  errors per run, unique materials break batching, logic is full of magic numbers, and the tests pass even when the
  checks are trivial or forced.

## MUST-FIX
Lead notes `reviews/world-lead.md` W-INT1..4 are items 1-4 and are mandatory. Verify every item with a test or a
probe; quote the numbers in status/world.md.

1. **W-INT1: player spawn.** `get_spawn_transform(&"player",0)` returns the raw city.json point
   (-123.5, 0.0, -300.5) facing (-1,0,0) (my probe B). It only snaps when the point is more than 6 m off a lane, it
   keeps the mirrored heading (item 5) and y = 0.0 (inside the road). In the lead's run the car sat against a
   façade and could not move. In mine it did not move in 4 s with accelerate held, with a police car 5 m ahead
   (`captures/review_world_r1c_t1_0.jpg`, `_t5_0.jpg`; I did not isolate the cause, so fix the spawn and re-test).
   Do: always snap to the closest lane centre, face the lane tangent, lift by `_lane_transform`'s 0.6 m, and walk
   forward along the lane until ≥ 30 m are clear (ShapeCast3D box 2.2×1.4×30 m against layers 1|3). Apply the same
   rule to police/rival/traffic spawns.
   Verify: new test check "player spawn: on lane (≤0.3 m), heading error ≤5°, free ahead ≥30 m".
2. **W-INT2: signal lenses.** `traffic_light_prop.gd:88` fails with "Out of bounds get index '3'" (464 errors in
   test_world_api, 1,380 in a 20 s game run). The glb has 6 `Lens_*` meshes in this order: Lens_A, Lens_A_Visor,
   Lens_G, Lens_G_Visor, Lens_R, Lens_R_Visor, and the code switches them by index. Result (probe B, lit lenses):
   Lens_R 920/920 masts always lit, Lens_R_Visor 920 lit, and the middle lens lights in red. The red and green
   lenses glow at the same time (`captures/review/world/r1_signal_1280.jpg`, left mast).
   Do: map lenses by exact name `Lens_R`/`Lens_A`/`Lens_G` (skip `*_Visor`) to states 0/1/2. Keep the glb's lens
   colours and do not overwrite albedo. Do not duplicate materials per mast (see item 4). Use one shared material
   per lens state or an instance uniform.
   Verify: probe shows that for every mast exactly one of R/A/G has emission > 0 and that it matches
   `signal_state()`. Add this check to test_gameplay_sites.
3. **W-INT3: the gas stations are invisible.** `gameplay_sites.gd:158` does `canopy.add_child(child)` while the
   child still belongs to the glb root. This causes 321 "Can't add child ... already has a parent 'gas_station'"
   errors per build. The glb is never added to the tree, so GasStation_gas_sinopex/petrochino have 0 meshes (probe
   A) and `captures/review_world_r1_gas.jpg` shows an empty plot. The pursuit breaker finds no `Support_*`, so the
   gas breaker is dead.
   Do: add the whole glb instance under the station root once and pass the glb's canopy node (the parent of the
   `Support_*` nodes) to `breaker.setup()`. No reparenting.
   Verify: 0 add_child errors; each station has ≥100 meshes and 6 supports registered; capture at (-1855,14,760)
   shows the 中石华 canopy.
4. **W-INT4: performance.** The lead measured 7-11 fps at the Bund with ≈4,964 draws and 10,749 objects. My
   world-only probe (`tmp/review/world/perf_c.gd`, fixed camera, environment loaded, 1080p):
   yanan_deck 3,859 draws / 8,781 objects / 46 fps, with Signals = 2,854 draws and 7,285 objects (920 masts × 16
   MeshInstances from traffic_light_mast.glb, unique lens materials), gantry/VMS parts 436 draws (`.duplicate()` per part), sites 419.
   dragon has 2,201 draws and lujiazui 2,319. Budget (GODOT.md §5): ≤600 draws (target 300), ≤2,000 objects,
   ≤3 M tris.
   Do:
   - Build the masts as MultiMesh: one MMI per mast part per tile, with lens state through per-instance colour or
     custom data.
   - Share materials across gantry/VMS parts and pass sign text through per-instance textures only on the panel.
   - Put signals only at junctions where `signals` is true and the junction is at grade (no masts on elevated
     junctions).
   - Group the 1,473 direct world children under ≈10 parents (Furniture, Signals, Sites, Signs, Lighting, ...).
     Today the core `tools/perf_probe.gd` iterates them one by one and timed out after 500 s.
   Verify: `tools/godot.sh perf` (core tool) per-subsystem table at the 6 viewpoints in status/world.md, world
   total ≤ 600 draws and ≤ 2,000 objects at each.
5. **All city.json headings are mirrored.** SCHEMA: `heading_deg 0 = north (−Z), 90 = east (+X)`. Every
   conversion uses `Basis(Vector3.UP, deg_to_rad(h))` or `rotation.y = deg_to_rad(h)`, which gives forward
   = (−sin h, 0, −cos h), so 90° points WEST. This applies at world.gd:243, route_builder.gd:66,
   gameplay_sites.gd:50/146/264/286/328, toll_plaza.gd:35, sky_lane_builder.gd:56/124,
   furniture_builder.gd:369-377, and world_builder.gd:143.
   Effects:
   - Checkpoint gates face backwards for E/W headings (elevated_sprint cp0 heading 90 has bearing 89.6° to the
     next checkpoint).
   - Gantries are rotated by about 103° and run along the road (`captures/review/world/r1_gantry_a_1280.jpg`).
   - Sites and pads are mirrored.
   - sky_lane_builder.gd:120 `backward = (-cos h, 0, sin h)` is also wrong; it must be (−sin h, 0, cos h).
   Do: one static helper (e.g. `api/heading.gd`: `yaw_from_heading(h) = -deg_to_rad(h)`) used everywhere.
   Verify: test that for every checkpoint i of all 5 routes `(-cp[i].basis.z).dot(cp[i+1].origin - cp[i].origin) > 0`,
   and that the player spawn forward is (+1,0,0) for heading 90.
6. **Racing lines are garbage** (probe B, 10 m samples):
   bund_sprint 18,200 m line for 6 checkpoints, 64 reversals, 236/1,821 samples > 4 m off any lane, longest
   straight segment 1,676 m (forced closure of a sprint); elevated_sprint 103,750 m / 251 reversals; grand_loop
   133,656 m / 336; lujiazui_ring 52,752 m / 195; river_loop 97,704 m / 217.
   Causes (route_builder.gd:94-165):
   - Whole lanes are appended from offset 0.
   - `_nearest_lane(..., exclude=current)` jumps to any lane, including the oncoming one.
   - The line is always closed with a straight segment.
   Do: shortest path (Dijkstra/A*) over `next_lanes`. Start at the lane nearest checkpoint i whose tangent agrees
   with the gate −Z (dot > 0.7), slice each lane from entry offset to exit offset, and stop at the lane nearest
   checkpoint i+1. Close the loop (by path back to cp0) only when the route is a circuit, i.e. city.json
   `kind` is "race" or laps > 1. The current "closed (gap 0.0 m)" test passes only because the code forces it.
   Verify, in test_world_api for all 5 routes:
   - line length ≤ 1.3 × polyline length through the checkpoints
   - 0 reversals (5 m steps, dot < −0.5)
   - ≥ 98 % of samples ≤ 2 m from a lane centre
   - sprints not closed
7. **Invisible floor over the river.** `terrain_builder.gd` GroundBody is one BoxShape3D over the whole window, top
   at y −0.02. Rays inside the Huangpu at (80,−300), (300,200) and (200,−900) hit `GroundBody` at y −0.02, not the
   water at −3 (probe A). Cars drive across the river on air. In addition, the 100 m cells are kept or dropped by
   their centre, which leaves stair-step overlaps and holes along every bank.
   Do: clip each land cell against the water polygons (`Geometry2D.clip_polygons` / `intersect_polygons`) and use
   the same clipped triangles for the render mesh and the collision (ConcavePolygonShape3D with backface
   collision). The ground then meets the bank walls exactly.
   Verify: probe with 50 random rays inside each water body that all hit y −3 (WaterBody), and 50 on land that hit
   ≥ −0.05.
8. **Landmarks: wrong placement and culled at 400 m.**
   a) Use `res://assets/landmarks/landmarks_manifest.json` (the landmarks unit's placement contract: anchor [x,z],
   rotation_y), not the hard-coded table in `landmark_anchors.gd`. Current (probe A):
   | glb | current | manifest |
   |---|---|---|
   | pearl_ring | (0,0,0) | (748, −488.8) |
   | lujiazui_backdrop (12 towers 150-260 m) | (0,0,0) | (748, −488.8) |
   | nanpu_bridge | y 45.5, rot 0 (deck ≈ 91 m, `captures/review_world_r1_nanpu.jpg`) | y 0, rot −2.0203 |
   | waibaidu_bridge | rot 0 | rot −0.1456 |
   | lupu_bridge_far | never loaded (`instantiate_dir` skips `*_far`) | (−300, 2900), rot −1.5708 |
   b) `prepare_instance()` sets `visibility_range_end = 400` on every landmark and Bund mesh. OPT (468 m), Jin Mao,
   SWFC and Shanghai Tower (632 m) are therefore invisible from the Bund. See
   `captures/review/world/r1_ref_compare.jpg`: `lujiazui_from_bund_night_2016_01.jpg` next to our empty horizon.
   They are also invisible from Lujiazui itself (`captures/review_world_r1_lujiazui.jpg` shows only sky).
   Landmarks get no range limit (or their own `_far` LOD). Put the 400 m end only on tiles that have a `_far`
   proxy: today roads have 61 tiles and 0 `_far`, and 3 block tiles have none. That is why flight120 draws only 60
   calls of mostly nothing.
   Verify: bund_east capture shows the 4 towers; flight120 shows the road network to ≥ 1.5 km.
9. **Bund floodlights are underground.** `bund_lights.json` positions are [x, y, z], e.g. Crown_CustomsHouse
   [−152.19, 77.7, −326.18]. `world_builder.gd:_add_bund_light` swizzles them to (x, z, y), so all 144 spots sit
   20-1,080 m below ground. The Bund façades are pale grey instead of gold #E9C98F on #C9B79A (compare
   `ref/shanghai/img/05_bund/hsbc_customs_night_2026.jpg` in r1_ref_compare.jpg). The direction is swizzled the
   same way, and the per-light `angle` (55°/48°) is ignored because the pool spots are fixed at 45°.
   Do: use position/direction as given; pass angle/energy/range per source and set `spot_angle` in `_apply_spot`.
   Verify: probe at (−140,3,−500) shows 12 active spots with 0 < y < 80; the capture shows gold façades.
10. **Light-pool decals never touch the road.** The sources sit at the lamp head (offset y 8.6 m), and the decal
   box is 6 m tall (±3 m), so 48 of 48 active decals end ≥ 2.6 m above the surface (probe B).
   Do: store a ground point per lamp at build time (ray down once, or use the lamp base y), centre the decal there,
   and use decals only for lamps beyond 60 m (dossier §3.7).
   Verify: probe reports 0 floating decals; a capture at 60-200 m shows pools on the asphalt.
11. **Light pool hitch.** There are 3,678 sources, and every 0.25 s they are `duplicate()`d and sorted with a
   GDScript lambda: one `_reassign()` takes 22.9 ms (probe B), which is a frame spike 4 times per second.
   Do: a spatial hash (64 m cells), gather sources within 120 m, partial-select the nearest 32+12, and the next 48
   for decals.
   Verify: print `_reassign` time in a test, ≤ 1.0 ms with the real city.
12. **Charge stations: wrong trigger and double geometry.** glTF extras arrive as meta `"extras"` (probe C:
   ChargeArea extras = {"charge_area_centre": [0,0,1.2], "charge_area_size": [40,18,2.4]}).
   `_meta_size` reads `get_meta("size", null)`, which prints "does not have any 'meta' values with the key
   'size'" and falls back. The triggers end up 80×80 m and 50×40 m from the POI size, and the procedural canopy is
   built on top of the glb (134 meshes = 129 glb + 5 procedural). `captures/review/world/r1_charge_1280.jpg` shows
   the dark slab over the road with trees through it.
   Do: read `get_meta("extras", {})` and convert Blender axes: size [x, y, z] maps to Godot (x, z, y) and
   centre [x, y, z] maps to (x, z, −y). Never build the procedural visual when the glb exists.
   Verify: probe shows ChargeArea box ≈ (40, ≥2.4, 18), meshes = 129, and 0 get_meta errors.
13. **Pursuit breakers.** Only the gas canopy has one (dead, item 3). The brief §5 also requires billboard and
   scaffold breakers. `billboard_pole.glb` (Support_1/2) and `scaffold.glb` already exist in
   `assets/props/street/`. Place them at the city's breaker sites (or at POIs you add next to roads, with a
   request to city_layout) and use their supports. Use the same 25 × 12 m zone, ≥ 60 km/h, 1.2 s collapse, and
   `Events.stunt(&"breaker", 500, ...)` with a label per kind (广告牌倒塌! / 脚手架倒塌!).
   Verify: test hits a Support at 70 km/h; the structure collapses in 1.2 s and a police car in the zone is
   wrecked.
14. **Toll plaza.**
   a) `_reported` is never reset (`toll_plaza.gd:349-351`), so only the first evasion of a session raises
   `toll_evaded`. Reset it per pass: on TollArea `body_exited`, or keep a per-vehicle cooldown of 5 s.
   b) Broken arms have `collision_layer = 1`, `collision_mask = 0` and get a fixed world impulse (120, 40, 0).
   Once unfrozen they fall through the road and always fly toward +X. Use layer 5 (debris), mask 1 (world), and
   an impulse along the hitting vehicle's velocity.
   Verify: in test_gameplay_sites, two passes give two infractions and a broken arm comes to rest at y ≥ 0 within
   3 s.
15. **Gantries and VMS have no sign at all.** `guide_gantry_27.glb` is only the truss (Post_L/R, Truss_*, Light),
   and `_from_glb` parts never set `"sign"`. `SignFactory._generate` therefore skips every glb gantry (sign mesh
   null). VMS entries have no `text`, so they are skipped as well. All 20 gantries and 9 VMS boards are blank
   (`captures/review/world/r1_gantry_a_1280.jpg`).
   Do:
   - Hang one panel per carriageway from Truss_Top: about 0.15 m thick, bottom at `clearance_m`, width = lanes × 3.5 m.
   - Panel texture, 2048 px wide: GB 5768.2 快速路 green ground for elevated roads, blue for surface roads, white
     border, Chinese line first and English second, with lane-direction arrows. Use the entry's `text`/`text_en`.
   - VMS `Screen`: amber LED dot text from a real-word list (前方畅通 / 外滩 2 km / 注意车距 ...), refreshed every 8 s.
   - Use one shared material per sign style; do not duplicate it per part.
   Verify: a capture 25 m before the gantry at (−660.8,10,231.3) reads "外滩 The Bund" across the lanes.
16. **Reflection probes cover 2 roads only.** `MAX_PROBES = 16` for the whole city. All 16 sit on the first two
   roads in city.json (x −1,900…−600 along Yan'an, and x ≈ −1,600), and 0 are active at the Bund (probe B).
   Dossier §3.5 says probes are mandatory on every drivable road.
   Do:
   - One probe per 120-170 m on every road; box rotated to the road tangent; size (road width + 40, 40, segment).
   - UPDATE_ONCE, AMBIENT_DISABLED, `interior = true` in tunnels.
   - Enable only the nearest ≤ 4 within 400 m (GODOT.md §5).
   Verify: probe count ≈ total road length / 150; 1-4 active at each of the 6 viewpoints.
17. **No occluders.** The city has 0 OccluderInstance3D (probe A). The buildings unit ships the occluder list in
   each `blocks_<tx>_<tz>.json` sidecar (`occluders`: [x, z, w, d, h], 164 entries in blocks_-1_0.json). The loader
   only looks for node meta, which these merged meshes do not have.
   Do: read the sidecar next to each glb and create a BoxOccluder3D per entry at height h/2.
   Verify: occluder count = sum over sidecars; street-level objects drop (tech §4: −73 %).
18. **Furniture placement.**
   a) `TILE = 1024.0` (the file header says 512, the brief says 512 m tiles, tech §5 says ~135 m cells with a
   300-400 m range). Use 512 m or less.
   b) 1,527 of 11,247 trees stand within 14 m of a junction centre, i.e. on the carriageway. Example: j_135
   Sichuan Rd × Fuzhou Rd in `captures/review/world/r1_signal_1280.jpg`.
   c) Surface-road trees (height_m 14) grow through the Yan'an deck (≈10 m); see the gantry captures.
   d) Trees stand inside the toll plaza and the charge bay.
   Do: drop any static prop whose XZ is within (lane_width × lanes/2 + 0.5 m) of a lane centre on the same level,
   or inside a junction box or a site footprint. Ray up from each tree base and skip or scale trees that would hit
   a deck. Print the rejected counts per kind and add a request to roads in status.
   Verify: 0 trees on lanes in a probe; a j_135 capture shows a clear junction.
19. **Engine errors must be 0.** test_world_api prints 332 ERROR lines (464 script errors) and still PASSes. A 20 s
   game run gives 1,380 + 214 world errors (W-INT2/3) plus `get_meta` errors.
   Do: make every test fail when the world build logs any error (count via an `OS.add_logger` Logger in the test,
   or the test host counter).
   Verify: 0 errors in all three tests and in a `tools/godot.sh shot` of main.tscn (world lines only).
20. **Grey-box sites.** PoliceStation_* is a 24×12×14 m box with one blue rectangle
   (`captures/review_world_r1_police.jpg`). HidingSpot_* is a slab on four posts. Both break ART §8 ("grey-box
   shapes") and §5 (no detail layer).
   Do: build a recognisable 派出所 with real geometry, not one box:
   - white tile cladding ≥ 512 px/m and a blue band with lit "外滩派出所 POLICE" text (parody, no real emblem)
   - window grid with a few lit windows
   - entrance canopy, red/blue roof light bar, parked-car bays
   Hiding spots should be a covered carport or underpass with columns, lights and signage.
   Verify: 5 m and 20 m captures show texture and readable text.
21. **The ground reads as a void.** The material is rough_concrete albedo × 0.135 (≈ #232325) with a mismatched
   concrete_wall_008 normal and no roughness map. At 12 m per 2K tile it gives 170 px/m (ART §5 wants ≥ 512 px/m at
   street level), and it is black at 5 m (`captures/review_world_r1b_ground5.jpg`).
   Do: use one matched set (Asphalt031 or aerial_asphalt_01: diff, nor, rough) at ≤ 4 m tiling, plus a
   world-space macro tint noise (±12 %) and grime/wet roughness breakup. Target albedo #2E2F33…#3A3B40 (the
   triplanar `concrete_stained.gdshader` is fine). Fix the "metal" proc material too (concrete albedo on metal) and
   give "foliage" an albedo texture.
   Verify: a 5 m capture shows grain; ground pixels have mean luminance ≥ 0.05.
22. **File size.** `game/world/build/furniture_builder.gd` has 414 lines (CONTRACTS §3: ≤ 400). Split it before you
   change it: the road-style derivation (`derive_from_roads`, `_lamps`, `_planters`, `_trees`, `_bins`) and the
   MultiMesh assembly go into their own files. Keep every file ≤ 400 lines.

## SHOULD-FIX
1. **Magic numbers in logic.** Name them as constants:
   - world.gd: 3.0 height weight, 6.0 snap distance, 37.0 traffic spacing, 0.6 lift, 4.0 look-ahead
   - world_builder.gd: 16 / 18 / 34 / 72 / 80 / 25 / 30
   - route_builder.gd: 35 / 6 / 8 / 12 / 24
   - gameplay_sites.gd: 24 / 10 / 80 / 70 and all procedural sizes
   - toll_plaza.gd: 120 / 40 / 20 km/h, −78°
2. **Dead or duplicate code.**
   - `AssetLibrary.apply_building_seeds` duplicates `prepare_instance` and is unused; `has_glbs` and
     `ProcMeshes._glow` are unused too.
   - LED/SODIUM/HERITAGE are defined in both prop_library.gd and furniture_builder.gd.
   - `KIND_ALIASES` overlaps with `GLB_FOR_KIND`.
   - Three `_centerline`/`_point_at` copies exist (furniture, signal, probe). Use `spline_util.gd`.
3. **MultiMesh splitting.** `prop_library._single_surface()` splits each prop into one MultiMesh per surface ("a
   MultiMesh has one surface" is false: a MultiMesh draws all surfaces of its mesh with their materials). It also
   drops the imported LODs: furniture costs 0.36-0.75 M prims per view and trees render at LOD0 out to 500 m. Keep
   the original multi-surface mesh in one MMI per prop per tile, and set `visibility_range_end` 300-400 m.
4. **`building_seed`.** Block tiles are merged per material (`blocks_-1_0_brick`, no meta, probe C), so every
   building of one material in a tile gets the same hash seed and the window patterns repeat (ART §8). Read the
   seeds from the sidecar, read glTF extras from meta `"extras"` (not top-level meta), and file a request to
   buildings for a per-vertex seed (CUSTOM0/UV2).
5. **Blocking build.** The build runs synchronously in `_ready` (≈12 s frozen window, so the progress events can
   never render). Build in phases with `await get_tree().process_frame` between them and emit the progress then.
6. **Lane graph.** 135 of 666 lanes are dead ends. List the ones farther than 100 m from the window edge and
   request the fix from roads. `nearest_road_transform` scans all lanes twice per call (0.7-1.2 ms); add a grid
   index for AI callers.
7. **Lamps.** The furniture `arms: 2` / `mount: median` fields are ignored (single-arm lamp). The light offset is
   not scaled with `height_m` (11 m lamps light from 8.6 m). Lamp posts and tree trunks have no collision; add
   static shapes per tile so cars cannot drive through them.
8. **Sky lane rings.** `rotate_object_local(Vector3.FORWARD, PI/2)` is also applied to the glb gate, and it leaves
   the torus fallback edge-on: rotate about RIGHT for the torus only.
9. **test_drive_lanes.** It samples 4 ground-level lanes only. Add an elevated deck lane (y ≈ 10), the Nanpu
   spiral and a bridge lane. Lines print "lane lane:" because `get_meta("id", "lane")` is never set; print `road_id`.
10. **Leaks.** The tests leak 366-582 ObjectDB instances at exit; free the world and the glb roots they
   instantiate (e.g. `_charge_area`, `_gas_model`, prop instances).

## Verified OK
- `tools/godot.sh check --only=res://world/` gives `CHECK 37 files, 0 failed, 0 engine errors, 0 warnings`.
- test_world_api PASS 229, test_drive_lanes PASS 13, test_gameplay_sites PASS 17 (but see MUST-FIX 6, 19).
  All are `extends Node`, per the lead rule.
- Build time 9.3-11.8 s (target < 15 s). `Events.loading_progress` and `loading_fraction` are emitted.
- Huangpu polygon and Suzhou Creek strip at y −3 with SH_water. Bank walls use the triplanar SH_concrete_pier,
  so the missing UVs are fine. Kill floor box at y −60.
- Light pool: 32 omni + 12 spot, shadows off, `distance_fade` 60/20 m. 48 decals (≤ 64 budget).
- Toll plaza: 16 frozen RigidBody3D arms and the ETC lanes lifted. Closed-lane entry raises `toll_evaded` once.
- 5 SkyLane nodes, each with a `LaunchPad` Area3D child (contract) and ring gates.
- `nearest_road_transform` level pick works: (−500,13,200) → y 10.6 (deck); (−500,0.5,200) → y 0.6 (surface).
- 123 minimap polylines, 35 POIs (charge/gas/toll/landmark/sky_lane/police_station/hiding_spot), 4 roadblocks.
- Ownership: Write/Edit only under game/world/** and status/world.md (jobs/world/log.jsonl). No scratch left behind.
- Static typing is nearly complete; only `graph` params at api/lane_links.gd:127,132 are untyped.

## Evidence
Machine load average was 36-63 during all runs (other units busy), so absolute fps are pessimistic. Draw and
object counts are load-independent.

**Checks and tests** (logs in `tmp/review/world/`):
- `tools/godot.sh check --only=res://world/` → `CHECK 37 files, 0 failed, 0 engine errors` (check.log)
- `tools/godot.sh test res://world/tests/test_world_api.gd` → `PASS all 229 checks`, but 332 ERROR lines,
  464 × `Out of bounds get index '3'` at traffic_light_prop.gd:88, 321 × `Can't add child ... 'gas_station'`, and
  `582 ObjectDB instances were leaked` (test_api.log)
- `test_drive_lanes.gd` → `PASS all 13 checks` (224 errors). `test_gameplay_sites.gd` → `PASS all 17 checks`.

**Reviewer probes** (scratch; reuse the logic in your tests):
- probe A, `tools/godot.sh test /Users/minimax/m/skyrush/tmp/review/world/probe_a.gd`:
  - landmark positions as in MUST-FIX 8
  - `OccluderInstance3D = 0`, `MultiMeshInstance3D = 1184` (311,798 instances), `MeshInstance3D = 19645`
  - rays inside the Huangpu hit `GroundBody` y −0.02
  - GasStation_* `meshes=0`
  - ChargeArea boxes (80,6,80) and (50,6,40), `meshes=134`
- probe B (`probe_b.gd`):
  - player spawn (−123.5, 0, −300.5) fwd (−1,0,0)
  - racing-line table as in MUST-FIX 6
  - `light sources = 3678`, `reassign took 22.9 ms`, `decals ... not reach the surface = 48`
  - lit lenses {Lens_R: 920, Lens_R_Visor: 920, Lens_A: 690, Lens_A_Visor: 460, Lens_G: 690, Lens_G_Visor: 460}
  - 16 probes on 2 roads, 0 active at the Bund
- probe C (`probe_c.gd`): extras are under meta `"extras"`; block meshes carry no meta.
- perf, world only (`perf_c.gd`: godot -s, fixed cams, environment.tscn + world.tscn, 1920×1080):

  | view | fps | draws | objs | prims |
  |---|---|---|---|---|
  | bund | 104 | 409 | 667 | 0.82 M |
  | yanan_deck | 46 | 3,859 | 8,781 | 1.02 M (Signals 2,854 draws / 7,285 objs; signs 436; sites 419; furniture 72 draws / 0.75 M prims) |
  | dragon | 66 | 2,201 | — | — |
  | lujiazui | 60 | 2,319 | — | — |
  | nanpu_spiral | 79 | 264 | — | — |
  | flight120 | 74 | 60 | — | — (the city is culled at 400 m) |

  The full game at the spawn (`perf_b.gd`, main.tscn) gave fps 15, draws 3,671, objs 7,559.
  The core `tools/perf_probe.gd` timed out after 500 s on 1,473 direct world children.
- `python3 tmp/review/world/glbtree.py` / `glbnodes.py`:
  - traffic_light_mast.glb lenses: Lens_A, Lens_A_Visor, Lens_G, Lens_G_Visor, Lens_R, Lens_R_Visor
  - guide_gantry_27.glb has no sign panel
- road_furniture.json analysis: 1,527 / 11,247 trees within 14 m of a junction centre.

**Captures** (`tools/godot.sh shot --scene=res://main.tscn --env-only ...`), in captures/:
- `review_world_r1_{bund_road,bund_east,river_bund,gas,charge,toll,signal,police,hide_deck,waibaidu,nanpu,lujiazui}.jpg`
- `review_world_r1b_{bank5,bank20,bank100,ground5,t3_0,t7_0}.jpg`
- `review_world_r1c_{gantry_a,gantry_b,aerial_river,toll20,t1_0,t5_0}.jpg` (with --stub=fx)
- Contact sheets: `captures/review/world/r1_sheet_{a,b,c,d}.jpg`
- Reference comparison: `captures/review/world/r1_ref_compare.jpg` (hsbc_customs_night_2026 and
  lujiazui_from_bund_night_2016_01 vs ours)
- The worker's 6 viewpoints: `captures/review/world/worker_v4_sheet.jpg`

**ART §10 checklist** on these captures:
1. Value structure: no; the car stands out only because the city is empty.
2. Palette and neon ≤ 15 %: neon is ~0 %, not cyberpunk; the Bund is not gold.
3. Detail at 5/20/100 m: the ground is black, sites are grey-box, gantries are blank.
4. Tiling: n/a.
5. Scale: trees taller than the deck clearance, gantries along the road.
6. Emissives: the toll canopy strips blow out.
7. Shanghai recognisable: no, there is no skyline.
8. Bevels: n/a.
9. Floating: the Nanpu bridge at +45.5 m, the gas station missing.
10. Store screenshot: no.

**Not world's (for the lead):**
- `res://fx/fx_rain.gdshader:17` fails to compile, and its streaks render as huge grey quads over main.tscn
  (`review_world_r1b_t3_0.jpg`).
- UNTEXTURED materials: Glass_Dark (blocks), Bund_Flag_Red, LM_PEARL_Alu/Glass, LM_RING_Steel,
  LM_TOWER_Core/Crown, LM_SWFC_Beam, LM_WAIBAIDU_Timber.
- Road materials have no normal maps (Road_Kerb_Granite, Road_Sidewalk_Paving, ...).
- The plane trees are flat-shaded uniform yellow.
- The city.json bund_sprint checkpoints cross the river at y 0.
