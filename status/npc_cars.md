# npc_cars status

Unit: NPC traffic fleet + police fleet (Blender → glTF). Owns `blender/npc_cars/**`, `game/assets/cars/npc/**`.

## State: the fleet is real car models (CC BY 4.0, the bus CC0), converted

The eleven cars of the traffic and the police are modified versions of real low poly car models (2026-10-26; the player said the
cars were "still placeholders"): `blender/npc_cars/web/convert_real.py` (with `real_mesh.py`, `real_rules.py`, `real_sources.py`,
`real_extras.py`; the whole fleet in about 15 s) builds them from the files of `blender/npc_cars/sources.json` (the URL, the sha256,
the author, the title and the licence of each), which `python blender/npc_cars/fetch_sources.py` downloads into
`F:/dev/skyrush-out/cache/cars` (not in the repository). The credits are in `CREDITS.md` and on the title screen.

| slot | source (author) | triangles | surfaces |
|---|---|---|---|
| sedan_ev | Kiri '10 (Daniel Zhabotinsky) | 11,028 | 22 |
| taxi | Kiri '10 + a roof sign | 11,040 | 23 |
| police_patrol | Kiri '10 + the police look | 13,084 | 26 |
| hatch_ev | Ace '11 (Daniel Zhabotinsky), the wheels of the Kiri '10 | 10,737 | 21 |
| suv_ev | Urban '10 (Daniel Zhabotinsky) | 15,600 | 24 |
| police_suv | Urban '10 + a push bar | 18,443 | 28 |
| robotaxi | SHC MC (denniswoo1993) + a LiDAR | 21,841 | 24 |
| police_interceptor | SHC MC | 23,223 | 26 |
| van | the minivan of the Generic passenger car pack (Comrade1280) | 7,450 | 21 |
| truck | LCT 3000 '07 (Daniel Zhabotinsky) | 12,576 | 20 |
| bus | City Bus (Grab3D, CC0) | 27,425 | 22 |

Still no texture and no UV: the textures are dropped and every face gets the plain colour its texture showed (the paint is the
game's shared car paint). The interiors are dropped (the glass is opaque). The police look is cut into the mesh (a navy band, a
yellow pinstripe, a red/blue light bar), there is no lettering. The GLB files are 6.9 MB together (0.9 MB before); in a parked
frame-probe A/B the median frame was 18.4 ms against 17.0 ms with the same draw calls (1034 against 1019). The earlier CC0 pack
("Free Low Poly Vehicles Pack" by Rgsdev) and its converter (`convert.py`, the section below) are kept in `blender/npc_cars/web/`
but no longer used. The police drone is still the procedural model of `blender/npc_cars/build.py`.

## The earlier CC0 pack (not used any more)

The cars of the pack were 1.4-1.9 k triangles, 70-95 KB each:

| model | source FBX | triangles | surfaces | notes |
|---|---|---|---|---|
| sedan_ev | Sedan | 1472 | 23 | |
| hatch_ev | Hatchback | 1382 | 22 | |
| suv_ev | SUV | 1752 | 24 | |
| taxi | Taxi | 1520 | 24 | the roof sign of the pack |
| robotaxi | Sports | 1422 | 23 | a LiDAR puck on the roof (added) |
| van | Van | 1396 | 21 | |
| bus | Bus | 1706 | 20 | 12 m, the rear axles are part of the Body |
| truck | Truck | 1864 | 21 | the cab of the pack's tractor + a cargo box and an under-run bar (added) |
| police_patrol | Police Sedan | 1512 | 23 | black and white, light bar |
| police_interceptor | Police Sports | 1418 | 23 | |
| police_suv | Police SUV | 1704 | 24 | |
| police_drone | procedural | 1456 | 17 | |

No texture and no UV: every surface is a plain colour. The GLB of a car is 70-95 KB.

## What the conversion of the earlier pack did (`convert.py`; `convert_real.py` keeps the same contract)

* Puts the car into the game frame (nose to Godot -Z, on the road, origin in the middle of the body, metres), scales it to the length
  of the fleet table and narrows it to the width of the table (and lowers the roof to the table's height: the pack's cars are bigger
  than the table says); the wheels keep their size.
* Splits the one body mesh **by face** into the nodes of the contract (CONTRACTS.md 6, the traffic lamps, the police light bar, the
  damage parts): `Body` (paint, trim), `Glass`, `Lamp_F`, `Lamp_R`, `Mirror_L/R`, the tear-off parts `Bumper_F`, `Bumper_R`, `Hood`
  and on the police cars `LightBar_Red`, `LightBar_Blue`; the wheels `Wheel_FL/FR/RL/RR` (origin = wheel centre, spin axis X; the
  extra axles of the bus and the truck are static and part of the Body); the empties `Light_Front`, `Light_Rear`, `Siren`.
* The paint is the shader material `SH_car_paint_npc` (its colour is the instance uniform `base_color_override`, so one material
  serves every car colour); the police cars are `NPC_police_black` / `NPC_police_white`; the glass is `NPC_glass_dark`; the lamps are
  `NPC_lamp_front`, `NPC_lamp_rear` and `NPC_lamp_brake` (the faces of the tail cluster that look straight back: the lens that
  `CarLights` flares and `TrafficLamps` lights when the car brakes).
* The bumpers are the faces under the lamps at the two ends (not the flank), the bonnet is what lies flat in front of the windscreen
  (80 % of the width: the fenders stay on the car). They sit on the origin of the car like every damage part, the flank faces stay in
  the Body, so **the Body AABB (the collider of a traffic car and of `vehicle/specs`) is still the whole length of the car**.
* The Body does not contain the mirrors (a mirror is 30 cm of width that the car has not).

## Rules for the units around it

* Re-run `python tools/gd.py test res://vehicle/specs/gen_specs.gd` after every reconversion (the vehicle specs read the Body AABB and
  the wheels from the GLB) and update `TrafficFleet.MODELS` if a size changed (`test_npc_nodes.gd` compares them, 0.12 m tolerance).
* `blender/npc_cars/build.py` refuses a car id: the procedural cars would overwrite the converted GLB files.
* Do not give a GLB a texture again without a reason: the old fleet shipped 262 extracted sheets, now there are none (the drone keeps
  three in `textures/`, made by `gen_textures.py`).

## How to test

* `python tools/gd.py blender run blender/npc_cars/web/convert.py [-- sedan_ev ...]`  (all 11, or the ids given)
* `python tools/gd.py import`, then `python tools/gd.py test res://vehicle/specs/gen_specs.gd`
* `python tools/gd.py test res://assets/cars/npc/tests/test_npc_nodes.gd`  (nodes, lamps on the right ends, on the ground, wheels,
  table dimensions, mirrors, tear-off parts, budget)
* `python tools/gd.py test res://assets/cars/npc/tests/test_npc_materials.gd`  (the material names the game looks for, flat colours)
* `python tools/gd.py test res://damage/tests/test_recycle.gd`  (the bumper of a police car comes off and is back after a recycle)
* a look: `python tools/gd.py shot --scene=res://assets/cars/npc/preview_npc.tscn --out=npc --env-only --cams="row1:0.25,2.4,-15:0.25,0.8,0:70"`

## Known limits

* The doors are not separate nodes (the old fleet had `Door_*` meshes, but the damage catalog never detaches them: `MODE_WRECK` parts
  other than the wheels are skipped). A torn-off bumper or bonnet leaves an open body (no engine bay, no inside).
* There is no interior, no number plate text and no taxi sign text: the plate is a white rectangle of the trim material.
* The cars are flat colours; the look comes from the paint shader and the light, not from textures.
* A car has 20-24 surfaces (draw calls): 8 of them are the four wheels (a tyre and a rim each).

## Licence

CC0 (`blender/npc_cars/web/source/License.txt`, the 21 FBX of the pack are kept there: 1.4 MB). No credit is needed; CREDITS.md names
the author anyway.
