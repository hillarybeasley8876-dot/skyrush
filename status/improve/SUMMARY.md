# improve/openworld — what changed and what is left

Branch `improve/openworld` (local, nothing pushed). The brief: open-world sports-car map (viaduct links, correct Z interaction, real
collisions, behaviour logic, the flying feature), with a weak cheap model (MiniMax M3.1 Flash) as the workers and the lead as the
reviewer (`tools/m31w`). Then: a web-sourced hero car (black and white), and "continue to optimise all bugs, correct interactions".

## The hero car

Khronos Car Concept (CC BY 4.0), converted by `blender/car/concept` to the vehicle contract: white pearl paint, black paint, black
rims, smoked glass. Collision box 1.9 m wide (the oracles' car), floor 0.34 m over the road (`MIN_BOX_BOTTOM`).

## Collisions and interactions fixed in the last rounds (every item has a test or a tool that measures it)

| what | cause | fix | check |
|---|---|---|---|
| the car flew or stuck to walls | wheel probes took walls/ceilings for ground; kerbs of 15 cm launched the car; solver spikes | ground normal limit, damped bump stop, solver spike guard, box floor | `vehicle/tests` (kerb climb, air boosts), `fuzz_drive.gd` |
| street props had no collision at all | the shapes were freed with their builder | the body keeps the shapes; shapes turn with the prop; soft furniture (bollards, bins, signs ...) is not solid | `test_prop_collision_orientation.gd` |
| bus shelters and noise walls across the road | heading mirrored in the roads generator; boxes put into world axes | generator fixed, shelters lie along the lanes, boxes that reach into a lane move away or go | `test_prop_alignment.gd` |
| kerb and median walls, the edge of the world | none existed / the ground ended at the window | kerb colliders, 100 m of extra ground and four walls | `test_edge_walls.gd`, `fuzz_drive.gd` |
| falls off the viaducts | open deck edges (903), low parapet collider with a chamfer | edge-fence job, `edgewalls.py` (237 walls), parapet collider 1.0 m with a vertical face | `fuzz_drive.gd --elevated=1`: 26 of 40 drives left the deck -> 0-2 |
| traffic cars of different lanes drove through each other, jammed on kerbs | the lane hash knew one lane only | `DriveContext.cells`, `_conflict_gap` (the younger car yields), box floor | `test_conflict_yield.gd`, `test_kerb_lane.gd`, `soak_traffic.gd` |
| the Bund facades stood in the west lanes | the dossier line is up to 10 m east of the road of the city | `bund/data.py` follows the city road (status/bund.md) | `test_bund_lanes.gd` |
| cross streets ran through the Bund buildings | the streets of the city run to the centre of the Bund | `roads/buildingcut.py` ends them at the buildings (status/roads.md) | `test_bund_lanes.gd`, the `check_*` oracles of tools/city |
| trees and lamps in the mouth of a junction | the filter kept 8 m around the centre, the box is bigger | `FurnitureFilter._index_mouths` (status/world.md) | `test_junction_mouths.gd` |
| the rivals stopped dead at the start of the Bund sprint (3-4 rescued in 20 s) | connector lanes widened the measured road by 10 m; a tree in the mouth of Fuzhou Rd | `RivalRoad.road_frame` leaves connectors out, `LANE_RATE`, the tree is gone | `test_real_start.gd` (both routes), `test_real_route.gd` |
| two tests died before they measured anything | no gate boards for the 8 gates of the sandbox loop | `gen_gate_textures.py` | `test_race_flow.gd` runs to its own thresholds now |
| 13 identical noise walls at the end of the Yan'an Elevated | a declared run longer than the road, `road.at` clamps | `min(b, road.length)` | the data: 33 -> 19 walls |

## Tools added (game/tools, tools/)

`fuzz_drive.gd` (random whole-game drives with a flight recorder), `soak_traffic.gd`, `height_map.gd`, `touch_probe.gd` (what a car
touches at a place, `--mask=4` for the props alone), `prop_lane_clearance.gd`, `tools/run_follow.py` (follow trials),
`blender/city/roads/edgewalls.py`, `blender/city/roads/buildingcut.py`.

## Test state (147 tests, `python tools/run_tests.py --jobs 3 --timeout 420`)

The failures that were in the baseline of the first round and are still there: `ai/rivals/test_performance` (0.54 ms against 0.35),
`ai/rivals/test_race_flow` (5 passes of 6, 4 contacts over 800 N*s), `ai/traffic/test_lanes_world`, `roads/test_lanes` (6 lanes that
end at a junction), `roads/test_drive_collision` (surface under the lanes, parapet in the way: the surface oracle is not a hole
detector, the ground backs it), `world/test_world_api` (the `test_loop` route), `ai/police/test_perf` (only under load),
`ai/rivals/test_real_route` (passes alone in 100 s, the suite gives a test 120 s).

## Known limits

* The collision hulls of the Oriental Pearl (the drum is cut now), the Shanghai Tower and the SWFC still lie over a few lanes (about 70
  samples of 150,000), the D0 streets east of the Bund run into the flood wall of the promenade (15 samples). A probe that writes the
  blocked samples for `buildingcut.py` to read would close the class.
* Street props are solid now (trees, lamps, shelters, planters): by the damage rules a head-on hit at 108 km/h or more wrecks the car.
* The racing line of the Bund sprint goes by Fuzhou Rd and Sichuan Rd now that Hankou Rd ends in the Customs House (the shortest path
  is a tie between several streets).
* The rivals race at 55 m/s on the Bund (200 km/h on a 50 km/h road): the speed profile is the grip budget of the car, not the limit
  of the road.

## Do not forget

* `world_cache.gd` VERSION has to be bumped when the furniture placement or the lane build changes (the key is the hash of the data).
* The generated assets (tiles, Bund glb, rebuilt blocks, ~1.4 GB of `.git`) are committed on the branch: look at the size before a push.
