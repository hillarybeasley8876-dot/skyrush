# vehicle review round 1 — VERDICT: FAIL

Reviewer: lead/art director (Opus). Every number below was measured by me on 2026-10-20 with the
current files; probe scripts you can read and copy into your own Node tests:
`tmp/review/veh_probe_a.gd` … `veh_probe_d.gd` (run: `tools/godot.sh test /Users/minimax/m/skyrush/tmp/review/veh_probe_a.gd`).

## Scores (0-10)
- function: **4** — the base car is good (0-100, top speed, brake, hop, roll motion, drift gauge,
  charge, tests run), but none of the 4 lead notes is satisfied and 12 integration bugs break
  other units (damage gets 22 % of the impulse, nitro permanently lifts top speed, menu drives the car).
- visual/feel: **4** — front wheels steer the wrong way, calipers never move, wing uses invented
  poses with the wrong sign at 16 °/s, 33 m teleport into the sky lane, yaw jets fire on every
  ground steer, drift angle only 37–53° instead of 26–52°.
- code: **5** — clean module split and files ≤ 400, but dozens of magic numbers in logic files,
  ~16 dead tuning constants + dead functions, tests violate the `extends Node` rule with `Variant` cars.

## MUST-FIX

Suggested order: 18e (split `arcade_car.gd` first, separate step) → 18a (Node tests) → 1, 2, 3, 6, 9
(small logic bugs) → 4, 5, 7, 14 (API/events) → 8, 16 → 12, 13, 15 → 11 → 10 → 17 → 18b-f → 19.
Each fix comes with its test; re-run the full suite and `feel_report` at the end.

1. **Lead note V-INT1 — `Events.boost_ended` is never emitted** (grep: no `boost_ended` in
   `game/vehicle`). Probe A: nitro at 240 km/h → after 3.5 s `kind=''` but 0 `boost_ended`;
   nitro while pinned against a wall → same. (The camera unit also reports this in `status/camera.md` #4.)
   Do: in `modules/boost.gd` keep the previous `kind`; when it goes from non-empty to `&""`
   (timer end, flight end, reset) raise a one-shot flag; `ArcadeCar` emits
   `Events.boost_ended.emit(self)` exactly once per boost. Every boost start (player and AI,
   incl. `air_mini`, `landing`) emits `boost_started` exactly once.
   Verify: new `tests/test_boost_events.gd` (Node test): nitro into a StaticBody wall 40 m ahead
   at 100 km/h → 1 `boost_started(&"nitro")`, 1 `boost_ended` within 3.0–3.2 s, `boost_kind == &""`.

2. **The nitro permanently raises the top speed; the battery cap is ignored.**
   Probe A: 6 s after the nitro ended at full throttle → **300.0 km/h**, `boost.speed_cap` still
   300 km/h (base top 250). Battery 0.076 → **249.6 km/h** (brief: < 0.15 caps at 180 km/h).
   Cause: `boost.speed_cap` is only written in `use_*()`/`start_*()`, never in `tick()`;
   `car_dynamics.gd:86` uses `boost.speed_cap` and never `power.speed_cap()`.
   Do: `boost.tick()` sets `speed_cap = _current_cap()` every tick; dynamics uses
   `power.speed_cap(boost.speed_cap)` (give dynamics the power module).
   Verify (add to `test_top_speed.gd`): ≤ 252 km/h within 4 s after the nitro ends; battery 0.10
   from 170 km/h for 6 s → ≤ 181 km/h; no state ever exceeds 330 km/h (V_CAP).

3. **Lead note 1 — the car drives under the title menu.** Probe A: `Game.mode = &"menu"`,
   accelerate held 1.5 s → **66.8 km/h** (`ui/menu/menu.gd:265` sets this mode; ↑/↓ menu
   navigation are also accelerate/brake). Do: `player_input.sample()` returns a zeroed snapshot
   (and clears the edge history) while `Game.mode == &"menu"` or `get_tree().paused`.
   Verify: test with mode menu + accelerate/nitro/hop pressed 2 s → speed < 1 km/h, N₂ unchanged,
   no `boost_started`/`hop` events; back to `&"free"` → no phantom edge fires.

4. **Lead note 2 — AI API is broken and undocumented.**
   a. `request_hop()` charges twice and emits an empty kind: probe A → N₂ 100 → **50.1** (want 75),
      `Events.hop` kind = `&""`. (`arcade_car.gd:172` spends 25, `car_dynamics.gd:234` spends again
      using a stale `last_hop`.) Route it through the thruster spool: `request_hop(big: bool = false)`
      → `thruster.begin_spool(big)`, one charge, `last_hop` set, the normal 0.08/0.15 s spool.
   b. `use_nitro()` emits no `boost_started` — rivals call it (`ai/rivals/rival_speed.gd:120`),
      so rival nitros have no FX/audio. Make it the same path as `_fire_nitro()`.
   c. Add `request_roll(dir: int) -> bool` (20 N₂, emits `barrel_roll`) and
      `request_launch() -> bool` (standing launch for AI, same N₂ ≥ 50 rule).
   d. Add `get_n2() -> float` (rivals read `car.boost.n2` directly today).
   e. Document the whole AI-facing API (signature, cost, events, preconditions) in a block at the
      top of `arcade_car.gd` AND in `status/vehicle.md`.
   Verify: `tests/test_ai_api.gd`: each call → exact N₂ delta (−100 / −25 / −50 / −20 / 0) and
   exactly one matching event with the right kind.

5. **Lead note 3 + the N₂ gains of dossier §5.2 are missing.** Probe A: `Events.takedown` with
   `Game.player = car` → N₂ 20 → **20.3** (self-refill only). Also missing: near miss +5
   (`Events.near_miss` for the player), clean landing after a Big Hop or barrel roll +15 with the
   toast `特技 TRICK!` (§5.4: roll must end ≥ 0.15 s before touchdown).
   Do: connect `Events.takedown` (player car only: `Game.player == self`), +50 and +25 per streak
   step, streak window 10 s (dossier TL;DR #23); constants in `tuning/`. Put the reward rules in
   a small module (e.g. `modules/rewards.gd`) — `arcade_car.gd` is 387 lines and must not grow.
   Verify: takedown, takedown 3 s later → +50 then +75; 12 s later → +50 again; near miss → +5;
   clean Big Hop landing → +15 and one toast.

6. **The barrel roll is free.** `thruster.request_roll()` spends from `thruster._n2`, a local copy
   that `set_n2()` overwrites next tick. Probe B: N₂ **175.0 → 175.0** (want −20). Do: spend from
   `boost` once when the roll starts; delete `thruster.spend()`/`_n2`. Also
   `player_input.gd:63-64` uses `is_action_pressed` for rolls → holding Q fires a 2nd roll the
   instant the first ends; use `is_action_just_pressed`.
   Verify: `test_roll.gd` asserts N₂ −20 ± 0.5 and a held key gives exactly one roll.

7. **空喷 and 落地喷 do not exist.** `use_air_mini()`, `use_landing_mini()`,
   `air_mini_available()`, `mark_air_mini_used()`, `landing_window_open()` are never called;
   `telemetry.mini_window` ignores the landing window, so the HUD never shows the 落地喷 prompt.
   SPEC §5 + dossier §5.3: air 小喷 = tap `mini_boost` (K or re-press accelerate) once per jump in
   the air → +6 m/s forward impulse, 0.5 s, `boost_started(&"air_mini")`, R1–R4 0.5; 落地喷 = tap
   within 0.45 s after a touchdown with airtime ≥ 0.3 s → normal 小喷, `boost_started(&"landing")`.
   Verify: `tests/test_air_boosts.gd`: hop → air tap → +6 ± 0.5 m/s, 2nd air tap refused;
   land, tap at +0.3 s → landing boost; tap at +0.6 s → refused; `mini_window` true while open.

8. **The collision impulse sent to the damage unit is ~22 % of the real one** (the damage unit
   reports this too, `status/damage.md` Requests). Probe B: 100 km/h head-on into a static wall →
   reported **11,771 N·s**; real Δp ≈ 1,900 kg × 27.8 m/s ≈ **52,800 N·s**. Cause: `impact.gd:43,66`
   computes `v_rel`/`v_n`/`ratio` from the *post*-impact `state.linear_velocity`.
   Do: use `_prev_velocity` (the pre-hit velocity) for `v_rel`, `v_n`, `ratio`; `impulse = mass × v_n`.
   The wall-glance yaw is dead code: `impact.glance_torque` is computed (`impact.gd:107-109`) but
   never applied — apply it in the car for 0.15 s (§7.2 "yaw 50 % toward the wall tangent over
   0.15 s"); move `8000.0`, `0.15`, `0.5` to `tuning/`. Use 0.35 as the scrape threshold (§7.2),
   not `IMPACT_CLEAN` 0.30 (that one is the drift-clean rule).
   Verify: `tests/test_impact.gd`: head-on 100 km/h → impulse 45,000–56,000 N·s, impact ≥ 0.9, one
   event per 0.15 s; 15° glance along a wall at 150 km/h → impact < 0.35, ≥ 90 % speed kept, yaw
   rate toward the tangent for 0.15 s, no event spam while grinding (≤ 7 events per second).

9. **完美起步 is granted by simply holding accelerate.** Probe A: accelerate held 2 s before
   `race_started` → launch fired. Cause: `arcade_car.gd:227-228` refreshes `_throttle_pressed_at`
   every tick while held. Do: store the press *edge* only (player and AI), require it inside
   `START_WINDOW` 0.28 s before `race_started`.
   Verify (`test_launch.gd`): edge at −0.20 s → launch; held from −2.0 s → no launch; edge at
   −0.50 s → no launch.

10. **Sky lane flight does not follow dossier §5.6 / the brief ("exit = descend + landing puff").**
    Probe B (sandbox lane, 150 km/h, steer +1 held): the take-off **teleports the car 33.0 m in
    one tick** (a 150 km/h tick is 0.35 m); the car drifts **11.58 m** off the centre line (tube
    half width 7). Causes: `_transition` is set and decremented but never used; `sky_flight.gd:79`
    `move_toward(lateral, …, 0.0)` is a no-op; `LANE_SPRING` is unused; `_end_flight()` just drops.
    Do: (a) 0.4 s transition: blend from the take-off transform to the lane frame (lerp origin,
    slerp basis), gravity 0, P1–P4 = 1.0 during it; (b) soft edge 30 m/s² per metre outside +
    hard clamp at half width + 1 m; (c) exit: descend at 3 m/s until the probes touch (max 2 s),
    landing cushion + `landed` event; at N₂ = 0 glide at 0.35 g and exit; (d) N₂ boost in flight
    raises the lane speed to 300 km/h; (e) pose bank −3.5° per m/s of lateral speed (max 35°) and
    pitch 2.5° per m/s of vertical speed.
    Verify: `test_sky_lane.gd` must steer +1 the whole flight (max |lateral| ≤ 7.5 m), assert the
    largest per-tick move ≤ 1.5 × v·dt, and vertical speed ≥ −3.5 m/s after the exit until touchdown.

11. **Drift angle out of the brief band and the player has almost no authority over it.**
    `feel_report` prints `drift slip 24 .. 48 deg` against the target `26 .. 52` and the test band
    was widened to 20–58 (`test_drift.gd:44`) to pass. Probe D (200 km/h, β every 0.1 s): steady β
    with steer −1 / +0.5 / +1 = **37° / 48° / 53°**; β crosses 26° only at ~0.45 s. Dossier §4.6:
    counter-steer ≈ 26°, full steer-in ≈ 52°. Do: `DRIFT_BETA_CMD_MIN/MAX` 0.628/0.768 rad →
    0.45/0.90 rad, cap β at 52°, make the entry reach 26° by 0.30 s; restore the test band 26–52
    from 0.40 s on, start the drift with N₂ = 0 (today N₂ = 100 clamps the gain at exactly 100.000).
    Verify: steer −1 → β 26–32°, steer +1 → β 46–52°, both 0.4–3.0 s; gauge 95–105 N₂.

12. **Visual binding (`car_visual.gd`) is wrong in five places.**
    a. Front wheels steer the wrong way. Probe B: steer +1, car yawing right (ω_y −0.92 rad/s),
       `steer_angle` +0.484 rad, but `Wheel_FL` X axis in car space = (0.885, 0, −0.466) = turned
       LEFT (`captures/review/vehicle/review_vehicle_r1_lock_wheel_fr.jpg`). `car_visual.gd:125`
       must use `Basis(Vector3.UP, -steer)`.
    b. `Caliper_FL/FR/RL/RR` are siblings of `Wheel_*` under `Roadster` in the glb and never move:
       they must follow the wheel centre (suspension) and the front steer, without the spin.
    c. Wing poses must come from the glb: `wing.get_meta("extras")["poses"]` =
       `{stowed 0, low_drag 1, high_downforce 15, air_brake 60}` (deg, positive = trailing edge UP,
       from `ref/roadster/roadster_loft.json`). The invented `{0, −3, −14, 26}` in `roadster.tres`
       only as a fallback. Sign: the Wing basis is identity with the trailing edge at local +Z,
       so `rotation.x = base − deg_to_rad(pitch)`; the current `+` pushes the edge into the deck.
       Target: trailing-edge height ≈ 1.19 m at air_brake, ≈ 0.97 m at high_downforce
       (ref photos `17_wing_deployed_closeup.jpg`, `08_rear_straight_daylight_wing_deployed.jpg`).
    d. Pose timing: today 16 °/s (`car_visual.gd:145-146`). Probe C: braking from 207 km/h, after
       1.0 s the wing is at 13° of 26°, then flips back to low_drag at 148 km/h — the air brake never
       deploys. Brief + dossier (patent): angle change ≤ 0.25 s → rate = |Δ| / 0.25 s with an ease,
       plus a 0.25 s hold before a new pose so it does not chatter around 150/60 km/h.
    e. Drift counter-steer: front wheel visual angle −β × 0.8 (`drift.visual_counter` is unused).
    Verify: `tests/test_visual.gd` (signs + timing numerically) and captures: front34 + top with
    `--press=steer_right` (wheels turned right, calipers inside the rims), rear34 at air_brake.

13. **Thruster telemetry violates the brief ("P5/P6 for yaw corrections in flight and barrel
    rolls; 0 otherwise").** Probe B: **P6 = 1.00 while steering on the road with 4 wheels down**
    → the FX unit shows yaw jets at every corner. Probe D: during a barrel roll with no steer input
    **P5 = P6 = 0**. Do: P5/P6 only while airborne/flying; during a roll fire by `roll_dir` (1.0);
    the yaw mapping is inverted — P5 (front-left, exhausts −X) pushes the nose RIGHT, so P5 =
    right yaw, P6 = left yaw. Landing cushion (P1–P4 0.8) only on a touchdown with airtime ≥ 0.3 s
    or v_y < −4 m/s (§5.5), not on every 1-tick wheel loss. Sky lane: P1–P4 1.0 in the transition.
    Roll rule: roll right (+1) → P5 = 1.0 (its −X exhaust pushes the car toward +X, the 3.5 m
    side-dodge), roll left → P6 = 1.0.
    Verify: a test table (grounded steer → P5 = P6 = 0; air yaw right → P5; roll right → P5 = 1.0
    for the 0.70 s; hop → P1–P4 1.0 for 0.15 s; Big Hop 0.30 s; 1-tick bump → no cushion).

14. **Events missing/too eager:** `Events.hover_changed` (contract) is never emitted — emit on
    hover start/stop. Emit `landed` only after ≥ 0.10 s of airtime (dossier §4.8 airborne rule).

15. **Two telemetry contract fields are wrong.** `car_readout.gd:68`
    `g_load = 1 + downforce_kg / (mass / 1000)` → at 250 km/h 1 + 1131 / 1.9 = **596 g** (real ≈ 1.6 g):
    divide by the mass in kg (better: the real body acceleration incl. cornering).
    `car_readout.gd:64` `altitude_m = origin.y` is world height; the contract says height above
    ground and the HUD gauge shows it (`ui/hud/hud.gd:228`) → on the 9 m sandbox deck or 延安高架 the
    HUD reads 9–12 m while driving. Use ≈ 0 when grounded and a downward ray (≤ 200 m) in the air.
    Verify: on the sandbox deck at x 80 / z 100 grounded → altitude < 0.5 m; g_load 1.0–2.0 at 250 km/h.

16. **Groups, reset and respawn.** The car never joins the `vehicles` group (CONTRACTS §3);
    `damage/damage_director.gd:97` tracks only that group (fx has a slow fallback scan) → the
    damage unit never tracks the player car spawned by `main.gd`. Add `&"vehicles"` in `_ready()` and
    `&"player"` when `player_controlled`. `reset_car` (R) is sampled (`player_input.gd:67`) but used
    by nobody → call `Game.respawn_player()` for the player; dossier §4.7: upside down for 1.5 s →
    auto-respawn. Override `reset_to()` in `ArcadeCar`: end the flight, clear roll/hover/drift/boost
    timers and `impact._prev_velocity` — today `_tick_flight` overwrites a respawn in a sky lane on
    the next tick, a respawn mid-roll restores the pre-roll basis, and the first tick after a
    teleport can report a fake impact.
    Verify: test: respawn during flight → `flying` false, car at the new transform after 0.5 s; car
    placed on its roof → respawned upright after 1.5–1.7 s; `get_nodes_in_group(&"vehicles")` has it.

17. **NPC presets point at missing glbs and the wrong wheel geometry.** 5 of 8 paths do not exist
    (`patrol.glb`, `interceptor.glb`, `heavy_suv.glb`, `sedan.glb`, `suv.glb`; the files are
    `police_patrol`, `police_interceptor`, `police_suv`, `sedan_ev`, `suv_ev`) → those cars render
    the flat white placeholder box (ART §5: no flat untextured surfaces); the police unit patches
    the paths at runtime as a workaround. The wheel data does not match the glbs and `car_visual`
    moves the glb wheels to the spec positions: sedan_ev wheels z ±1.49 / r 0.347 vs spec ±1.35 /
    0.33; bus front −3.40, rear +2.60, r 0.48 vs spec ±2.75 / 0.45 → wheels drawn 14–65 cm outside
    their arches. Do: generate every preset from its glb (Wheel_* translations = wheel centres;
    mount = centre + REST_LEN − static sag; radius from the tyre AABB; body box from the glb AABB)
    with a generator kept in an owned path (e.g. `game/vehicle/specs/gen_specs.gd`), and add presets
    for `hatch_ev`, `robotaxi`, `truck`. Verify: a test that loads every preset + glb and checks
    |wheel rest position − spec centre| < 0.02 m, plus one capture sheet of all presets parked.

18. **Code rules (CONTRACTS §3, brief, lead rules).**
    a. All 11 tests, `feel_report.gd` and `vehicle_test.gd` are `extends SceneTree` with `Variant`
       cars — lead rule: tests `extends Node`, run by `tools/test_host.gd`, typed `ArcadeCar`.
    b. Magic numbers in logic files (brief: every number in `tuning/` or `CarSpec`): arcade_car.gd
       :88-89 masks, :123 100.0, :155/227/384 0.5, :191 0.1, :360 20.0, :382 1.0/50.0;
       boost.gd :116-122 0.3/0.4/0.8/0.9 (use `Tuning.STACK`), :165 0.5, :247 6, :254 4.0;
       car_dynamics.gd :238 0.15/0.30, :243 9.81 (use the project gravity), :253 2.0, :266 0.10,
       :281 0.3/0.1, :288/:291 4.0, :310 0.25, :313 0.85; drift.gd :63 0.8, :94 1.1, :124 0.5/2.4,
       :127 0.15, :133 10.0, :149 12.0/−0.3, :152 0.5/2, :164 2.0, :184 0.5, :194-196 10.0/66.0;
       thruster.gd :82 0.5, :104 0.15/0.08; car_readout.gd :50 40.0, :67 9.81, :80-89 levels,
       :113 8.0; car_visual.gd :111 10.0/4.0, :135-146 150/60/0.25/4.0; sky_flight.gd :67 4.0,
       :80 0.2; power.gd :16 0.05; impact.gd :106-108.
    c. Dead code: tuning constants never read — `STACK`, `LANE_SPRING`, `PARK_SPEED`, `GRIP_CURVE`,
       `ACKERMAN`, `A0`, `STATIC_SAG`, `BRAKE_FRONT_SHARE`, `DRIFT_YAW_MIN/MAX`, `DRIFT_BETA_CLAMP`,
       `HIT_TANGENTIAL_KEEP`, `HIT_BOUNCE`, `DAMAGE_K`, `DAMAGE_OFFSET`, `LAND_VERTICAL_SAFE`.
       Implement what the dossier asks (§4.5 grip curve + surface_mult, §4.7 park rule below
       0.5 m/s) or delete; damage constants belong to the damage unit. Stale comments:
       car_dynamics.gd:145 ("applied at the height of the centre of mass"), sky_flight.gd:76.
    d. `impact.gd:34` untyped `drift` parameter; `Array`/`Dictionary` per-wheel states → typed.
    e. `arcade_car.gd` is 387/400 lines: split first (bus handlers + rewards + AI API into
       modules), as a separate step, before adding the features above.
    f. Scratch left in `tmp/vehicle/` (drift/drive/force/loop/npc logs, `results/`,
       `make_specs.py`): delete; a kept generator goes to an owned path. Godot was started in the
       background (`(tools/godot.sh test … &) ; sleep 100`) — forbidden; run in the foreground.

19. **Status/evidence must be true.** `status/vehicle.md` says "the roadster glb is not in the
    project yet, so the car shows the placeholder body" — false: `roadster.glb` (62,930 tris) loads
    and is visible in your own `veh_*.jpg`. "slip 24-48 deg" is listed as a pass although the brief
    band is 26–52. Rewrite the evidence with the real numbers after the fixes and re-shoot driving,
    drifting, hopping, flying and `main.tscn` (plus the steer and air-brake shots of item 12).

## SHOULD-FIX
- Demo lighting: `demo/demo_car.gd` uses a flat BG colour + one directional light, so the
  `SH_car_paint` reads as matte lavender plastic with no reflections
  (`captures/review/vehicle/review_vehicle_r1_steer_front34.jpg`). Instance the environment unit's
  `res://world/env/environment.tscn` (or the core stub environment) so the evidence shows the hero
  car as ART §1 requires; put the camera/light numbers in consts.
- `feel_report.gd` must print ONE table of all measured numbers (brief): add launch 0–100, roll
  360° time, landing lateral drift, stability, WCWW cap, sky lane max lateral, charge, β per steer
  input, and the CPU of `_physics_process` too (the 4 shape casts run there, not in
  `_integrate_forces`, so 47 µs/tick is only part of the per-car cost).
- Per-tick allocations: `thruster_outputs()` builds a new Dictionary and 8 formatted keys per car
  per tick, `update_visual()` builds 4 Dictionaries — preallocate StringName keys and reuse.
- `impact._last_report` grows forever — prune entries older than 1 s.
- Robustness when the visual is replaced at runtime (brief pitfall): guard `wing`, `brake_light`,
  wheels and calipers with `is_instance_valid()` and re-find them when `Model` changes (the damage
  unit detaches panels).
- Placeholder: the brief asks for a white *wedge*; use the shared `SH_car_paint` and a tyre material
  from the library instead of flat StandardMaterial3D boxes.
- Missing dossier details: no hop under a ceiling (3 m up-ray, §5.3), landing snap-align over
  0.12 s (§4.8), hard landing > 14 m/s → report it (§4.8), floor contacts (normal·up > 0.7) should
  not be reported as `vehicle_collided` unless v_n > 14 m/s.
- `test_roll.gd` stops at 350°: measure until `thruster.rolling` is false and require 355–365° in
  0.65–0.75 s; `test_landing.gd`: add a 10° roll/yaw misaligned drop.

## Verified OK
- `tools/godot.sh check` on the vehicle-owned dirs (`modules, tuning, specs, tests, cars, demo`):
  36 files, 0 failed, 0 errors. (`--only=res://vehicle/` also loads `vehicle/camera/`, whose 2 parse
  errors belong to the camera unit.)
- All 11 tests run and pass as written (67 checks, exit 0), feel table: 0-100 2.42 s, launch 0.80 s,
  top 250.0 km/h, N₂ top 300.4 km/h, brake 100-0 24.4 m / 1.75 s, hop apex 3.36 m, Big Hop 7.62 m,
  8 m drop at 150 km/h lands flat with 0.0 m lateral drift, 295–300 km/h lane changes without
  roll-over or tunnelling, charge bay → N₂ 200 / battery 1.0 / +20 HP / `charge` boost.
- QQ cap formula exact: 小喷 272.0, N₂ 300.0, CW 306.6, WCW 308.8, CWW 317.6, WCWW 319.8 km/h.
- Drift gauge from an empty tank: 101.8 N₂ for a 3 s drift at 200 km/h (target 95–105).
- Physics CPU 47 µs per car per tick in `_integrate_forces` (budget 250 µs).
- `main.tscn` with the real units: the player car drives (176 km/h at 3 s with nitro, 250 km/h at
  7 s), the HUD reads the telemetry, 0 errors from `res://vehicle/` (1,780 errors from other units).
- glb binding: `Model` under `Visual`, `MaterialLibrary.apply()` swaps `Body` surface 0 to
  `res://shaders/car_paint.gdshader`; `LightBar_Rear` gets a per-car material duplicate and goes
  4 → 10 on braking; wheel spin sign and suspension travel are correct, the wheels sit in the arches.
- Hard steer at 100 km/h without drift: max roll 2.4°, no spin (the police's roll-over report does
  not reproduce on the Roadster); 0.6 m drop with full throttle: worst pitch/roll 5.1° (modes'
  tumble report fixed); 0 `landed` events in 8 s of straight driving at 250 km/h.
- Ownership: every Write/Edit/sed in the job log is inside `game/vehicle/**` (not `camera/`),
  `status/vehicle.md` or `tmp/vehicle/`.
- Jolt flags set (`continuous_cd`, `contact_monitor`, `max_contacts_reported = 8`), input read in
  `_physics_process`, keyboard ramp 4.0/6.0 per s, gamepad `s·|s|` with a 0.12 dead zone.

## Evidence
- `tools/godot.sh check --only=res://vehicle/modules/,res://vehicle/tuning/,res://vehicle/specs/,res://vehicle/tests/,res://vehicle/cars/,res://vehicle/demo/`
  → `CHECK 36 files, 0 failed, 0 engine errors, 0 warnings`.
- `tools/godot.sh test res://vehicle/tests/<each>.gd` → every `RESULT n checks, 0 failures`; logs in
  `tmp/review/veh/*.log`; `feel_report` → `drift slip (3 s) 24 .. 48 deg | 26 .. 52 deg`,
  `physics CPU 47 us/tick`.
- Probe A (`tmp/review/veh_probe_a.gd`): `after burn kind='' cap=300.0 km/h ended_signals=0`;
  `6s after nitro speed=300.0 km/h`; `battery=0.076 speed=249.6 km/h`;
  `AI hop n2 100 -> 50.1 (want 75) hop events=[&""]`; `takedown n2 20 -> 20.3 (want 70)`;
  `menu mode speed=66.8 km/h (want 0)`; `held-2s start launches=1 kind='launch' (want 0)`.
- Probe B: `roll n2 175.0 -> 175.0`; `wall impulses=[11770.7]`; `steer=1.00 angle=0.484 rad;
  visual FL axis=(0.885, 0.0, -0.466)`; `yaw rate=-0.92; P5=0.00 P6=1.00 grounded=4`;
  `drift pending=101.8`; `hard steer 100: max roll 2.4 deg`; `drop 0.6 m + throttle: worst 5.1 deg`;
  `sky: max per-tick move 33.00 m, max lateral 11.58 m (tube 7)`.
- Probe C: glb `Wing extras poses {stowed 0, low_drag 1, high_downforce 15, air_brake 60}` vs spec
  `{0, -3, -14, 26}`; braking from 207 km/h: wing 1.0 → 5.0 → 9.0 → 13.0° per 0.25 s, then
  `low_drag` at 148 km/h; `bar_energy=10.0` while braking.
- Probe D: β every 0.1 s, steer −1 → settles 37°; +0.5 → 48°; +1 → 52–53°; roll without steer →
  `P5=0.00 P6=0.00 P1=0.00 R1=0.00`.
- glb JSON: `Caliper_FL parent=Roadster t=[-0.78, 0.343, -1.413]` (sibling of `Wheel_FL`);
  NPC wheels: sedan_ev ±1.49 / bus −3.40,+2.60 vs specs ±1.35 / ±2.75.
- Captures (`captures/review/vehicle/`): `worker_sheet.jpg` (your 6 shots), `steer_sheet.jpg` +
  `steer_front_crop.jpg` and `review_vehicle_r1_lock_wheel_fr.jpg` (steer right held → front wheels
  turned left), `review_vehicle_r1_main_t3_0.jpg` / `_t7_0.jpg` (main.tscn, `main_sheet.jpg`).
