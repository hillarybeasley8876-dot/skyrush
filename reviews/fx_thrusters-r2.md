# fx_thrusters review round 2 — VERDICT: FAIL

## Scores (0-10): function, visual, code
- **function 4** — Fixed since r1: the stub-car fallback follows the car, at most 2 cars get the full
  plume (player first), and the capacity is 3,200 particles per car. Still broken:
  - the rear launch cloud never emits;
  - `detach()` leaves the real-glb plumes firing forever;
  - attach after detach still raises the engine error;
  - particle collision is off;
  - the flipbook never changes frame;
  - the landing ring is vertical;
  - the GPU cost is 1.45–1.64 ms/view at h = 1.6 m (budget 1.2).
- **visual 3** — Plume colour, demo lighting and proximity fade are right now. But:
  - every particle draws frame 0 (a disc with a bite), so the plumes read as rows of identical
    "Pac-Man" cotton balls;
  - the lift columns are dotted strings;
  - the "ground cloud" is a shell of balls that flies 4–8 m into the sky;
  - there is no launch trail (photo 29);
  - the shock diamonds have only 1.12–1.22 peak/trough contrast;
  - the cloud is invisible at 100 m.
- **code 5** — Typed code, named constants, files ≤ 288 lines. But five real bugs got past the tests
  (INF accumulator, wrong disconnect target, orphaned NozzleFX, dead collision box, unused flipbook),
  and several comments and status claims are false (MUST-FIX 12).

## Round-1 MUST-FIX status
| r1 # | Item | Now |
|---|---|---|
| 1 | Fallback anchors parented to the car | **OK** (test + `captures/rv2_stub_t3_0.jpg`) |
| 2 | GPU budget | **FAIL** — 1.451 / 1.642 ms/view at h = 1.6 (MUST-FIX 11) |
| 3 | Continuous vapour column | **FAIL** (MUST-FIX 5) |
| 4 | Ground cloud shape | **FAIL** (MUST-FIX 3, 4) |
| 5 | Sprites | **Partly**: fade, border α 0.000, mipmaps and Decal OK; flipbook unused and sprite design FAIL (MUST-FIX 1, 2) |
| 6 | Landing puff bursts outward | **FAIL** (MUST-FIX 7) |
| 7 | At most 2 full-plume cars | **OK** (weak test, SHOULD-FIX 1) |
| 8 | Attach after detach without error | **FAIL** — still raises (MUST-FIX 9) |

Lead notes: 1 OK, 2 FAIL, 3 FAIL, 4 FAIL, 5 OK. The lead's project rules were violated (MUST-FIX 12).

## MUST-FIX
1. **The flipbook is never used: every particle draws frame 0.**
   - Probe (`tmp/review/fx_thrusters/probe_r2.gd`): JetVapour has `anim_speed=0.0/0.0`
     `anim_offset=0.0/0.0`. `ground_cloud.gd` and `landing_puff.gd` never set them either.
   - Frame 0 is a disc with a dark bite on its right. That is the identical "C / Pac-Man" puff in
     `captures/rv2_dist_d5.jpg`, `rv2_chase_t10_4.jpg` and `rv2_chase_t13_0.jpg`.
   - The comment at `nozzle_fx.gd:130` ("the flipbook advances with the particle's age") is false:
     with `anim_speed` 0 the frame never advances.
   - Do:
     - In all 3 process materials set `anim_speed_min = anim_speed_max = 0.0`,
       `anim_offset_min = 0.0`, `anim_offset_max = 1.0`. Each particle then gets a random frame and
       keeps it. The 16 frames are different puffs, not a time sequence, so do not play through them.
     - `angular_velocity` is in degrees/s, so today's ±0.6 / ±0.3 is static. Use ±30 for the vapour
       and ±12 for the clouds.
   - Verify:
     - A test asserts `anim_offset_max >= 0.99` on the vapour, lift cloud, rear cloud and landing puff.
     - In the d5 capture, no two neighbouring puffs have the same shape.
2. **The puff sprite reads as moon rock, not vapour** (贴图纹理要细化;
   `captures/review/fx_thrusters/r2/atlas_view.jpg`).
   - Every frame has a clean circular silhouette. In `gen_textures.py:125-127`,
     `fall = (1-rw²)^0.45` is a plateau and `edge` is a smoothstep at r = 1.
   - Every frame has hard-edged holes. Line 129 thresholds the density
     (`clip((density-0.34)*2.6)`), and line 116 (`clip(1-b*2.2)`) turns the Worley cells into cracks.
   - `soft_puff_n.png` is the gradient of that thresholded alpha ×40, so it shows dried-mud crack
     ridges.
   - The frames are 256² (r1 asked for 512²).
   - Do:
     - Atlas 2048², 512² per frame, 16 frames.
     - Density per frame = union of 6–10 soft lobes (Gaussians, σ 0.12–0.25 of the frame, centres at
       r ≤ 0.45) × (0.6 + 0.4·billow), where billow = 1 − |2·fbm − 1| (5–6 octaves, domain warp
       ≈ 0.06 of the frame).
     - α = smoothstep(0.08, 0.65, density): no hard threshold and no Worley cut-outs. The outline is
       lobed, never a circle. Keep `smoothstep(0.98, 0.80, r)` only as a safety mask.
     - Normal map from the density blurred with σ ≈ 6 px, used as a height field, gentle (mean |n.xy|
       0.2–0.35): rounded lobes, no ridges.
     - Make 4 of the 16 frames elongated 1.6 : 1 (wisps) for the jet tails.
   - Verify:
     - `gen_textures.py` prints per frame:
       - border α = 0.000;
       - max |Δα| per pixel ≤ 0.03;
       - coefficient of variation of the α = 0.1 contour radius ≥ 0.12 (a circle gives 0);
       - α < 0.05 on ≤ 5 % of the pixels inside the outer contour.
     - Save `captures/fx_thrusters/atlas_preview.jpg` over #101828. No circle and no crater may show.
3. **The lift "ground cloud" is an expanding shell that flies into the sky** (lead note 4, brief
   layer 3).
   - `ground_cloud.gd:59-70` emits from a 0.8 m sphere placed 1 m above the hit
     (`_update_one(_lift, lift_hit, IDENTITY, Vector3.UP)`), with `radial_accel` 6–12 m/s². The probe
     reads `radial_velocity=0.0-0.0`.
   - That acceleration pushes every particle away from the centre for its whole 3 s life:
     - the upper half climbs forever: puffs sit 4–8 m above the car in `captures/rv2_hop_rear_t3_0.jpg`
       and in every `captures/rv2_land_*.jpg`;
     - the lower half dives into the road;
     - the cloud speeds up instead of bursting out and slowing down.
   - `captures/rv2_strip_s1..s4.jpg` (camera 30 m behind, the 20 m poles at x = ±10): about 5 m of
     sparse puffs, 1–3 m above the road.
   - Video t = 118–120 (`sheetD_strip.jpg`, bottom row): a dense wall wider than 2 car lengths,
     sitting on the road. Dossier §6: 1 s after touchdown ~20 m wide, ~2.5 m tall, lasting 3–5 s.
   - Do (dossier §6.3 item 3):
     - `EMISSION_SHAPE_RING` with `emission_ring_axis = Vector3.UP`, radius 1.2, inner 0.3,
       height 0.2, emitter at `lift_hit + (0, 0.3, 0)`.
     - `radial_velocity_min/max = 6/12` (pivot = emitter origin), `radial_accel = 0`.
     - Up 1–3 m/s, spread 15°, damping 3, gravity 0.
     - Size 1.5 → 5 m, #E6EAEE α 0.55 → 0.25 → 0, lifetime 2.5–4 s.
     - 60–90 particles per burst every 0.25 s while firing, or continuous ≈ 300/s.
     - Collision on (MUST-FIX 10).
   - Verify:
     - The strip cams above at 0 / 0.5 / 1 / 2 s after the jet reaches the road, at h = 1.6 and 6 m.
     - At 1 s the cloud spans ≥ 16 m between the poles, is 2–3 m tall and sits on the road, with no
       puff above 4 m.
     - Overhead: a round footprint.
     - d100 (`68,22,72 → 0,3,0`): a clearly visible white mass.
4. **The rear launch cloud never emits, and if it did it would blow forward** (brief layer 3 "Rear
   launch"; photo 29).
   - `thruster_rig.gd:195` starts the sum at `var exit_pos := Vector3(INF, INF, INF)` and line 204
     adds to it. INF + x = INF, so `_rear_exit` is always INF.
     - Probe, rear nozzles at 1.0, car on the road: `_rear_exit=(inf, inf, inf)`,
       `RearCloud.emitting=false`.
     - The test "rear cloud is off 2.5 m above the road" passes only because the cloud can never be on.
   - `ground_cloud.gd:110` builds the basis with `Basis.looking_at(rear_dir)`, which puts −Z on the
     jet. The material direction is +Z, so the cloud would go toward the car's nose (probe: `(0, 0, -1)`
     for a jet along +Z).
   - `captures/rv2_boost_overhead_t3_0.jpg` vs photo 29 (`sheetB_29_28.jpg`, top row): no trail at
     all, against a dense white plume 12–13 m long and 4–5 m wide.
   - Do:
     - Start both sums at `Vector3.ZERO` (`exit_pos` and `dir`).
     - Emit along the jet (`direction = (0, 0, -1)` with that basis).
     - Trail: 10–14 m/s, spread 9°, radial_velocity 1–2 m/s, damping 1.5, size 0.8 → 3.5 m,
       α 0.5 → 0, ~250/s, collision on.
     - `inherit_velocity_ratio = 0` (dossier: "the gas stays where it was emitted").
   - Verify:
     - New test: rear nozzles at 1.0, car on the road → `RearCloud.emitting` is true, and its world
       emission direction · car +Z > 0.9.
     - Overhead capture at cycle t = 10.4 (1.0 s into the moving boost), next to photo 29: the trail
       starts at the nozzles, is 12–13 m long and 4–5 m wide at the far end.
5. **The vapour is still a beaded spray, not a column** (lead note 2, r1 MUST-FIX 3; the status
   "Known issues" admits it).
   - `captures/rv2_hover_side_t3_0.jpg` and `rv2_dist_d5.jpg` show dotted strings of 0.1–0.38 m
     sprites. Photos 27 and 28 show a dense, continuous, turbulent column, 0.4–0.8 m wide at 3–5 m.
   - Likely contributors (probe): `fixed_fps` is the default 30, so at 30–32 m/s a particle moves ~1 m
     per simulation step, and the default `turbulence_influence` of 0.1 is applied per step. Both make
     the look depend on the frame rate. The demo's `Engine.max_fps = 60` only hides that.
   - Do (recommended, because the budget forbids more particles):
     - Add a **JetColumn mesh per nozzle**: an open tapered tube, 16 × 12 segments, length × intensity.
       Radius 0.05 → 0.35 m over 3 m (lift), → 0.5 m over 4 m (rear), → 0.15 m over 1 m (yaw).
     - Give it an alpha-blended shader: two noise layers scrolling along UV.y at the jet speed (×1.0
       and ×0.6); α = smoothstep(0.3, 0.75, noise) × pow(facing, 1.2) × (1 − v)^1.5, at most 0.5 near
       the throat. Lit tint, or a fake top light. One draw call per nozzle.
     - The particles then only do the breakup further out:
       - scale [[0, 0.2], [0.3, 0.6], [1, 1.4]] m (dossier);
       - α 0.25 → 0.1 → 0, 150 alive per nozzle, random frame (MUST-FIX 1);
       - `fixed_fps = 120`, turbulence_influence ≈ 0.025.
   - Verify:
     - d5 cam (`3.2,5.2,4.2 → 0,3.6,0`, fov 55) while hovering: no individually readable sprite in the
       column; it is continuous from the nozzle to the road and 0.4–0.8 m wide 3 m below the car.
     - The same shot at 60 and at 120 fps (add a `--demo-fps` option) looks the same.
     - Side by side with photo 27.
6. **The shock diamonds are not clearly visible** (lead note 3).
   - Luminance along the P2 jet axis in `captures/rv2_diam_p.jpg` (1.8 m away, perpendicular):
     peaks 244 / 237 / 215 / 190, troughs 212 / 187 / 156, so peak/trough is **1.12–1.22**. It reads
     as a soft flashlight beam.
   - In the rear close-ups (`rv2_core_t3_0.jpg`, `rv2_diam_r.jpg`, `r2/sheetG_core_vs18.jpg`) the four
     rear cores merge into one white slab, with no bands.
   - Cause: the base between rings, `energy·(0.25 + 0.55·fade)` ≈ 1.2 HDR, sits in the AgX shoulder
     and above the glow threshold (1.1), which flattens the bands.
   - Do, in `jet_core.gdshader`:
     - between rings ≤ 0.8 HDR (e.g. `energy * (0.12 + 0.3 * fade)`);
     - ring peaks ×4 (`1.0 + rings * 4.0`), `ring_width` 0.02;
     - `pinch` 0.25, so the silhouette necks at each diamond;
     - an axial core term `exp(-pow((1.0 - facing) * 6.0, 2.0))`;
     - first diamond ≈ 3 HDR ("just enough bloom").
   - Verify:
     - A python luminance profile along the P2 axis at 1.5–1.8 m, and along R1 in the core_rear
       capture. Print both in the status.
     - Each must show 4 maxima with peak/trough ≥ 1.6, decreasing ≈ 1.0 / 0.7 / 0.45 / 0.25.
     - Redo `compare_core.jpg`.
7. **The landing puff is a vertical hoop half under the road, and it does not burst outward**
   (r1 MUST-FIX 6).
   - The ring axis is never set, so it stays at Godot's default (0, 0, 1) (probe: `ring_axis=(0, 0, 1)`).
     With the emitter basis `[X 1.2, Y 1.0, Z 2.4]` the ring stands upright: 2.9 m wide, 2.4 m tall,
     centred 0.18 m above the road, so its lower half is underground.
   - `radial_accel` 5.5–6.5 m/s² against damping 4 leaves a net ≈ 2 m/s², about 0.16 m of outward
     travel in 0.4 s.
   - `captures/rv2_land_t3_75 / t4_0 / t4_4` (hop landing) and `t9_55 / t9_8` (6 m drop), see
     `r2/sheetE_land.jpg`: no low ring past the wheels. Keyframe t140 shows a dense ring around the
     car at ground level.
   - Do:
     - `emission_ring_axis = Vector3.UP`.
     - `radial_velocity_min/max = 5.5/6.5` m/s (r1 asked for a velocity, not an acceleration),
       `radial_accel = 0`.
     - Up 0.8 m/s, spread 10°, damping 4, scale 0.8 → 2.5 m, 64 particles, α 0.7 → 0, collision on.
     - Rotate the 4 × 6 m decal with the car's yaw (`landing_puff.gd:104` sets the rotation to zero).
   - Verify:
     - Rear-cam frames 0.15 s and 0.4 s after `Events.landed` (`--warm=1 --times=3.75,4.0`): a ring
       ≤ 1 m tall reaching ≥ 2 m past the wheels at 0.4 s, and nothing under the road. Compare with
       `ref/video/keyframes/t140.jpg`.
     - A test asserts `emission_ring_axis == Vector3.UP`.
8. **On cars with real markers, `detach()` leaves the plumes firing forever and leaks nodes.**
   - `tmp/review/fx_thrusters/probe_detach.gd` (DemoCar + roadster.glb, all nozzles at 1.0):
     - after `detach()`: `[fx nodes, emitting, cores visible] = [10, 10, 10]`, `attached=0`;
     - after re-attach, marker `Nozzle_R1` has two plume children (`FxNozzle_R1`, `@Node3D@4`).
   - Cause: `thruster_rig.gd::_build_nozzle()` parents each NozzleFX to the car's marker, but
     `_exit_tree()` frees only the fallback anchors. An orphan keeps its last `_target`.
   - Do: keep every NozzleFX in the rig and `queue_free()` all of them in `_exit_tree()`, whether
     they hang off a marker or a fallback anchor.
   - Verify: a test on a car with real markers (DemoCar + glb, or a stub with `Nozzle_*` Node3D
     children):
     - fire, detach, wait 2 frames → no NozzleFX left under the car;
     - re-attach → exactly one per marker.
9. **Attach after detach still raises the engine error** (r1 MUST-FIX 8; the status says it is fixed).
   - `tools/godot.sh test res://fx/thrusters/tests/test_thrusters.gd` prints
     `ERROR: Signal 'tree_exiting' is already connected to given callable
     'Node3D(thruster_system.gd)::_on_vehicle_gone'` right before `PASS attach after detach works`.
   - Probe after detach: `tree_exiting connections to the system after detach = 1`.
   - Cause: in `thruster_system.gd:139`, `callback.get_object()` is the ThrusterSystem (it owns the
     bound method), not the vehicle. So line 141 never disconnects `vehicle.tree_exiting`.
   - Do: store the vehicle per key (`Dictionary[int, VehicleBase]` or a WeakRef), disconnect from
     `vehicle.tree_exiting`, and guard `connect` with `is_connected`.
   - Verify: the test counts engine errors (an `OS.add_logger` counter like `res://tools/error_counter.gd`)
     and asserts 0 over attach → detach → attach. The test log has no `ERROR:` line.
10. **Particle collision is off, so the collision box does nothing — and the box sits 0.5 m too high.**
    - Probe: `collision_mode=0` (DISABLED) on the vapour and the clouds.
      - The status claim "the vapour lands on it and spreads instead of sinking" is false.
      - The lift columns run into the road; the proximity fade hides where they cross it.
    - `thruster_rig.gd:190` puts the 0.5 m box with its bottom on the road. Its top face, where
      particles would rest, is 0.5 m above the road.
    - The comment at `nozzle_fx.gd:113-115` is wrong. Godot's damping is linear (v −= d·Δt):
      32 m/s at 30 m/s² stops after 32²/60 ≈ 17 m. The turbulence scattering the direction is what
      shortens the jet, not "a third more" damping.
    - Do:
      - `collision_mode = COLLISION_RIGID`, `collision_bounce = 0`, `collision_friction = 0.3`,
        `collision_use_scale = true` on the vapour, the clouds and the landing puff.
      - Box position = `hit − (0, size.y / 2, 0)`, so its top face is the road.
      - Fix the comment.
    - Verify:
      - Side capture at h = 1.6 (hop): the column hits the road and spreads sideways; nothing goes
        below the road surface.
      - A test asserts `collision_mode != COLLISION_DISABLED`.
11. **The GPU cost is over budget, and both the bench and the normalisation are wrong**
    (r1 MUST-FIX 2).
    - `demo/bench8.gd` never hides the FX before window 0, so the first "off" window is measured with
      the FX on.
    - My corrected copy (`tmp/review/fx_thrusters/bench8_fixed.gd`, which calls `_set_fx(false)` at
      the end of `_setup()`): **h = 1.6 → 1.451 ms/view**, h = 6.0 → 0.975 ms/view. The shipped bench
      gives 1.642 ms/view at h = 1.6.
    - Budget: ≤ 1.2 ms, and that was without the rear launch cloud, which never ran (MUST-FIX 4).
    - The status's "≈ 1.1 ms normalised" divides by the base of a different scene (demo 2.58 ms/view
      vs GODOT.md's bench_world 1.82). GODOT.md §3.1 allows only in-run deltas.
    - The line `BENCH particles=…` prints `RENDER_TOTAL_PRIMITIVES_IN_FRAME`, not particles.
    - Do:
      - Fix the bench: hide the FX before window 0, correct the label, and add `--h=0.4` (both clouds
        running).
      - Ways to cut cost:
        - the JetColumn mesh lets the vapour drop to ~150 particles per nozzle;
        - measure `DRAW_ORDER_INDEX` against `VIEW_DEPTH` for the vapour (VIEW_DEPTH sorts once per
          view, and same-colour alpha vapour hardly needs sorting);
        - fewer, bigger cloud particles at lower α;
        - per-vertex cloud shading if still needed.
    - Verify: the status shows 3 raw runs each at h = 0.4 / 1.6 / 6.0, with the `uptime` load average.
      The median is ≤ 1.2 ms/view.
12. **Evidence, claims and the lead's project rules.**
    - `captures/fxth_final_hover_side_t3_0.jpg` is a `cp` of `fxth_K2_hover_side_t3_0.jpg` (log step
      363). That capture predates later edits: `nozzle_fx.gd` at step 371, the `nozzle_table.gd`
      damping at step 390.
    - Claims the probes contradict:
      - "16 distinct puffs": only frame 0 renders.
      - "the vapour lands on it and spreads": collision is off.
      - "attach after detach no longer raises": it still raises.
      - "a visible white mass at 100 m": `rv2_dist_d100.jpg` shows a faint smear.
      - "inside the 1.2 ms budget": 1.45–1.64 ms/view.
      - "32 PASS": the run prints 28 PASS.
    - Lead rules broken:
      - 11 background runs (`nohup … &`, log steps 323–368, Godot captures and benches);
      - 97 commands writing logs to `/tmp/*.log`, still lying there (e.g. `/tmp/final_check.log`). Scratch
        belongs in `tmp/fx_thrusters/` and is deleted at the end.
    - Do:
      - Regenerate every status capture with one foreground script after the last code change.
      - Quote command output for every claim.
      - No `nohup` or `&`. Delete your `/tmp` logs.
    - Verify: every capture is newer than the newest file in `game/fx/thrusters/`, and the log has no
      `nohup` or `&` runs.

## SHOULD-FIX
1. **The tier test is weak.**
   - `_system.attach(_npcs[0])` returns early because that car is already attached, so
     `_recompute_tiers()` never runs after `Game.player` is set. The test passes only because the player
     happens to be the 2nd car attached.
   - Write the r1 test: attach 3 NPCs first, then attach a new player car last. Assert exactly 2 rigs at
     tier 0 among all attached cars (including `_car`), one of them the player.
   - Recompute the tiers when `Game.player` changes (e.g. on `Events.player_respawned`).
2. `thruster_system.gd::_process` calls `_remove_rig(key)` inside `for key in _rigs`, which erases from
   the dictionary while iterating it. Collect the stale keys first, then remove them.
3. **Typing.** The demo's `var _system: Node3D` calls `.attach()` dynamically, and the tests use
   `_rig() -> Node` with `.call("get_nozzle")`. Use the preloaded script types.
4. **Magic numbers left:**
   - `landing_puff.gd`: `Color(0.949, 0.965, 0.980, …)` twice (it is `PlumeAssets.VAPOUR_BIRTH`),
     `cull_mask = 1048575`, `PUFF_LIFETIME + 0.1`, damping 4.0, the ring inner factor ×0.72, ring
     height 0.1.
   - `nozzle_fx.gd`: core colour, energy and ring vectors (brief values, make them consts), the 0.95
     speed factor, throat disc sizes.
   - `ground_cloud.gd`: gravities −0.4 / −0.2, and 0.85.
5. **Demo ground** (the stage for the money shot):
   - There is still no puddle mask (r1 SHOULD-FIX 4; ART §5: roughness 0.35 dry → 0.05 in puddles,
     driven by a mask).
   - The 4.17 m tile repeat (`uv1_scale` 48 on 200 m) shows as repeated cracks and bright speckle in
     `rv2_land_*.jpg` and `rv2_boost_overhead_t3_0.jpg`.
   - Add a world-space macro noise tint and a puddle mask.
6. `test_thrusters.gd:216-217` has a duplicate doc comment. The test exits with "4 ObjectDB instances
   were leaked" and "1 resources still in use": free the cars and the system before `quit()`.
7. `GROUND_REACH = 6.5` while the brief says ≤ 6 m. Use 6.0, or justify 6.5 in the comment.
8. Lights: the brief asks for energy 0.5–1 while firing, but `_update_lights()` uses the raw throttle,
   which gives 0.1 at 10 %. Use `lerpf(0.5, 1.0, best)`.

## Verified OK
- **Check:** `tools/godot.sh check --only=res://fx/thrusters/` → `CHECK 15 files, 0 failed,
  0 engine errors, 0 warnings`.
- **Tests:** `tools/godot.sh test res://fx/thrusters/tests/test_thrusters.gd` → 28 PASS,
  `TESTS PASS`. But it prints an engine `ERROR` (MUST-FIX 9).
- **Stub fallback:** the anchors follow the car at the dossier positions and directions (test +
  `rv2_stub_t3_0.jpg`). `--demo-car=stub` works.
- **Tiers:** player + 1 car get the full plume, the 3rd car is reduced, the rest are core only.
  Capacity is 3,200 per full car (≤ 6,000) and scales with the preset (120 per nozzle on low, in the
  headless probe).
- **Billboards:**
  - the vapour is shaded `SHADING_MODE_PER_VERTEX`;
  - proximity fade is 0.25 / 0.6 m;
  - border α is 0.000 on all 16 frames and on the ring;
  - mipmaps are on;
  - the ground ring is a `Decal`.
- **Colours:** core #EAF4FF; throat #9FD8FF up to energy 3; 2 omni lights #CFE3FF, range 2 m;
  vapour #F2F6FA α .35 → #D8DEE6. No orange comes from the FX: the warm pixels (0.24 % of the core
  close-up) are the car's bronze nozzle rims.
- **Lead notes 1 and 5:** the demo lighting is neutral, and the real glb is used.
- **Landing gating:** a crash spawns no puff; clean/wobble above 4 m/s spawns one; leaving a sky lane
  spawns one.
- **Telemetry keys:** the vehicle writes StringName keys (`vehicle/modules/car_readout.gd`) and the rig
  reads Strings. They resolve to the same entry (probe_keys: 0.7).
- **Ownership:** Write/Edit touched only `game/fx/thrusters/**` and `status/fx_thrusters.md`. The probe
  files were removed, and no unit process is left running.
- **File sizes:** max 288 lines (`thruster_rig.gd`).

## Evidence
All commands run from `/Users/minimax/m/skyrush`.

**Probes**
- `tools/godot.sh test /Users/minimax/m/skyrush/tmp/review/fx_thrusters/probe_r2.gd`:
  - `PROBE default anim_speed=0.0/0.0 anim_offset=0.0/0.0 collision_mode=0 (DISABLED=0) ring_axis=(0.0, 0.0, 1.0)`
  - `PROBE rear fired at y=0: _rear_exit=(inf, inf, inf) _rear_hit=(0.0, 0.0, 2.085) RearCloud.emitting=false`
  - `PROBE vapour R1 anim_speed=0.0/0.0 anim_offset=0.0/0.0 collision_mode=0 amount=120 lifetime=1.2 damping=10.0 scale_curve_max=(1.0, 0.38)`
  - `PROBE cloud collision_mode=0 radial_accel=6.0-12.0 radial_velocity=0.0-0.0`
  - `PROBE rear cloud world dir for jet dir +Z: (0.0, 0.0, -1.0)`
  - `PROBE landing puff ring_axis=(0.0, 0.0, 1.0) emitter basis=[X: (1.2, 0.0, 0.0), Y: (0.0, 1.0, 0.0), Z: (0.0, 0.0, 2.4)]`
  - `PROBE tree_exiting connections to the system after detach = 1`, followed by the `ERROR: Signal 'tree_exiting' is already connected…` line.
- `probe_detach.gd`:
  - `PROBE 0.5 s after detach (telemetry still 1.0): [10, 10, 10] attached=0`
  - `children of marker Nozzle_R1 = [FxNozzle_R1:<…>, @Node3D@4:<…>]`
- `probe_defaults.gd`: `GPUParticles3D fixed_fps=30 interpolate=true`, `turbulence_influence=0.1/0.1`.
- `probe_keys.gd`: `StringName key read with String: 0.7`.

**Bench** — `python3 tools/slots.py heavy 4 -- /opt/homebrew/bin/godot --path game --windowed --resolution 1920x1080 --always-on-top -s <bench> -- --h=<h>`, load average 42–58:
  - shipped `res://fx/thrusters/demo/bench8.gd --h=1.6`: `on=33.45 off=20.32 delta=13.13 per_view=1.642 ms`
  - `tmp/review/fx_thrusters/bench8_fixed.gd --h=1.6`: `on=32.35 off=20.74 delta=11.61 per_view=1.451 ms`
  - `tmp/review/fx_thrusters/bench8_fixed.gd --h=6.0`: `on=27.33 off=19.52 delta=7.80 per_view=0.975 ms`

**Atlas** (numpy over `textures/soft_puff.png`): 1024² RGBA, 16 frames of 256², border α 0.000,
coverage 0.19–0.56 per frame, every frame inside a circle. `soft_puff_n.png` has mean rgb
(0.5, 0.5, 0.965).

**Diamond profile** (`captures/rv2_diam_p.jpg`, column x = 800, rows 220–620): peaks 244 / 237 / 215 / 190
at y ≈ 244 / 292 / 348 / 396, troughs 212 / 187 / 156.

**Captures** (`captures/`), made with `tools/godot.sh shot --scene=res://fx/thrusters/demo/thruster_demo.tscn …`:

| Capture | Settings |
|---|---|
| `rv2_hop_rear_t3_0` | hop/rear |
| `rv2_hover_side_t3_0` | hover/side |
| `rv2_boost_overhead_t3_0` | boost/overhead |
| `rv2_core_t3_0` | core_rear/core_rear |
| `rv2_dist_{d5,d20,d100}` | hover, `--warm=180`, r1 cams |
| `rv2_strip_s{1..4}` | hover, cam `0,2.2,30 → 0,2,0` fov 50, `--warm=30` → t ≈ 1.0 / 1.5 / 2.0 / 2.5 s |
| `rv2_land_t{3_75,4_0,4_4,9_55,9_8}` | cycle, rear cam, `--warm=1` |
| `rv2_stub_t3_0` | `--demo-car=stub` |
| `rv2_chase_t{2_6,10_4,13_0}` | cycle, chase cam |
| `rv2_diam_p` | lift jet, 1.8 m, perpendicular |
| `rv2_diam_r` | rear cores only, `--demo-fx=core` |

**Sheets** (`captures/review/fx_thrusters/r2/`):
- `sheetA_18_27.jpg`: photo 18 | hop rear; photo 27 | hover side.
- `sheetB_29_28.jpg`: photo 29 | boost overhead; photo 28 | chase hop.
- `sheetC_core_dist.jpg`: core close-up, d5, d20, d100.
- `sheetD_strip.jpg`: mine on top, video t = 118.0 / 118.5 / 119.0 / 120.0 below.
- `sheetE_land.jpg`: landing frames + keyframe t140.
- `sheetF_stub_chase_core.jpg`.
- `sheetG_core_vs18.jpg`: rear cores ×2 vs a crop of photo 18.
- `sheetH_diamonds.jpg`.
- `atlas_view.jpg`.

**Worker log** (`jobs/fx_thrusters/log.jsonl`):
- `nohup` at steps 323, 326, 329, 332, 334, 337, 345, 347, 352, 363, 368;
- `cp captures/fxth_K2_hover_side_t3_0.jpg captures/fxth_final_hover_side_t3_0.jpg` at step 363;
- 97 commands log to `/tmp`.

**ART §10 checklist on the captures**
1. Value: the car reads, but the cloud balls in the sky clutter the frame.
2. Palette: OK.
3. Detail at 5 / 20 / 100 m: **FAIL** — identical sprites at 5 m, sparse at 20 m, nearly invisible at 100 m.
4. Tiling: **FAIL** — one sprite frame everywhere, and the demo floor repeats.
5. Scale: **FAIL** — the cloud is ~5 m wide instead of 20 m.
6. Emissives: the rear cores saturate into one slab.
9. Floating: **FAIL** — cloud puffs 4–8 m in the air.
10. Store screenshot: no.
