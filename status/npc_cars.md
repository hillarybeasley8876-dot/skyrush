# npc_cars status

Unit: NPC traffic fleet + police fleet (Blender → glTF). Owns `blender/npc_cars/**`,
`game/assets/cars/npc/**`.

Round 4: the fleet was **switched to the lead's shared body generator**
(`lib/car_body.py` + `lib/car_profile.py` + `lib/wells.py`) with the tested spec
values, and the wheels, the fascias and the box vehicles were rebuilt on top of
it.  `body_loft.py` and `profile.py` are gone (no dead code).

## Done

### 1. The bodies come from the shared generator (lead note LEAD-NPCBODY)
- Every `kind == "car"` model is built with
  `car_body.build(spec, col, materials=[paint, trim, glass, gloss_black], levels=1)`.
  Level 1 keeps the car inside the 30 k triangle budget of the lead's note
  (level 2 was 23 k triangles for the shell alone) and the panels still read
  as smooth (the cage is dense: a station every 20 cm).
- The lead's tested spec values are in `spec.py`: the sedan family
  (`roof_rear_y=-0.75, roof_drop=0.05, crown_y=0.10, deck_y=-1.78, deck_z=1.04,
  dlo_rear=-0.85, dlo_rail_end=-1.10`), the hatch (`dlo_rear=-1.02,
  dlo_rail_end=-1.10`) and the interceptor (`roof_rear_y=-0.55, roof_drop=0.04,
  crown_y=0.0, deck_y=-1.75, dlo_rear=-0.98, dlo_rail_end=-0.60`).  The SUV and
  the police SUV follow the "upright pillar" rule (`dlo_rear = dlo_rail_end + 0.08`).
- The result: no facets, a clean DLO (a raked A pillar, a black mirror sail, a
  black B pillar, a teardrop rear), a crowned roof, no plank roofs.

### 2. The details are fitted to the new body by ray casting
`body.py` keeps the ray-cast fitting helpers (the doors, the bonnet, the lamps,
the plates, the bumpers, the grille, the mirrors) and every panel now sits on
the *new* surface.  New in this round:
- the headlamps are a unit with a dark reflector and an emissive strip in it,
  the fog lamps and the lower honeycomb intake are separate,
- the tail has a full width red LED bar, side units, reverse lamps and a black
  diffuser,
- the mirrors are a cap on a stalk with a dark glass face and an LED repeater,
- the door handles sit in a recess.

### 3. The wheels are not black holes any more (r3 item 4)
- The rim is a modelled 5 twin spoke face: the spoke faces stand 2 cm proud of
  the barrel, the barrel is a hollow tube so the brake disc (#5B5D61) and the
  caliper show through the gaps.
- The rim is a bright alloy (#B9BDC3, gunmetal #6E7276 for the police); the
  material is only half metallic, because a fully metallic rim turns black in
  a night world.
- The tyre is a revolved profile with rounded shoulders and the shared tread /
  sidewall normal map (with the SKYRUSH CITYGRIP lettering).
- The wheels are centred on `parts["anchors"]["wheels"]`, radius = `wr`,
  width = `ww`.

### 4. The box vehicles (r3 item 5, lead item 5)
- The bus shell is bevelled hard (0.14 m, 4 segments) and the roof cap is
  inset, so the nose and the roof read as rounded.
- The glazed band is one continuous band of flush dark glass split by black
  pillars every 1.4 m; the passenger doors are glazed leaves named
  `Door_FR` / `Door_RR` (the damage unit needs them separate).
- The bus wheels are 1.0 m tyres (0.29 m wide) in real arches with black
  liners; the liner is a half arch, so nothing reaches under the road.
- The route signs are at their true aspect: the UV covers the whole 1024x256
  image, the front sign reads 申城公交 71路 and the side sign 71.
- The bumpers are on the body (the old one floated at 2.7 m because a sign
  variable overwrote the bumper height).
- The van and the truck got the same treatment: a raked cab screen, real
  mirrors, the blue 沪B plates on the right cells of the plate atlas.

### 5. Number plates (r3 item 6)
- The front plate is mirrored on purpose (u falls when x rises), so the
  characters read the right way round for a viewer of the nose; the rear plate
  reads the other way.  The test checks it.
- The plate UVs use the real atlas size (2048x480), so the van, the truck and
  the bus sit inside one cell instead of straddling two.

### 6. The import churn (r3 item 8, lead note)
- `texlib.save` writes a sheet only when its bytes changed: a rebuild that
  produces the same image does not touch the file.
- `build.export_glb` writes the .glb only when the bytes changed.
- The cause of the non-determinism was found and fixed in two places:
  the shared `common.bevel` **modifier** is not bit-exact between two
  evaluations (it is now a bmesh bevel in `meshutil.bevel`, applied at once),
  and the ray cast onto the body wobbles in the last bits (the sample points
  are now rounded to 0.01 mm, `body.sample_surface`).
  With both fixes two exports of the same scene are byte identical.
- The embedded textures are written as WEBP (alpha) or JPEG (opaque) into the
  scratch folder before the export, so the .glb does not carry the raw PNGs
  (the folder went from 87 MB to 31 MB, the .glb files from 4.4 MB to ~2 MB).
- The 358 stale per-model image copies (Godot had extracted them in an earlier
  import) are deleted; the .import files keep `gltf/embedded_image_handling=1`
  (embed as WebP), so no new copies are written.

### 7. The lineup render (r3 item 9, lead verification)
- `lineup.py -- side` renders an **orthographic side** lineup of all twelve
  vehicles in the §4.7 traffic mix, on a 1 m ground grid, with a 1.75 m human
  silhouette next to the sedan.
- The row axis bug is fixed (the .glb is Y-up: the length is along Y, so the
  row runs along Y and the camera looks along -X).
- `captures/blender/lineup_side.jpg` and `lineup_fleet_night.jpg`.

### 8. The code rules (r3 item 11)
- `body_loft.py` and `profile.py` are deleted; the profile maths lives in
  `lib/car_profile.py` (core-owned).
- `build_box_details` is split into one function per part (all of them under
  40 lines), the magic numbers moved into the spec tables (the livery box, the
  route signs, the roof sign, the lamp sizes).
- The test is split: `test_npc_nodes.gd` (the node and geometry contract) and
  `test_npc_materials.gd` (the material and UV contract), with the new checks
  for the ground clearance, the front plate orientation, the bus bumpers and
  the route sign coverage.

## In progress / next
- The cross-process byte stability: two builds of the same model in the same
  Blender session are now identical, but two *separate* runs still differ in a
  few float bits of the wheel-well boolean (`lib/wells.py`, core-owned).  The
  box vehicles, the drone and the textures are stable across runs; the eight
  cars are not yet.  Next step: a canonical vertex order after the boolean (or
  a `wells.cut` that sorts its output).
- The interior is still a stack of boxes (visible through the 55 % glass).
  The seats want a proper shape and a darker cabin.
- The taxi's lower body wears `NPC_taxi_skirt` (its own material), the roof
  sign is 0.95 m wide with 申城出租 on the front and the rear and TAXI on the
  sides, and the robotaxi's LiDAR ring is cyan (#19E6FF) - all modelled, all
  still to be judged at game distance.

## How to test (exact commands)
- `python3 blender/npc_cars/gen_textures.py`      (system python3 + PIL)
- `tools/blender.sh run blender/npc_cars/build.py` (rebuild + export all 12)
- `tools/blender.sh run blender/npc_cars/build.py -- sedan_ev` (one model)
- `python3 blender/npc_cars/check_glb.py game/assets/cars/npc/*.glb`
- `tools/blender.sh preview game/assets/cars/npc/<model>.glb <model> --views front34,rear34,side,front,rear,close_front34 --light both`
- `tools/blender.sh run blender/npc_cars/lineup.py -- side`   (orthographic lineup)
- `tools/blender.sh run blender/npc_cars/lineup.py -- night`  (night fleet)
- `tools/godot.sh test res://assets/cars/npc/tests/test_npc_nodes.gd`
- `tools/godot.sh test res://assets/cars/npc/tests/test_npc_materials.gd`
- `tools/godot.sh check --only=res://assets/cars/npc/`
- `tools/godot.sh shot --scene=res://assets/cars/npc/preview_npc.tscn --out=npc_r4 --cams=police:11,1.5,-8:0.35,-0.06,1`

## Evidence
- `tools/godot.sh check --only=res://assets/cars/npc/` -> `CHECK 3 files, 0 failed,
  0 engine errors, 0 warnings`.
- `tools/godot.sh test res://assets/cars/npc/tests/test_npc_nodes.gd` -> 84 PASS / 0 FAIL.
- `tools/godot.sh test res://assets/cars/npc/tests/test_npc_materials.gd` -> 14 PASS / 0 FAIL.
- `python3 blender/npc_cars/check_glb.py game/assets/cars/npc/*.glb` -> `total problems: 0`
  (the contract nodes, the texture sets, the tangents, the double sided
  materials and the bounding boxes against the brief).
- Triangles per model (the budget of the brief: 10-25 k for the cars, <= 30 k
  for the box vehicles, <= 8 k for the drone):
  sedan_ev 21 906 | suv_ev 21 718 | hatch_ev 21 174 | taxi 22 066 | robotaxi 19 440 |
  police_patrol 22 232 | police_interceptor 22 124 | police_suv 23 420 |
  van 7 992 | truck 9 578 | bus 9 554 | police_drone 1 456.
- Surfaces (draw calls): 34 for the traffic cars, 38-42 for the taxi and the
  police cars, 24-27 for the box vehicles, 17 for the drone.  The shared
  generator gives the body three material slots (paint, underbody trim, black
  pillar) and every wheel two (tyre, rim), so the count is higher than the
  flat r3 fleet; the test documents the new budget.
- `captures/blender/lineup_side.jpg` - the orthographic side lineup of all
  twelve vehicles on a 1 m grid with the 1.75 m figure.
- `captures/blender/lineup_fleet_night.jpg` - the night fleet.
- `captures/npc_r4_police.jpg` and `captures/npc_preview_r4_t2_0.jpg` - the
  Godot preview scene at night (`CAPTURE errors=0 warnings=0`, 185-226 fps).
- Texture budget: 27 shared sheets, 5.0 MB in `game/assets/cars/npc/textures/`;
  the twelve .glb files together 23 MB (each one embeds the sheets it uses);
  the whole folder 31 MB.

## Known issues
- The eight cars are still re-imported by Godot when the fleet is rebuilt: two
  separate Blender runs differ in a few float bits of the wheel-well boolean
  (`lib/wells.py`, core-owned).  Everything else in the unit is byte stable.
- The .glb files embed the shared sheets (about 2 MB each), so the folder is
  31 MB and not the 12 MB of the r3 review.  The only way to share the images
  between the models is the `shared_texture_dir` route of `lib/export.py`,
  which writes a .gltf - the other units load `res://assets/cars/npc/<name>.glb`
  and the paths must not change.
- The interior is a stack of boxes and shows through the 55 % glass.
- The bus and the truck are 0.3-0.5 m wider than the brief's table because
  their mirror arms stick out (the body is on spec).

## Requests
- core (`lib/wells.py`): the EXACT boolean of the wheel wells gives a
  different vertex order between two Blender runs, so the .glb is not byte
  stable.  A canonical order (or a sorted output) would make the whole fleet
  import-stable.
- core (`lib/export.py`): an `image_format` option (WEBP / JPEG) would let
  the unit use the shared library without writing the compressed sheets into a
  scratch folder first.
- shaders: the taxi and the police livery need `use_livery = true` on
  `SH_car_paint_taxi` / `SH_car_paint_police` for the UV2 decal sheet to show
  in game (the sheet is in the second UV set, named `UV1` in the mesh).
- core: `MaterialLibrary.TEXTURE_UNIFORMS` does not copy `livery_tex`, so a
  runtime swap still drops the livery.
- vehicle/damage: this unit names the doors `Door_FL/FR/RL/RR` (the unit brief)
  rather than CONTRACTS §6's `Door_L/Door_R`; the police light bar is
  `LightBar` + `LightBar_Red` / `LightBar_Blue` + a `Siren` empty; the bus doors
  are `Door_FR` / `Door_RR` (the right hand side of the bus).
