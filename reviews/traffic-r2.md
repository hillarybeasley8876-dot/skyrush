# traffic review round 2 — VERDICT: FAIL

Reviewer: strict reviewer / art director. Every number below was measured by me on the current
project (world.tscn builds 8 845–9 119 lanes, the count changes between builds; machine load 14–50
on 10 cores). Scratch: `tmp/review/traffic/diag2_*.gd` + `*.log`; captures and sheets:
`captures/review/traffic/review_traffic_r2_*.jpg`, `r2_*_sheet_v.jpg`. Real progress since r1:
paint colours, 0 cross-level neighbours, junction connectors (0 teleports in 50 s), wreck friction,
hard cap, sliced ring, Node tests. But in the real city the traffic still does not work: up to 41 %
of the cars end up standing still, cars drive through each other, nobody overtakes, the player is
never seen by the AI, the brake lamps never light, deck cars stop at street lights in mid-air, and
the tick costs 2–3× its budget. Fix MUST-FIX 1–12 in order.

Note: right now the world skips all 198 road tiles ("not imported yet" — a world/roads problem, not
yours), so my deck captures have no deck mesh; my close-ups were taken on `bund_zhongshan_e1`.

## Scores (0-10)
- function: **4** (r1: 3) — IDM, paint, connectors, contacts, cap work; MOBIL, player reaction,
  leader lookup across lane ends, signals, wreck indexing, budget do not.
- visual/feel: **3** (r1: 2) — colours right now; lamps are flat untextured stickers with no brake
  state, the road ahead is nearly empty, queues freeze on the ramps, wrecks barely turn.
- code: **4** (r1: 5) — split director and typing are good; two files > 400 lines, dead code,
  tests that cannot fail or measure the wrong thing, status claims that are not true.

## MUST-FIX

1. **Brake lamps never light; the lamps are flat untextured stickers.**
   Wrong: `TrafficLamps._with_prefix()` only walks the DIRECT children of `Visual`, but the glb lamps
   live at `Visual/sedan_ev2/sedan_ev/Lamp_R`. Probe `diag2_lamps.log`: `LAMPS found: head 0 tail 0
   ind_l 2 ind_r 2`; after 0.5 s of `brake_override`: `braking=true … energy after 0.5 s brake: 0.8`.
   6 m rear captures cruise `review_traffic_r2_rear_t5_0.jpg` vs braking `…_t8_5.jpg`, 400×120 lamp
   crop: red px 1967 vs 1976, mean R 190.6 vs 190.4 — identical. Also `_setup_lamps()` puts ONE
   `material_override` on the whole mesh: `Lamp_R` has 3 surfaces (`NPC_lamp_rear`, `NPC_lamp_brake`,
   `NPC_lamp_front` = reversing lamp) → all one red; `Lamp_F` has `NPC_lamp_front` + `NPC_gloss_black`
   → the black housing glows white (flecks at the bumper corners, `r2_lamp_crops_v.jpg`).
   `traffic_lights.gdshader` samples no texture (the lens detail of the npc `npc_trim` atlas is
   lost), fades alpha by the atlas UVs (meaningless on a real mesh) and is `blend_add` +
   `cull_disabled`: the back faces of the red rear bar shine through the cabin glass in the front
   3/4 view (`review_traffic_r2_front_t5_0.jpg`). `r2_vs_ref_v.jpg` top: our rear = flat orange-red
   rectangles (brightest pixel #E76251), `cp04_nfs2015_wet_night.jpg` = structured lenses, hot cores,
   bloom, reflection on the wet road.
   Do: (a) find lamps recursively: `visual.find_children("Lamp_*", "MeshInstance3D", true, false)`;
   (b) work per SURFACE by material name with `set_surface_override_material(i, …)`:
   `NPC_lamp_rear` → tail, `NPC_lamp_brake` → brake, `NPC_lamp_front` on `Lamp_R` → reversing lens
   unlit, `NPC_lamp_front` on `Lamp_F` → head, `NPC_gloss_black`/others untouched; (c) keep the
   textures: shared duplicates of the glb's own lamp StandardMaterial3D per state (brake surface
   "off" ≈ 0.25× and "on" ≈ 1.5× the imported `emission_energy_multiplier` — ≥ 4× apart —, tail 1×,
   reversing lens 0.02×) swapped on the surface only when the state changes — no instance uniform
   (your status says the city's instance buffer is full); tint the emission to tail/brake
   `#FF1A2E`, head `#F4F7FF`, indicator `#FFB000` only where the lens texture is neutral; opaque,
   back-face culled; let the environment glow (threshold 1.1) bloom the brake state.
   Verify: a test spawns all 7 models and asserts ≥ 1 tail, ≥ 1 brake and ≥ 1 head surface found and
   that braking switches the brake surfaces to the "on" material (≥ 4× the "off" energy); captures
   at 6 m rear cruise vs brake: in the 400×120 lamp crop the brake frame's lamp luminance ≥ 1.6× the
   cruise frame and visible bloom; front 3/4 at 6 m: housing dark, no red through the glass, lens
   texture readable.

2. **The AI never sees the player in the game's start order.** `_physics_process` sets `ctx.player`
   only `if _player != Game.player`, and `_refresh_world()` assigns `_player = Game.player` without
   touching `ctx.player`. `main.gd` ORDER creates `player_car` before `traffic`, so in the real game
   `ctx.player` stays null forever: `diag2_logic.log` (Game.player set before `add_child(director)`) →
   `CTX player set: false` after 20 s. `_react_to_player()` returns early → no car ever moves away
   or brakes for the player (r1 #5; your result says "assigned every tick" — it is not).
   Do: `ctx.player = _player` unconditionally every tick after the validity check, and in
   `_refresh_world()`.
   Verify: test with Game.player set BEFORE the director exists: `ctx.player` non-null after 2
   ticks; 100 cars approached from behind at 20 m/s closing within 40 m → 15–25 % change lane,
   5–15 % brake (print both).

3. **MOBIL never fires; the lane-change geometry is still the r1 one.**
   Wrong: `TrafficLaneChange.update()` calls `_accel_in_lane(ctx, follower, speed, desired_speed,
   car_length)` for the current lane AND for the candidate with identical arguments → gain always 0
   → `IDM.should_change_lane()` never true. Sandbox (`diag2_logic`): sedan v0 25 m/s behind a van at
   4 m/s, lane 1 free 7.6 m to the left, 20 s → `changed lane false, indicator false, speed 4.0`;
   city (`diag2_run`): 90 cars × 50 s → `changes 0`. Still open from r1 #2/#3: `_start_change()`
   keeps `s` when it switches lanes, and the gap is the lane average `left_gap/right_gap` from
   `_mean_offset()` (pairs points by proportional index) — `LaneGraph.neighbour_gap()` exists but
   nothing calls it. City audit (`diag2_graph`): of 16 744 neighbour pairs 13 843 have an along-road
   `s` mismatch > 5 m (worst 1 096 m — that is how far a car will jump once MOBIL works); stored
   gaps like 0.8 m (`bund_north` 0 → 139) or a cross street as neighbour (0 → 136 `st_d0_ns_3`).
   Do: `_accel_in_lane(ctx, lane, s_on_lane, …)` evaluated on the TARGET lane with
   `s_t = graph.closest_offset_near(target, position, s, 30.0)`; use `s_t` in `_lane_clear()`,
   `_follower_brake()` and set `follower.s = s_t` in `_start_change()`; gap =
   `graph.neighbour_gap(lane, target, s)`, accept only 2.8–4.5 m with |dy| ≤ 0.3 m at the car and a
   heading within 15°; pass that gap to `start_change()`.
   Verify: sandbox fast-behind-slow test changes lane within 6 s, indicator on ≥ 1.0 s before; world
   test 70 cars × 120 s: ≥ 1 change per car-minute on multi-lane roads; per change the body jump at
   the start < 0.3 m and |dy| < 0.3 m (print counts and the worst).

4. **Leader lookup is blind across lane ends → cars drive through each other and deadlock.**
   A car on a connector keeps the `s` it had when it left its lane (`advance()` only grows
   `connector_s`), so all cars on one connector sit at ≈ lane length in the hash in arbitrary order,
   and a leader that already entered the next lane is invisible (`leader_entry(lane, s)` searches the
   own lane only). `diag2_flow` (90 cars, 35 s): 647 samples of two non-wreck cars < 2.5 m apart
   (387 on different lanes), e.g. two cars on lane 8818 at s 36.2/36.3, gap −4.8 m; deadlock on lane
   6450 (`conn true`, gaps −4.8/−3.9 m, 0 m/s) with the queue behind on lane 917 `ramp_xizang_off`
   (gaps −2.2…−3.6 m, 0 m/s). `diag2_perf`: cars at 0 m/s on elevated lanes 20 → 32 of 90 (load 48)
   and 13 → 37 of 90 (load 14) after 20 / 40 s — the jam only grows.
   Do: index a connector car at `lane_length(from) + connector_s` on its old lane AND at
   `entry − (connector_length − connector_s)` on the target lane; choose the next lane when the car
   is ≤ 100 m from the lane end (keep the choice) and continue the leader search onto it, adding the
   remaining distance; never feed a negative gap to the IDM (an overlap = hold the REAR car only).
   Verify: world test 70 cars × 120 s at 4×: 0 pairs of non-wreck cars closer than 0.8 × the shorter
   car length; no car at 0 m/s for > 20 s on a green or signal-less lane (print the longest).

5. **Phantom traffic lights on the expressway; cars freeze inside the junction.**
   `TrafficJunctions` gives a junction to 9 063 of 9 112 lanes (`diag2_graph`) and to 268 of the 271
   deck lanes higher than 6 m — 103 of them red/amber at one instant (`diag2_signals`), e.g. lane 1
   `yanan_elevated` end (−631, 9.3, 215) → `j_ramp_xizang_on_yanan_elevated` RED; lane 635
   `ns_elevated` end y 20.2 → `j_ns_elevated_st_d3b_ew_14` (a street under the deck). city.json lists
   `yanan_elevated` in 77 junctions (plan-view crossings) and the 45 m match ignores height. Seen:
   `diag2_flow` yanan_elevated lane 8821 car at s 50.2/53.9, no leader, 0 m/s. The light is also
   tested when `to_end < 0` (past the line / on the connector) → red inside the box gives a negative
   stop gap and the car freezes there; amber always stops, even 1 m before the line.
   Do: a lane gets a light only if `LanePath.elevated == false`, its road is a surface street (no
   ramp), its end y < 2 m and it ends ≤ 20 m (2D) from a `signals: true` junction of its own road;
   skip the light when `to_end < 0` or `follower.on_connector()`; on amber stop only if
   `v² / (2 · IDM.B_COMF) < to_end`. Keep the `get_lane_junction` request in status.
   Verify: the audit prints 0 elevated/ramp lanes with a light; world test: a surface car stops with
   its front bumper 0–3 m before a red line and starts on green; 0 elevated cars stopped at a light
   during the long run.

6. **Desired speed is never updated when a car changes road.** `desired_speed` is set once in
   `setup()` from the spawn lane. `diag2_flow`: a car on `yanan_elevated` (80 km/h) with v0 12.0 m/s
   and cars on 40 km/h ramps with v0 22–24 m/s → 43 km/h blockers on the expressway that nobody can
   overtake (see 3), speeders on the ramps.
   Do: keep the driver factor U(0.9, 1.1) as a field; on every lane entry (continuation or lane
   change) set `desired_speed = limit(lane) × factor`.
   Verify: test asserts |v0 − limit × factor| < 0.1 m/s after every lane entry (70 cars × 60 s).

7. **Wrecks: stale lane state, wrong impulse, barely any tumble.**
   (a) `_tick_wreck()` never re-projects `follower.s` and `speed` keeps its pre-crash value, so the
   hash shows the wreck where it was hit, still "moving" at e.g. 12 m/s → followers do not brake for
   the real body (r1 #7b only half done). (b) `_become_wreck()` applies the impulse at
   `lever = (point − origin) × normal` — a cross product used as a POSITION (must be the contact
   offset `point − origin`) —, adds 0.5·m·closing on top of the solver's own response (12.0 →
   18.5 m/s after my 15 m/s ram) and then OVERWRITES `angular_velocity` with random ±2.5 rad/s.
   Result (`shot2_wreck.log`, 2 t box at +15 m/s, 0.6 m offset): yaw −162° → −155° (7°), roll ≤ 7°,
   18.5 → 0 m/s in 1.2 s (≈ 1.5 g); `r2_wreck_sheet_v.jpg` reads as a hard brake, not a crash.
   (c) A wreck is removed the moment it is out of view and > 60 m; dossier §6.1 wants 2 s unseen.
   Do: on WRECK set `speed = 0`; every tick `follower.s = closest_offset(lane, body)` and index the
   wreck at the body (and on the lane it overlaps); impulse only at `point − origin`, no extra
   linear momentum; an angular kick about `(point − origin) × normal` scaled by the closing speed
   (≈ 0.12 rad/s per m/s) instead of random values; removal after ≥ 8 s, 2 s unseen and > 60 m.
   Verify: 4-frame strip over 2 s of a 15 m/s ram at 0.6 m offset: yaw ≥ 30°, at rest within 3 s; a
   side hit ≥ 15 m/s rolls ≥ 20°; the follower stops ≥ 2 m behind the wreck BODY, then passes it in
   the next lane.

8. **Dead-end cars vanish in view; short lanes become fake loops.** `_remove_dead()` removes a
   non-wreck `despawn` car at once, visible or not; the city has 323 dead-end lanes (55 elevated,
   `diag2_graph`); `diag2_run`: `vanish in view at 118 m mode 0 despawn true`. `_detect_loop()`
   calls any lane whose ends are < 8 m apart a loop, so the city has 383 "loops" — e.g. lane 6443
   `ramp_rt_wb_nb`, 6.0 m long, whose only link is ITSELF through a 9 m connector (`diag2_flow`
   INFO line): a car circles on the spot; `diag2_run` counted 35 car-samples on such lanes < 30 m.
   Do: a dead-end car stops at the lane end (brake lamps on) and goes only after 2 s unseen; a loop
   needs a length ≥ 50 m (short lanes without valid links are dead ends).
   Verify: 60 s chase diag → `vanish_view 0`; the audit prints 0 loops shorter than 50 m.

9. **Performance is 2–3× over budget on the city; spawns hitch.** world.tscn, 90 cars (cap), the
   director's steps timed by hand (`diag2_perf_b.log`, load 14–27): tick median **1.312 ms**, p90
   1.98, p99 4.37 → **2.6 ms per 60 fps frame**; mean per tick: FAR car ticks 0.99, `_rebuild_index`
   + player 0.25, events 0.08, NEAR 0.06, modes 0.05; one spawn median 0.64 ms, **max 546 ms** (first
   `load()` of a model glb). At load 48 (`diag2_run.log`): median 1.452, p99 7.0 ms. Budget §7.7:
   1.0 ms per frame for 70 cars — still ≈ 2× over when scaled to 70 cars.
   Do: (a) FAR cars ≤ 120 m update every 2nd tick, > 120 m every 4th, and do only the transform
   while nothing changes (no lamp/shadow/lane-change work); (b) `_insert_player()` re-projects within
   8 m, not 60 m; (c) preload the 7 fleet glbs in the director's `_ready()`
   (`ResourceLoader.load_threaded_request`) and keep a pool of 90 cars built behind the loading
   screen: spawn = take + place (≤ 0.1 ms), despawn = hide + return; (d) never call
   `signal_state()` for lanes without a light (all decks, see 5).
   Verify: the perf test of 10(c) on world.tscn with exactly 70 live cars: median ≤ 0.5 ms per tick
   (1.0 ms per frame), p99 ≤ 2.0 ms, one spawn ≤ 0.1 ms; print the load average with the numbers.

10. **The tests do not test what they claim — and they fail or skip on the current build.**
    (a) `test_lanes_world` (city part) reads `get_lane_paths()` one frame after `add_child(world)` →
    `FAIL world.tscn has lanes (0)`. The world builds asynchronously (CONTRACTS §4, commit 209cd3c):
    `await Game.world_ready()` first. Your status blames the world rebuild — my diags that await the
    build get 8 845–9 119 lanes. Same bug in `test_junctions` (prints `SKIP the city has no lanes`
    and exits 0 — it can never fail) and in `demo/traffic_demo.gd` (`_graph` null → no lane, the
    player is never placed).
    (b) The sandbox part FAILS now: `FAIL sandbox.tscn: cars are still on the road (0)`. With
    `density_override = 0` every car that passes 420 m from the stub player is removed, so the
    "0.133 ms" median is measured while the fleet shrinks to 0 — not a 70-car number. Keep 70 live
    cars for the whole run (player at the loop centre, or despawn off in the test) and assert the
    count every second.
    (c) Budget metric: `tick_ms` is an EMA (0.15) and `TrafficCar.integrate_ms` is the EMA of ONE
    car's call. Use raw per-tick times plus the SUM of all NEAR `_integrate` calls of that tick;
    report median and p99 of the raw values, on world.tscn.
    (d) Jump check: at 4× a far car beyond 200 m already moves 1.5–2.2 m per update (your worst
    "1.70 m" is that cadence), so the 2.0 m limit cannot see a real jump; compare each step with the
    expected one (speed × dt × update period) + 0.3 m.
    (e) The label "no car is 0.05 m above or below its path" prints the measured value as if it were
    the threshold (2.0 m is what is checked).
    (f) Add the checks of items 1–8 (lamp surfaces per model + brake switch, ctx.player, MOBIL,
    overlaps/standstill, lights, v0, wreck follower, vanish count). City checks must FAIL (exit 1),
    never SKIP, when the world has no lanes after `world_ready()`.
    Verify: I re-run all tests: no SKIP, every number of items 1–9 printed in PASS/FAIL lines.

11. **The road ahead is still nearly empty; required captures missing (r1 #11/#15).** Chase camera
    on the deck at 25 m/s (`diag2_run`, 50 s, 90 alive): median **5** cars in view < 300 m and **2**
    ahead within 150 m in the player's direction; my chase shots `review_traffic_r2_chase_t8_0/
    t16_0.jpg` (`r2_chase_sheet_v.jpg`) show no traffic car at all. Dossier §6.1: 1 car per 45 m per
    lane → ≈ 10 ahead within 150 m on a 3-lane deck; `sh06_ring_road_light_trails.jpg` is solid
    trails (`r2_vs_ref_v.jpg` bottom). The ring spreads the 90-car cap over every road at deck height
    in a 420 m disc. Your `traffic_deck_t26_0.jpg` has 3 cars in frame, `traffic_sandbox_t20_0.jpg`
    none.
    Do: weight the target and the spawn spots to the player's road and heading (≥ 60 % of the cars on
    lanes of the player's road_id with heading within 30°, 70 % of those ahead; density per lane over
    0–350 m on that road; the rest on other roads). Then, after 1–8, captures: (a) Yan'an deck from
    the chase camera at ≥ 100 km/h with ≥ 6 cars ahead; (b) 6 m rear cruise vs braking + the lamp
    crop numbers; (c) front 3/4 at 6 m (lamps, head-lamp pool, blob shadow); (d) 4-frame wreck strip;
    (e) (a) hstacked with `sh06` + `sh05_yanan_elevated_blue_soffit.jpg` and a written list of what
    still differs. If the world renders no roads when you capture (its import is broken right now),
    say so and retake later — never submit a shot without traffic in it.
    Verify: 60 s chase diag on the deck: median ≥ 8 cars in view < 300 m, ≥ 6 ahead < 150 m.

12. **Code rules (CONTRACTS §3, lead notes).**
    (a) Files ≤ 400 lines: `traffic_car.gd` 450, `lane_graph.gd` 426 — split FIRST, as its own step
    (e.g. `traffic_car_physics.gd` for `_integrate/_check_contacts/_become_wreck/
    _apply_wreck_physics`, `lane_links.gd` for `_build_next/_link_entry/_make_connector/_straight_of/
    _turns_of`); nothing in the unit may exceed 400.
    (b) Dead code: `traffic_car.gd` `HORN_RADIUS`, `HORN_COOLDOWN`, `_horn_cooldown` (decremented,
    never read), `_was_close`, `from_prefill` (written, never read); `traffic_director.gd`
    `NEAR_MISS_RANGE`; `traffic_junctions.gd` `unresolved_world`; `lane_follower.gd` `_turn_angle()`,
    `_closest_lateral()`; `traffic_lamps.gd` `is_braking()`; `LaneGraph.dropped_neighbours` (never
    incremented). Also fix `advance()`: in the "lanes meet" branch `lane = next_lane` runs BEFORE
    `graph.entry_offset(lane, next_lane)`, so the entry is looked up as `next → next` (always 0) and
    the overshoot of `s` is dropped; same overshoot loss when a connector ends.
    (c) Magic numbers still in logic: `traffic_car.gd` 0.9/1.1 (v0 spread), 0.7 (start speed), 25.0,
    3.6, 6.0 (search radius); `traffic_director.gd` 4.0 ×2, 2.0, 0.7; `traffic_lane_change.gd` 2.5.
    (d) Scratch outside owned paths this round: `game/inspect_curve_tmp.gd`, `game/inspect_glb_tmp.gd`,
    `game/inspect_decal_tmp.gd/.tscn` (core-owned `game/`) and `/tmp/inspect_glb.gd`. They are gone
    now; next time only `tmp/traffic/` (lead note).
    (e) `status/traffic.md` and the result must state measured facts. Not true on this build: "ctx.player
    assigned every tick", "brake 4× brighter" (2.6/0.8 = 3.25× and never applied), "gap measured where
    the car is", "the sandbox part passes now (9 PASS)", "city 0 lanes because of the rebuild".

## SHOULD-FIX
- Fleet: add the shipped `robotaxi.glb` to `TrafficFleet.MODELS`; take length/width/height from the
  glb `Body` AABB instead of hand-typed numbers so the box collider matches the mesh.
- Horn: require ≥ 5 m/s relative speed (a player standing in a queue next to a car gets honked every
  3 s); erase `_horn_cooldown` entries on `car_removed` (the dictionary grows with every spawn).
- `vehicle_collided` fires every physics tick while two bodies stay in contact ≥ 0.5 m/s — rate-limit
  per collider (once per 0.25 s) so a scrape does not drain HP in the damage unit.
- Normal spawns 120–350 m; dossier §6.1 says 180–350 m.
- `ai/common/README.md`: document connectors, entry offsets, `neighbour_gap`, `LaneGrid` (it still
  says LaneGraph has "nearest lane"); police uses `LaneGraph` — keep the API stable, run their check.
- Head-lamp pool: not visible at 6 m in `review_traffic_r2_front_t5_0.jpg`; once 1 works, aim for a
  soft pool 4–20 m ahead without clipping.
- Indicator cards sit at the body AABB corners (x ±(half_w − 0.10), z = AABB end ± 0.02) and float
  in front of rounded corners; better drive an amber lamp surface or raycast the card onto the body.
- Prefill spawns 50 cars inside the view at 25–120 m on the first frames after the world is ready
  (`spawn_view 50`); finish the prefill before the loading screen hides.

## Verified OK
- `tools/godot.sh check --only=res://ai/traffic/,res://ai/common/` → `CHECK 29 files, 0 failed,
  0 engine errors, 0 warnings`.
- `test_idm` 23 PASS (IDM maths, platoon spread 4.83 → 0.00, hash leader/follower); `test_paint`
  10 PASS (5 colours × 8 paint surfaces carry `base_color_override`; probe: Body override
  (0.0549, 0.0588, 0.0667) = #0E0F11) — the close-ups show a black sedan, not white (r1 #1 fixed).
- `test_spawn_ring` 8 PASS (32 cars, spawns 123.5–347.2 m, 0 in view, 10 removed).
- Neighbours on another level: 0 of 16 744 pairs (worst dy 0.99 m; r1: 65) — r1 #3 level part fixed.
- Junction connectors: 0 frame-to-frame jumps beyond the expected step + 1 m in 50 s with 90 cars on
  the city, 0 in view (r1: 10 teleports of 100–378 m in view) — r1 #2 jump part fixed.
- Hard cap: 90 alive with `--quality=high`, never more (r1 #10 fixed).
- Contacts below 6 m/s closing no longer wreck (`_check_contacts`, r1 #6 fixed in code).
- Wrecks now come to rest (friction 0.9, damping, CCD): 18.5 → 0 m/s in 1.2 s (r1: still 18.4 m/s
  1.5 s after the hit).
- The ring scan is sliced: ring part 0.018–0.049 ms mean per tick (r1: 25–150 ms hitch every 2 s).
- All five tests `extends Node` (lead note); the director is split into ring / junctions / player
  events; head lights limited to the 4 nearest NEAR cars; indicator 1.5 Hz with a per-car phase;
  density × 0.7 in races/pursuits; group `traffic_director`; blob-shadow decal per near car.
- Ownership: every Write/Edit of this round is inside `game/ai/traffic/**`, `game/ai/common/**`,
  `status/traffic.md`, `tmp/traffic/` — except the scratch files of 12(d) (deleted).

## Evidence
Commands from `/Users/minimax/m/skyrush` (logs in `tmp/review/traffic/`):
- `tools/godot.sh check --only=res://ai/traffic/,res://ai/common/` → `r2_check.log` (above).
- `tools/godot.sh test res://ai/traffic/tests/<t>.gd -- --timeout=290` for the five tests
  (`r2_tests.sh`, `r2_test_*.log`): idm 23 PASS exit 0; paint 10 PASS exit 0; spawn_ring 8 PASS
  exit 0; junctions `SKIP the city has no lanes (the world did not build)` exit 0; lanes_world exit 1:
  `FAIL sandbox.tscn: cars are still on the road (0)`, `PERF sandbox.tscn: 0.133 ms per frame (tick
  0.132, physics 0.000)`, `FAIL world.tscn has lanes (0)`, `LANES/WORLD TESTS FAILED (2 failures)`.
- `tools/godot.sh test /Users/minimax/m/skyrush/tmp/review/traffic/<diag>.gd -- --timeout=290`
  (each awaits `Game.world_ready()`; reproduce any number with it):
  - `diag2_graph` → `[world] built in 47.29 s (9112 lanes)`, `GRAPH lanes 9112 links 41680 dropped
    79444 dead_ends 323 (elevated 55) loops 383 connectors>25m 10650`, `NEIGHBOURS pairs 16744
    cross_level(dy>1m) 0 … s_mismatch>5m 13843 worst 1096 m`, `JUNCTIONS … 9063 / 9112`.
  - `diag2_run` (kinematic player on yanan_elevated at 25 m/s, chase camera, 50 s) → `COST tick ms:
    median 1.452 p99 7.024 max 54.827 … cars 90`, `VIEW median cars in view<300m 5, ahead<150m on
    deck 2`, `RUN {"tp_any": 0, "tp_view": 0, "vanish_view": 1, "spawn_view": 50, "changes": 0, …}`,
    `vanish in view at 118 m mode 0 despawn true`.
  - `diag2_perf` / `diag2_perf_b` → see item 9 and 4 (`STOPPED on elevated lanes: 13 of 90` → `37 of
    90`, `TOTAL per tick: median 1.312 p90 1.979 p99 4.373 ms`, `SPAWN one car: … median 0.64 ms max
    546.50 ms`, ramp queue on lane 6443 at signal 2 with gaps 0.8–7.7 m).
  - `diag2_flow` → `OVERLAPS (centre < 2.5 m, sampled 2/s after 10 s): 647, across lanes 387`, the
    `OVERLAP …` and `STUCK …` lines quoted in 4–6.
  - `diag2_signals` → `ELEVATED lanes 497, with a junction 494`, `DECK lanes (y>6 m) 271, with a
    junction 268, red/amber right now 103`.
  - `diag2_lamps` (sandbox) → item 1; `diag2_logic` (sandbox) → items 2 and 3.
- Captures: `tools/godot.sh shot --scene=/Users/minimax/m/skyrush/tmp/review/traffic/
  review2_scene.tscn --out=review/traffic/review_traffic_r2_<x> --mode=chase|close [--front]|wreck
  [--road=bund_zhongshan_e1 --miny=-5] --times=… --warm=60` → `review_traffic_r2_chase_t8_0/t16_0`,
  `_rear_t5_0/t8_5`, `_front_t5_0`, `_wreck_t1_3/1_7/2_4/4_0` (wreck telemetry in
  `shot2_wreck.log`). Sheets: `r2_chase_sheet_v.jpg`, `r2_close_sheet_v.jpg`, `r2_lamp_crops_v.jpg`,
  `r2_wreck_sheet_v.jpg`, `r2_vs_ref_v.jpg` (our rear lamps vs `cp04_nfs2015_wet_night.jpg`; your
  `traffic_deck_t26_0.jpg` vs `sh06_ring_road_light_trails.jpg`), your shots in
  `r2_worker_sheet_v.jpg` / `r2_worker_sheet2_v.jpg`.
- Scratch scripts are the reviewer's: do not edit them; write your own tests in
  `game/ai/traffic/tests/`.
