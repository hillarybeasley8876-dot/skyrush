# fx_thrusters review round 1 — VERDICT: FAIL

## Scores (0-10): function, visual, code
- **function 4** — The API, 40/120 ms smoothing, real-glb markers and the 36 tests work. But:
  - the stub-car fallback is broken: plumes stay at the world origin;
  - GPU cost is ~15× over budget;
  - more than 2 cars can get the full plume;
  - attach after detach raises an engine error.
- **visual 3** — The jet core and its diamonds read well up close. Everything else does not match
  the photos: the vapour is a dotted spray of separate "cotton balls", the ground cloud is a flat
  square carpet with hard ground-intersection lines, and the cloud is invisible at 100 m.
- **code 6** — Small files (max 298 lines) with a clean split. But: untyped `Node` calls, magic
  numbers in logic, a stale tuning comment, and a perf mode that never fires a nozzle.

## MUST-FIX
1. **Fallback nozzles are not parented to the car.** On the stub car the plumes stay at the world origin.
   - Cause: `thruster_rig.gd::_fallback_anchor()` adds the anchor to `FallbackAnchors`. That node is
     a child of the rig, and the rig is a child of ThrusterSystem, not of the vehicle.
   - Probe: `res://core/stubs/stub_car.tscn` at (0,5,0). 10/10 nozzles are wrong; their car-local
     y is −4.5 / −4.85 / −4.7, so the plumes fire from (x,0.5,z) world and never follow the car.
   - The mis-oriented-marker path (`_resolve_anchor` → `_fallback_anchor(local_pos, …)`) has the same bug.
   - Brief: "fall back to the dossier §5 positions … **parented to the car**".
   - Do: parent each fallback anchor to `vehicle.get_visual_root()` (or to `vehicle` if that is null),
     with `position` = the `NozzleTable` pos in car space. Free these anchors in `detach()` / rig
     `_exit_tree()`, because they now live under the car.
   - Verify:
     - New test in `tests/test_thrusters.gd`: instance `res://core/stubs/stub_car.tscn`, attach it,
       move it to (10,5,−3) with yaw 90°, wait 1 frame.
     - Assert for all 10 nozzles: `car.global_transform.affine_inverse() * fx.global_position` is
       within 0.01 m of the table pos, and the car-local −Z · table dir > 0.99.
     - Add `--demo-car=stub` and capture the stub hovering at 6 m (side cam).
2. **GPU cost is ~15× over budget, and the perf evidence is invalid.**
   - My 8-view bench (method: ref/tech/GODOT.md §3.1; script: `tmp/review/fx_thrusters/bench8.gd`):
     real glb, all 10 nozzles at 1.0, chase cam (0,1.9,6.6) vFOV 62°, 8 × 1920×1080 views,
     interleaved FX on/off windows.

     | Car height | Frame, FX on | Frame, FX off | Extra per 1080p view |
     |---|---|---|---|
     | 1.6 m | 235.9 ms | 73.3 ms | **+20.3 ms** |
     | 6.0 m | 195.6 ms | 60.9 ms | **+16.8 ms** |

     - Even the most conservative bound is ≥ 6.5 ms/view. Budget: **≤ 1.2 ms**.
     - The engine printed `timeout waiting for fence` while the FX were on.
     - Single-window capture: 35 fps at 5 m vs 116 fps at 20 m.
   - Causes:
     - Capacity is **21,600 particles per full car** (10 × 2,000 vapour + 2 × 800 cloud).
     - Emission is 3,333/s per nozzle (brief: 300–600/s), all alpha-blended and lit per pixel.
     - Two full cars = 43,200, against a whole-game budget of ≤ 20k billboards (brief, GODOT.md §3.2).
   - `thruster_demo.gd --demo-perf` returns from `_process` before `_write_telemetry()`, so no
     nozzle ever fires during its A/B. It also times CPU `delta`, not GPU. The status numbers
     (1.99 / 3.03 ms, 41 vs 52 fps) are not usable.
   - Do:
     - (a) ≤ 500 vapour particles alive per nozzle (≈ 420/s × 1.2 s).
     - (b) Vapour material `shading_mode = SHADING_MODE_PER_VERTEX`: still lit by the neon, far
       cheaper per pixel.
     - (c) Ground clouds: ≤ 400 particles alive per car, in total.
     - (d) Tier 1 = core + 25 % vapour and no cloud. Tier 2 = core only.
     - (e) Replace `--demo-perf` with an 8-view bench in `demo/` (same method as bench8.gd): all 10
       nozzles at 1.0, fixed chase cam, ≥ 8 interleaved on/off windows, print ms/view.
   - Verify: the status file shows the bench output for h=1.6 and h=6.0 at **≤ 1.2 ms/view**, and
     the per-car capacity (sum of `amount`) is ≤ 6,000.
3. **The vapour is a beaded spray of small balls, not a continuous column that breaks into billows**
   (lead note 2 is not met).
   - In `captures/review_fx_thrusters_r1_dist_d5.jpg` every sprite is a separate dot. The lift
     plumes are dotted strings.
   - Photo `27_live_flight_plumes_side.jpg` shows a dense column that widens to 0.4–0.8 m at 3–5 m.
   - Current values vs dossier §6.3:

     | Parameter | Now | Dossier §6.3 |
     |---|---|---|
     | Size | 0.05 → 0.40 m | 0.12 → 1.4 m |
     | Lifetime | 0.6 s | 0.8–1.4 s |
     | Damping | 26 | 100 |
     | Emission | 3,333/s | 300–600/s |

   - Do:
     - Scale curve (1 m quad): [[0,0.12],[0.15,0.35],[0.5,0.9],[1,1.4]].
     - Lifetime 1.2 s with `lifetime_randomness` 0.3.
     - Damping 80–100, so a 32 m/s lift jet stops at ~5–6 m (v0²/2d).
     - Alpha 0.35 → 0.12 → 0; about 420 particles/s.
     - The jet must hit the road and spread, not pass through it. Put a `GPUParticlesCollisionBox3D`
       (≈ 24 × 0.5 × 24 m) at the raycast hit with `collision_mode = COLLISION_RIGID`,
       bounce 0, friction 0.
     - Fix the stale comment at `nozzle_fx.gd:106-107`. It says "40 … about 5 m", but the code uses
       26, which travels ≈ 13 m in 0.6 s.
   - Verify: run `--demo-phase=hover --warm=180 --cams="d5:3.2,5.2,4.2:0,3.6,0:55"`. There must
     be no individually readable puffs, and the column must be continuous from the nozzle to the
     road. Compare side by side with photo 27.
4. **The ground cloud has the wrong shape, height and dynamics** (lead note 4 is not met).
   - `ground_cloud.gd` spawns uniformly in a 14 × 0.3 × 14 m box, with 0.2–0.7 m/s upward speed
     and 0.6–1.4 m particles.
   - The result:
     - It appears at full width at once.
     - It stays a flat carpet ≤ ~1 m tall.
     - The square footprint is visible: a diamond in `captures/review_fx_thrusters_r1_dist_d20.jpg`,
       a rectangle in `…_boost_overhead_t2_5.jpg`.
     - It is invisible at 100 m (`…_dist_d100.jpg`).
   - Video t=118–120 (`captures/review/fx_thrusters/strip_sheet_s.jpg`, bottom row) shows a dense
     dome taller than the car, ~20 m wide by 1 s.
   - Do (dossier §6.3 item 3):
     - Emission sphere r 0.8 m at the hit point.
     - `radial_velocity_min/max` 6 / 12 m/s.
     - Direction +Y with `initial_velocity` 1–3 m/s, spread 20°, damping 3.
     - Scale 1.5 → 5 m, lifetime 2.5–4 s, colour #E6EAEE with α ≤ 0.5 → 0.
     - Re-trigger every 0.25 s while firing, within the MUST-FIX 2 budget.
   - Rear launch cloud:
     - Emit only while the rear nozzles are ≤ 1.2 m above the road. Today it also fires with the
       car 2.5 m up (`…_core_rear_core_rear_t2_5.jpg`).
     - Start it at the nozzle exit and trail it backwards: a cone with 9° half-angle, 12–13 m long
       and 4–5 m wide after 1 s (`29_live_launch_plume_overhead.jpg`).
     - Never centre it under or ahead of the car. Today the ±5 m box is centred 1.5 m behind the nozzles.
   - Verify:
     - A side strip at 0 / 0.5 / 1 / 2 s, with two thin poles 20 m apart in the demo as a scale
       bar, stacked over video frames t=118.0 / 118.5 / 119.0 / 120.0.
     - A round footprint from overhead.
     - A visible white mass in the d100 view (`--cams="d100:68,22,72:0,3,0:55"`).
5. **Hard sprite edges and an unrefined texture** (acceptance: "no hard sprite edges";
   user: 贴图纹理什么都要细化).
   - (a) **No soft particles.** `plume_assets.gd::_make_billboard` never enables proximity fade.
     - Every billboard cuts the road in a straight line. This gives the flat-bottomed half-domes in
       `captures/review_fx_thrusters_r1_chase_t2_5.jpg` and the horizontal "venetian blind" bands
       in `captures/review/fx_thrusters/crops_s.jpg`.
     - Set `proximity_fade_enabled = true` with distance 0.6 m (cloud) / 0.25 m (vapour).
   - (b) **Non-zero alpha at the quad border.**
     - `soft_puff.png` reaches **0.125** at the border (must be 0.000), so the square shows.
       `ring_decal.png` reaches 0.106.
     - Multiply alpha by `smoothstep(1.0, 0.82, r)` on the **unwarped** radius.
   - (c) **The puff is one smooth 256² blob** (mean |dα|/px 0.0025) with baked ball shading
     (rgb 0.95 → 0.86), so every particle reads as a ball. Replace it:
     - A 4 × 4 flipbook atlas (2048², 512² per frame) of ≥ 16 distinct billowy puffs.
     - Domain-warped 6-octave fBm combined with inverted-Worley billows, with torn, wispy edges.
       No baked ball shading.
     - A matching normal map from the density (`normal_enabled`), so scene lights shade the billows.
     - `particles_anim_h_frames = 4`, `particles_anim_v_frames = 4`, random `anim_offset` per particle.
   - (d) **No mipmaps.** Both `.import` files have `mipmaps/generate=false`, which is why distant
     sprites sparkle (speckle grain in the d5 crop). Set it to `true`.
   - Verify: `gen_textures.py` prints border alpha = 0.000 for every frame of both textures, and the
     d5 and chase-hop crops show no straight lines and no speckle.
6. **The landing puff fires straight up instead of bursting out radially.**
   - `landing_puff.gd` uses direction +Y, spread 45°, 4–6 m/s, which makes a vertical fountain.
   - Its ring (r 1.2 m) is hidden under the 4.38 × 1.98 m body, so it barely shows in
     `captures/review/fx_thrusters/land_sheet_s.jpg`.
   - Gameplay dossier §5.5 asks for radial 6 m/s + upward 0.8 m/s.
   - Do: `radial_velocity_min/max` 5.5 / 6.5, `initial_velocity` 0.8, spread 10°. Stretch the ring
     to the car footprint: emitter basis = car yaw, scale x 1.2 / z 2.4.
   - Verify: rear-cam frames 0.15 s and 0.4 s after `Events.landed` show a low ring bursting
     outward past the wheels, next to `ref/video/keyframes/t140.jpg`.
7. **More than 2 cars get the full plume.**
   - `_tier_for()` gives full FX to the first two cars attached, and then to the player as well.
   - Probe: 2 NPCs, then the player, then 1 NPC → **3 rigs at tier 0**. Brief: max 2 (player + one).
   - Tier 2 is dead code: `_full_count` never reaches `MAX_FULL_FX + 2`.
   - Do: reserve one full slot for `Game.player`. When a full car detaches, promote the next car.
     Tier 2 = core only.
   - Verify: a test that attaches 3 NPCs and then the player, and asserts exactly 2 rigs at tier 0,
     one of them the player.
8. **Attach after detach raises an engine error.**
   - Error: `Signal 'tree_exiting' is already connected to given callable '…::_on_vehicle_gone'`.
   - Do: disconnect the signal in `_remove_rig()`, or check `is_connected` before connecting.
   - Verify: a test that does attach → detach → attach, then asserts `attached_count() == 1` and
     0 engine errors (test_host counts them).

## SHOULD-FIX
1. **Jet core polish.** Make the 4 bands read as diamonds, not uniform rings.
   - Multiply the ring term by `pow(facing, 3.0)` so the bands are brightest on the axis and fade
     at the silhouette.
   - Pinch the radius ~12 % at each diamond in `vertex()`.
   - Add streaky noise scrolling along UV.y (~10 m/s) after the 3rd diamond, so the cone does not
     look CG-smooth.
   - Raise energy from 1.05 to ~1.5 (brief).
2. **Static typing.** `rig: Node`, `fx: Node` and the demo's `_system: Node3D` are used with dynamic
   calls (`update_from_telemetry`, `set_target`, `get_value`, `attach`). Type them with the
   preloaded scripts (`var rig: ThrusterRig`). Use typed dictionaries
   (`Dictionary[int, ThrusterRig]`, `Dictionary[String, NozzleFX]`) and typed loop variables.
3. **Magic numbers in logic.** Turn these into named consts:

   | File | Literals |
   |---|---|
   | `nozzle_fx.gd::_apply` | 0.002, 0.55, 3.0 (call it THROAT_ENERGY_MAX) |
   | `thruster_rig.gd` | dot 0.5, 1.5 m ahead, 0.05, 0.25 m |
   | `ground_cloud.gd` | 0.12, the box extents |
   | `landing_puff.gd` | 0.18, 0.03, 0.4, 0.1 |
   | `thruster_system.gd` | `MAX_FULL_FX + 2` |

4. **Demo ground.** In photo 18 the floor reflects the cloud; the demo floor should too.
   - Add `asphalt_02_nor_gl.jpg` as the normal map.
   - Metallic 0.2 → 0.0.
   - Add a puddle roughness mask, 0.35 → 0.05 (ART §5).
   - Hide the 4.17 m tile repeat (uv1_scale 48 on 200 m) with macro variation.
5. **Demo boost.** Launch 0 → 27 m/s in 1 s instead of a constant 5.3 m/s crawl (photo 29 shows a
   12–13 m trail at t=1.00 s). Consider `inherit_velocity_ratio` ≈ 0.5 for the rear vapour, so the
   trail does not streak at 300 km/h.
6. **Small items.**
   - Ultra `particles` 1.3 is clamped to 1.0.
   - `_was_flying` entries are never erased.
   - Use a `Decal` node for the 0.25 s ground ring, so it projects onto kerbs and slopes.
7. **More tests.**
   - Ground-cloud trigger: lift nozzle 5 m up → emitting, 9 m up → not emitting.
   - Rear cloud off at 2.5 m altitude.
   - Crash landing → no puff.
   - `Events.flight_changed` true → false → puff.
   - Particle count scales with Settings.

## Verified OK
- **Check:** `tools/godot.sh check --only=res://fx/thrusters/` → `CHECK 14 files, 0 failed, 0 engine errors, 0 warnings`.
- **Tests:** `tools/godot.sh test res://fx/thrusters/tests/test_thrusters.gd` → 36 PASS lines,
  `TESTS PASS`. The tests are `extends Node`, as the project rule requires.
- **Ownership** (from `jobs/fx_thrusters/log.jsonl`): Write/Edit only touched `game/fx/thrusters/**`
  and `status/fx_thrusters.md`. `tmp/fx_thrusters` and `probe_api.gd` were cleaned up.
  `blender/car/thrusters.py` was written by car_model.
- **File sizes:** all ≤ 400 lines (largest: `demo/thruster_demo.gd`, 298).
- **Real glb:** 10 `Nozzle_*` empties whose positions and −Z directions match `NozzleTable` /
  dossier §5 (checked by parsing the glb). The demo uses it (lead note 5 OK).
- **Colours:** core #EAF4FF, throat #9FD8FF up to energy 3, 2 omni lights per car at #CFE3FF
  range 2 m, vapour #F2F6FA → #D8DEE6 with α 0.28 ≤ 0.35. No orange, fire or sparks.
- **Demo lighting** is cool-white key + cyan fill, and the plumes no longer read pink (lead note 1 OK).
- **Shock diamonds** are visible at 1.5 m and `compare_core.jpg` exists (lead note 3 OK).
- **Vapour** uses `local_coords = false` and `DRAW_ORDER_VIEW_DEPTH`.
- **Landing puff** is gated correctly: clean/wobble and impact > 4 m/s, plus sky-lane exit.

## Evidence
- Probe: `tools/godot.sh test /Users/minimax/m/skyrush/tmp/review/fx_thrusters/probe_fx.gd`
  - `PROBE stub fallback nozzles bad=10 of 10` (e.g. `Nozzle_R1 loc=(-0.36, -4.5, 2.085)`)
  - `PROBE full-tier particle capacity per car = 21600`
  - `PROBE full-FX rigs = 3 (brief: max 2 = player + one)`
  - `ERROR: Signal 'tree_exiting' is already connected …`
- Bench: `python3 tools/slots.py heavy 4 -- godot --path game --windowed --resolution 1920x1080 --always-on-top -s .../tmp/review/fx_thrusters/bench8.gd -- --h=1.6` (and `--h=6.0`)
  - `BENCH frame_ms on=235.93 off=73.34 … per_view=20.324 ms`
  - `BENCH frame_ms on=195.57 off=60.88 … per_view=16.836 ms`
- Textures (numpy over the PNGs):
  - `soft_puff.png`: border α max 0.125, mean |dα|/px 0.0025.
  - `ring_decal.png`: border α max 0.106.
  - Both `.import` files: `mipmaps/generate=false`.
- Captures, all in `captures/`:
  - Single shots: `review_fx_thrusters_r1_{hop_rear,hover_side,boost_overhead,core_rear_core_rear}_t2_5.jpg`
  - Cloud-growth strip: `review_fx_thrusters_r1_strip_t{2_0,2_5,3_0,4_0}.jpg`
  - Distance views: `review_fx_thrusters_r1_dist_{d5,d20,d100}.jpg`
  - Landing: `review_fx_thrusters_r1_land_t{8_4,9_0,9_3,9_9}.jpg`
  - Chase cam: `review_fx_thrusters_r1_chase_t{2_5,10_4,13_2}.jpg`
- Comparison sheets in `captures/review/fx_thrusters/`:
  - `sheet_18_27_s.jpg`: photos 18 / 27 vs mine
  - `sheet_29_core_s.jpg`: photo 29 vs mine, plus core close-ups
  - `strip_sheet_s.jpg`: mine vs video t=118–120
  - `dist_sheet_s.jpg`: 5 / 20 / 100 m
  - `land_sheet_s.jpg`: vs keyframes t140 / t150
  - `chase_sheet_s.jpg`
  - `crops_s.jpg`: ground-intersection lines and speckle
- Single-window fps from the captures: 35 at 5 m vs 116 at 20 m and 121 at 100 m. Other shots ran
  at 206–298 fps.
