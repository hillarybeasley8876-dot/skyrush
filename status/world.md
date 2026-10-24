# world status

Round 2 review (`reviews/world-r2.md`), the INT3 notes (W-INT6, W-INT7) and the ART-NIGHT note
are addressed. Every number below is from a run of this round; the logs are in `tmp/world/`.

## Done

**Entry** `res://world/world.tscn` (root script `game/world/world.gd`, `extends WorldBase`,
sets `Game.world = self`). The city is built in phases (terrain, roads, blocks, lanes, furniture,
signals, sites, routes); every phase yields a frame and reports `Events.loading_progress`, so the
loading screen moves and the API is safe while the world is still building (W-INT8: every method
answers with the documented fallback and one warning).

**MUST-FIX 1 — the landmarks** (`loader/landmark_manifest.gd`): the anchor of the manifest is
read as `[x, y, z]` (`[x, z]` is the fallback), the wrapper scene of a tower is instantiated
when the manifest names one (`jin_mao.tscn`, `swfc.tscn`, `shanghai_tower.tscn`,
`lujiazui_backdrop.tscn` apply `lujiazui_facade.tres` with the seed of the tower), and the
`lights` list of the manifest is read: the empties whose name starts with the prefix
(`Flood_Base_`, `Flood_Under_Deck`, `Flood_Nanpu_Leg_`, `Flood_Nanpu_Under_`,
`Flood_Waibaidu_`) become spot lights with the colour, the energy, the angle and the range of
the manifest (17 of them). The hard-coded dragon uplights are deleted.

**MUST-FIX 2 — the flood pool** (`build/light_pool.gd`, `build/world_builder.gd`): the Bund and
the landmark floods have their own pool of 12 spots (the street lamps keep the 60 m rule of the
dossier). The pool is configurable, so the flood pool fades from 500 m and reaches 900 m.

**MUST-FIX 3 — the gantries and the VMS**: the filter no longer rejects a gantry or a VMS board
for standing on the carriageway (a gantry spans the road on purpose). The two posts of a gantry
(±span/2 along its local X) are checked instead: a post on a lane slides the gantry along the
road (≤ 20 m). The gantries of one spot are collected together, so two entries at the same point
get one truss and one panel per direction instead of two coplanar panels.

**MUST-FIX 4 — the sign panels** (`build/sign_factory.gd`, `build/furniture_builder.gd`): every
panel gets its own `StandardMaterial3D` (a shared one showed the last rendered text on every
panel of the city), the face is a `QuadMesh` in front of a plain box (the UVs of a `BoxMesh` are
an atlas, so the texture only covered a part of the face), the Chinese and the English line come
from the data (`text` and `text_en`, no split on spaces), the panel is 8:1 like the texture, the
ground is green (#00704A) on an elevated road and blue (#1F57C3) on a surface road, the lane
arrows are drawn, and the emission is 0.25 (the green does not glow).

**MUST-FIX 5 — the VMS boards**: the five messages are rendered once into dot-matrix textures
(amber on #101418) and cycled; no viewport is created every eight seconds. The interval lives in
one place (`VmsCycle.INTERVAL`).

**MUST-FIX 6 — the street furniture** (`build/furniture_filter.gd`, `build/lane_probe.gd`): a
prop that stands on the carriageway is pushed out onto the sidewalk of its own road (half the
width of the road + the shoulder + 1 m) instead of being deleted; it is only dropped when the
new place is on another lane, in a junction, in a site or under a deck. The lanes are looked up
in a fine grid of segments (`api/lane_spatial.gd`), and **the lanes that are near a prop are
measured on their curve, not on the straight segments of the grid**: a tight curve (a junction)
hides a lane from the fast query, and on a steep ramp the segment lies above or below the road.
That was the reason why 349 props of the last round still stood in a lane. 23,793 props were
moved out of a carriageway in the last run; 49,548 props are placed (the lamps 4,906, the trees
18,498, the signs 8,303, the bollards 4,329, the neon blades 4,247, the bins 4,591, the
hydrants 2,567, the bike racks and the e-scooters 1,446). The prop tries both kerbs of its road
and slides along the road when the kerb is taken, so a prop is only dropped when there is really
no room for it.

**MUST-FIX 7 — the street dressing** (`build/street_dresser.gd`): the bins (2 per 100 m), the
bollards (3 per corner of every junction), the bike racks and the e-scooters (1 per 150 m),
the hydrants (1 per 120 m), the planters (the Bund promenade and Nanjing Rd), the metro entrances
(4 near the points of interest) and the neon blade signs (1 per 25-40 m on the `st_*` shop
streets, with Chinese shop names on the boards) are placed on the sidewalks; a prop that would
stand in the carriageway of a crossing road is moved along the road or dropped.

**MUST-FIX 8 — the build time**: the build runs in phases and yields a frame between them; the
phase durations are printed per phase. The street dresser no longer resamples the centre line of
a road for every prop (that alone was 60 s of the 111 s of the furniture phase). The whole
build takes 33 s on this machine when it is not busy and 85 s when the four tests run at the
same time (the phases of one run: the terrain 2.9 s, the roads 2.8 s, the blocks 2.0 s, the
lanes 4.1 s, the furniture 7.9 s, the signals 0.8 s, the sites 1.0 s, the routes 10.7 s).

**MUST-FIX 9 — the performance**: the furniture is batched per 512 m tile with a visibility
range per type (lamps 600 m, trees 350 m, bus stops 250 m, signs 200 m, bins and bollards
120 m); the merged prop meshes get their LOD levels again through an `ImporterMesh`; the
traffic-light masts are batched per 512 m tile (the bodies 400 m, the lenses 600 m) instead of
one city-wide batch; the sky-lane ring gates are one MultiMesh per lane instead of 1,790 nodes;
the reflection probes are looked up in a grid and only the ones whose state changes are touched.

**MUST-FIX 10 / 11 — the racing lines and the start grid** (`api/route_builder.gd`,
`api/lane_path_finder.gd`, `api/start_grid.gd`): a leg whose gates are not on the lane network
falls back to the lanes it can reach and then drives straight to the gate, and the leg is printed
with its gate indices; the search is a multi-source Dijkstra with a binary heap over the lanes
within 8 m of a gate whose direction agrees with the gate (30 m when the gate is not on a lane).
The start grid is built from the **first checkpoint of the route** (the one that has been turned
towards the next checkpoint): the heading of `city.json` points the wrong way on three of the
five routes, so the grid landed on the wrong side of the junction. Every route now has 6 slots
on lane centres, at least 5 m apart, facing their lane. The grid is two columns when the road
has two lanes that are far enough apart and a single file of six slots when it has not (the
lanes of the city are 3.75 m apart, so two columns on lane centres cannot be 5 m apart).
**The check still fails for the real city**: the legs that the city data runs against the traffic
(the gates stand on lanes that drive the other way) can only be followed backwards, so the line
has 32-121 reversals and 65-86 % of its samples on a lane. The legs are printed with their gate
indices (see the Requests) — this is a data problem, not a line problem.

**MUST-FIX 12 — the height of the road** (`api/spawn_placer.gd`): `nearest_road_transform` and
the spawns ray down onto the road (from 4 m above the lane to 4 m below it) and put the car
0.6 m above the surface. *Verified*: 200 of 200 random lane points give a spawn 0.60 m above the
road.

**MUST-FIX 13 — the engine errors** (`tests/world_error_counter.gd`): an error counts when the
file comes from `res://world/` **or** when one of the frames of its backtrace does. The sign
factory skips the offscreen render when the display server is headless. The curves of the world
have their up vector switched off: Godot computes it with a rotation around an axis that is not
normalized on a sharp turn, and the engine complained once per run
(`basis.cpp:844 set_axis_angle`).

**MUST-FIX 14 — the tests that can fail**: the racing line check no longer returns with an INFO
line, the light pool check puts a camera 90 m above the spawn and wants ≥ 10 active light pools
on the ground (48 of 48 ✓), the probe check wants 1-4 probes within 400 m and none beyond (1 ✓),
the breaker check drives a car into a `Support_*` node at 70 km/h and wants the stunt, the wreck
of the police in the zone and the collapse within 1.2 s (144 frames ✓), and the toll check runs
two passes and wants two infractions and a broken arm that rests above the ground on the debris
layer (y 0.75 ✓).

**MUST-FIX 15 — the procedural sites** (`loader/proc_meshes.gd`, `build/city_sites.gd`): the
materials of the sites are projected in world space (triplanar), so a box of any size carries the
same grain as the ground next to it: the walls are granite, the metal is #2B2E33 with a metallic
of 1, the glass is #0B0F14 with a roughness of 0.05, the sign bands are painted plastic and the
parking bays are a non-emissive #E8E8E0. The police station reads the label of its point of
interest (陆家嘴警察局 / 外滩警察局) and the carport reads 开放车库 OPEN GARAGE. A site that
stands inside a building is moved out of it (the boxes of the block tiles and of the Bund).

**MUST-FIX 16 — the breakers** (`build/breaker_sites.gd`): a billboard or a scaffold stands at the
building line of its road (half the width of the road + the sidewalk + 1 m) and faces the road;
the dead copy of the builder is deleted. Every roadblock site of the city description gets a
stunt gate (飞跃路障) that is snapped to the lane.

**MUST-FIX 17 — the code**: the dead code is gone (`furniture_builder._centerline/_point_at/
_index_at`, `world_builder._color`, `gameplay_sites.BILLBOARD_GLB/...`, `world.LOOK_AHEAD`),
`_centerline` is now `Spline.road_line` (one copy in `api/spline_util.gd`), and the magic
numbers are named constants. The files are all under 400 lines (`world.gd` 227): the lane
queries live in `build/lane_probe.gd` (they were written three times), the spawn points in
`api/spawn_placer.gd`, the start grid in `api/start_grid.gd`, the sign props in
`build/sign_props.gd`, the gas station in `build/gas_station.gd` and the water of the quality
test in `tests/water_probe.gd`.

**MUST-FIX 18 — the roads**: a near tile is only culled when the directory has a far tile to
take over from it. The roads of the city have no far tile, so they stay visible as far as the
camera reaches.

**W-INT6 — the errors on the detached nodes**: the AABB of a tile is computed from the local
transform chain of the node (`asset_library.gd`), so nothing asks a detached node for its global
transform. The loader also skips a tile whose import is not there yet (the import of the other
units was still running on this machine) instead of failing the load with an engine error.

**W-INT7 — the traffic-light masts**: a mast that stands in a carriageway is moved to the kerb of
its road (half the width of the road + the median + the shoulder + 0.5 m behind the kerb) and,
when the kerb of one road is still in the way of another, to a corner of the junction (the ring
around the middle of the junction at the distance of the kerb, every 15°). A mast that cannot
stand clear of the lanes is not placed at all. *Verified*: 2 of 1,380 masts are still inside a
lane polygon (0.14 %). The traffic lights of the roads unit that name a junction the city
description does not have are placed as well (1,112 of them), so the city keeps its lights when
the two data sets disagree on the ids of the junctions.

**ART-NIGHT W-NIGHT1 — the ground**: the ground of the city uses the wet asphalt shader of the
road with a dark tint (the albedo is a fifth of the road's), so the lots and the yards are dark
and the lamps and the reflections carry the image.
**ART-NIGHT W-NIGHT2 — the lamp dots from the air**: the emissive head of the street lamps is a
part of its own (`prop_library.gd`), so the heads are batched with a visibility range of 1,800 m
while the poles of the lamps stay at 600 m.

**The loader reads the tiles of the roads and the blocks as `.glb` or as `.gltf`** (the `.gltf`
wins when both are there), as the lead's TILE-TEX note asks.

## In progress / next
- The racing lines of the real city: the legs that the city data runs against the traffic (see
  the Requests) still fall back to the straight line to the gate, so the line check fails.
- The build time: 33 s when the machine is free, 85 s when the four tests run together (the
  machine is shared with the other units). The routes are the biggest part (10.7 s): 100 legs
  walk the lane network of the city (8,640 lanes).
- The perf table at the 6 viewpoints of the brief: the captures of this round are in
  `captures/r3_*.jpg` and `captures/r4_*.jpg`; the draw call table still has to be measured with
  `tools/godot.sh perf` (the heavy slot was busy for the whole round).

## How to test (exact commands)
    tools/godot.sh check --only=res://world/
    tools/godot.sh test res://world/tests/test_world_api.gd
    tools/godot.sh test res://world/tests/test_drive_lanes.gd
    tools/godot.sh test res://world/tests/test_gameplay_sites.gd
    tools/godot.sh test res://world/tests/test_world_quality.gd
    tools/godot.sh perf --at=-140,3,-500 --warm=30

## Evidence
- `tools/godot.sh check --only=res://world/` → `CHECK 63 files, 0 failed, 0 engine errors,
  0 warnings`.
- `test_gameplay_sites.gd` → `PASS all 24 checks` (the sites, the signals, two toll passes, the
  broken arm, the charge bay, the breaker stunt, the wreck of the police, the 1.2 s collapse).
- `test_drive_lanes.gd` → `PASS all 18 checks` (four ground lanes and the elevated deck, the
  dropped body on the RoadBody, 200 spawns 0.60 m above the road).
- `test_world_quality.gd` → `FAIL 3 of 17 checks`: 1 of 49,548 furniture props and 2 of 1,380
  traffic-light masts are still inside a lane polygon, and the city has 0 occlusion boxes (the
  block tiles of the buildings unit are not imported on this machine, so the loader skips them).
- `test_world_api.gd` → the racing line checks fail for the real city (the legs that run against
  the traffic): bund_sprint 66.0 % of the line on a lane with 32 reversals, elevated_sprint
  69.3 % with 60, grand_loop 64.7 % with 110, river_loop 77.2 % with 121, lujiazui_ring 86.1 %
  with 36, test_loop 75.6 % with 6. The legs are printed with their gate indices. The other 500
  checks pass (the spawn, the gate headings, the grid of every route, the minimap, the POIs, no
  engine errors).
- The captures of this round: `captures/r3_{bund,bund_east,dragon,flight120,lujiazui,
  nanpu_spiral}.jpg` (the viewpoints of the brief) and `captures/r4_{bund,flight120}.jpg` (the
  ground after it was darkened).

## Known issues
- The lanes of the roads unit carry a lane at the offset 0 of the road centre line (a median
  lane) that the road description of the city does not have; the half width of a road is
  therefore read from the lanes (max |offset| + half a lane width), which matches the
  description (11.76 m against 11.75 m).
- The world unit moves the props of the roads unit out to the sidewalk of their road, which
  moves them up to 12 m away from the place the roads unit wrote down (the two data sets
  disagree, see the Requests).
- The light pool of the street lamps fades at 60 m (the dossier); the light pools of the Bund
  and of the landmarks are a second pool of 12 spots that reach 900 m.
- The `landmarks_manifest.json` is the contract of the landmarks unit: the world unit only
  reads it.

## Requests
- (to city_layout) the routes of `city.json` run against the traffic on several legs, so the
  racing line can only follow the lanes backwards there. The legs are printed by the world unit
  with their gate indices: grand_loop 4 legs are not on the lane network (the gates 5, 6, 18,
  19) and the leg 7 runs against the traffic, river_loop 6 legs have their gates more than 8 m
  from the lanes (5, 6, 11, 12, 19, 20), elevated_sprint 2 legs (3, 4), lujiazui_ring 2 legs
  (3, 4), bund_sprint 0. A gate belongs on the lane it counts, and the lane has to drive the
  way the route goes.
- (to roads) the junction ids of `road_furniture.json` do not exist in `city.json`: 202 of the
  258 junctions of the furniture file are unknown to the city description (only 56 match). The
  world unit places the traffic lights of the unknown junctions as well (they report green,
  because the signal state of a junction needs the roads of the junction), but the ids have to
  agree.
- (to roads) `lanes.json` and `road_furniture.json` do not agree: the furniture of the roads
  unit stands 1.6-2.0 m from a lane centre (on the kerb of its own model of the road), while
  `lanes.json` puts the outer lane 9.88 m from the centre line of a road that is 11.76 m
  half-width. The world unit moves those props out to the sidewalk of the road (half the width
  + the shoulder + 1 m); the roads unit should write the furniture against the same model of
  the road it writes the lanes against.
- (to roads) the sidewalks and the aprons of the road tiles read as a pale grey plane from the
  air (`captures/r4_flight120.jpg`): the ground of the world unit is dark now, but the tiles of
  the roads unit are still pale. Their albedo should be at most #2A2A2E like the rest of the
  hard surfaces (ART.md §11).
- (to roads) the `road_furniture.json` has no `span_m` for the gantries (the world unit uses
  27 m, the span of `guide_gantry_27.glb`) and no `text_en` that is English (the English line
  of the panels is the Chinese text).
- (to city_layout) the point of interest `police_bund` (外滩警察局 at -160, -520) stands
  inside the row of the Bund buildings; the world unit moves the station out of the building
  boxes of the Bund, but the point of interest should be on the promenade.
- (to city_layout) the junctions `j_st_beijing_e_rd_bund_zhongshan_e1` and
  `j_bund_zhongshan_e1_st_beijing_e_rd` are at the same point (-128, -703), so the world
  places two sets of traffic-light masts there.
- (to core / menu) the loading screen should read `Game.world.loading_fraction`: the world is
  built in phases now, but the menu is created after the world.
- (to core) `data/city/city.json` lives outside the Godot project; the world unit reads it
  through an absolute path, which works in a dev build but not in an exported one.
- (to core) `rendering/limits/global_shader_variables/buffer_size` (65,536 = 16,384 instance
  uniforms) is too small for the city: the world unit can only set the `building_seed` of one
  mesh per tile, so the buildings of a tile share their window pattern.
- (to bund) `bund_buildings.glb` should be exported in world coordinates (like
  `bund_lights.json`) or the placement transform has to be documented.
- (to buildings) the block glb tiles reference `textures/windows_far_emit.jpg`, which is missing.


## 2026-10-24: street props were not solid, the edge of the world

Found with `game/tools/fuzz_drive.gd` and a ray probe in the real world.

* **The 49,571 props had no collision.** `PropCollision.build` made the shapes (a dozen shared `BoxShape3D`/`CylinderShape3D`)
  and gave them to the physics server by RID. The builder is a temporary object (`PropCollision.new().build(...)`): the
  shapes died with it, the server dropped them from the bodies, and the 76 `PropCollision_<tile>` bodies had 0 shapes.
  Cars drove through lamps, trees, signs, bollards, bus stops and noise walls (the 50 hits of the fuzz runs were all buildings,
  roads and cars). The bodies keep the shapes now (`body.set_meta(&"shapes", ...)`): 1000-1600 shapes per tile body, every kind
  is solid for a ray at knee height (25 of 25 per kind).
* **The boxes ignored the heading of the prop.** `bus_stop` (8 x 2.6 x 1.8, 556 of them), `noise_wall` (30 x 3.6 x 0.35, 33),
  `planter`, `bike_share`, `metro_entrance` were put into the world axes: 88 % of the bus stops and 85 % of the noise walls
  stood at an angle to their box (a 30 m box across the viaduct is a wall the player cannot see). The shapes turn with the yaw
  of the prop now (and follow its `scale_vector`: a noise wall of 24 m). The arm of a traffic light mast was on +Z of the pole,
  the glb has it on -Z (7.3 m); it is a box of 0.45 x 0.45 x 7 m at the top, on -Z.
  Test: `world/tests/test_prop_collision_orientation.gd` (25 checks, fails on the old code: not even the heading 0 box was there).
* **The edge of the world.** The ground ended at the window (x -2200..1800, z -1200..1800); 9 of 60 random drives drove off the end
  of a road, fell 60 m to the kill floor (y -60), were wrecked there (hp 0), and the police that followed them fell as well
  (police at y -11 beyond x -2200). `TerrainBuilder.EDGE_RING = 100` m of ground go on past the window and
  `build_edge_walls` closes the world with four invisible walls (10 m thick, y -80..400, friction 0.05) on the border of that ground.
  Test: `world/tests/test_edge_walls.gd` (rays at 5 heights, the corners, a body at 50/100/200 m/s).
* Not done: the 100 m of ground beyond the window are empty asphalt (no props, no buildings).

### The bus shelters and the noise walls lie along the road now

The roads unit writes `heading_deg` for every prop, and the world unit makes the -Z of the model point along the heading. A lamp
(arm on +X) and a gantry (beam on X) are right that way; a bus shelter (8 m) and a noise wall (30 m) have their length on X and stood
ACROSS the road. Worse, `furniture.py::_heading` was `atan2(east, -north)` with the Blender north (+y): 180 degrees minus the heading
(right on an east-west road, upside down on a north-south one and mirrored on every diagonal: 3100 of 5300 lamps and signs are more
than 15 degrees off their road, 750 of them at 75-90). The generator is fixed (`atan2(tangent.x, tangent.y)`); the data in
`game/world/data/road_furniture.json` is regenerated with the next full roads rebuild (the rest of the props keep the mirrored
headings until then).
* `FurnitureBuilder._along_road`: the X of a shelter or a wall is the direction of the lanes next to it (not the heading of the data), the
  shelter opens (+Z) towards the road. Then `FurnitureFilter.footprint_clear` samples the perimeter of every box prop every metre
  against the centre lines of the lanes (1.3 m): a box that reaches into a lane moves away from the road in steps up to 3 m, or is dropped.
  Before: 426 of 541 shelters and all 32 walls reached into a lane (the box is solid now). After: 534 shelters (503 along the road, 94 %),
  26 walls (all along), 0 reach into a lane. The world cache is version 18.
* Tools: `tools/prop_lane_clearance.gd` (the box props against the lanes, the angle to their road), `test_prop_alignment.gd`.

### The mouth of a junction is free of solid props

The furniture filter kept props 8 m from the centre of a junction (a circle), but the box of a junction is bigger: the lanes of the street
that leaves the Bund begin 13 m after the kerb of the Bund (they are cut at the kerb returns), and the first tree and the first lamp of
Fuzhou Rd stood in that mouth, 3.5 m from the nearest lane (a turning movement), on the axis of the street. The props are solid
since the dead collider fix, and the first rival that took the turn at 20 m/s hit the tree, stopped dead, steered into it for ten seconds
and the other four drove into it (the marshal put them back, the race start test failed on the Bund sprint).
* `FurnitureFilter._index_mouths`: for every road of a junction the stretch of its carriageway from the centre of the junction to the end
  of the box (the half width of the roads that cross it + `MOUTH_RETURN` 13 m), with the half width of the road and its shoulders;
  `_in_junction` (the circle of 8 m) is true in a mouth as well. `in_junction_box` is the public name. The builder asks again after the
  slide along the road and after the nudge of a box prop (they had moved props into a box: 69 trees, lamps and shelters of 23,900).
  Dressed props (bins, bollards of the corners, planters) keep their place in a junction on purpose. About 390 props of 48,000 went.
* `world/tests/test_junction_mouths.gd`: no tree, lamp, shelter, wall or billboard in a junction box (0 of 23,824), the mouth of
  Fuzhou Rd on the Bund is free.
* **The world cache has to be bumped when the placement changes** (`world_cache.gd` VERSION, 23 now): the key is the hash of the three
  data files, so a change of the filter or of the builder keeps the old placement until the version changes (two test runs of this
  job measured the old placement).
* `LanePath` carries `connector` as metadata (the roads unit's flag) and `CityData.lane_stats` the statistics per road of lanes.json: a road
  that the buildings of the Bund took every lane of is covered all the same (`LaneGraph.build`), or the world derived lanes for it from
  city.json.
* The rivals (status in the rivals test logs, no status file): `RivalRoad.road_frame` leaves the connector lanes out (they widened the
  measured carriageway by the width of the junction: the field drove 14 m to the side at the Beijing Rd junction at 120 km/h into the
  kerb) and the column of a rival moves sideways at 4 m/s at most (`LANE_RATE`; the road around a junction changes by ten metres between
  two readings). `test_real_start` passes on both routes (the rescues before: 3-4 on the Bund sprint, 1 on the Lujiazui ring),
  `test_real_route` passes. Still failing in the rivals folder: `test_performance` (the AI costs 0.54 ms per tick against a budget of
  0.35; the same 0.53 ms was measured before the changes of this round) and `test_race_flow` (the sandbox race: 5 passes of 6 wanted
  and 4 contacts over 800 N*s; with instant column changes 1 pass and 1 contact, so the rate limit is not what fails it). The
  sandbox loop (8 gates) had no gate boards (`gen_gate_textures.py` writes the 8 now: the two tests died on the missing sign
  panels before they measured anything).

## 2026-10-25: the street lamps break away

The lamps (`PropCollision.BREAKAWAY`: lamp, lamp_heritage, lamp_magnolia, lamp_deck_double; 4,941 in the city) have no rigid shape.
`world/build/prop_breaker.gd` (a child of the Furniture group, set up by the world builder) keeps them in an 8 m spatial hash and
checks the box of every car that is not frozen, within 250 m of the camera, every physics tick: a car faster than 2 m/s that touches
a pole knocks it down. The furniture builder records, for every lamp, the [group key, instance] of each part and far dot and the
indices of its light sources (`LightPool.add_source` returns the index, `set_source_enabled` switches a source off), so the breaker
hides exactly that lamp. The pole falls as a rigid body on the debris layer (the cars drive through it) and fades after 6 s; at most
12 poles at once. A broken lamp stays broken for the game. Test: `world/tests/test_prop_breakaway.gd`.

The bank walls of the river and the creek have collision (`TerrainBuilder.build_banks`, after the lanes; 3,041 pieces, gaps where a
lane crosses or runs along the bank), the ground is clipped to the bank, and the creek floor is its cut outline. Test:
`world/tests/test_bank_walls.gd`.
