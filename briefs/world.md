# Brief: world — assemble the playable Shanghai in Godot (WorldBase)

## Goal
One scene that loads the whole city (roads, blocks, Bund, landmarks, props, water), places all
furniture and gameplay sites from data, wires every trigger, and runs at 60 fps — implementing the
`WorldBase` contract that AI, modes, HUD and the player rely on.

## You own
`game/world/**` except `game/world/env/` (environment unit) and the roads unit's data files
`game/world/data/{lanes,minimap,road_furniture}.json`. Entry (Modules unit `world`):
`res://world/world.tscn` whose root script `extends WorldBase` and sets `Game.world = self`.

## Read first
`core/contracts/world_base.gd`, `lane_path.gd`, `race_route.gd`, `sky_lane.gd`, `charge_station.gd`,
`stunt_gate.gd`, `core/events.gd`, `core/materials/material_library.gd`, `core/sandbox/*` (a tiny
WorldBase example), `data/city/SCHEMA.md`, `data/city/test_city.json` (develop on it; switch to
`city.json` when it validates), `ref/tech/GODOT.md` §4–§6 + §10 (HLOD, MultiMesh, occluders,
visibility ranges, backface collision, kill floor), `ref/art/DOSSIER.md` §3.4–3.7 (light budget,
light pooling, probes, light-pool decals, soffit wash), `ref/gameplay/DOSSIER.md` §3.4 (pursuit
breakers, charge bays, hiding spots, toll infraction), §5.6–5.7 (sky lanes, obstacles),
`ref/shanghai/SHANGHAI_DOSSIER.md` §7.2 (toll plaza gameplay hooks), §10 (map), `ART.md`.

## Deliverables
1. **Loader** (`world/loader/*.gd`): reads city.json + roads data; instantiates every
   `res://assets/city/roads/roads_*.glb`, `res://assets/city/blocks/blocks_*.glb` (+ `_far` HLOD
   with `visibility_range_begin` 350 m / near tiles `visibility_range_end` 400 m), the Bund glbs,
   landmarks at their dossier anchors, props sites at POIs; calls `MaterialLibrary.apply()` on each;
   sets `building_seed` instance uniforms from glb metadata; skips missing files gracefully
   (warn once). Emits `Events.loading_progress`. Target < 15 s to playable on this Mac.
2. **Water**: Huangpu polygon + Suzhou Creek strip at y −3 with `SH_water` (environment unit's
   material; plain dark glossy fallback), vertical bank walls (concrete) where banks are walls.
   Ground plane at y −0.02 under land (dark asphalt/earth textured, never untextured), kill floor box
   at y −60.
3. **Furniture placement** from `road_furniture.json`: MultiMeshInstance3D per prop type per 512 m
   tile for static repeated props (planters, lamps, trees, bins, bollards); real scenes for
   interactive ones (traffic lights with lens switching on a per-junction phase cycle 30 s / 3 s
   amber; `signal_state()` implemented; guide gantries with generated sign textures; VMS). 
4. **Lights**: emissive heads everywhere; a pool of ≤ 32 OmniLight3D/SpotLight3D (no shadows,
   `distance_fade` 60 m) re-assigned every 0.25 s to the lamps nearest the camera; Bund uplights from
   `game/assets/bund/bund_lights.json` (pooled too, ≤ 12 SpotLights); dragon-pillar uplights;
   light-pool decals for far lamps; soffit wash per art dossier §3.7. Reflection probes per art
   dossier §3.5 along roads — only those within 400 m enabled; measure cost.
5. **Gameplay sites**: `ChargeStation` areas at charge POIs (sized from the charge_station glb's
   `ChargeArea`); `StuntGate`s over gas-station canopies ("飞跃加油站!"), the toll plaza
   ("飞跃收费站!") and roadblock sites; **toll plaza logic** (barrier arms = RigidBody3D frozen until
   hit → become debris; ETC lanes lift automatically; passing a closed lane or flying over →
   `Events.infraction(player, &"toll_evaded")`); **pursuit breakers** (gas canopy / billboard /
   scaffold: hitting `Support_*` at ≥ 60 km/h collapses it in 1.2 s, wrecks police within the
   25 × 12 m zone behind it via `vehicle.wreck(player)`, emits `Events.stunt(&"breaker", 500,
   "加油站坍塌!")`); **sky lanes** from city.json (SkyLane node + LaunchPad + pad glb + ring gates
   every `ring_spacing` + gantry 300 m before); hiding spots as POIs.
6. **WorldBase API**: spawn transforms (player/police/traffic/rival from city.json spawns and
   lanes), `nearest_road_transform()` (closest lane point, facing lane direction, on the correct
   deck level — use the car's height to pick elevated vs surface), lane paths from lanes.json
   (Curve3D per lane, `next_lanes` indices), routes → RaceRoute (checkpoint transforms, racing line
   through the lanes, grid), minimap polylines from minimap.json, POIs (incl. sky lanes, police
   stations), roadblock sites, `signal_state()`.
7. **Performance pass**: occluders from building metadata, visibility ranges, MultiMesh chunking;
   report fps at 6 standard viewpoints (Bund road, Yan'an deck, under the dragon interchange,
   Lujiazui, Nanpu spiral top, flight altitude 120 m) in status — target ≥ 60 fps at 1080p on high.
8. Tests: `world/tests/test_world_api.gd` (headless: loads test_city then city, checks every
   API method, lane continuity, spawn points on roads, routes closed), `test_drive_lanes.gd`
   (headless physics: a probe body follows sample lanes at 100 km/h without falling through).

## Acceptance
`main.tscn` boots into the real city with the player car on the Bund; captures at the 6
viewpoints look complete (no missing tiles, no untextured surfaces, lights where expected);
API tests pass; fps targets met or the gap explained with numbers.
