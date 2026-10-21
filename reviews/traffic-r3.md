# traffic review round 3 — VERDICT: FAIL

Reviewer: strict reviewer / art director. All numbers measured by me on the current build (world.tscn
8 501 lanes; machine load 17–68 on 10 cores, so treat ms numbers as indicative). Scratch:
`tmp/review/traffic/diag3_*.gd|.log`, `r3_*.log`; images `captures/review/traffic/r3_*.jpg`.
Real progress since r2: brake lamps work (1.70×), the AI sees the player, MOBIL fires, the junction
lookahead and the lights work (0 deck lights, cars stop 3.0 m before a red line and go on green), v0
per road, dead ends never vanish in view, the deck ahead is populated (7–11 cars < 150 m), files split.
But the NEAR cars — the ones the player actually sees — float, fly off the deck and get wrecked by the
road itself, the mode switch still snaps cars in view, wrecks are a straight shove, the lamps glow
through the cabin, cars still interpenetrate at merges, the budget is still blown and two tests cannot
fail. Fix MUST-FIX 1–8 in order; split `traffic_car.gd` first (8e).

## Scores (0-10)
- function: **5** (r2: 4) — r2 #2/#3/#5/#6/#8/#11 fixed; NEAR physics, merges, jumps, perf open.
- visual/feel: **4** (r2: 3) — dense deck and readable brake lamps; floating/flying cars, spontaneous
  wrecks, 3° "crash", red bar through the glass, flat lens glow.
- code: **5** (r2: 4) — clean split, typed, documented; dead code, magic numbers, a 422-line test,
  a test that never runs its main check, status claims that did not happen.

## MUST-FIX

1. **NEAR cars float, fly off the deck and are wrecked by the road (new, top priority).**
   Wrong: `TrafficCarPhysics.integrate()` writes `Vector3(wanted.x, state.linear_velocity.y, wanted.z)`
   with the FLATTENED lane tangent and `gravity_scale = 0`: any vertical velocity (a depenetration, a
   shove) is kept for ever, grades are not followed, and only a fall > `FALL_LIMIT` 1.2 m BELOW the lane
   is corrected. `check_contacts()` treats the road deck / parapet like a car: on any grade the ground
   contact closes at ≥ 0.5 m/s → "nudge" `apply_central_impulse(normal * mass * 1.2)` (upward, again
   every 0.25 s) + `Events.vehicle_collided` with the ROAD as `other`; ≥ 6 m/s → `become_wreck()`.
   Measured (Yan'an deck chase, NEAR = within 60 m of the player, i.e. the cars on screen):
   - `diag3_height`: NEAR body − road surface (ray, layer 1): max **+2.93 m**, **79 of 450** samples
     off by > 0.15 m. FAR: 23 of 1 377, min −0.92 m (lane y lies up to 0.92 m under the collision
     surface in places → sunk FAR cars).
   - `diag3_height2`: lane 8254 `yanan_elevated` car 1.90 m above its lane rising at **vy +9.82 m/s**;
     lane 8253 2.56 m (vy +6.55); lane 5942 `ramp_l3_eb_nb` 2.61 m (vy +6.06); on lane 8257 (−0.5 %
     grade) a NEAR car drifts from 0.17 to 0.40 m above its lane in 44 m with vy 0.00; lane 5950
     `ramp_rt_sb_wb` (−2 %) 0.31–0.50 m above its lane.
   - `diag3_events` (40 s): **17** `vehicle_collided` from traffic against `roads_-4_1_concrete`,
     `roads_-3_1_surface`, `roads_-3_1_concrete`, `roads_-2_1_concrete`; **7 of 10** traffic wrecks had
     a road, not a vehicle, as source; 5 NEAR cars flew up at > 1 m/s (max 5.7).
   - `diag3_jump`: two cars on lanes 8253/8254 at s ≈ 932 popped up **0.51 m in one tick** at the
     FAR→NEAR switch and stayed up (dy 0.49–0.51 m).
   Do: (a) follow the lane in 3D: `wanted.y = slope(s) * speed + clampf((centre.y − pos.y) *
   VERTICAL_GAIN, −VERTICAL_MAX, VERTICAL_MAX)` (slope from the unflattened lane, gain ≈ 8 /s, cap
   ≈ 3 m/s); never carry the old `state.linear_velocity.y` for a non-wreck; hard-snap only beyond
   ±0.5 m. (b) `check_contacts()`: a collider that is not a `VehicleBase` and whose contact normal is
   within 45° of UP is ground — no impulse, no event, no wreck; against walls use the HORIZONTAL closing
   speed and never apply the 1.2 m/s shove to a static body. (c) FAR cars on the surface: at graph
   build cast one ray (layer 1) per LaneSampler point and store the lane→surface offset (or request
   the roads unit to put lane y on the collision surface — write it in status), print how many
   samples differ by > 0.10 m.
   Verify: a world.tscn test (deck + one ramp, 60 s chase): |body − road| ≤ 0.10 m for ≥ 99 % of
   NEAR and FAR samples within 150 m, max ≤ 0.25 m; 0 non-wreck cars with |vy| > 1 m/s; 0
   `vehicle_collided` with a non-vehicle `other` and 0 wrecks with a non-vehicle source while nobody
   touches the traffic. Print all four numbers.

2. **The FAR↔NEAR switch still snaps cars in view; `lane_error()` measures nothing.**
   Wrong: `_actual_lateral` is only written in `_place_on_lane()`, so in NEAR mode `lane_error()` =
   |lateral at the switch − S-curve lateral|, not the body's error. `TrafficModes` switches NEAR→FAR
   whenever that number is < `2.0` (magic) and `_place_on_lane()` teleports the body onto the lane;
   `check_stuck()` reads the same fake value. `_stop_at_dead_end()` returns before `_place_on_lane()`,
   so a dead-end body lags its clamped `s` and snaps at the next switch.
   Measured: test_lanes_world `FAIL sandbox.tscn: no car moves more than 0.3 m more than its own step
   (worst 0.70 m)` and `FAIL world.tscn: no car leaves its path by more than 1.0 m (worst 2.77 m)`;
   `diag3_run` (60 s deck chase): **206** steps > expected + 0.3 m within 150 m in
   view, worst step at a mode switch **47.2 m**; examples: NEAR cars 0.49–0.65 m in one tick where
   0.12–0.17 m was expected, FAR cars at 146–149 m 1.91–2.01 m per update where speed × dt = 0.60 m;
   `diag3_jump`: dead-end car on lane 8265 (v 0, s 12.00) snapped 0.37 m at 66 m.
   Do: store the body's real lateral/vertical error in `integrate()`; NEAR→FAR only when |lateral|
   < 0.15 m, |vertical| < 0.10 m and yaw error < 3° (stay NEAR up to 90 m otherwise) or blend the FAR
   transform from the body pose to the lane over 0.5 s; place the body in `_stop_at_dead_end()`; log
   lane / s / conn / mode for every jump the test finds and fix the FAR stepping cases.
   Verify: test_lanes_world jump check PASS on sandbox AND world (≤ 0.3 m over the step, printed with
   the worst car's lane and mode); a 60 s deck chase: 0 steps > step + 0.3 m within 150 m in view.

3. **Lamps: the tail bar glows through the cabin, the lens pattern is washed out, the reversing lens
   looks lit.** Brake itself now works — sandbox, 6 m behind, brake forced off vs on
   (`r3_lamp_cruise_t6_0.jpg` / `r3_lamp_brake_t6_0.jpg`, `r3_lamp_sheet.jpg` top row): lamp-crop
   luminance 1 177 k → 1 999 k (**1.70×**), red px 6 807 → 11 879, bloom on the brake blocks. Still wrong:
   (a) r2 #1 verify "no red through the glass" fails: `r3_lamp_front_t6_0.jpg` front 3/4 at 5 m shows a
   pink-red bar through the side windows (151 px, median #C8787F, x 620–780 y 375–410); the same on the
   city sedan and the 申城出租 taxi (`r3_front_crop.jpg`). The lens shells have inner faces and the body
   panels are one-sided, so `cull_mode = CULL_BACK` does not help.
   (b) `TrafficLampMaterials._lens()` sets `emission = tint` with `EMISSION_OP_ADD`: the constant tint
   (1.0, 0.10, 0.18) is ADDED to the atlas emission (`npc_trim.png` `lamp_red` strip: std 41.8, max 112
   → ≤ 0.16 linear), so the 50 %-duty LED strip of the model is flattened into one uniform glow — the
   bar reads as a neon tube, the unlit brake blocks as flat salmon rectangles. Reference
   `ref/art/img/cp04_nfs2015_wet_night.jpg` (`r3_lamp_sheet.jpg` bottom right): segmented lenses with
   hot cores and dark gaps.
   (c) The reversing lens (`REVERSE_FACTOR 0.02`) keeps its bright albedo (atlas `lamp` × (0.55, 0.60,
   0.68)) → two white patches under the brake blocks that read as lit reversing lamps.
   Do: (a) emit only on the faces that look out of the car: extend `traffic_lights.gdshader` (or a lens
   shader of your own) with `varying vec3 obj_n` = model-space NORMAL from `vertex()`, emission ×
   `smoothstep(0.2, 0.5, dot(obj_n, lamp_axis))` (lamp_axis +Z for `Lamp_R`, −Z for `Lamp_F` in the
   model space of the glb), inner faces drawn in the dark housing colour; (b) `EMISSION_OP_MULTIPLY`
   with the atlas as emission texture and the energy raised (×4–6) so the strip modulates the glow;
   (c) unlit lenses (brake off, reversing): albedo × 0.3, roughness 0.08, metallic 0.6 — clear glass
   over a chrome reflector, not a white sticker.
   Verify: front 3/4 at 5 m: 0 red px through the glass; rear crop at 4 m: luminance std inside the
   lit tail bar ≥ 20 % of its mean (the strip is visible) and the brake/cruise ratio still ≥ 1.6×;
   reversing lens mean luminance ≤ 0.5× the cruising tail bar. Hstack the crops with cp04.

4. **Wrecks in the city are a straight shove, not a crash.** `shot3b_wreck.log` + `r3_wreck_s2_3 …
   s5_5.jpg` (`r3_wreck_sheet.jpg`, fixed camera): Yan'an deck, 2 t box at +15 m/s closing, 0.6 m
   off-centre rear hit on the black sedan: yaw −90° → **−87° (3°)**, pitch 19° / roll −17° for 0.4 s
   then flat, speed **16.4 → 21.8 m/s** and a straight 3.0 s slide out of frame. test_wreck's 43° does
   not reproduce on the real road. `become_wreck()` still adds `direction * mass * closing * 0.35` of
   linear impulse (r2 #7: no extra linear momentum — and its own doc comment says "No extra momentum
   is added"), and 7 of 10 city wrecks were triggered by the road (item 1).
   Do: remove the linear impulse; build the kick from the HORIZONTAL lever arm: yaw rate =
   `UP.dot(lever_h.cross(push_h)) * WRECK_YAW_PER_SPEED * closing` (≈ 0.25 rad/s per m/s for a 1 m
   lever), roll about the car's forward axis for side hits; use the manifold point with the largest
   |lateral offset|, not the first one.
   Verify: test_wreck also on world.tscn (deck): rear-offset 15 m/s ram → yaw ≥ 30° within 1.5 s;
   side T-bone 15 m/s → roll ≥ 20° or yaw ≥ 45° (assert `ROLL_LIMIT`, see 7b); at rest ≤ 3 s; a
   4-frame strip from a fixed camera.

5. **Cars still drive through each other at merges and on ramps; a queue still freezes.**
   test_lanes_world (world): `FAIL … no two cars of a lane drive through each other (122, worst
   2.00 m)`, `FAIL … longest 20.1 s on the lane 6704`. My oriented-box probe (`diag3_run`/`_events`/
   `_height`, 40–60 s deck chases): 5–13 interpenetrations per run in front of the player, e.g. lane
   5942 `ramp_l3_eb_nb` two cars **0.18 m** apart (v 4.8 / 6.9 m/s); the `ramp_rt_sb_wb` connector
   (lane 5950) merging into `yanan_elevated` 8254/8255 at 1.90 m and 1.08 m — the merging car and
   the main-lane car never see each other. `_start_change()` also moves after the 1.0 s indicator
   lead without re-checking the target lane, and LaneHash ignores a car at the same `s`
   (`d > s + 0.01`).
   Do: merges — a connector/lane that joins a lane with traffic yields: look up the target lane around
   the entry point (−(v·T + length) … +length) and stop at the merge point (virtual leader) until the
   gap is clear, main lane has priority (zipper when both queue); re-run `_lane_clear()` when the
   indicator lead ends; break `s` ties in LaneHash by object id.
   Verify: test_lanes_world overlaps 0 and longest standstill ≤ 20 s on both worlds; the box probe
   reports 0 interpenetrations in a 60 s deck chase (I will re-run `diag3_run.gd`).

6. **Still over the §7.7 budget; first spawns of a model hitch.**
   Measured: test_lanes_world `PERF world.tscn: 0.668 ms per tick (median), 5.522 ms (p99)` and
   `PERF sandbox.tscn: 1.070 ms … 4.188 ms` (budget 0.5 / 2.0 ms per tick, load 28–40); my deck
   chases (tick + NEAR physics, raw): median 0.75–1.45 ms, **p10 0.41–0.59 ms**, p99 3.7–15.4 ms, max
   18.8–225 ms (load 17–57) — even the p10 is at or over the median budget. Single-tick part samples:
   index 0.17–0.20, cars 0.46–0.52, events 0.08, modes 0.05 ms. `diag3_spawn` (40 spawns, empty pool):
   median 0.40 ms but **max 27.8 ms** for the first car of a model; pool hit median 0.087 ms (OK).
   Do: (a) build one car per model (better: the whole 90-car pool in fleet proportions) while the
   world builds — no glb instantiate / `TrafficLampMaterials.set_for()` / `body_aabb()` after
   `world_ready`; (b) `TrafficPlayerEvents.update()` walks every car with two Dictionary ops per tick:
   keep the horn cooldown as a TrafficCar field and visit only the NEAR list TrafficModes already
   builds; (c) FAR cars beyond 120 m with no leader within 150 m: skip `plan_next()` and the IDM
   (cruise at v0); (d) wrecks are re-projected twice per tick (`_tick_wreck()` and `index_wreck()`,
   25 m window each) — once is enough; (e) print the load average with every PERF line.
   Verify: test_lanes_world PERF on world.tscn with 70 live cars: median ≤ 0.5 ms and p99 ≤ 2.0 ms
   per tick at load ≤ 10 — if the machine is busy, print p10 too and require p10 ≤ 0.25 ms; max tick
   after the prefill ≤ 4 ms; assert one pool spawn ≤ 0.1 ms (see 7c).

7. **Tests that cannot fail, checks that were never written, a test over 400 lines.**
   (a) `test_junctions._test_stop_at_a_red_light()` contains `await` but `_run()` calls it WITHOUT
   `await`: the coroutine returns at its first `await`, `_run()` prints `JUNCTION TESTS OK` and quits.
   My run printed 6 PASS lines and nothing about stopping — the red-light part never runs. (Behaviour
   is fine — `diag3_signal`: 3 cars stopped 3.03–3.04 m before the line on red and left on green —
   but the test must prove it.) (b) `test_wreck` measures `worst_roll` and never asserts `ROLL_LIMIT`.
   (c) `test_lanes_world` declares `SPAWN_BUDGET_MS` / `_spawn_costs` and measures no spawn. (d) the
   lane-change check is silently halved (`CHANGE_PER_MINUTE * _multi_minutes * 0.5`). (e) No test
   covers the brief's deliverable 5 (`near_miss` at ≤ 1.2 m and ≥ 60 km/h) or the horn.
   (f) `test_lanes_world.gd` is **422 lines** — split it (e.g. a `lanes_world_probe.gd` for sampling and
   report). (g) Status/result claim "test_junctions 8 PASS" and "a car stops in front of a red line and
   goes on when it turns green" — neither happened in the test.
   Verify: I re-run all tests: the junction test prints the stop distance (≤ 3.5 m) and the restart on
   green; roll, spawn cost and ≥ 1.0 change per car-minute are asserted; a near-miss test passes
   (1.0 m / 20 m/s → 1 event; 1.5 m → 0; 10 m/s → 0; horn at ≤ 1.5 m and ≥ 5 m/s).

8. **Code rules (CONTRACTS §3).**
   (a) Dead code — r2 #12b's `TrafficLamps.is_braking()` is still there; also `TrafficCar.
   BRAKE_OVERRIDE_ACCEL` (unused duplicate of TrafficCarDriving's), `TrafficCar.braking` and
   `TrafficCar.integrate_ms` (written, never read), `TrafficRing.KEEP_MIN`, `LaneGraph.
   NEIGHBOUR_SAMPLES`, `LaneHash.object_at()/distance_at()`, `LaneFollower.change_time_left()`,
   `LaneGrid.cell_count()`.
   (b) Magic numbers in logic: `25.0` (traffic_car.gd:400, traffic_index.gd:51), `6.0`
   (traffic_car_physics.gd:68), `0.35` (traffic_car_physics.gd:164), `0.05` (traffic_car_physics.gd:167),
   `2.0` (traffic_modes.gd:39).
   (c) r2 #12b half done: `LaneFollower.advance()` still drops the overshoot in the "lanes meet" branch
   (`s = entry` — must be `entry + (s − old_length)`) and when a connector starts (`connector_s = 0.0`).
   (d) The physics-material setup is duplicated in `_reset_physics()` and `_build_body()`; stale docs:
   the TrafficMaterials header ("energy is an instance uniform"), `TrafficIndex.insert_player()` ("not
   every tick" — it calls `grid.nearest_lane()` every tick while the player is off its lane),
   `become_wreck()` ("No extra momentum is added").
   (e) `traffic_car.gd` is exactly 400 lines: split it FIRST, as its own step (e.g.
   `traffic_car_modes.gd` for `set_mode/_place_on_lane/_tick_wreck/_stop_at_dead_end`), then do 1–2.
   Verify: `check --only=res://ai/traffic/,res://ai/common/` clean, every file ≤ 400 lines, a grep for
   each name above finds no dead symbol.

## SHOULD-FIX
- **class_name hygiene** (CONTRACTS §3: `class_name` only for contract classes and where the brief
  says so). Drop it from the helpers only LaneGraph uses — `LaneLinks`, `LaneNeighbours`,
  `LaneSampler` (preload them in `lane_graph.gd`). The world builder has its own
  `const LaneLinks := preload(...)`, and between 14:21 and 14:36 today world.tscn did not parse
  (`world_builder.gd:258 … argument 2 should be "LaneGraph" but is "res://world/api/lane_graph.gd"`)
  because the global `LaneGraph` won over the world's const. Keep `LaneGraph`/`LaneFollower`/
  `LaneGrid`/`DriveContext`/`IDM`/`AISteering`: police and rivals use them (`check --only=
  res://ai/police/,res://ai/rivals/` → 65 files, 0 failed) — do not rename those.
- **Slow ring fill**: after the director starts (and after every respawn) the city needs ~20 s to
  reach its population (`diag3_run`: 5 s 21 cars, 10 s 39, 15 s 51, 20 s 73); my chase shot
  `r3_chase_t10_0.jpg` (10 s in) shows an empty deck for ~150 m, unlike `sh06_ring_road_light_trails.jpg`
  / `sh05_yanan_elevated_blue_soffit.jpg` (`r3_chase_vs_ref.jpg`). `_spawn_missing()` `break`s on the
  first rejected spot — keep trying up to the per-tick budget.
- After a respawn (`TELEPORT_DISTANCE`) the prefill allows spawns in view for 8 s although no loading
  screen hides them: after a respawn only out-of-view spots ≥ 120 m.
- FAR cars beyond 120 m move at 30 Hz with physics interpolation off (0.6–0.8 m steps on the deck
  ahead): give cars inside the frustum < 200 m the 60 Hz cadence.
- Head-lamp pool: a `light_projector` texture (low-beam cut-off + hot spot) instead of a plain disc;
  the indicator cards are still flat amber quads with a UV fade — give them the atlas `lamp` pattern
  or drive an amber lens surface; check both at 4 m.
- `TrafficJunctions` reads `globalize_path("res://") + "../data/city/city.json"` — outside `res://`,
  so an exported build has no traffic lights; keep the `get_lane_junction` request and warn once.
- `revert_lane()` keeps the target lane's `s` on the old lane and does not bump `lane_serial` (no
  speed-limit refresh); `_on_race_started()` sets density 0.7 for ever (reset when the race ends).

## Verified OK
- `tools/godot.sh check --only=res://ai/traffic/,res://ai/common/` → `CHECK 41 files, 0 failed,
  0 engine errors, 0 warnings`.
- test_idm 23 PASS, test_paint 10, test_mobil 6, test_lamps 50 (all 8 models: tail, head, brake
  lens, brake ×6 / ×4 bus-van-truck, housing untouched), test_wreck 5, test_spawn_ring 8 (183.5–347.2 m,
  0 in view), test_junctions 6 (audit part only, see 7a); test_lanes_world 20 PASS / 8 FAIL.
- r2 #1 brake state readable (1.70× lamp luminance, bloom); r2 #2 `ctx.player` every tick ("the
  traffic sees the player" on both worlds); r2 #3 MOBIL: indicator 1.00 s before, start jump 0.21 m,
  3.95 changes per car-minute on multi-lane roads; r2 #5 280 lanes with a light, 0 on decks/ramps/
  above ground, `deck_light_stops 0` in all my chases, stop 3.03–3.04 m before the line, restart on
  green (`diag3_signal*.log`); r2 #6 v0 0 wrong; r2 #8 `vanish_view 0` in all 5 chases, loops ≥ 50 m;
  r2 #11 deck density after the fill: median 21–26 cars in view < 300 m, 7–11 ahead < 150 m on the
  player's level (r2: 5 / 2), spawns in view 44–67 per run but 0 closer than 120 m.
- Fleet mix incl. robotaxi, AABB-sized colliders, horn rate limit + `horn_requested` (the audio unit
  connects to it), `vehicle_collided` rate-limited per collider, pool hit 0.087 ms.
- Lead notes satisfied: all 8 tests `extends Node` and run through test_host, every run ended by
  itself (slowest test_junctions 65 s, test_lanes_world 95 s), `tmp/traffic/` is empty.
- Ownership: round-3 log (session e2b74c4e) — every Write/Edit and shell write inside
  `game/ai/traffic/**`, `game/ai/common/**`, `status/traffic.md`, `tmp/traffic/` (now empty).
  No /tmp backups this round.

## Evidence
All from `/Users/minimax/m/skyrush`; logs in `tmp/review/traffic/`.
- `r3_tests.sh` → `r3_check.log`, `r3_test_<name>.log`, `r3_tests_summary.log` (all exit 0 except
  test_lanes_world exit 1: `FAIL sandbox … worst 0.70 m`, `FAIL world … worst 2.77 m` (lane
  deviation), `FAIL world … (122, worst 2.00 m)`, `FAIL world … longest 20.1 s on the lane 6704`,
  PERF/p99 fails quoted in 6). test_junctions log ends `PASS the city has a lane that ends at a light`
  → `JUNCTION TESTS OK (0 failures)`.
- `tools/godot.sh test /Users/minimax/m/skyrush/tmp/review/traffic/<diag>.gd -- --timeout=290`
  (Game.player set before the director, stub player at 25 m/s on `yanan_elevated`, chase camera):
  `diag3_run` (COST, VIEW, RUN jump/overlap/vanish lines), `diag3_jump` (per-jump lane/s/dy dumps),
  `diag3_height` + `diag3_height2` (HEIGHT, LANE-GROUND, float lines), `diag3_events` (EVENTS
  `traffic_vs_static 17 … static_wrecks 7 … fly_cars 5`), `diag3_signal` + `diag3_signal2` (red
  lights), `diag3_spawn` (`SPAWN first build ms: min 0.34 median 0.40 max 27.78 | pool hit ms: …
  median 0.087`).
- Captures (`tools/godot.sh shot --scene=/Users/minimax/m/skyrush/tmp/review/traffic/
  review3_scene.tscn --mode=chase|close [--front] [--brakeat=0|1000] [--world=res://core/sandbox/
  sandbox.tscn]|wreck --snaps=…`): `captures/review/traffic/r3_lamp_cruise_t6_0.jpg`,
  `r3_lamp_brake_t6_0.jpg`, `r3_lamp_front_t6_0.jpg`, `review_traffic_r3_front_t5_0.jpg`,
  `r3_wreck_s2_3/2_6/3_0/3_6/5_5.jpg`, `r3_chase_t10_0.jpg`; sheets `r3_lamp_sheet.jpg` (vs cp04),
  `r3_front_crop.jpg`, `r3_wreck_sheet.jpg`, `r3_chase_vs_ref.jpg` (vs sh06/sh05), your shots in
  `r3_worker_sheet.jpg` (your "close" shot looks up at a car through a gantry from below — retake it
  at road level).
- Scratch scripts are the reviewer's: do not edit them; put your own tests in `game/ai/traffic/tests/`.
