# Lead notes for world (mandatory)
TILE-TEX (lead, 08:05): roads/buildings will switch their tiles from `.glb` to `.gltf` (+ shared textures in
  `res://assets/city/_tex/`). The loader must accept both `roads_*.glb|gltf` and `blocks_*.glb|gltf` (prefer .gltf when both exist).
W-INT5 (lead perf probe, 01:20, audio/traffic/police/damage/fx stubbed): baseline 3,677 draws / 7,575 objects at the spawn view;
  World = 3,431 draws of which Roads 5 and Landmarks 21 — the rest is furniture/sites: each gantry ≈ 64 draws, hundreds of
  individual `Furniture_*` nodes (115 lamps, 220 bus stops, 96 trees, 72 heritage lamps near the spawn). Use one
  MultiMeshInstance3D per prop type per tile (with visibility_range_end per type: lamps 600 m, trees 350 m, bus stops 250 m,
  bins/bollards 120 m), real scenes only for interactive props, and request merged props from the props unit (PR-INT1).
  Target ≤ 600 draws / ≤ 2,000 objects at the 6 standard viewpoints; print the perf table in status.
W-INT1 (lead integration run 00:50, `tools/godot.sh drive ... --skip-menu`): the player spawns at (-131.7, 0, 298.2) pressed against a heritage building
  facade (not on any lane) and cannot move. `get_spawn_transform(&"player", 0)` must return a point ON a drivable lane centre, facing
  the lane direction, ≥ 30 m of free straight ahead (snap the city.json spawn to the nearest lane; never trust raw coordinates).
W-INT2: `res://world/build/traffic_light_prop.gd:88` "Out of bounds get index '3' (on base: Array[Color])" — 1,150 errors in 18 s.
W-INT3: gas-station breaker reparenting spams "Can't add child 'X' to 'Canopy', already has a parent 'gas_station'" (~100 errors) — use
  `reparent()` or remove_child first, and do it once.
W-INT4: performance: fps 7–11 at the Bund with draw calls ≈ 4,964 and 10,749 objects (budget ≤ 600 draws, ≤ 2,000 objects; tech dossier §5).
  MultiMesh all repeated props per tile, merge static meshes per material, visibility ranges/HLOD, occluders. Report draw calls per
  subsystem (roads / blocks / props / bund / landmarks / traffic) in status with `tools/godot.sh perf` (core tool).

## Project-wide rules added by the lead (include in your feedback if the worker violates them)
- Tests must be `extends Node` scripts run with `tools/godot.sh test res://...` (test_host loads them at runtime after autoloads; see CONTRACTS.md §3 and `game/core/tests/test_core_smoke.gd`). `-s` SceneTree scripts compile before autoloads and break on Events/Game/VehicleBase.
- Every run must end by itself: tools/slots.py now kills headless runs after 300 s, windowed after 600 s, Blender after 2400 s. No Godot/Blender in the background, no scratch tests left running.
- Scratch files go to tmp/<unit>/ and are deleted when done; nothing outside owned paths.

## INT3 — lead integration drive 10-20 09:00 (evidence: captures/lead_int3_t2_0.jpg / _t6_0 / _t10_0 / _t14_0 (lead integration drive 10-20 09:00, `tools/godot.sh drive --timeline=res://tools/timelines/smoke_drive.json --skip-menu --debug --shots=2,6,10,14 --out=lead_int3`, all 13 units real))
W-INT6: 261 engine errors per 18 s run from `res://world/loader/asset_library.gd:221` `_aabb()` → `get_global_transform()` on a node that
  is not inside the tree (called from `collect_boxes` ← `_build_landmarks` world_builder.gd:164), + 8 at asset_library.gd:68 and 4 at
  world.gd:158. Compute AABBs from the node-local transform chain (or after add_child), never on detached nodes. Gate: the drive above
  must print 0 ERROR lines from res://world/**.
W-INT7: at the spawn junction (Bund × Yan'an E Rd, car at (0,0,-13) heading north) the traffic-light masts stand INSIDE the carriageway
  (in line between lanes, the car drives straight at one) and pale corner slabs lie on the road surface. Masts go on the kerb corners,
  ≥ 0.5 m behind the kerb line of the real road widths in city.json; corner islands/sidewalks must never overlap lane polygons.
  Add a test: no mast/pole collision shape within any lane polygon at every signalised junction.

## INT4 — lead integration drive 10-20 09:55 (tmp/lead/int4.log)
W-INT8: every WorldBase API method must be safe before the build finishes (`data == null`, no lanes yet):
  return the documented fallback without a script error (one push_warning at most). Callers are told to
  `await Game.world_ready()` (core/game.gd, reads your `loading_fraction`), but the API must not crash.
  Also: `[world] built in 37.60 s (9873 lanes)` — 9,873 lane paths and 38 s to build on this machine is
  too slow for a game start; target ≤ 10 s (cache the lane graph / build tiles lazily around the player).

## ART-NIGHT (10-20 10:20, evidence: captures/lead_view1_{bund,lujiazui,dragon,yanan,spiral,sky,toll,charge}.jpg, captures/lead_view2_{pudong,pearl,pillar}.jpg (main.tscn --skip-menu --env-only)) — mandatory, see ART.md §11
W-NIGHT1: the ground mesh (ground_builder.gd) reads as a PALE GREY flat plane between buildings and under the
  decks (lead_view1_lujiazui/sky/toll, lead_view2_pudong/pillar). Use dark ground materials with texture and macro
  variation (wet asphalt for lots/yards, paving for plazas, grass in parks; albedo ≤ #2A2A2E for hard surfaces),
  using the swap-in SH_* materials, so the lights and reflections carry the image — never a light grey plane.
W-NIGHT2: from 120 m altitude the street grid must read as lines of lamp dots (ART.md §11): make sure every
  street lamp has an emissive head visible at distance (visibility range ≥ 1,500 m for the head mesh or a
  far-LOD dot sprite batch).
