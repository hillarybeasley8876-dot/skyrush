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

## The traffic and police cars: "Free Low Poly Vehicles Pack" (CC0)

The cars of the traffic and the police (`game/assets/cars/npc/*.glb`: sedan, hatchback, SUV, taxi, robotaxi, van, bus, truck and the
three police cars) are converted from the **Free Low Poly Vehicles Pack** by **Rgsdev** (Raphael Goncalves):

* Source: the FBX files of the pack, kept in `blender/npc_cars/web/source/` with their `License.txt`
* Licence: CC0 1.0 (public domain), no credit needed; it is given anyway
* Changes: the cars were scaled and narrowed to the sizes of the fleet table, the roofs were lowered, the body mesh was split into the
  parts of the SKYRUSH car contract (bumpers, bonnet, lamps, glass, mirrors, light bar), the materials were replaced by the game's
  paint, glass and lamp materials, and a cargo box (truck) and a LiDAR puck (robotaxi) were added. The conversion is in
  `blender/npc_cars/web/convert.py` and can be re-run.

## Other assets

* Textures: Poly Haven, ambientCG (CC0), downloaded by `tools/textures/fetch.py`
* Fonts: Smiley Sans, Noto Sans SC (SIL OFL, licences in `game/assets/fonts/`)
