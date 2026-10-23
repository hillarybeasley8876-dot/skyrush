# CONTRACTS.md — code + asset contracts, file ownership

Core-owned. A worker that needs a change here writes a request in `status/<unit>.md`.

## 1. Coordinates, units, naming
- Metres, kilograms, seconds. Godot: **Y up, −Z forward, +X right**. Blender: **Z up, +Y forward,
  +X right** (the glTF exporter maps Blender +Y → Godot −Z, so a car modelled facing +Y in Blender
  faces −Z in Godot). Apply all transforms before export (scale 1, rotation 0).
- World map: origin at the Bund end of 延安东路, Godot X east, −Z north (so +Z south).
- Node/file names: ASCII `PascalCase` for nodes, `snake_case` for files. Chinese text only in UI
  strings, signs and textures.

## 2. Blender → glTF → Godot
- Every asset is produced by a Python script under `blender/<unit>/` run with
  `tools/blender.sh run <script>`; scripts are deterministic (fixed seeds) and rebuild from nothing.
- Shared helpers: `blender/lib/` (core-owned): `common.py` (reset, collections, apply, naming),
  `mats.py` (PBR materials from the texture library), `export.py` (glTF export with the project
  settings), `uv.py` (box/cube projection UVs in metres). Use them; do not copy them.
- Export `.glb` (binary, images embedded) to `game/assets/<area>/<name>.glb`. Settings come from
  `blender/lib/export.py` (Y-up, apply modifiers, tangents, vertex colours only if used, no
  cameras/lights unless the brief says so, KHR_materials_emissive_strength on).
- Import hints by node-name suffix (Godot): `-col` trimesh collision + mesh, `-colonly` trimesh
  collision only, `-convcolonly` convex collision only. Roads, decks, ramps, buildings get
  simplified `-colonly` meshes; never use render meshes > 20k tris as collision.
- **Markers**: Blender Empties exported as Node3D. Blender local **+Y = the direction the effect
  points** (exhaust leaving a nozzle, a lamp's beam), which becomes Godot **−Z**. Names are contract
  (see §5).
- **Materials**: Principled BSDF only (+ image textures, normal maps, emission). Material names are
  contract: names starting `SH_` are replaced at runtime by the shared shader library
  (`MaterialLibrary.apply(node)`, see §6) — e.g. `SH_car_paint`, `SH_glass_tinted`, `SH_facade_lit`,
  `SH_neon`, `SH_hologram`, `SH_wet_asphalt`, `SH_water`. All other materials are used as imported.
- **Textures**: CC0 only, from the shared library `game/assets/textures/<id>/` (Poly Haven /
  ambientCG, 2K JPG/PNG, files `<id>_diff.jpg`, `_nor_gl.jpg`, `_rough.jpg`, `_ao.jpg`, `_disp.jpg`
  when present). Generated textures (decals, signs, liveries, atlases) go to the unit's own
  `game/assets/<area>/textures/`. Texel density targets: hero car 2048 px/m² body detail via
  tiling + decals, props ≥ 512 px/m, buildings tileable/trim sheets ≥ 256 px/m at street level.
- Polycount budgets (LOD0): hero car ≤ 180k tris, NPC car ≤ 25k, police car ≤ 30k, landmark tower
  ≤ 150k, street prop ≤ 3k, building ≤ 6k (use textures for detail). Godot generates LODs.

## 3. Godot project rules
- GDScript 2 with static typing everywhere; `class_name` only for contract classes (core) and
  where the brief says so. Files ≤ 400 lines. No `get_node("../..")` across units: use `Game`,
  `Events`, groups, or exported NodePaths inside your own scene.
- Physics layers: 1 world, 2 vehicle, 3 prop, 4 trigger, 5 debris. Groups: `vehicles`, `player`,
  `police`, `traffic`, `rivals`, `props_breakable`.
- Never edit `project.godot`, `main.*`, `core/**`, `tools/**` (core-owned). Input actions are
  registered by `core/input_setup.gd`.
- Quality scaling: read `Settings.feature("ssr")` etc. (presets in `core/settings.gd`).
- Every unit ships tests: `game/<unit dir>/tests/test_*.gd` run with `tools/godot.sh test res://...`.
  **Tests `extends Node`** (loaded at runtime by `res://tools/test_host.gd`, see
  `res://core/tests/test_core_smoke.gd`): print `PASS`/`FAIL` lines and call
  `get_tree().quit(0|1)`. GOTCHA: a script run with `-s` (`extends SceneTree`) is compiled BEFORE
  autoloads exist, so it must not reference `Events`/`Game`/`Settings`/`Modules` or any class_name
  type that uses them (VehicleBase, ArcadeCar, ...) — use the Node test convention instead.

## 4. Core API (game/core)
- Autoloads: `Events` (signal bus, `core/events.gd`), `Game` (world/player/options/slow-mo/respawn),
  `Settings` (quality presets, volumes), `Modules` (unit registry with stub fallback).
- Contracts: `VehicleBase` (RigidBody3D base for every car), `CarTelemetry`, `WorldBase`,
  `LanePath`, `RaceRoute`, `SkyLane`, `ChargeStation`, `StuntGate`, `MaterialLibrary`, `SmokeFX` (shared smoke /
  vapour particles, `core/fx/smoke.gd`, atlas in `assets/textures/fx/`). Read the source — the doc
  comments are the spec.
- The real world builds over several seconds after it enters the tree. Before calling ANY WorldBase
  method (spawns, lanes, routes, POIs) at start-up, `await Game.world_ready()` (or check
  `Game.world_built()`); main.gd keeps the player frozen until then.
- Physics interpolation is OFF (120 Hz physics, integer ratio to 60/120 Hz displays). Cameras follow
  in `_physics_process` or read the body transform directly; `reset_to()` handles teleports.
- Options: `Game.option("key")` for `--key=value` user args; `--stub=unit,..` forces stubs,
  `--debug` shows the F3 overlay, `--spawn=x,y,z,yaw` teleports the player, `--quality=low..ultra`.

## 5. Units and owned paths
| Unit | Entry scene / output | Owns |
|---|---|---|
| core (lead) | `main.tscn` | `game/project.godot`, `game/main.*`, `game/core/**`, `game/tools/**`, `tools/**`, `blender/lib/**`, docs |
| car_model | `game/assets/cars/roadster/roadster.glb` | `blender/car/**`, `game/assets/cars/roadster/**` |
| npc_cars | `game/assets/cars/npc/*.glb` | `blender/npc_cars/**`, `game/assets/cars/npc/**` |
| landmarks | `game/assets/landmarks/*.glb` | `blender/landmarks/**`, `game/assets/landmarks/**` |
| props | `game/assets/props/*.glb` | `blender/props/**`, `game/assets/props/**`, `tools/signs/**` |
| roads | `game/assets/city/roads/*.glb` + `game/world/data/{lanes,minimap,road_furniture}.json` | `blender/city/roads/**`, `game/assets/city/roads/**`, those 3 data files |
| buildings | `game/assets/city/blocks/*.glb` | `blender/city/buildings/**`, `game/assets/city/blocks/**` |
| bund | `game/assets/bund/*.glb` | `blender/bund/**`, `game/assets/bund/**` |
| city_layout | `data/city/city.json` | `data/city/**` (except SCHEMA.md, test_city.json), `tools/city/**` |
| world | `res://world/world.tscn` (WorldBase) | `game/world/**` except `env/` and the 3 roads data files |
| environment | `res://world/env/environment.tscn` | `game/world/env/**` |
| shaders | `MaterialLibrary` entries | `game/shaders/**` |
| vehicle | `res://vehicle/player_car.tscn`, `res://vehicle/cars/*.tscn` | `game/vehicle/**` except `camera/` |
| camera | `res://vehicle/camera/chase_camera.tscn` | `game/vehicle/camera/**` |
| fx | `res://fx/fx_director.tscn` | `game/fx/**` |
| damage | `res://damage/damage_director.tscn` | `game/damage/**` |
| traffic | `res://ai/traffic/traffic_director.tscn` | `game/ai/traffic/**`, `game/ai/common/**` |
| police | `res://ai/police/police_director.tscn` | `game/ai/police/**` |
| rivals | `res://ai/rivals/rival_director.tscn` | `game/ai/rivals/**` |
| modes | `res://modes/mode_director.tscn` | `game/modes/**` |
| hud | `res://ui/hud/hud.tscn` | `game/ui/hud/**`, `game/ui/theme/**` |
| menu | `res://ui/menu/menu.tscn` | `game/ui/menu/**` |
| audio | `res://audio/audio_director.tscn` | `game/audio/**`, `tools/audio/**` |

## 6. Marker names (car glTF, under the root node)
`Body`, `Glass`, `Interior`, `Wheel_FL`, `Wheel_FR`, `Wheel_RL`, `Wheel_RR` (origin at wheel
centre, spin axis X), `Caliper_*`, `Wing` (origin at hinge), `Door_L`, `Door_R` (origin at hinge),
`Bumper_F`, `Bumper_R`, `Hood`, `Diffuser` (detachable panels), `LightBar_Rear`, `Lamp_FL`,
`Lamp_FR`, `Brake_Light` meshes; Empties: `Nozzle_R1`..`Nozzle_R4` (rear, +Y = exhaust
direction), `Nozzle_P1`..`Nozzle_P6` (perimeter: P1/P2 front corners down, P3/P4 sides, P5/P6
rear corners down), `Fan_Intake`, `Light_Front`, `Light_Rear`, `Camera_Hood`, `Seat_Driver`.
Since 2026-10-23 the hero glb is the black and white Car Concept (`blender/car/concept/`): it also has
`Mirror_L`, `Mirror_R`, `Skirt_L`, `Skirt_R` and `Plate_Rear` (parts of the damage catalogue), carries no texture,
and has no `Diffuser`, `Lamp_Front` or `*_Inner` surfaces; `Wheel_*` is one mesh (rim, tyre and disc), the
contract materials are `SH_car_paint` (white), `SH_car_paint_black` (gloss black panels, ignores the racing
colour) and `SH_glass_smoke`.
