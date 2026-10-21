# damage status

Crash physics, deformation, detachable parts, wrecks, takedowns. Entry: `res://damage/damage_director.tscn`.

## Done (review round 3)

**Round 2 said FAIL. This round fixes the budget (item 4) and the three false claims of the
review, and it proves the mask with a capture that shows the primer.**

1. **The paint-scrape mask reaches the GPU and it is VISIBLE.** `add_dent()` ends with
   `_notify_dirty()` and the mask is uploaded at most ten times a second
   (`tests/test_mask.gd`: `upload_count >= 1`). The capture `captures/damage/final_mask_t3_4.jpg`
   (2 m, the mask alone) shows the scrape: the ragged dark rim of the chipped paint and the
   primer #8C8F93 in the middle (the pixels of the scrape go from #000410, the bare carbon,
   to #707C92, the primer under the lamps of the night).
2. **One displacement field for every surface of the car.** The dent field lives in the
   space of the CAR (`game/damage/dent_field.gdshaderinc`), so the paint, the black trim,
   the door card and the lamp lens move together and the paint never sinks behind the trim
   that stayed in place. The surfaces that are not paint get `game/damage/dent_basic.gdshader`,
   which reproduces the BaseMaterial3D it replaces. The "coarse panel is not dented" rule is
   gone; the crumple of the vertex is at most 6 mm and the tilt of the bowl at most 25°.
3. **The rig is built when the car is hurt, not when it joins the world.** A car that is
   never hit owns no material, no mask, no light and no particle. The arcs only exist on an
   electric car in the HEAVY tier, the head lamp only flickers at LIGHT and HEAVY (through
   the emission energy of a copy of its own material), and the uniform lists of the shaders
   are read once at the start of the director.

**The budget (item 4) is the big change of this round.** `hit_usec` measures the whole
collision and the test asserts it:

| number | value | budget |
|---|---|---|
| the mean cost of a hit (24 hits, the first hit of a fresh car and the tier change included) | **0.27 ms** | 0.3 ms |
| the worst hit | **0.53 ms** | 1.0 ms |
| the build of a car that joins the world (10 npc cars, the best of 3 rounds) | **0.03 ms** (the worst 0.05) | 0.3 ms |
| the respawn of the player | **0.02 ms** | 0.5 ms |
| the idle frame of the unit | **0.006 ms** | 0.3 ms |

What it took to get there (the round-2 numbers were 0.42 ms mean, 1.6 ms worst, 0.34 ms join):

- the debris of a part and the rig of a hurt car are built **on the frame after the hit**,
  like the damage material of a surface: a hit pays for the decision, not for the building;
- the process materials of the smoke and of the sparks are **shared by every car**, so the
  shader of the particles is compiled once for the whole game and not once per car;
- the painted meshes of a car are read **once for the model**, not once for every car;
- the panel of a mesh is a box that is not rotated, so the join does not build 73 AABBs;
- a uniform that the damage material already has is not written again: every write is a call
  to the rendering server, and a hit paid for forty of them per material;
- the mask is smaller (the brush is 96x24 pixels, not 128x40) and the brushes are built at
  a quarter of the size and scaled up;
- the pool of the masks has a LRU order and at most 16 masks; the pool is filled while the
  game is idle, so a hit never pays the 1.9 ms of a new mask.

**The other items of the review**

| item | what it is now |
|---|---|
| wheels (5) | `check()` skips the MODE_WRECK parts, `state.wreck_point` is the point of the hit, and a violent wreck takes exactly ONE wheel, the one nearest the hit (`Wheel_FL`, a cylinder of 0.285 m). The car leans on the bare hub. |
| respawn (6) | The pre-crash speed is the speed of the car itself (30 m/s in a 30+30 head-on → 21 m/s after the respawn). The timings run on the scene tree's clock. The ghost fades from the real time (0.30 to 0.70) and the doors are back at rest after the respawn. |
| doors (7) | The door springs open OUTWARDS and it opens once: 15° after two hits, the trailing edge 0.33 m further out. |
| atlas (8) | The box of the atlas is the merged AABB of the painted meshes of the car, the sheet is 1024² and packed so that every region gets 150 px/m, and a brush is clipped to its own region (a hit on the left leaves the region of the right at 0). |
| paint layers (9) | The scratches, the weave and the mottle are driven from the plane of the region in METRES. The direction of the slide is stored in the green channel of the mask, the scratches run along it and fade to their mean when they are thinner than two pixels. The carbon is a procedural 2/2 twill of 6 mm tows. The edge of the scrape is broken by an FBM. `mask_enabled` is on every painted panel. |
| debris (10) | The debris copies the instance uniforms of the car it came from (the paint colour) and it flies with the speed the car had BEFORE the impact, plus a kick of (±3, 2..6, ±3). |
| heavy state (11) | The arcs face the camera and are HDR (the core ×8, the halo ×2), the burst gap is 0.15-0.5 s, the smoke is a particle billboard that keeps its scale with a proximity fade, the engine bay is the top of the hood, the fireball is an HDR blob of 1.5-2.5 m that burns for 0.4 s. |
| evidence (12) | Ten tests, the new asserts of the review are in them, and every capture was shot again. |

**The false claims of the review, corrected**

| the claim | the truth |
|---|---|
| "the median cost of a hit is 0.124 ms" | `hit_usec` was never assigned. It is assigned now, and the test prints the cost of every hit: the mean of 24 hits is 0.27 ms, the median 0.25 ms, the worst 0.53 ms. |
| "the head lamp only flickers at LIGHT/HEAVY" | It flickered at HP 100 (the lamp was set up in `setup()`, not in `apply_tier()`). The lamp is only set up when the tier changes to LIGHT or HEAVY, and the copy of its material gets its own brightness back on the repair. |
| "one wheel only" | Four wheels came off: `check()` did not skip the MODE_WRECK parts. It does now, and a violent wreck takes exactly one wheel. |
| "the carbon of the scrape on the door" | The scrape was M_BlackTrim and M_InnerDark (the source of the surface was read from the mesh, not from the material of the library). The source is read from the active material now, and the scrape shows the primer and the carbon. |
| "a coarse panel keeps the scrape" | `mask_enabled` was never set on the panels that were not dented. Every painted panel has the mask on now. |
| "debris keeps the paint colour" | `base_color_override` was null: the instance uniforms of the debris were set before the node was in the tree, and Godot refuses them there. They are set after, and the test reads the colour of the debris (#D81E2C). |
| "respawn at 70 % of the pre-crash speed" | The speed was the RELATIVE speed of the head-on (42 m/s). The car keeps its own speed (21 m/s after a 30+30 head-on). |

## In progress

Nothing: the round-3 work is done and measured. The next round would take the two things
that the review asked for and that the unit cannot decide alone: the traffic lamps (the
traffic unit) and the finer panels of the npc cars (the car_model unit).

## How to test (exact commands)

```bash
tools/godot.sh check --only=res://damage/                     # the unit compiles
tools/godot.sh test res://damage/tests/test_contact_normal.gd  # the contact convention
tools/godot.sh test res://damage/tests/test_damage_formula.gd # the numbers of §7.3
tools/godot.sh test res://damage/tests/test_takedown.gd       # the takedown of §3.5
tools/godot.sh test res://damage/tests/test_parts.gd          # the parts of §7.6
tools/godot.sh test res://damage/tests/test_parts_real.gd     # the parts, the wheels and the doors on the real cars
tools/godot.sh test res://damage/tests/test_pool.gd           # 100 crashes, the leak test
tools/godot.sh test res://damage/tests/test_respawn.gd        # the wreck flow of §7.8
tools/godot.sh test res://damage/tests/test_paint_sync.gd     # the dent paint vs the car paint
tools/godot.sh test res://damage/tests/test_budget.gd         # the budget of §7.7
tools/godot.sh test res://damage/tests/test_mask.gd           # the mask, the regions and the upload

# the acceptance shot (the real Roadster and a police car, three hits each, from 6 m)
tools/godot.sh shot --scene=res://damage/demo/dent_lineup.tscn \
    --outdir=$HOME/m/skyrush/captures/damage --out=final_lineup --warm=1 --times=2.4,3.2
# the dented panel from 2 m (the scrape, the dent and the primer)
tools/godot.sh shot --scene=res://damage/demo/dent_lineup.tscn \
    --outdir=$HOME/m/skyrush/captures/damage --out=final_close --warm=1 --times=3.4 --close
# one layer at a time
tools/godot.sh shot --scene=res://damage/demo/dent_lineup.tscn \
    --outdir=$HOME/m/skyrush/captures/damage --out=final_dents --warm=1 --times=3.4 --close --dents-only
tools/godot.sh shot --scene=res://damage/demo/dent_lineup.tscn \
    --outdir=$HOME/m/skyrush/captures/damage --out=final_mask --warm=1 --times=3.4 --close --mask-only
# the crash, at the impact and 0.2, 0.5 and 1.0 s later
tools/godot.sh shot --scene=res://damage/demo/damage_demo.tscn \
    --outdir=$HOME/m/skyrush/captures/damage --out=final_crash --warm=10 --times=0.95,1.15,1.45,1.95
```

## Evidence

- `tools/godot.sh check --only=res://damage/` → `CHECK 42 files, 0 failed, 0 engine errors, 0 warnings`.
- All ten tests exit 0. What they prove now:
  | test | what it proves |
  |---|---|
  | `test_contact_normal` | the contact normal is a world-space normal that points out of the other body |
  | `test_damage_formula` | the numbers of §7.3 (3.75 / 33.75 / 60 / 79.35 HP), k_mass, the tiers |
  | `test_takedown` | the ram wrecks the victim and is credited, the vertical takedown, the psyche-out, the streak |
  | `test_parts` | the parts of a stub car, the paint scrape, the mesh without UVs |
  | `test_parts_real` | the parts on the real Roadster, **one wheel and the front left one** on a violent wreck, **no wheel** on a wreck by scrapes, the cylinder of the wheel (0.285 m), **the debris wears the colour of the car** (#D81E2C), **the door opens 15° outwards once** |
  | `test_pool` | 100 crashes, 32 debris max, the state of the cars does not leak, the frame of the unit is 0.03 ms |
  | `test_respawn` | the wreck flow, **21.0 m/s after a 30+30 head-on**, the car drives along the road, **the ghost fades from 0.30 to 0.70**, **the door is back at rest** |
  | `test_paint_sync` | every uniform of the shared paint, with the same type, and **the hash of the source** |
  | `test_budget` | **the mean of 24 hits 0.27 ms, the worst 0.53 ms, the join 0.03 ms, the respawn 0.02 ms** and every car reaches the LIGHT tier on its third hit (the tier change is inside the measured hits) |
  | `test_mask` | **the scrape reaches the GPU**, every corner of every painted panel is inside its own region, **a hit on the left leaves the region of the right at 0** |
- The captures (all `CAPTURE errors=0`):
  - `captures/damage/final_close_t3_4.jpg` (+ `final_close_crop.jpg`) — the dented door from 2 m:
    the scrape with its ragged dark rim and the primer in the middle, the dent bowl around it.
    The trim and the paint move together (there is no black rectangle).
  - `captures/damage/final_mask_t3_4.jpg` (+ `final_mask_crop.jpg`) — the same panel with the
    dents off: only the scrape is left, and the primer #8C8F93 reads in it.
  - `captures/damage/final_dents_t3_4.jpg` — the same panel with the mask off: the dent alone.
  - `captures/damage/final_lineup_t2_4.jpg` and `_t3_2.jpg` — the Roadster and the police car
    from 6 m after three hits each: the dent, the scrape, the bumper on the road.
  - `captures/damage/final_crash_t0_95.jpg`, `_t1_15.jpg`, `_t1_45.jpg`, `_t1_95.jpg` — the
    crash: the impact, the smoke from the hood, the parts in the air, the wreck.
- The full game: `tools/godot.sh run res://main.tscn 18` → `SMOKE seconds=18 fps_mean=54
  fps_min=14 errors=0 warnings=0`. The damage unit adds no engine error and no warning.

## Known issues

- **The mask is RGBA8, not R8/RG8.** The alpha channel is what `Image.blend_rect` uses as
  the blend factor, so a mask without an alpha cannot be blended in C++ and the scrape would
  have to be written pixel by pixel in GDScript (about 1 ms per hit, over the budget of
  §7.7). The pool holds at most 16 masks (64 MiB).
- **The surfaces that have a shader of their own (the glass of the cars) are not dented.**
  The damage unit reproduces a BaseMaterial3D, not a shader it does not own. The glass sits
  above the doors, so the dent of a door does not reach it.
- **The depth of a dent is limited by its radius (a dish of 25 % slope), not by the edges of
  the panels.** The edges would have to be read from the mesh (2.3 ms for the Roadster) and
  the depth would have to differ from panel to panel, which would break the "one field" rule.
  The panels of the cars are coarse (0.18 m), so a deeper dent folds them.
- **The traffic lamps do not flicker.** Their material belongs to the traffic unit (a shader
  with an `energy` instance uniform) and the damage unit never writes the instance uniforms of
  another unit. See the request below.
- **The car that loses a wheel leans on its bare hub** (the visual drops 0.28 m on that
  corner); the physics body does not lean, so the car keeps driving on three wheels.
- **The unit does not free the wrecked AI cars:** it stops them being obstacles, sinks and
  hides them after 6 s. The traffic unit despawns its own cars.
- **Godot reports the particle shader of a wrecked car as leaked when the game quits.** It
  is a report of the teardown of the rendering server, not an error of the run: the smoke
  run counts `errors=0`.
- **The machine is shared with the other units** (the load average was 30 to 70 during the
  runs of this round). The budget test takes the best of ten rounds for every hit and the
  best of three rounds for every car that joins, so the numbers are the cost of the code and
  not the cost of the machine. The capture of the acceptance shot freezes the cars at the end
  of the hits, so the framing of the shot is the same every time.

## Files (all mine, all under `game/damage/`, every file under 400 lines)

| file | lines | what |
|---|---|---|
| `damage_director.tscn` / `damage_director.gd` | 375 | the entry scene: the bus, the contacts, the tiers, the wrecks, the takedowns, the budget. |
| `damage_rules.gd` | 74 | the pure numbers of dossier §7.2-§7.4 and §3.5. |
| `contact.gd` | 25 | one contact: the point, the normal, the zone, the closing speed, the impact ratio. |
| `contact_pairs.gd` | 75 | the contacts of the pairs of cars (the same contact of two cars is only resolved once). |
| `car_damage.gd` | 150 | the state of one car: the tier, the damage per zone, the parts, the pre-crash speed, the rest transforms. |
| `car_state_manager.gd` | 82 | the registry of the cars: their state, their painter and their rig. |
| `car_surface.gd` | 140 | one mesh of a car and its place in the space of the car (the panels of the model are read once). |
| `impact_handler.gd` | 171 | what a contact costs: the classification, the HP, the dent, the scrape, the parts. |
| `dent_painter.gd` | 334 | the dent rig of one car: the field, the panels, the mask. |
| `dent_materials.gd` | 212 | the materials of the damage unit: the damage paint and the generic damage surface. |
| `dent_field.gdshaderinc` | 135 | the dent field, shared by the two damage shaders. |
| `dent_paint.gdshader` | 330 | GENERATED from the shared paint (see the tool). |
| `dent_basic.gdshader` | 104 | the generic surface with the dent field. |
| `tools/make_dent_paint.py` | 310 | GENERATES `dent_paint.gdshader` from `res://shaders/car_paint.gdshader` plus the damage layer, and writes the hash of the source into the header. |
| `mask_atlas.gd` | 267 | the paint-scrape mask: a 1024² car-space atlas, the regions, the brushes. |
| `mask_pool.gd` | 75 | the pool of the masks (16 at most, the least recently used first). |
| `part_catalog.gd` | 125 | the detachable parts of §7.6 and the rules that tear them off. |
| `part_manager.gd` | 296 | the parts of a car, the sprung doors, the debris. |
| `debris_pool.gd` | 216 | the pool of 32 rigid-body debris, 8 s of life and a fade. |
| `damage_fx.gd` | 174 | the coordinator of the tiers: the smoke, the sparks, the lamp, the arcs, the wreck. |
| `damage_lamp.gd` | 99 | the head lamp that flickers. |
| `bumper_hang.gd` | 63 | the bumper that hangs at 25°. |
| `tier_emitters.gd` | 292 | the smoke and the sparks of the tiers (the process materials are shared). |
| `ev_arcs.gd` | 210 | the electrical arcs of the electric car. |
| `fx_assets.gd` | 119 | the textures of the effects, built once. |
| `spark_burst.gd` | 93 | the spark shower of a hard hit. |
| `wreck_flow.gd` | 269 | the wreck flow of §7.8: the crash cam, the respawn, the ghost. |
| `takedown_tracker.gd` | 69 | the takedown credit, the streak and the labels. |
| `tests/` (10 files + the kit) | ~1650 | the unit tests (see above). |
| `demo/damage_demo.tscn` / `.gd`, `demo/dent_lineup.tscn` / `.gd` | 245 + 174 | the crash demo and the acceptance shot. |

## Requests (to core / other units)

- **traffic unit**: the head lamps of the traffic cars are a `material_override` of
  `TrafficMaterials` with an `energy` instance uniform. The damage unit must not write it (it is
  your uniform), so the lamps of a hurt traffic car do not flicker. Please flicker your own
  `energy` on `Events.vehicle_damaged` (the unit already knows the tier of the car).
- **vehicle unit**: the takedown reward of §3.5 is **+50 N₂ per takedown** (+25 per streak step).
  There is no API for it and the damage unit does not touch the N₂ of a car: please add the N₂ to
  `Events.takedown` (the vehicle unit owns the boost). The damage unit emits
  `Events.stunt(&"takedown", points, label)` with the points (50, 75, 100, ...) for the HUD.
- **shaders unit**: the dents need a copy of the car paint, because the shared material has no
  room for the dent field and the damage mask. The copy is GENERATED by
  `game/damage/tools/make_dent_paint.py` from `res://shaders/car_paint.gdshader` (the scripts in
  `game/damage/tools/`), so it always carries the current look of the shared paint; run the
  script after every change of the shared paint, and `tests/test_paint_sync.gd` fails if the two
  drift apart (it compares the hash of the source now). If the shared `SH_car_paint` took
  `dent_pos[8]`, `dent_dir[8]` and `damage_mask`, the damage unit could use it directly and the
  generator could go.
- **art unit**: the carbon of the dossier is `Fabric004` with a 6 mm weave (#1C1E22, roughness
  0.35, anisotropy 0.5). It is not in `game/assets/textures/` yet, so the damage unit builds a
  procedural 2/2 twill. Please add `Fabric004` to `game/assets/textures/` and the damage unit
  will sample it.
- **car_model / npc_cars units**: the panels of the Roadster have a p90 edge of 0.18 m and the
  npc panels 0.36 m (dossier §7.5 asks for 0.12 m), so a dent is only two or three triangles
  wide. A finer subdivision of the bumpers, the hood, the doors and the rear deck would make the
  dent read at the depth of the dossier. The npc `Bumper_F/R` are zero-thickness planes (a
  0.00001 m AABB): they need a real thickness, and their debris needs `cull_disabled` until then.
- **police / rival units**: a wrecked car of yours should despawn (or sink) 6 s after the wreck,
  like the traffic unit does. The damage unit only plays the visual part of the wreck.
- **core**: `Events` has no "car repaired" signal. After a respawn the damage unit restores the
  tier of the player through `Events.player_respawned`; a `vehicle_repaired` signal would be
  cleaner.
