# The hero Roadster, black and white (blender/car/concept)

`game/assets/cars/roadster/roadster.glb` is the Khronos **Car Concept** turned into the SKYRUSH hero car:
white pearl body, gloss black panels, black wheels, neutral smoke glass. The model was found on the web
(glTF-Sample-Assets, CC BY 4.0, see `/CREDITS.md`), it was not modelled here. The older procedural
Roadster (`../`, `build_all.py` and friends) is still in the repository but it no longer feeds the game.

## Build

```sh
python tools/gd.py blender run blender/car/concept/build_hero.py -- --out F:/dev/skyrush-out/tmp/car/roadster.glb
copy the glb to game/assets/cars/roadster/roadster.glb, then:  python tools/gd.py import
python tools/gd.py test res://assets/cars/roadster/tests/test_roadster.gd
# a look at it without Godot (Cycles on the CPU): add  --preview F:/dev/skyrush-out/tmp/car/look
```

The build is deterministic: the same source gives the same bytes (SHA-256 of the shipped glb
`e962b671...`). It needs about 15 s.

## What the script does to the concept

| step | file | what |
|---|---|---|
| 1 | `concept_import.py` | imports the glb, bakes every part into world space, **straightens the wheels** (the concept is posed with its front wheels steered 30 degrees and every wheel spun to a random angle), turns the car to face +Y, puts the middle of the wheelbase on the origin and the tyres on the ground |
| 2 | `concept_body.py` | the wheels (tyre + rim + disc in one mesh, origin on the hub, spin axis X) and the calipers (put behind the axle, they were at random angles); the hood is cut out of the front shell; the lower black panels are split into `Bumper_F`, `Bumper_R`, `Skirt_L`, `Skirt_R`; doors (origin on the front edge, so the damage unit can spring them open), mirrors, glass, lamps, a light interior; everything else (wipers 24k triangles, engine, axles, door cards, seat frames, pedals) is dropped; the rest of the body is one mesh |
| 3 | `concept_extras.py` | what the concept lacks: the active **wing** (blade on two posts, the four poses in the glTF extras), the four rear **nozzle** bells, the `Brake_Light` strip, the markers of CONTRACTS.md 6 (nozzle jets, lights, hood camera, seat), the root `Roadster`, the export |

Triangles: 213k in the concept, **65k** here (the first Roadster had 71k). The wheels are 5.1k each (the
rims were 12.2k, decimated to 4.3k), the body shell 17k, the doors 3.6k each.

## Decisions that are easy to get wrong

* **No symmetric decimation.** `Decimate` with `use_symmetry` tears holes along the creases (the
  concept is not exactly symmetric); the body shows black slivers. The plain collapse is clean at 0.4.
* **No texture at all.** The paints are the game's own shaders (`SH_car_paint`, `SH_car_paint_black`,
  `SH_glass_smoke`, swapped in by `MaterialLibrary`), the rest are plain colours. The glb has no image, so
  Godot extracts nothing next to it and the Khronos logos that were in the concept's textures are not in the
  derived model (the licence excludes logos).
* **The black paint ignores the racing colour.** `SH_car_paint_black` has `allow_override = false`, so a
  rival that takes its racing colour keeps black panels (`shaders/tests/test_two_tone.gd`).
* **The scheme is a test.** `assets/cars/roadster/tests/test_roadster.gd` fails on any coloured surface
  (except the lights), any texture, a gold or red accent material, wheels that are not on their hubs, a
  rotated wheel node, a door that is not hinged on its front edge, a nozzle that fires the wrong way.
* **The wheel layout is the spec.** `vehicle/specs/roadster.tres` was written from these numbers
  (track 1.952 / 1.964, wheelbase 2.80, tyre radius 0.384, body box 2.10 x 0.86 x 4.30 centred at y 0.65).
  If you move a wheel, regenerate the spec.

## Not done

* `Diffuser` (a detachable rear diffuser): the concept has no separate piece; the catalogue ignores the name.
* The old procedural car had a printed plate texture and tyre lettering. This one has neither.
* The traffic and police cars (`assets/cars/npc`) are still the stylised procedural ones.
