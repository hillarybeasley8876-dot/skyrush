# Credits and licences of third-party assets

## The hero car: "Car Concept" (CC BY 4.0)

The Roadster you drive (`game/assets/cars/roadster/roadster.glb`) is a modified version of
**Car Concept** from the Khronos glTF Sample Assets:

* Model and textures: **Eric Chadwick**, (c) 2024 Darmstadt Graphics Group GmbH
* Source: https://github.com/KhronosGroup/glTF-Sample-Assets/tree/main/Models/CarConcept
* Licence: Creative Commons Attribution 4.0 International, https://creativecommons.org/licenses/by/4.0/
* The asset itself started from the public domain (CC0) model "Free Concept Car 004" by **Unity Fan**:
  https://sketchfab.com/3d-models/free-concept-car-004-public-domain-cc0-4cba124633eb494eadc3bb0c4660ad7e

**Changes made** (CC BY 4.0 section 3(a)(1)(B)): the wheels were straightened and re-centred, the car was
turned to face +Y and re-origined, the mesh was reduced from 213k to 65k triangles (wipers, engine, axles,
door cards, seat frames and other hidden parts removed, the rest decimated), the parts were renamed and
split to the SKYRUSH car contract (hood, doors, mirrors, bumpers, skirts, wheels, calipers, glass,
interior), a wing, rear nozzles, a brake light strip and the contract markers were added, and the whole
car was re-painted **black and white** (white pearl body, gloss black panels, black wheels, smoke
glass). All textures were removed. The conversion is in `blender/car/concept/` and can be re-run; the
original file and its licence text are kept in `blender/car/concept/source/`.

The licence of the original excludes the Khronos and 3D Commerce logos; they were part of the concept's
textures and are **not** in the derived model.

The credit is also shown on the title screen of the game.

## The traffic and police cars (CC BY 4.0, one CC0)

The cars of the traffic and the police (`game/assets/cars/npc/*.glb`, all but the drone) are modified versions of these models.
The list with the download links and the sha256 of every file is `blender/npc_cars/sources.json`;
`python blender/npc_cars/fetch_sources.py` downloads them (they are not in the repository) and
`blender/npc_cars/web/convert_real.py` converts them.

| Cars | Model | Author | Licence | Source |
|---|---|---|---|---|
| sedan, taxi, patrol car | **Kiri '10 - Low poly model** (in the Objaverse snapshot: "Generic sedan 2010 - Low poly model") | **Daniel Zhabotinsky** | CC BY 4.0 | https://sketchfab.com/3d-models/kiri-10-low-poly-model-7fd6e15785fa4aa9bfd6e31eb7c97ba6, via Objaverse (allenai/objaverse) |
| hatchback | **Ace '11 - Low Poly model** ("Modern Hatchback - Low Poly model") | **Daniel Zhabotinsky** | CC BY 4.0 | https://sketchfab.com/3d-models/ace-11-low-poly-model-055ff8a21b8d4d279debca089e2fafcd, via Objaverse (allenai/objaverse) |
| SUV, heavy police SUV | **Urban '10 - Low poly model** ("Generic SUV - Low poly model") | **Daniel Zhabotinsky** | CC BY 4.0 | https://sketchfab.com/3d-models/urban-10-low-poly-model-2866efdfa943484391ef8313768e074d, via Objaverse (allenai/objaverse) |
| box truck | **LCT 3000 '07- Low poly model** (in the Objaverse snapshot: "Light Commercial Truck '07- Low poly model") | **Daniel Zhabotinsky** | CC BY 4.0 | https://sketchfab.com/3d-models/3be03b6a43aa41898c9ca806b8787052, via Objaverse (allenai/objaverse) |
| van | the minivan of **Generic passenger car pack** | **Comrade1280** | CC BY 4.0 | https://sketchfab.com/3d-models/generic-passenger-car-pack-20f9af9b8a404d5cb022ac6fe87f21f5, via Objaverse (allenai/objaverse) |
| robotaxi, police interceptor | **SHC MC Free Promotion Car** | **denniswoo1993 (SHCreations)**, https://sketchfab.com/denniswoo1993 | CC BY 4.0 | https://opengameart.org/content/shc-mc-free-promotion-car (submitted by brylie; original https://sketchfab.com/models/cfaabdec76a74b68a48ba5657b6d9aee) |
| city bus | **City Bus** (Cozy Vehicles Kit) | **Grab3D** | CC0 1.0 (no credit needed; given anyway) | https://grab3d.com/models/vehicles/city-bus/ |

Licence: Creative Commons Attribution 4.0 International, https://creativecommons.org/licenses/by/4.0/ (CC0 1.0:
https://creativecommons.org/publicdomain/zero/1.0/).

**Changes made** (CC BY 4.0 section 3(a)(1)(B)): every model was turned to face the game's forward axis, re-origined and
scaled (the Kiri '10 was also made 5-7 % wider, the Urban '10 of the heavy police SUV 4 % wider and the SHC MC 6 % narrower;
the minivan was taken out of its pack), its interior, the inner surface of its double window panes and the parts hidden
behind the lamp lenses were removed, the mesh was split into the parts of the SKYRUSH car contract (body, bonnet, bumpers,
mirrors, glass, lamps, four wheels with their origin on the hub), **all textures were removed** and every face got a plain
material of the colour its texture showed (paint, one black for the trims, chrome, silver, lamp lenses, tyres, rims), the
paint became the game's shared car paint, the wheels of the Ace '11 were replaced by the wheels of the Kiri '10, the
honeycomb grilles of the SHC MC were replaced by dark plates and its wheels and lamp housings were decimated, the window
glass of the city bus was decimated. Added: a roof sign (taxi), a roof LiDAR (robotaxi), the fictional "天巡 SKYPOL" police
look (a navy band and a yellow pinstripe cut into the body, a light bar, a push bar on the heavy SUV) and the box of the
truck repainted as a white cargo box. No brand badge, emblem or text of the originals is used.

The credit is also shown on the title screen of the game.

The earlier low poly fleet ("Free Low Poly Vehicles Pack" by Rgsdev, CC0) is no longer used by the game; its FBX files and the
old converter are still in `blender/npc_cars/web/` (`source/`, `convert.py`).

## Other assets

* Textures: Poly Haven, ambientCG (CC0), downloaded by `tools/textures/fetch.py`
* Fonts: Smiley Sans, Noto Sans SC (SIL OFL, licences in `game/assets/fonts/`)
