# traffic review round 1 — VERDICT: FAIL

Reviewer: lead's art director / strict reviewer. Everything below was re-measured by me on the
CURRENT project (world.tscn now builds **1488 lanes**, not the 666 your status quotes). Scratch
diagnostics: `tmp/review/traffic/diag_*.gd`, logs `tmp/review/traffic/*.log`, captures
`captures/review/traffic/*.jpg`. Read MUST-FIX 1–16 in order; each one is mandatory.

## Scores (0-10)
- function: **3** — IDM maths, lane hash and the near miss work; junctions, lights, player
  reaction, horn, contacts, wrecks and the cap do not.
- visual/feel: **2** — every car is white, lamps are floating quads, braking shows no red light,
  cars hover (no contact shadow), wrecks glide upright on a frictionless road, the road ahead of
  the player is empty, cars teleport 100–378 m in view.
- code: **5** — clean file split, typed, documented; but the tests break the lead's rules and
  cannot fail, there is a per-tick O(all lanes) search, magic numbers, stale/false status claims.

## MUST-FIX

1. **Paint colour is never applied — all traffic is white `#E8E8E6`.**
   Wrong: `TrafficVisual._apply_colour()` compares `get_surface_override_material(i) ==
   TrafficMaterials.paint()`, but `MaterialLibrary._with_textures()` hands each glb a *duplicate*
   of `SH_car_paint_npc` (the glb paint has textures), so nothing matches; and it writes
   `"base_color"`, which in `res://shaders/car_paint.gdshader` is a PLAIN uniform — the
   per-instance uniform is `base_color_override` (vec4, used when alpha > 0).
   Measured (`diag_touch.gd`): sedan spawned `#0E0F11` and SUV `#1F3A5F` both report
   `base_color_override=<null>`, material `base_color=(0.91,0.91,0.90)`. Capture
   `review_traffic_r1_rear_t7_5.jpg`: the "black" sedan is white.
   Do: find the paint surfaces by shader (`(mat as ShaderMaterial).shader.resource_path.ends_with(
   "car_paint.gdshader")`) and call `mi.set_instance_shader_parameter(&"base_color_override",
   Color(c.r, c.g, c.b, 1.0))`; leave `SH_car_paint_taxi` (taxi teal) alone.
   Verify: a test spawns one car per palette colour (`e8e8e6 9da3a8 0e0f11 5a5f63 1f3a5f`) and
   asserts the override on every paint surface; a capture with ≥ 6 cars shows the mix.

2. **Lane-end continuations teleport cars hundreds of metres (visible).**
   Measured on world.tscn (`diag_graph.gd`): 13140 continuation links, **4994 jump > 15 m** from
   the lane end to the next lane's start, **346 change level (dy > 1 m)**, e.g. lane 0
   `yanan_elevated` → 39 `yanan_rd_surface`: 406.9 m, dy 9.6 m. `LaneFollower.advance()` always
   enters the next lane at `s = 0`. In a 40 s drive (`diag_run.gd`) **10 teleports of 100–378 m
   happened inside the camera frustum**, three of them NEAR cars 34–46 m from the player; worst
   body-to-lane deviation **25.4 m**. `_start_change()` also keeps `s` unchanged when it switches
   to a neighbour lane that starts elsewhere.
   Do: validate every link once in `LaneGraph._build_next()` — entry `s_j =
   closest_offset(j, end_i)`; keep the link only if the entry point is ≤ 20 m horizontally from
   `end_i`, |dy| ≤ 1.0 m and the heading change ≤ 100°; store `s_j` per link and enter there;
   cross the junction box on a cubic Hermite connector (end_i, tangent_i) → (entry_j, tangent_j)
   so cars turn instead of jumping/sliding. Re-project `s` on the target lane in
   `_start_change()`. Dead ends (134 lanes): stop at the end and despawn only when not visible.
   Verify: world test, 60 cars × 120 s at 4×: **0** frame-to-frame jumps > 2 m for any
   non-wreck car (print the worst), print dropped-link counts.

3. **Neighbour lanes across levels / garbage gaps.** `_build_neighbours()` buckets by x/z only
   and `_mean_offset()` pairs points by *proportional index*, not position. Measured: 65 of 2450
   neighbour pairs are on another level (lane 2 `yanan_elevated` ↔ 30 `yanan_rd_surface` dy 9.9 m;
   6 `ns_elevated` ↔ 434 `st_ns_03_04` dy 14.6 m); stored gaps range 0.1–39.2 m
   (`NEIGHBOUR_MAX_DISTANCE := 25.0`). A FAR car "changing lane" there drops 10 m through the deck.
   Do: a neighbour must have |dy| ≤ 1.0 m and a centre distance of 2.8–4.5 m measured at the
   car's own `s` via `closest_offset` when the change is decided (not a lane average); cell size
   6 m. Verify: the audit prints 0 cross-level pairs; a test asserts |dy| < 0.3 m between the
   start and end of every lane change on world.tscn.

4. **Red lights are ignored in the integrated game.** `_collect_junctions()` searches nodes named
   `Signals_<id>`; the current world batches its masts (`world/build/mast_batch.gd`) and has none:
   **0 / 1488 lanes resolve a junction** (`diag_graph.gd`), so `signal_state()` is never asked.
   Your status still claims "198 of 666".
   Do: stop depending on another unit's node names. Write the contract request in
   `status/traffic.md` → Requests with the exact signature (e.g. `WorldBase.get_lane_junction(
   lane: int) -> StringName`, data = city.json junctions `{id, x, z, roads, signals}` matched by
   `road_id` within 45 m of the lane end). Until it lands: `push_warning` once when 0 lanes
   resolve, and keep a world test that FAILS in that case.
   Verify: world test — ≥ 1 lane resolves, and a car approaching a red stops with its front
   bumper 0–3 m before the stop line and starts again on green.

5. **The player is never given to the AI: no reaction, no horn.** `ctx.player` is never assigned
   (only read at `traffic_car.gd:217`, `traffic_lane_change.gd:99`), so `_react_to_player()`
   (20 % move away / 10 % brake 2 m/s²) and `_check_horn()` always return early. Also
   `HORN_RADIUS 1.5` is compared with the *centre* distance (< 1.9 m means the bodies overlap).
   Measured (`diag_horn.gd`): passes at 1.0 m and 0.3 m side gap, +20 m/s → `horn_requested` = 0.
   And `near_miss_cooldown` only counts down while the car is within 12 m: the second pass
   (0.3 m gap, 2 s later) produced **no** near miss.
   Do: `ctx.player = _player` every tick; horn when the side gap (same maths as `_gap_to_car`)
   ≤ 1.5 m, once per car per 3 s, 0.6 s; decay the cooldown for every car every tick.
   Verify: scripted pass at 1.0 m → near_miss 1, horn 1; again at 0.3 m 2 s later → near_miss 1;
   100 cars approached at 20 m/s closing within 40 m → 15–25 % change lane, 5–15 % brake.

6. **Any touch by a dynamic body wrecks a traffic car.** `_check_contacts()` only filters
   *static* contacts below 6 m/s; every RigidBody contact goes to `_enter_wreck()` which sets
   `mode = WRECK` (AI off, deleted 8 s later). Measured (`diag_touch.gd`): a 1.5 t body closing at
   **2.0 m/s** → NEAR → WRECK. Every nudge from the player, police, debris or another traffic car
   kills the car — dossier §6.1 says WRECK only at a closing speed ≥ 6 m/s.
   Do: wreck only when `v_n ≥ WRECK_SPEED` for any collider; below it emit
   `vehicle_collided`, apply the shove and stay NEAR (lateral control recovers).
   Verify: test — 2 m/s touch: still NEAR and within 0.5 m of its lane after 3 s; 8 m/s: WRECK.

7. **Wrecks glide upright on ice, cause pile-ups, and vanish in view.**
   (a) The real contact path `_enter_wreck()` never calls `set_mode(WRECK)`, so `linear_damp`
   stays 0.0, `angular_damp` 0.5 and the physics material friction stays **0.0**. Measured
   (`wreck_dbg.gd`, 2 t body at +15 m/s): the hit car speeds up 19.7 → 23.2 m/s and is still
   doing 18.4 m/s 1.5 s later, upright; captures `review_traffic_r1_wreck_t2_3/2_7/3_4/5_0.jpg`
   show no yaw, roll or stop. (b) `_rebuild_index()` drops wrecks from the lane hash, so the
   car behind does not brake: NEAR follower hit the wreck at 12.6 m/s and became a wreck; a FAR
   follower drove *through* it (centre distance 3.04 m < 4.4 m). (c) `despawn = true` removes a
   wreck after 8 s even on screen.
   Do: one `_become_wreck(point, impulse)` for both paths: friction 0.9, bounce 0.15,
   linear_damp 0.3, angular_damp 0.6, CCD on, impulse applied at the contact point ≥ 0.5 m off
   the COM so the car yaws/rolls; keep wrecks in the hash as stopped obstacles (speed 0) so IDM
   brakes and MOBIL steers around; remove only after ≥ 8 s AND 2 s out of view AND > 60 m away.
   Verify: 4-frame capture strip over 2 s of a 15 m/s ram: yaw ≥ 45°, at rest within 3 s; test:
   the follower stops ≥ 2 m behind a wreck, then passes it in the next lane.

8. **Leader speed is wrong behind FAR cars.** `_update_speed()` (traffic_car.gd:196) and
   `TrafficLaneChange` (:134, :145) read `lead.get_speed_kmh()` = `linear_velocity`. A frozen
   kinematic body moved by transform reports 0 (or 2× on the moved tick beyond 200 m). Measured:
   **6424 / 16449** FAR samples report < 1 km/h while `speed` > 5 m/s. Followers brake for a
   "stopped" leader → accordion queues and false MOBIL gains.
   Do: for a `TrafficCar` leader use its lane `speed`; for any other `VehicleBase` (player,
   police) use `linear_velocity.dot(lane tangent)`.
   Verify: platoon test on world lanes, all FAR: steady flow, no car below −1 m/s², every
   follower within 10 % of its leader's speed after 20 s.

9. **Performance is far over budget.** Measured on world.tscn, 70 cars, ≥ 10 NEAR, minimum of
   300 batches of 10 ticks (`diag_perf.gd`; machine load 35–45, so treat absolute ms as up to
   ~1.5× high — the algorithmic problems are load-independent):
   - player > 4 m from its last lane (flying, hopping, sidewalk, junction box, gas station):
     `_insert_player()` calls `LaneGraph.nearest_lane()` = 1487 lanes × 256 samples **every
     tick** → **11.0 ms per tick = 22 ms per frame**;
   - player on its lane: 0.78 ms per tick = **1.56 ms per frame** (budget §7.7: 1.0 ms incl. the
     NEAR `_integrate_forces`, which your measurement leaves out);
   - `_refresh_population()` walks every lane at 20 m steps every 2 s: **25–150 ms** single-frame
     hitch (150.5 / 37.6 / 25.5 ms in three runs) = a visible stutter every 2 s.
   Do: a static grid (≈ 50 m cells) of lane samples built once; `nearest_lane` and the ring scan
   only visit cells within 420 m; when the player is off-lane keep the last lane and re-search
   at most every 0.25 s; time-slice the ring scan (≤ 0.2 ms per tick); cache per-lane constants.
   Verify: perf test with exactly 70 cars, ≥ 10 NEAR, player on- and off-lane: total traffic
   cost (tick + physics delta) ≤ 1.0 ms per 60 fps frame and no single tick > 2.0 ms incl. the
   ring — enforced, no load-based skipping.

10. **Hard cap 90 is not hard.** `_target_count = clampi(..., int(HARD_CAP * scale))` with
    `Settings.feature("traffic")` = 1.25 on ultra → measured **112 cars** alive (two runs).
    Do: clamp to `HARD_CAP` after scaling. Verify: test with `--quality=ultra` → peak ≤ 90.

11. **The road ahead of the player is empty.** The spawn rule "outside the frustum" rejects the
    whole ring in front of the camera, so cars only appear beside/behind. Measured (`diag_run`,
    player at 22 m/s on the Bund): **0–3 cars in view within 300 m for the first 28 s while
    112 were alive**. Game capture `review_traffic_r1_game_t4_0.jpg`: 169 km/h on the 6-lane
    Bund road, not one tail light ahead — compare `ref/art/img/sh06_ring_road_light_trails.jpg`
    (dense red trails) in `captures/review/traffic/game_vs_ref.jpg`.
    Do: prefill the full ring (25–350 m) on the first frame / behind the loading screen and after
    respawn/teleport; for later spawns ahead allow points > 300 m whose line of sight to the camera
    is blocked (raycast) or behind a bend/crest; keep 70 % of new cars on the player's road
    direction. Re-check `_in_view()` at spawn time (candidates are up to 2 s old; 1 spawn in view
    was measured). Verify: 60 s at 22 m/s on `yanan_elevated` → median ≥ 6 cars in view
    < 300 m and ≥ 2 in the player's direction < 150 m; deck capture at night with ≥ 6 cars.

12. **Lamps are floating quads; braking shows no red light.** `TrafficVisual._add_lamps()` puts 8
    additive quads at bounding-box guesses while the glb has real `Lamp_F` / `Lamp_R` meshes
    (`NPC_lamp_front` / `NPC_lamp_rear`) and markers `Light_Front` / `Light_Rear` (sedan
    y 0.61, z ∓2.305). Close captures (`captures/review/traffic/lamps_sheet.jpg`):
    `review_traffic_r1_rear_t7_5.jpg` (car braking to 1 m/s) shows a white bar and two white
    rectangles and **no red brake light** — the red quads sit inside the body; the front 3/4
    (`review_traffic_r1_front_t5_0.jpg`) shows a glowing strip floating outside the right corner.
    Do: delete the quads; drive the glb's `Lamp_R`/`Lamp_F` with one shared lamp ShaderMaterial
    per kind + `instance uniform float energy`: tail red `#FF1A2E` energy ≈ 0.8, brake ×4, keep
    G,B ≤ 8 % of R so AgX does not wash it to white (target the `#B23719` trails of sh06);
    head `#F4F7FF`; amber `#FFB000` indicator cards placed on the body surface at lamp height
    (from the mesh AABB, 2 cm proud, never outside the silhouette); one soft additive halo
    billboard per rear lamp for braking bloom. Verify: 5 m rear captures cruise vs braking —
    the brake state must read unmistakably red; nothing glows outside the body outline.

13. **Cars hover: no contact shadow, head-lamp hot spot under the bumper.** The night lights are
    shadowless, so nothing grounds the cars; the head-lamp `SpotLight3D` (0.55 m high, −9°,
    44°, range 24 m) paints a white blob right under the front bumper
    (`review_traffic_r1_front_t5_0.jpg`, `review_traffic_r1_demo_t12_0.jpg`). Numerically the
    tyres touch (gap 0.002 m) — it is a lighting/grounding defect, not a height one.
    Do: a per-car blob-shadow `Decal` (soft radial texture, 1.15× the footprint, alpha ≈ 0.6,
    hidden while a wreck is airborne); aim the spot from `Light_Front`, pitch −3°, range 35 m,
    attenuation so the pool starts ~4 m ahead (low beam), energy so it does not clip.
    Verify: front 3/4 capture at 6 m — tyres visibly planted, no hot spot at the bumper.

14. **Tests break the lead's rules and cannot fail.** All three tests `extends SceneTree`
    (lead note: tests must `extends Node` via `tools/godot.sh test`). `test_lanes_world.gd` runs
    only the 2-lane sandbox although `res://world/world.tscn` exists (brief: run on both); its
    lane check uses the car's own `lane_error()`, which is identically 0 for FAR cars
    (`_place_on_lane()` writes `_actual_lateral = follower.lateral`) and skips lane-changing cars
    → "worst 0.00 m"; "no errors" is in the doc comment but never checked (my re-run printed
    `SHADER ERROR` and still said OK); "falls through" only checks final positions; perf uses
    60 cars (brief: 70) and skips the budget when the machine is busy (it printed 1.026 ms/frame
    and passed). Do: convert to `extends Node`; run sandbox AND world.tscn; geometric deviation
    every tick (body → closest point of its lane, horizontal + vertical; during a change compare
    with the S-curve target); jump detector (> 2 m per tick); count engine errors from
    `res://ai/` and fail on any; 70 cars; enforce the budget (print the load, never skip).
    Verify: the reviewer re-runs the tests and sees all of the above as PASS/FAIL lines.

15. **Required captures are missing.** No capture on the sandbox loop; no player-view capture of
    traffic on the Yan'an elevated deck at night (`traffic_top_t14_0.jpg` is an overhead with dots,
    `traffic_chase_t26_0.jpg` is under a deck); `traffic_t24_0.jpg` shows two cars standing on a
    paved forecourt beside buildings — explain or fix. The demo teleports a frozen kinematic
    "player" into the lane every frame (it rams cars), so its shots are not representative.
    Do: (a) sandbox loop; (b) `yanan_elevated` at night from the chase camera at ≥ 100 km/h with
    ≥ 6 cars in frame; (c) 5 m rear cruise vs braking; (d) wreck strip; put (b) side by side with
    `ref/art/img/sh06_ring_road_light_trails.jpg` and `sh05_yanan_elevated_blue_soffit.jpg`
    (ffmpeg hstack) and say what still differs. Use a real `player_car.tscn` on autodrive.

16. **Code rules and hygiene.** (a) Magic numbers in logic — name them: traffic_car.gd
    `200.0`, `45.0`, `< 2` (signal state: add `SIGNAL_RED/AMBER/GREEN`), `-0.4`, `1.2`, `0.7`,
    `25.0`, `6.0`, `±2.5/±1.5`, `1.2` impulse; traffic_director.gd `4.0`, `60.0`, `2.0`, `7.0`,
    `1.0`, `0.75`; traffic_lane_change.gd `70.0`; traffic_lamps.gd `0.6`, `-9.0`,
    `Color("fff0d2")`. (b) Type the loop variables (`for dir: int in [-1, 1]`, 7 places).
    (c) `traffic_director.gd` is 392 lines: split it BEFORE these fixes (ring/population →
    `traffic_ring.gd`, junction lookup → `traffic_junctions.gd`, near miss + horn →
    `traffic_player_events.gd`). (d) You left `/tmp/dir_backup.gd` and
    `/tmp/traffic_director_backup.gd` — scratch belongs in `tmp/traffic/` and must be deleted.
    (e) Correct `status/traffic.md`: the horn, the player reaction, the red-light stops and the
    0.97 ms claim are not true on the current build.

## SHOULD-FIX
- Head-lamp spot lights: up to one per NEAR car within 46 m (10–15 lights). ART.md §4 budget is
  ≤ 48 lights near the camera and the world already pools 44 — cap the traffic at the 4 nearest
  cars in front of the camera, pooled.
- Indicators blink in global sync (`fmod(ctx.time, 0.8)`): give each car a phase offset; 1.5 Hz.
- Brake lamps: add hysteresis (on below −0.6 m/s², off above −0.2) and a 0.3 s hold.
- `ctx.density_scale` is never set: apply 0.7 on races/pursuits yourself
  (`Events.race_started`, `Events.pursuit_state_changed`). Join group `traffic_director` (the demo
  looks for it; nothing adds it).
- `lane_hash`/`lane_follower`: document in `ai/common/README.md` the new connector + entry-s API
  so police and rivals do not re-introduce the teleports.

## Verified OK
- `tools/godot.sh check --only=res://ai/traffic/,res://ai/common/` → `CHECK 23 files, 0 failed,
  0 engine errors, 0 warnings`.
- IDM / MOBIL / LaneHash maths: `test_idm` all PASS (free accel 2.00, emergency cap, s0 gap,
  platoon spread 4.83 → 0.00, hash leader/follower/gap). Game values match dossier §6.1.
- Near miss fires for a 1.0 m side gap at +20 m/s (`diag_horn.gd`: `near_miss=1`).
- Ring distances in `test_spawn_ring`: 181.8–348.1 m, despawn works (6 removed); no wreck or
  removal in view in my 60 s run (`pop_view 0`).
- `TrafficCar` extends `VehicleBase`, team TRAFFIC, groups `traffic` + `vehicles`, emits
  `vehicle_collided`; FAR→NEAR sets the velocity first; NEAR keeps `axis_lock_angular_x/z`.
- The 7 npc glbs are used; type mix 5 % taxi / 8 % van / 4 % bus+truck is coded correctly.
- Ownership: every Write/Edit in `jobs/traffic/log.jsonl` is inside `game/ai/traffic/**`,
  `game/ai/common/**`, `status/traffic.md`, `tmp/traffic/` (deleted) — except the two `/tmp`
  backups (MUST-FIX 16d). All files ≤ 400 lines (max 392).
- Not traffic's fault (reported to the lead, no action for you): `glass_tinted.gdshader:29`
  uses `maxf` (shader error in every traffic run), world `mast_batch.gd` `INSTANCE_CUSTOM`
  error, world `route_builder` `looking_at` error, a flat green column on the Yan'an deck.

## Evidence
Commands (from `/Users/minimax/m/skyrush`; machine load average 22–45 on 10 cores):
- `tools/godot.sh test res://ai/traffic/tests/test_lanes_world.gd` → `PASS the world has lanes
  (2)` (sandbox only), `worst 0.00 m`, `TRAFFIC PERF 60 cars: 0.513 ms per tick (1.026 ms per
  60 fps frame)`, `the budget check is skipped`, `SHADER ERROR … maxf` yet `OK`.
- `tools/godot.sh test res://ai/traffic/tests/test_spawn_ring.gd` → 8 PASS, peak 40 cars.
- `tools/godot.sh test /Users/minimax/m/skyrush/tmp/review/traffic/diag_graph.gd` →
  `[world] built in 12.29 s (1488 lanes)`, `NEIGHBOURS pairs=2450 other_level(dy>1.5m)=65`,
  `NEXT links=13140 jump<=1m=8067 1-5m=22 5-15m=57 >15m=4994 vertical(dy>1m)=346 dead_ends=134`,
  `JUNCTIONS lanes ending at a resolved junction: 0 / 1488`.
- `… diag_run.gd` (player kinematic at 22 m/s on `bund_zhongshan_e1`, camera behind it):
  run 1 (60 s) `POPULATION refresh 150.5 ms`, `teleport_view 2` (95.0 m, 8.1 m), `far_v_zero
  10529 / 25994`, `cars=112`; run 2 (40 s) `teleport_view 10` (261.2, 199.9, 200.0, 261.1,
  104.7, 103.4, 377.8 … m; three NEAR at 34–46 m), `worst_dev 25.37 m`, `far_v_zero 6424 /
  16449`, visible cars in view < 300 m `0–3` per second for the first 28 s, `cars=112`.
- `… diag_perf.gd` (70 cars, 10 NEAR): `A tick(): min 11.040 ms` (player 6 m off its lane),
  `A2 tick() player on lane: min 0.780 ms … 1.561 ms per 60fps frame`, `C _refresh_population():
  min 37.6 ms`.
- `… diag_touch.gd`: `PAINT sedan black … base_color_override=<null> … material base_color=
  (0.9098, 0.9098, 0.902)`, same for the blue SUV; `FLOAT NEAR … gap 0.002 m`; `TOUCH before:
  mode 1 … closing at 2.0 m/s` → `TOUCH after 1 s: mode 2`.
- `… diag_horn.gd`: `PASS-BY side gap 1.0 m … horn_requested=0 near_miss=1`, `gap 0.3 m …
  horn_requested=0 near_miss=0`, `WRECK-IN-LANE (NEAR follower) … follower mode 2 speed 12.6`,
  `(FAR follower): closest centre distance 3.04 m … follower mode 0`.
- `… wreck_dbg.gd --mode=wreck`: car `mode 1 v 19.7` → hit at t 2.41 `mode 2 v 23.2` → t 3.91
  `v 18.4`, height unchanged (no tumble).
- Captures (all in `captures/review/traffic/`): `worker_sheet.jpg` (your 5 shots),
  `demo_sheet.jpg` (`review_traffic_r1_demo_t12_0/t22_0`: all cars white, hovering look),
  `close_sheet.jpg`, `lamps_sheet.jpg` (`review_traffic_r1_rear_t5_0`, `rear_t7_5` braking =
  no red, `front_t5_0` floating strip + bumper hot spot), `wreck_sheet.jpg`
  (`review_traffic_r1_wreck_t2_3/2_7/3_4/5_0`), `game_vs_ref.jpg` (`review_traffic_r1_game_t4_0
  /t7_0` vs `sh06`, `sh05`).
- Reproduce any of it: `tools/godot.sh test /Users/minimax/m/skyrush/tmp/review/traffic/<diag>.gd
  -- --timeout=280` (scratch scripts are the reviewer's; do not edit them, write your own tests
  under `game/ai/traffic/tests/`).
