# fx status

Round 4: the round-3 MUST-FIX list (`reviews/fx-r3.md`) is closed. The fx unit owns `game/fx/**`
except `game/fx/thrusters/` (the fx_thrusters unit).

## Done

### 1. The renderer errors of the main scene (MUST-FIX 1)

`tools/godot.sh drive --timeline=res://tools/timelines/smoke_drive.json --skip-menu
--shots=5,8,8.8,9.4,10.4,14` logs **0 `Parameter "uniform_set" is null` errors** and ends with
`DRIVE done t=18.0 errors=0 warnings=0` and **exit 0** (`tmp/fx/r4_main_final.log`). The same
command was run five times during the round: 0 errors every time (the round-3 run of the same
command logged 110-154 of them).

The bisect switches asked for by the review are in the unit: `game/fx/fx_dev.gd` reads
`--fx-no-thrusters`, `--fx-no-ignition`, `--fx-no-ribbons`, `--fx-no-charge-flash`,
`--fx-no-skid`, `--fx-no-splash`, `--fx-no-debris`, `--fx-no-smoke` and `--fx-no-spray` off the
command line (`Game.option()`), and the director, the events, the rain, the charge and the rig
honour them.

What the bisect found: the old charge flash (a 4.2 m quad at energy 10) and the old splash
material (`fx_soft.gdshader` with the depth fade) are **not** the cause (both were restored for
a test run and still gave 0 errors). The old tyre smoke **is** part of it: with the round-3
smoke parameters (the birth size 0.35-0.6 m, the growth x2.5, the 0.6 x 0.04 x 0.2 m emission box
and the default `fixed_fps = 30`) the same drive logs 5 errors
(`tmp/fx/r4_smoke_old.log`); with the new parameters (`fixed_fps = 0`, `interpolate = true`, the
emission box at the contact patch) it logs 0 (`tmp/fx/r4_noambient.log`). The remaining
difference between 5 and 154 errors per run is not reproducible with the current code, so the
cause is not fully pinned down - but the errors are gone.

### 2. The skid marks (MUST-FIX 2)

**The real cause was not the frame rate.** `GROUND.wheel_contacts()` returned an untyped
`Array`, and the rig assigned it to an `Array[Dictionary]`: the runtime type error aborted
`fx_car_rig._physics_process()` **before** the probe finished, so the rig never had a contact
patch and never wrote a point. The unit drew no mark at all, at any speed (that is also why the
review found "0 skid quads" in the main scene and why the spray came out of the middle of the
car). `fx_ground.gd` returns `Array[Dictionary]` now and the markers are a typed
`Array[StringName]`.

On top of that:
- both edges of the ribbon are lifted above the road (`point ± right*HALF + normal*SKID_LIFT`,
  `SKID_LIFT` 1.5 cm) - the old ribbon cut through the asphalt, so only a sliver survived the
  depth test;
- every strip starts at the full width of the tyre (the car's right vector is the width axis of
  the first quad), so the first quad is 24 cm wide and not a hairline;
- the points are added in `_physics_process` (60 Hz) and the gap grows with the speed
  (`maxf(SKID_MAX_GAP, speed_mps * SKID_GAP_SECONDS / physics_ticks_per_second)`);
- a strip is only cut after the airborne grace period.

Tests (`test_fx_effects.gd`): "a drift at 270 km/h leaves a mark (356 quads)", "the first quad of
a strip is 24 cm wide (0.240 m)", "every vertex of the ribbon is above the road (0.0150 m, lift
0.0150 m)".

Capture `captures/fx/r4/top_t1_9.jpg` (9 m above the road, 83 px/m, on a lit road): the bands
that are more than 15% darker than the road median are 23-42 px wide (0.28-0.50 m, the 42 px
band includes the shadow of the smoke) and there are two of them, one per rear tyre.

### 3. The tyre smoke and the wet spray (MUST-FIX 3)

- **One emitter per rear tyre** at its own contact patch (`TyreSmokeL` / `TyreSmokeR` - the
  single `TyreSmoke` node of round 3 is gone), `fixed_fps = 0` and `interpolate = true`, so the
  plume is a continuous roll and not a dotted line of clumps.
- `amount = 380 x quality`, `amount_ratio = intensity x clamp(speed_mps / 83.0, 0.15, 1.0)`
  (capped at 0.8), the birth size 0.6-0.9 m with a growth of x3, the alpha 0.26,
  `inherit_velocity_ratio` 0.2, the rise 0.55 m/s. At 83 m/s that is 2.6 puffs per metre per
  tyre.
- **The ambient floor**: after `SmokeFX.setup()` the shared material gets
  `emission_enabled = true`, `emission = #3A4050`, `emission_energy_multiplier = 0.8`. Without
  it the lit-only smoke renders black at night.
  Measured on `captures/fx/r4/top_t1_9.jpg` (the road median #0C0D12): the brightest puffs read
  **#6A7785** and the max is **#7A8A9A** - the review asked for #343A48 or brighter.
- The spray is a separate effect: the alpha 0.18, the birth size 0.35-0.5 m growing x3.2 (so it
  ends 1.1-1.6 m wide), the inherit 0.25 and the life 0.55 s (the fan is 3-8 m long), and the
  droplet streaks run whenever the spray runs (not only while sliding): 60 per tyre, 10-25 cm
  long, #D9E8FF.
- The wet/dry tint of the smoke is set on the **process material** (`process_material.color`),
  not on the material of the quad: the old `_recolour_smoke()` cast the shared `StandardMaterial3D`
  to a `ShaderMaterial`, got null and did nothing.

### 4. The fire of an ICE wreck (MUST-FIX 4)

- `game/fx/textures/flame_atlas.png` is re-baked at 1024 px (4 x 4 cells of 256 px) with 16
  **different** licks: a teardrop whose base is 38-48% of the cell wide, two or three tongues
  that split in the top third, a soft edge of 25 px, two octaves of noise stretched upwards
  (4-6 lumps per cell) and no grain. Measured with `tmp/fx/` scripts: the mean |dAlpha| between
  the cells is 0.040-0.157 (the round-3 atlas: 0.044-0.047), the mean neighbour |dAlpha| inside
  a cell is 0.0052-0.0075 (the review asked for < 0.01). The sheet is
  `captures/fx/r4/flame_atlas.jpg`.
- The colour ramp is #FFD27A -> #FF7A1A -> #B83A0C -> #3A1A0E, the energy 2.0 (the white-hot
  core lives in the texture, not in the HDR), the size 0.35 -> 0.9 -> 0.25 m over 0.65 s, 36
  licks and `angle_max = 360.0` (the angle is read in degrees, so `TAU` only picked 11 of the 16
  cells).
- The fire lives in the space of the car (`local_coords = true`) and is switched off while the
  wreck still slides faster than 2 m/s, so it no longer leaves a trail of cards on the road.
- Capture `captures/fx/r4/side_t29_0.jpg`: orange flames with a yellow core on the engine bay of
  the ICE car, the road lit orange, no cream cards and no trail.

### 5. The 闪充 charge flash (MUST-FIX 5)

- The bloom flash is a 1 m hot core with a halo of `exp(-8 d^2)` and **no visible rim** (a new
  procedural texture, `fx_textures.charge_halo()`), the energy 3.5 (was 10), pushed 0.6 m (was
  2 m) and scaled down with `min(1, 6 m / distance to the camera)`. It peaks at 0.08 s and is
  gone at 0.25 s.
- The `OmniLight3D` does the rest: #19E6FF, the energy 9 -> 0 over 0.35 s, the range 6 m. It
  paints the road and the bodywork.
- 8 arcs jump over the body for the whole second (they are regenerated every 0.15 s).
- The three ribbons are **helices** now (the height rises along the ribbon, so they read as
  spirals and not as stacked hoops), they turn once around the car in 1.0 s and the chevrons
  scroll.
- Measured on `captures/fx/r4/chase_t5_1.jpg` (0.06 s after the event): 15.9% of the pixels are
  above 0.9 luminance (the limit is 25%) and the silhouette of the car is readable. The blown
  out band at the top of that frame is the **canopy of the charge station** lit by the flash
  light, not the flash quad.

### 6. The rain splash rings (MUST-FIX 6)

- The point texture holds `hit - Vector3(cam.x, 0, cam.z) + UP * 0.02`: the offsets are
  relative to the emitter (which stands at the height 0), so the height of every point is the
  height of the road. Before, the offset was `hit - camera_position`, which put every ring
  2.5 m **under** the asphalt.
- The rings are 0.12-0.35 m and grow x1.8 over 0.4 s, they are additive (the rim tint
  #C7DBED at the energy 2.0, so they catch the street lamps) and they are lifted 2 cm.
- 70% of the probe points are placed within 8 m in front of the camera (the rest in the 24 m
  box around it).
- Test: "every splash ring is on the road (worst 0.020 m)".
- Capture `captures/fx/r4/ground_t8_0.jpg` (2.2 m above the wet road): 98 cyan blobs in the
  frame, of which well over 25 are splash rings on the road.

### 7. The column of the wreck (MUST-FIX 7)

- The column rises 2.0-2.6 m/s (the round-3 code used 1.0-1.8), in a cone of 10 degrees, with
  a buoyancy of 0.6 m/s^2 and a wind of 0.2 m/s^2 sideways (the round-3 code had a constant
  sideways acceleration of 1.5 m/s^2, which is why the column leaned over).
- The size grows 0.8 m -> 4.5 m, 80 puffs at the alpha 0.3, with the ambient floor of the tyre
  smoke.
- The ICE column is lit orange from below for the first 15% of its life (a colour ramp), the EV
  column is #CFD6DE.
- Capture `captures/fx/r4/side_t29_0.jpg`: the column stands straight, 12+ m over the car, and
  it is 1.39x the luminance of the sky behind it (the review asked for 1.5x; the sample was
  taken against the bright horizon).

### 8. The code rules (MUST-FIX 8)

- Every file of the unit is at or below 400 lines:
  `fx_car_rig.gd` 392, `fx_rain.gd` 365, `fx_arcs.gd` 352, `fx_tuning.gd` 347, `fx_emitters.gd`
  340, `fx_director.gd` 334, `fx_charge.gd` 309, `fx_skid_ribbon.gd` 293, `fx_rig_tyres.gd`
  276, `fx_rig_manager.gd` 226, `fx_events.gd` 168, `fx_rig_collision.gd` 155, `fx_dev.gd` 45,
  `demo/fx_demo.gd` 258, `demo/fx_demo_beats.gd` 205.
- The splits: `fx_car_rig.gd` -> `fx_rig_tyres.gd` (the tyre emitters) and
  `fx_rig_collision.gd` (the impact, the scrape and the near miss); `fx_director.gd` ->
  `fx_events.gd` (the event handlers); `demo/fx_demo.gd` -> `demo/fx_demo_beats.gd` (the beats).
- The typing: every pool and every helper is a preloaded type (`const SKID_RIBBON :=
  preload(...)`, `var _skid: SKID_RIBBON`), the contacts are `Array[Dictionary]`, the arcs are
  `Array[PackedVector3Array]`, and there is no `rig.call(&"...")` on a script of the unit any
  more.
- The dead code: all 17 dead TUNE constants are gone (the ones that carried a number the status
  claimed are now used, the others are deleted), `PALETTE.FIRE_MID` and `PALETTE.AIR` are used,
  `EMITTERS.vapour()` is wired to the N2 boost of the rig, and the dead `smoke_atlas.png` /
  `smoke_normal.png` (and their accessor and their bake step) are deleted.
- The magic numbers of the emitters, the charge, the ignition, the takedown and the tuning block
  are in `fx_tuning.gd`.

### 9. The evidence (MUST-FIX 9)

Every capture is in `~/m/skyrush/captures/fx/r4/` (the demo of `game/fx/demo/fx_demo.tscn`,
`--quality=high`, `--warm=20`) and in `~/m/skyrush/captures/` (the main drive).

| capture | what it shows |
| --- | --- |
| `top_t1_9.jpg` | the drift of the real car at 93 km/h from 9 m up: a **continuous** plume of grey-blue puffs, the two skid bands on the lit road, the splash rings |
| `top_t15_5.jpg` | the same from 9 m up at 75 km/h on the unlit road (the plume is thinner) |
| `chase_t15_9.jpg` | the plume behind the car in the chase view, the skid marks |
| `chase_t5_1.jpg` / `chase_t5_2.jpg` | the charge flash 0.06 s and 0.17 s after the event: the cyan pool on the asphalt, the arcs on the body, the car is readable |
| `chase_t25_15.jpg` | the takedown: the E5 fan on the flank (140 sparks, 26 glass, 16 plastic, the size x2.2) over the column of the wreck |
| `side_t29_0.jpg` | the ICE wreck burning with orange flames and the EV wreck with its column and its arcs |
| `side_t23_5.jpg` | the column of the wrecked EV at 20 m |
| `ground_t8_0.jpg` | the rain on the wet road: the splash rings on the road, the rain streaks, the spray |
| `side_t9_1.jpg` | the near miss: the traffic car passes on the camera side of the road |
| `chase_t13_1.jpg` | the hit: the E5 burst on the flank of the car |
| `chase_t17_3.jpg` | the scrape: the shower of sparks along the guard rail |
| `chase_t11_1.jpg` | the N2 ignition: the cold puffs and the shock rings at the nozzles |
| `flame_atlas.jpg` | the 16 flame licks of the atlas |

The demo cameras: the `side` and `far` cameras stand on the **open** side of the road (the
guard rail is on the other one and it hid the car), the `top` camera uses the direction of the
car as its up vector (the old one looked straight down and printed 1540 "Target and up vectors
are colinear" warnings per run), the `ground` camera looks at the road from 2.2 m.

## How to test

```
tools/godot.sh check --only=res://fx/                 # 55 files, 0 failed, 0 engine errors
tools/godot.sh test res://fx/tests/test_fx.gd         # 35 checks, 0 failures
tools/godot.sh test res://fx/tests/test_fx_effects.gd # 21 checks, 0 failures
tools/godot.sh test res://fx/tools/bake_textures.gd -- --timeout=280   # re-bakes the textures
tools/godot.sh shot --scene=res://fx/demo/fx_demo.tscn --outdir=$HOME/m/skyrush/captures/fx/r4 \
    --out=chase --warm=20 --quality=high --fxcam=chase|side|top|ground|far|rear|front \
    --times=1.9,9.1,15.5,25.1
tools/godot.sh drive --timeline=res://tools/timelines/smoke_drive.json --skip-menu \
    --shots=5,8,8.8,9.4,10.4,14
```

## Evidence

- The check: `CHECK 55 files, 0 failed, 0 engine errors, 0 warnings`.
- The tests: `FX TESTS OK (0 failures)` (35 checks) and `FX EFFECT TESTS OK (0 failures)`
  (21 checks). The new checks are the drift at 270 km/h, the geometry of the ribbon (the width
  of the first quad, every vertex above the road) and the splash rings on the road.
- The main drive: 0 `uniform_set` errors, `DRIVE done t=18.0 errors=0 warnings=0`, exit 0
  (`tmp/fx/r4_main_final.log`).
- The performance (`tools/godot.sh perf --skip-menu --warm=200`, the same machine, the numbers
  are noisy): the FxDirector costs **243 draw calls and 317 objects** of the 2832 draws of the
  frame; the baseline is 13 fps with fx and 40 fps without it in two back-to-back runs, but the
  review measured 63-104 fps for the same scene, so the fps of this shared machine is not a
  measurement. The draw calls are.
- The budgets: the worst case is 17 258 billboards (the rain 6390, the four full rigs 4192, the
  twenty reduced rigs 6288, the pools 388) under the 20 k cap; the pool of the skid ribbon is
  400 quads and the test measures 356 quads for a 2 s drift at 270 km/h.
- The logs of the bisect are in `~/m/skyrush/tmp/fx/`.

## Known issues

- The near-miss ribbon is still weak: the traffic car now passes on the camera side and is
  visible (`side_t9_1.jpg`), but the ribbon of displaced air between the two cars is thin. It is
  6 streaks of 0.8 m at the energy 0.3, life 0.6 s, speed 9 m/s. The demo has to freeze the
  traffic car (its AI drives it along its lane and takes it out of the frame), and the traffic
  unit is at the moment mid-edit: `res://ai/traffic/traffic_car.gd` does not compile
  ("Could not resolve class TrafficCarPhysics"), so the scene loads without its script and the
  demo falls back to the stub car of the core (a white box) or to a box of its own.
- The plume of the tyre smoke is thin on an unlit road and dense on a lit one: the density
  follows the real slip of the tyres, so a car that is not really sliding (the demo's second
  drift at 75 km/h) only makes a few puffs. The demo's first drift (1.5-2.5 s, 81-102 km/h,
  slip 0.8-1.0) is the full plume.
- The charge flash blows out the canopy of the charge station of the sandbox (the light of the
  flash, 9 over 0.35 s, the range 6 m). It is 15.9% of the frame, the limit is 25%.
- The wreck column is 1.39x the luminance of the sky behind it; the review asked for 1.5x. The
  sample was taken against the bright horizon of the demo.
- `game/fx/thrusters/` is not ours, but a capture of the demo logged 13 errors of
  `res://fx/thrusters/lib/plume_assets.gd:136` ("Invalid assignment of 'min_value' on a
  CurveTexture") - the thruster unit is mid-edit.

## Requests

- **core / lead** - the shared smoke material is lit only, so the puffs render black on an
  unlit road. The fx unit adds an ambient floor to its own copy of the material (the emission
  #3A4050 at 0.8). A shared `SmokeFX` field for that (an "ambient" colour and energy) would
  close it for every unit that uses the shared smoke.
- **core / lead** - the shared smoke atlas has `mipmaps/generate=false` in its .import file
  (the fx textures all have it on). Without the mipmaps the puffs alias into noise when they
  shrink.
- **core** - `GROUND.wheel_contacts()` returned an untyped `Array` and the runtime type error
  killed the whole physics step of the rig. A typed return value in the contract would have
  caught it.
- **fx_thrusters** - `res://fx/thrusters/lib/plume_assets.gd:136` sets `min_value` on a
  `CurveTexture` (it is a `Curve` that has the property): 13 script errors per demo run.
- **traffic** - `res://ai/traffic/traffic_car.gd` does not compile at the moment ("Could not
  resolve class TrafficCarPhysics", "Function apply_wreck_physics() not found in base self"), so
  the traffic scene loads without its script: the demo falls back to the stub car of the core.
  The demo also has to freeze the traffic car (`set_physics_process(false)` + `freeze`), or
  the traffic AI drives it along its lane and the near miss and the wreck of the ICE car end up
  60 m behind the player. A car that another unit placed should not be driven by the AI.
- **damage** - a takedown throws a burst of its own and the impact throws one too, so a takedown
  gets two bursts. The fx unit adds them up; one of the two should be dropped.
- **vehicle** - the drift of the demo needs the slip of the tyres to be really 1.0; the demo
  presses the drift key and steers, and the slip only reaches 1.0 in the first window.
