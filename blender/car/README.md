# The hero Roadster (blender/car)

> **Since 2026-10-23 the game's Roadster is not built here any more.** The hero car is the Khronos Car Concept,
> converted and painted black and white by `blender/car/concept/` (see its README). This procedural car, the
> 2nd-gen Tesla Roadster described below, stays in the repository as the reference it was built from.

Procedural build of the SKYRUSH hero car, the 2nd-gen Tesla Roadster as revealed
on 2026-10-15, with the **Rocket** trim (4 rear nozzles + 6 perimeter nozzles,
one driver seat and a COPV tank in the passenger space).

Everything is rebuilt from `ref/roadster/roadster_loft.json`: no number is
retyped, the JSON is the single source of truth.

## Build

```bash
/usr/bin/python3 blender/car/gen_textures.py        # the image maps (numpy + PIL)
tools/blender.sh run blender/car/build_all.py        # the model + the glb export
tools/blender.sh preview game/assets/cars/roadster/roadster.glb roadster --target-height 1.147
tools/blender.sh run blender/car/wheel_id.py         # the wheel's area fractions
tools/blender.sh run blender/car/capture.py          # the review captures
/usr/bin/python3 blender/car/compare.py             # the capture / photo sheets
tools/blender.sh run blender/car/overlay_render.py   # the orthographic masks
/usr/bin/python3 blender/car/overlay_check.py       # the overlay numbers
/usr/bin/python3 blender/car/red_audit.py           # the tail bar's pixel count
```

The output is `game/assets/cars/roadster/roadster.glb`.

**The maps are Blender inputs only.** They live in `blender/car/textures/`
(38 maps, 4.8 MB); the glb embeds them and Godot extracts its own copies
into `game/assets/cars/roadster/`. Nothing in `game/` loads the Blender
copies, so `game/assets/cars/roadster/textures/` does not exist: every PNG
there would cost a second Godot import (lead note IMPORT-CHURN). The
generator compares the bytes and writes a file only when it changes, so a
second run prints `textures: written 0 / unchanged 33` and the mtimes do not
move. The glb is exported to `tmp/car_model/roadster.glb` and copied into
`game/` only when the bytes differ.

## The modules

| file | what it does |
|---|---|
| `build_all.py` | the driver: materials, shell, panels, details, wheels, interior, export |
| `matset.py` | every material of the car, created exactly once |
| `materials.py` | the Principled BSDF factory (image textures, glTF-safe node graphs) |
| `regions.py` | where the detachable panels and the panel-gap lines are |
| `cuts.py` | the bisect planes of the JSON panel lines and the seam check |
| `panels.py` | the panels, cut OUT of the shell, with their dark inner surfaces |
| `valance.py` | the rear channel, the five round ports and their trough |
| `diffuser.py` | the four suction fans and the diffuser's fins and shelf |
| `wingparts.py` | the slat, the end plates and the struts of the wing |
| `details.py` | the light bars, the jewels, the plate, the markers, the intake |
| `thrusters.py` | the nozzles, the bores and the perimeter nozzles |
| `wheels.py` | the six-blade rims, the tyres and the brakes |
| `interior.py` | the seat, the COPV tank, the yoke, the screen, the ambient strips |
| `suspension.py` | the wishbones and the coilovers behind the wheels |
| `merge.py` | the static details, joined per material (fewer draw calls) |
| `finishing.py` | the arch lips, the material check and the triangle report |
| `wheel_id.py` | the flat ID render of the wheel face (the area fractions) |
| `capture.py` | the review captures (the studio rig) |
| `compare.py` | the capture / photo sheets |
| `overlay_render.py` / `overlay_check.py` | the orthographic masks and the numbers |
| `red_audit.py` | the red-pixel count of the tail bar (review r3 #8) |
| `texmaps.py` | the maps that need the mesh: the panel-gap normal map, the canopy frit |
| `uvtool.py` | the UV-space projection and rasterising helpers |
| `uv_car.py` | the one UV layer per mesh (smart, box, polar or cube) |
| `gen_textures.py` | the driver of the texture generator |
| `tex_common.py` | the shared helpers of the texture generator |
| `tex_body.py` | the plate, the light bars, the grille and the lens maps |
| `tex_wheels.py` | the tyres, the brake disc, the metals and the rim grain |
| `tex_parts.py` | the carbon, the trim and the interior maps |

## The shell

The shell comes from the lead's builder (`blender/lib/roadster_body.py`, core
owned): `body, glass, liners = roadster_body.build(col)`. The car does NOT build
its own loft. The detachable panels are then cut OUT of that shell
(`car/panels.py`), so a panel IS the skin - there is no duplicate surface
floating over the body and no sign-inverted offset. Behind every panel sits a
dark inner surface 15 mm inside, so the body never shows a hole when the damage
system throws a panel off.

## The UV layout

Every mesh carries exactly ONE uv layer (`UVMap`), because the glTF exporter
emits a second material for every extra uv set (that is what produced the
"M_BlackTrim.001" duplicates of the earlier build). The layer is a per-face
projection:

* the body, the glass and the panels keep the lead's smart projection - the
  4 mm panel-gap normal map and the canopy frit band are drawn in that space
  (`car/texmaps.py`);
* the faces of a tiling material (the black trim, the carbon, the interior) get
  a normalised box projection, so the grain keeps a constant texel density;
* the wheels, the brake discs and the nozzle rings get a polar projection
  (`u` = angle, `v` = radius or depth), so the machining marks and the radial
  brushing run in the right direction.

The body map is 4096 px (the gap grooves are 4 mm wide, see dossier §7.1); the
glass map is 1024 px; the rest is 512-2048 px.

## The panel cuts

The shell is bisected along the JSON panel lines **before** the panels are
picked (`car/cuts.py`): planes for the cowl, the vent hood and the wing edge,
and one plane per segment of `door_front_cut` / `door_rear_cut`, limited to
that segment's z range. The build prints the distance between the panel's
boundary and the JSON line, per panel; it is **0.0 mm for every panel**
(`Door_L/R`, `Hood`, `Wing`), so the geometric seam and the 4 mm groove
painted into the panel-gap map are the same line and every cut shows one
crisp groove.

## The wheel face

The rim is built in photo 13's layout: six wide white blades (#E6E6E8) with a
1 mm chamfer along their edges, and between two blades a dark V-spoke whose
two arms are 18 mm wide, with the brushed gold vane in the middle of the V,
recessed 6 mm below the arms. The dark hex cap with its two engraved rings
closes the hub. `tools/blender.sh run blender/car/wheel_id.py` renders the face
with flat ID colours and prints the area fractions (the review wants white
>= 55 %, dark <= 30 %, gold 5..10 %): **67.7 / 24.9 / 7.4 %** on the front
wheel and **68.3 / 24.1 / 7.5 %** on the rear one.

## The node names (CONTRACTS.md §6)

`Roadster` (root empty) > `Body`, `Glass`, `ArchLiners`, `Door_L`/`Door_R`
(+ `Door_Inner_*`), `Hood` (+ `Hood_Inner`), `Bumper_F`/`Bumper_R` (+ `_Inner`),
`Skirt_L`/`Skirt_R` (+ `_Inner`), `HeadlampPanel_L`/`_R` (+ `_Inner`), `Wing`
(+ `Wing_Slat`, `Wing_EndPlate_L/R`, `Wing_Strut_L/R`, `Wing_Inner`),
`Wheel_FL/FR/RL/RR` (+ `Tyre_*`), `Caliper_FL/FR/RL/RR` (with the disc),
`Diffuser`, `LightBar_Rear`, `Brake_Light`, `Lamp_Front`, `Lamp_FL/FR`,
`Plate_Rear`, `NozzleMesh_R1..R4`, `NozzleMesh_P1..P6` (+ `NozzleThroat_*`),
`Fan_R1..R4`, the markers `Nozzle_R1..R4`, `Nozzle_P1..P6`, `Fan_Intake`,
`Light_Front`, `Light_Rear`, `Camera_Hood`, `Seat_Driver`.

### The wing

`Wing` is the stowed deck lid; its pivot is the main element's leading edge
(`parts.wing.poses.stowed.le`). The pose angles live in the node's `poses`
property: `stowed` 0 deg, `low_drag` 1 deg, `high_downforce` 15 deg,
`air_brake` 60 deg (the JSON `parts.wing.poses.*.pitch_deg`).

**Deploy contract:** the game rotates the `Wing` about its local X by
**-pitch_deg** (the JSON's positive pitch lifts the trailing edge) and sets
the local scale of `Wing_Slat`, `Wing_Strut_L/R` and `Wing_EndPlate_L/R` from
**0.001 (stowed, as exported) to 1.0 (deployed)**. The parts are built at
their full deployed size from the JSON (`main_span_half`, `chord_total`,
`slat_chord`, `struts_x`, `endplate_bottom_z`, `endplate_cant_deg`) and are
collapsed in the stowed pose, so the car's height stays 1.147 m and the
stowed deck shows no carbon. The end plates hang from the wing's OWN leading
edge (the chord runs `chord_total` behind it) and the struts are swan-necks
of 20 x 40 mm.

### The brake light

`Brake_Light` is the inner half of the rear bar, 1 mm proud of `LightBar_Rear`
so the two never fight for the same pixels. Its material `M_BrakeLight` keeps a
weak red emission (2.5, its own map): the middle of the bar must still read as
a red line at 8.4 m, where the bar is only two pixels high. The game can raise
it further when the brakes are on.

### The light bar under AgX

The rear bar is 14 mm high with a 6 mm core. The map is built with
`lb["height"] * 1000`, so the core is really 6 mm inside the 14 mm lens. The
core is (255,26,42) and the lens (110,10,18), and the emission strength is
**10**: the lens reaches 1.55 and the core 10, so both bloom (the HDR
threshold is 1.1). Under AgX the core turns pink-white inside a saturated red
halo, which is what photo 19 shows; a 2.5 mm emissive bevel above and below
the lens keeps the edge readable at grazing angles. `red_audit.py` measures
the saturated red pixels in the car crop of the in-game chase capture.

### The rear bores

The four rear nozzles and the four fan ports are round holes in the valance.
They are cut with a boolean and then triangulated inside Blender, and the
triangles that lie inside the bore are dropped: a boolean leaves a "keyhole"
n-gon, and the glTF exporter's own triangulation would fill the hole again.
The dark surface behind the valance (`Bumper_R_Inner`) is cut with the same
bores, so the bore really goes through. The gold throat stands 2 mm proud of
the valance: its lip covers the edge of the hole and its 55 mm bore goes
30 mm deep, grading #B08458 -> #2A1A0E down the bore.

## Notes and deviations

* The glass is `SH_glass_gold` with the base colour #5A3F2A (the brief) and an
  alpha of 0.92 (the brief says 0.85): the canopy has to read as one continuous
  dark bronze shell, as in photo 03.
* The rear plate is the Chinese new-energy plate 0.48 x 0.14 m with the text
  沪A·D2049R (the brief); the JSON's `parts.plate` still carries the concept
  render's "RDSTR" plate, so the brief's version is used.
* The black trim uses the ambientCG `Plastic 006` set of the shared library
  (`tools/textures/fetch.py ambientcg Plastic006`); the rest of the maps are
  generated (`car/tex_*.py`).
* The review wants the tail bar to be 10 and its core (255,26,42): both are
  used. The review's own acceptance number (1200 saturated red pixels in the
  car crop at 8.4 m) is not met - the bar gives 419 - because a 14 mm bar is
  1.9 px high at that distance and the pink-white core it asks for is not a
  saturated red pixel. The bar's own peak is brighter than every NPC tail
  light in the same frame.
* The tyre maps are 2048x512 (the same pixel count as 1024²): the lettering
  runs once around the circumference. The two body maps are 4096², everything
  else is 1024² or less.
* The static details are joined per material (`car/merge.py`) to keep the
  draw calls down: 91 objects, 96 surfaces. The 62 contract meshes and their
  nine inner surfaces already need 84 of them.
