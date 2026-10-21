# car_model status

## Done (review round 3)

**#1 IMPORT-CHURN (the mandatory lead note).**
- The generated maps live in `blender/car/textures/` (Blender inputs only).
  `game/assets/cars/roadster/textures/` and its 38 `.import` files are gone.
- `tex_common.save()` and `texmaps.save_png()` encode to memory, compare the
  bytes with the file and write only when they differ. The generator prints
  `textures: written 0 / unchanged 33` and the shell maps
  `shell maps: written 0 / unchanged 5`; the PNG mtimes do not move.
- The glb is exported to `tmp/car_model/roadster.glb` and copied into `game/`
  only when the bytes differ. **Known limit:** two consecutive exports still
  differ in ~100 of the 9.5 M bytes (float noise in the last bits of some
  normals, from the boolean solver), so the glb itself is rewritten on every
  build. The 38 PNGs - the expensive part - are not.
- **Sizes:** 38 maps in `blender/car/textures/` = **4.8 MB**; Godot extracted
  38 PNGs into `game/assets/cars/roadster/` = **5.1 MB**; the glb is
  **9.49 MB**. Only the two body maps are 4096²; the tyre maps are 2048x512
  (the same pixel count as 1024², because the lettering runs around the
  circumference); everything else is 1024² or less. `titanium_nor` is now
  512².
- Every Godot and Blender run is in the foreground (`tools/godot.sh`,
  `tools/blender.sh`); no `nohup ... &` anywhere.

**#2 The plate and its frame.** `Plate_Frame` is a 5 mm black ring with a
hole (front face y -2.097, 10 mm deep, 1 mm bevel), the plate's face is at
y -2.094: **the test measures 3.0 mm** between the frame's front face and the
plate. `Brake_Light` is 1.0 mm proud of the bar.

**#3 The panels are cut on the JSON lines.** `car/cuts.py` bisects the shell
along every JSON line before the panels are picked, and the build prints the
seam of every panel: **all of them are 0.0 mm off the JSON line**
(`door_front_0/1`, `door_rear_0`, `door_lower`, `cowl`, `vent_hood`,
`wing_edge`, `headlamp_rear`). The panel-gap map is drawn on the same lines,
so every cut shows one crisp 4 mm groove.

**#4 The wing.** The end plates are built from the wing's own leading edge
(`chord_total` behind the LE, hanging to `endplate_bottom_z`, canted 15°),
6 mm carbon with a 1 mm bevel; the struts are swan-necks of 20 x 40 mm; the
slat, the struts and the end plates are collapsed to 0.001 in the stowed
pose, so the stowed deck is clean white. The deploy contract (in the README
and in the `deploy_contract` property): **rotate the local X axis by
-pitch_deg, and scale the slat, the struts and the end plates from 0.001 to
1**. The test checks the stowed positions and the deployed end plates
(x ±0.74..0.80, z 0.78..1.15, length 1.70..2.40 in the Godot frame).

**#5 The contract meshes.** `Lamp_FL/FR` are the emissive jewels (36 tris
each, M_Jewel); `Bumper_R_Inner` has M_InnerDark; the reflectors are 120 x 12
mm lenses lying flat on the tail; the `Diffuser`'s origin is at its centroid.
The test checks that **every one of the 96 surfaces has a material**.

**#6 The right-hand tyres.** The left tyre is the right one turned 180° about
the axle (not mirrored) and its u is flipped, so the lettering reads the same
way on both sides: the test measures **+1 / +1**.

**#7 The wheel face.** The face is rebuilt: six wide white blades (#E6E6E8,
1 mm chamfers), six dark V-spokes whose two arms are 18 mm wide, and the
brushed gold vane inside each V, recessed 6 mm below the arms, plus the dark
hex cap with its two engraved rings. The flat ID render
(`tools/blender.sh run blender/car/wheel_id.py`) prints the area fractions:
**Wheel_FR white 67.7 % / dark 24.9 % / gold 7.4 %** and
**Wheel_RR white 68.3 % / dark 24.1 % / gold 7.5 %**
(target: white >= 55 %, dark <= 30 %, gold 5..10 %).

**#8 The rear light bar.** `M_LightBarRear` is at strength 10, the lens is
(110,10,18) and the 6 mm core (255,26,42), with a 2.5 mm emissive bevel above
and below the lens. In the game look the bar reads as a **pink-white core
inside a red halo** (the core (253,167,150), the halo 3 px above and below),
which is what photo 19 shows. `red_audit.py` now measures the review's round
3 metric (saturated red: R > 120, R > 1.8 G, R > 1.8 B).

**#9 The rear valance.** The four nozzles stand in one recessed channel with
five small round ports (a collar and a cup, so they read as black round
holes), the four fans sit 150 mm deep in matte `M_InnerDark` tunnels with
satin black rims and a dark grille, and the diffuser is five full-height
carbon fins with a shelf. The gold throats do not glow any more
(`M_NozzleGold` has no emission) and the bores of P1-P6 are punched.

**#10 The trim.** The black trim uses the library normal at a 0.55 strength
tiled at 0.50 m with a roughness of 0.55, and `M_ArchLip` (0.35) is on the
outermost band of the arch liners. The inner surfaces use a specular of 0.15,
so the deep recesses stay matte instead of mirroring the sky.

**#11 The triangle budget.** **71 217 triangles** (the brief asks for
70k-110k), 91 objects, 96 surfaces. The wheels and the tyres take 30 %.
`Cockpit` is 2 148 tris (<= 3k).

**#12 The test.** `tests/test_roadster.gd` is split into
`roadster_checks.gd` and `roadster_checks2.gd` and prints **21 checks, all
PASS**.

**#13 Honest reporting.** `overlay_check.rear_check()` measures the RENDERED
mask (the orthographic rear mask and the bar mask) against photo 08: the
light bar's row (photo 490 vs model 520, -67 mm), its span (753 px vs 760 px,
-16 mm) and its centre (x 798 vs 801, -6 mm).

**SHOULD-FIX items that are done**
- **Draw calls.** The static, non-contract details are merged per material
  (`car/merge.py`): 37 objects into 10 groups (the fan rims, the grilles, the
  nozzle throats, the suspension, the cabin, the inner surfaces, the red
  accents, the screens, the side markers, the reflectors). **96 surfaces**
  (134 before). The 62 contract meshes and their 9 inner surfaces already
  need 84 surfaces, so the review's target of 80 is out of reach without
  renaming contract meshes.
- **The empty except.** `panels._inner_surface()` counts the side walls it
  cannot build and the build prints them (none are skipped at the moment).
- **The splitter.** The carbon lip under the prow is now **1.10 m wide**
  (it was 0.34 m), with the prow overhanging in the middle.
- **The cabin.** `M_RedAccent` is at 0.5, so the ambient strips only show as
  faint shapes through the canopy.

## In progress / next
- The glb is still rewritten on every build (the float noise above); the
  textures are not.
- The synthetic maps (gold_nor, wheel_nor, copv_nor, seat_weave_nor) are
  still almost perfectly periodic; they need the irregularity the review
  asks for.

## How to test (exact commands)
```bash
/usr/bin/python3 blender/car/gen_textures.py                 # the image maps
tools/blender.sh run blender/car/build_all.py                 # the model + the glb
tools/blender.sh run blender/car/wheel_id.py                  # the wheel's area fractions
tools/blender.sh run blender/car/capture.py                   # the review captures
/usr/bin/python3 blender/car/compare.py                      # the compare sheets
tools/blender.sh run blender/car/overlay_render.py            # the orthographic masks
/usr/bin/python3 blender/car/overlay_check.py                # the overlay numbers
/usr/bin/python3 blender/car/red_audit.py                    # the tail bar's pixel count
tools/godot.sh check --only=res://assets/cars/roadster/
tools/godot.sh test res://assets/cars/roadster/tests/test_roadster.gd
tools/godot.sh shot --scene=res://assets/cars/roadster/preview_roadster.tscn \
    --out=car_glb --cams=res://assets/cars/roadster/preview_cams.json --warm=90
# the in-game look (the environment unit's scene) with the car cameras
tools/godot.sh shot --scene=res://world/env/lookdev.tscn --out=lookdev_car \
    --cams=res://assets/cars/roadster/lookdev_cams_car.json --warm=90
```

## Evidence
- **The Godot test: PASS all checks (21).** 62 contract node names, the
  contract materials, no duplicated material name, the bounding box
  1.977 x 1.145 x 4.380 m, every mesh inside the body+wheel AABB, every
  `*_Inner` inside its panel, the diffuser symmetric, the wheel hubs at
  0.343/0.367, the left/right layout, the body's UVs inside 0..1, 88 normal
  textures with relief, the plate 1:1, **all 96 surfaces have a material**,
  `Lamp_FL/FR` emissive, **the plate 3.0 mm clear of its frame**, the brake
  light 1.0 mm clear of the bar, the wing's poses, every wing part stowed on
  the wing, the deployed end plates in place, the tyres wound the same way
  (+1 / +1).
- **The build prints:** `cut door_front_0 12 seam edges, 0.0 mm off the JSON
  line` (and the same for the other seven cuts), `Door_R seam 0.0 mm off the
  JSON line (door_front_0, door_front_1, door_rear_0, door_lower)`, `Hood
  seam 0.0 mm`, `Wing seam 0.0 mm`, `MERGED 37 detail objects into 10
  groups`, `TRIS 71217 objects 91`.
- **The wheel's area fractions:** white 67.7 % / dark 24.9 % / gold 7.4 %
  (front) and 68.3 / 24.1 / 7.5 % (rear).
- **The overlays** (`captures/car_model/overlay_*.jpg`): side MAE 4 mm,
  max 16 mm; top clean MAE 63 mm (n=68); the rear's light bar row -67 mm,
  its span -16 mm, its centre -6 mm, the model's widest row 893 px.
- **The tail bar** (`red_audit.py`): in the car crop of the in-game chase
  capture (8.4 m) **419 saturated red pixels in 6 rows**, the peak
  (215,118,112) (luminance 138). The NPC tail lights in the same frame peak
  at (255,123,115) (luminance 150) and at 20 m the bar still gives 175.
- **The captures** in `captures/car_model/`: `compare_rear.jpg` (the in-game
  rear next to photo 09 and the in-game chase next to photo 08),
  `compare_wheel.jpg` (the wheel at 0.9 m next to photo 13),
  `compare_wing.jpg` (the deployed wing next to photo 17 and the stowed deck
  next to photo 16), `compare_front.jpg` (photo 03), plus `rear_valance.png`,
  `rear_close.png`, `front34_low.png`, `front_low.png`, `wheel.png`,
  `wheel09.png`, `tyre_front.png`, `tyre_rear.png`, `door_line.png`,
  `deck_line.png`, `deck_stowed.png`, `cockpit.png`, `canopy.png`,
  `wing_deployed.png` and the three overlay sheets.
- **The Godot shots** in `captures/`: `car_glb_{front34,rear34,side,
  close_rear,close_wheel,chase,far20,far20t,top,door,deck,hood,plate,
  valance}.jpg` (14 shots, 0 errors, 0 warnings) and
  `lookdev_car_car_{chase84,far20,far20t,rear09,rear08}.jpg`.

## Known issues
- **The tail bar's pixel count.** The review's acceptance number (1200
  saturated red pixels in the car crop at 8.4 m) is not met: the bar gives
  **419**. The reason is the geometry: the JSON's bar is 14 mm high, which is
  1.9 px at 8.4 m, and the review also asks for a pink-white core - a
  pink-white core is not a saturated red pixel. The bar's own peak
  (253,167,150) is brighter than every NPC tail light (255,123,115) in
  luminance, and the halo is 3 px above and below the bar.
- **The glb is rewritten on every build** (float noise in ~100 bytes); the
  textures are not.
- **The top overlay's clean MAE is 63 mm** (the review's own run on the round
  3 glb measured 24 mm). The difference is the wider splitter (1.10 m, the
  review's SHOULD-FIX): the photo's nose is narrower, so the lip's ends
  stick out of the top silhouette.
- The in-game chase view is a night scene, so the tail bar is compared with
  the NPC cars' brake lights rather than with the daylight photo 08.
- The 4 fan ports are 24 cm across (the JSON's `parts.fans.d`) and still read
  as large rings in the valance.
- The perimeter nozzles P1-P6 sit on the closed body shell, so their gold
  throat is only 2 mm deep (there is no hole in the body's skin); the four
  rear nozzles have real 30 mm bores.

## Requests (to core / other units)
- **The tail bar's idle level.** `vehicle/modules/car_lights.gd` uses the
  glb's strength as the idle level and multiplies it by 2.5 for braking.
  With the glb's strength 10 the vehicle should pass `idle_override = 4`
  (vehicle brief: 4 -> 10), otherwise the bar is 10 at idle and 25 while
  braking.
- **One UV layer per mesh.** The glTF exporter emits a SECOND material for
  every material that samples a uv set other than the first one of its mesh.
  Worth a line in CONTRACTS.md §2.
- `lib.common.set_parent` loses a freshly assigned location (the matrix is
  only refreshed on a depsgraph update); the car scripts work around it with
  `car/paths.parent_to()` / `parent_local()`.
- The shaders unit's `SH_car_paint.tres` / `SH_glass_gold.tres` lost their
  `shader_parameter/*` values while I worked (another unit is editing them);
  the car's look in Godot depends on them being restored.
- The canopy shader's `base_alpha` 0.68 makes the canopy see-through from
  above, while photo 12 shows an opaque bronze mirror.
