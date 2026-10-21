# vehicle review round 3 — VERDICT: FAIL

Reviewer: lead/art director (Opus), 2026-10-20. Every number below was measured by me on the
current files. Probe scripts (Node tests, copy what you need into your own tests):
`tmp/review/veh3/probe_a.gd` … `probe_f.gd`, run with
`tools/godot.sh test /Users/minimax/m/skyrush/tmp/review/veh3/probe_a.gd`; logs in
`tmp/review/veh3/logs/`. Timelines `tmp/review/veh3/tl_rear.json`, `tl_main.json`; bar meter
`tmp/review/veh3/barscan.py`.

## Scores (0-10)
- function: **5** — every R2 item is really fixed (386/386 checks, the nitro key, the air, the
  heading, the per-car suspension, the sky lane, one pop-up per event), but the QQ drift loop is
  broken at both ends of the exit (a released drift never ends; a counter-steered exit keeps the
  car 50–67° sideways for 1.3 s), one 断位 permanently halves every later drift, the Big Hop is
  1.8 m short at 250 km/h, and one barrel roll turns every later bump into "+15 N₂ TRICK".
- visual/feel: **4** — drifting at speed is the core feel and it is wrong (main.tscn: the car
  circles at 265 km/h with no input until it hits a building); the hero red light bar is
  salmon-pink with a dark 0.93 m hole in the middle while driving.
- code: **6** — typed, ≤ 318 lines per file, clean module split; but the magic-number claim is
  false for the third round running, three dead constants, six orphan `.uid` files, a stale
  false comment, a duplicated cushion formula, and the project-wide import cache was deleted.

## MUST-FIX
Order: 9 (hygiene, quick) → 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8. Every fix ships with its test; re-run
all tests + feel_report, then re-shoot the evidence named in item 8.

1. **A released drift never ends (perpetual 265 km/h circle).** `drift.gd:129-131` "unwinds"
   with `omega = lerpf(omega, 0.0, dt / DRIFT_UNWIND_TIME)` — but `omega` is recomputed from
   scratch every tick, so this is a constant ×0.944, not a fade. With the button released and
   the steer neutral, β stays ≈ 36° and the dossier exit (β < 12°) never comes.
   Probe A (200 km/h, 2 s right drift, then drift off + steer 0 + throttle): `t+1s state=drift
   beta=36.1 yaw=-1.28 … t+5s state=drift beta=35.8 yaw=-1.30 speed=243 turned=374 deg`,
   `left the drift after -1.00 s (never in 5 s)`. main.tscn (my timeline `tl_main.json`, keys
   released at 7.6 s): `drift` from 6.8 s to the end at 12.0 s (263–267 km/h until the brake at
   10.2 s, still `drift` at 160 km/h at 12.0 s); the car circled (x −40→−137→−38, z 22→92→−18)
   into a building (`captures/review/vehicle/r3_main_sheet.jpg`, tile 3: camera inside a wall,
   police pursuit triggered).
   Do: keep a persistent `_unwind` factor (1 → 0 over `DRIFT_UNWIND_TIME` with `move_toward`)
   that runs while the button is released AND the steer is not held into the drift
   (`steer × dir < DRIFT_MIN_STEER`); multiply ω_target by it; it resets to 1 when the button or
   the steer-into-drift comes back. Released + steer held into the drift keeps the QQ arc
   (unchanged); counter-steer keeps the fast 拉车头 exit (unchanged).
   Verify (new checks in `test_drift.gd`, keys via `Input.action_press` once, the AI path for the
   rest): released + steer 0 → state leaves `drift` within ≤ 1.0 s, heading change after the
   release ≤ 90°; released + steer +1 held → still `drift` after 2 s; counter-steer −0.5 →
   `recover` within 0.3 s (now 0.28 s — keep it).

2. **RECOVER does nothing: after a clean exit the car slides 50–67° sideways for over a second.**
   `drift._update_recover()` computes the dossier's RECOVER assist (λ 5.2/s) and the yaw damping,
   but `car_dynamics.gd:252-264` applies `yaw_torque` and `assist_accel` only
   `if drift.state == &"drift"`. In RECOVER the tyres are still at `tyre_scale` ≈ 0.05→0.6, so
   nothing straightens the car; then GRIP snaps `rear_mu`/`tyre_scale` to 1.0 (`drift.gd:173-175`).
   Probe B (counter-steer −0.5 for 0.4 s, then 0): `t+0.25 drift β 44.9` → `t+0.30 recover 45.3`
   → `t+0.55 recover 59.5` → `t+0.90 grip 67.2` → `t+1.30 grip 61.0` → `t+1.60 grip 49.1`.
   The 小喷 window (0.5 s from the exit) is therefore spent while the nose is 45–60° off the
   velocity — the boost pushes the car sideways. The dossier (§1.2.4, §4.6 RECOVER row): the
   nose is straight, then the 小喷.
   Do: apply the RECOVER yaw torque and lateral assist in `_apply_drift` (all three states share
   one apply path); fade `tyre_scale`/`rear_mu` to 1.0 over `DRIFT_RECOVER_FADE` without the final
   snap. The 断位 exit uses the same path.
   Verify (test_drift): after the counter-steer exit of a 3 s drift at 200 km/h: |β| ≤ 12° at
   +0.35 s and ≤ 5° at +0.6 s after the exit, |β| never grows by > 1° between 0.05 s samples,
   no overshoot > 5° to the other side, `mini_window` open while |β| < 12°; the same for a 断位 exit.

3. **One 断位 (drift cut) permanently changes every later drift.** `drift.gd:105` sets
   `_cut_timer = DRIFT_CUT_TIME` (0.20 s); nothing ever counts it down (only `reset()` clears it),
   so `drift.gd:144` uses `DRIFT_CUT_LAMBDA` 5.2 instead of 2.0 for every drift until a respawn.
   Probe F (same input, steer −0.45): `drift 1 (fresh car): beta 32.3 deg` → after one cut
   `3 s later: cut_timer=0.20` → `drift 2 (after one cut): beta 16.7 deg` (outside 26–52°; the
   gauge drops with it).
   Do: count `_cut_timer` down in `update()` and clear it when a new drift starts.
   Verify (test_drift): drift, 断位, 3 s of grip, the same drift again → β within ±1° of the first.

4. **Hop and Big Hop are 0.7–1.8 m short at speed (downforce in the air).** `car_dynamics.gd:150`
   applies `−up × 2.3·v²` every tick, also with no wheel on the ground (dossier §4.7: the fan-car
   downforce, "kept modest for jumps" — a fan needs the ground under it). At 250 km/h that is +5.8 m/s² on top of the
   2 g air gravity. `test_hop`/`feel_report` only measure from a standstill, so they pass.
   Probe E (no throttle): hop 2.98 / 2.71 / 2.33 m and Big Hop 7.58 / **6.90 / 5.98 m** at
   0 / 150 / 250 km/h; probe D (player keys, W held, 120 km/h): hop 2.75 m, Big Hop 6.91 m.
   Dossier §5.3: Big Hop apex 7.8 m, clears a bus and (with hover) a gas-station canopy; §5.7:
   "Big Hop at 150 km/h spends 0.57 s (24 m) above 7 m" — today it does not at any racing speed.
   Do: scale the downforce by the grounded share (`grounded / 4.0`, 0 in the air).
   Verify: `test_hop` and `feel_report` measure hop and Big Hop at 0, 150 and 250 km/h (rows for
   each): hop 3.1 ± 0.3 m, Big Hop 7.8 ± 0.4 m at every speed; Big Hop at 150 km/h ≥ 0.5 s above
   7 m; touchdown still clean with W held (probe D shape).

5. **One barrel roll (or Big Hop) turns every later landing into "+15 N₂ TRICK".**
   `thruster.last_hop` and `thruster.roll_end_time` are cleared only in `thruster.reset()`
   (respawn; `thruster.gd:119, 134-135`), and `arcade_car.gd:280` calls `events.check_trick()` on
   every `landed` tick — outside the `LAND_AIRTIME_MIN` gate of line 277.
   Probe C (player car): roll + landing → `["trick+15"]` n2 145 (correct); then a plain hop with
   no roll → `["trick+15"]` n2 140 (want 125); then three 0.6 m drops (a road crest) →
   `["trick+15", "trick+15", "trick+15"]` n2 185. Free N₂ and a HUD pop-up on every bump.
   Do: evaluate the trick once per jump, only when `landing_airtime ≥ LAND_AIRTIME_MIN`; consume
   `last_hop` and `roll_end_time` on every landing (also a 1-tick one).
   Verify (test_rewards): roll + landing → 1 trick; then a plain hop → 0; three 0.6 m drops → 0
   and N₂ unchanged; a Big Hop → 1.

6. **The hero rear light bar: salmon-pink, and dark in the middle while driving** (SPEC pillar 1
   "full-width red rear light bar"; ART §2/§5; the user asked for refined textures everywhere).
   car_model re-exported the glb at 10:19 (after your shots at 10:10–10:15): `M_LightBarRear`
   and `M_BrakeLight` are both emissive strength **3.2**, white factor × emissive texture
   `lightbar_rear` (6 mm core (255,10,18) inside a 14 mm lens (110,4,8)); `Brake_Light`
   (x ±0.465, z max 2.095) sits 1 mm proud of `LightBar_Rear` (z max 2.094), i.e. it is the
   outer face of the middle 0.93 m of the 1.69 m bar. car_model tuned 3.2 so the bar stays red
   under AgX (status/car_model.md #4: at 3.6 it turns pink; 328 px R>180 & G<90 at 8.4 m).
   Your code: `roadster.tres:28 brake_light_idle = 8.0` (2.5× the authored level), braking 20;
   `car_lights.gd:46/78-80` keeps the box at **0** while driving and 10 while braking;
   `car_lights.gd:95` overwrites the authored emission colour with #FF1A2E.
   Measured (my night rear, `tl_rear.json`, `--rearcam`, `barscan.py`; probe A
   `idle: bar=8.00 box=0.00`, `braking: bar=20.00 box=10.00`):
   idle — the 5 middle segments peak (190,112,104) vs the ends (255,150,120): a visibly darker
   block (`captures/review/vehicle/r3_rear_bar_zoom.jpg`, top); **0** px with R>180 & G<90;
   braking — peak (255,167,147) pink-white, 10 saturated px, segments 4, 5 and 8 only 3–4
   red rows vs 15–18 at the ends). Refs `ref/roadster/img/19_rear_lightbar_night_driving.jpg`,
   `34_rear_lightbar_glow_wing.jpg`: a saturated #FF1A2E bar with a red halo
   (`r3_rear_idle_brake_vs_ref.jpg`).
   Do: (a) the box is bound like the bar: idle = its authored strength, braking = ratio × authored
   (delete `brake_only`; R2 7c "off otherwise" was right for the old glb, not for this one);
   (b) delete the `brake_light_idle = 8.0` override (idle = authored, read from the glb);
   (c) do not overwrite the emission colour (bar, box, NPC lamps) — change only the energy, the
   texture carries the core/lens detail; (d) choose `BRAKE_LIGHT_RATIO` in 1.5–2.5 so braking is
   clearly brighter while the halo stays red; (e) keep `emission_enabled` on and write the energy
   only when it changes (toggling the feature recompiles a shader variant → a hitch on the first
   brake of every car type; today every car rewrites up to 3 materials every physics tick).
   Verify: `tools/godot.sh drive --timeline=/Users/minimax/m/skyrush/tmp/review/veh3/tl_rear.json
   --scene=res://vehicle/demo/demo_car.tscn --shots=4.3,5.0 --out=veh_rear_r4 --rearcam`, then
   `python3 tmp/review/veh3/barscan.py captures/veh_rear_r4_t4_3.jpg 450 520 560 1040` (idle) and
   `… veh_rear_r4_t5_0.jpg 440 540 520 1080` (braking). Idle: every one of the 13 segments has
   peak R ≥ 200 and ≥ 2 red rows, and ≥ 400 px have R>180 & G<90 (now 0). Braking: red px
   (R>150 & R>G+60) ≥ 1.8 × idle, every segment has ≥ its idle red rows. Save the crops next to refs 19
   and 34 as `captures/veh_rear_r4_vs_ref.jpg`. test_visual: bar and box 3.2 → 3.2 × ratio → 3.2.

7. **Lead note 2 (mandatory): the AI-facing API is gone from the status.** The round-3 rewrite of
   `status/vehicle.md` dropped it (`grep -n "request_hop\|set_drift" status/vehicle.md` → nothing).
   Restore a section "AI-facing API": all 7 calls (`set_controls`, `set_drift`, `use_nitro`,
   `request_hop`, `request_roll`, `request_launch`, `get_n2`) with signature, N₂ cost,
   preconditions (launch: < 5 km/h, ≥ 3 wheels, throttle > `THROTTLE_ON`, N₂ ≥ 50; roll: airborne;
   hop: ≥ 2 wheels, 3 m clearance, cooldown) and the event each raises. Same rule in the header of
   `arcade_car.gd:21-22` (today it says only "needs half a tank").

8. **Evidence and status must be true (R1 #19, R2 #9 again).**
   a. "No logic file has a magic number left (MUST-FIX 8c)" — false, see 9c.
   b. Re-shoot after the fixes and name each file in the status with what it proves:
      `veh_rear_r4_*` + `veh_rear_r4_vs_ref.jpg` (item 6); for items 1–2 the β series (every
      0.05 s from the exit to +1.0 s, neutral release and counter-steer) printed by the new
      test_drift checks, pasted into the status (the drive CSV has no β);
      a Big Hop at 150 km/h with `--sidecam` at the apex (item 4, altitude in the overlay ≥ 7.4 m).
   c. Add every new measured number to `feel_report` (exit β at +0.35 s, apex at 150/250 km/h).

9. **Code and process rules (CONTRACTS §3, lead rules).**
   a. Outside owned paths: this round's session (`0e87808e…` in `jobs/vehicle/log.jsonl`) ran `rm -f game/.godot/imported/*.glb-*.scn
      game/.godot/imported/*.glb-*.md5 && tools/godot.sh import` — that wipes the imported glbs of
      every unit (city, landmarks, bund, props…) and forces a project-wide re-import in the single
      import slot that every `tools/godot.sh` call of every unit waits on. Never touch
      `game/.godot/`; for a stale import run `tools/godot.sh import` (core's import doctor) and
      write it under Requests.
   b. Scratch probes were written into `game/vehicle/tests/` (scratch goes to `tmp/vehicle/`) and
      left orphans: delete `game/vehicle/tests/probe_{glb,hop,launch,mat,lights}.gd.uid` and
      `game/vehicle/tuning/car_tuning.gd.uid`.
   c. Magic numbers (R1 18b, R2 8c — third time): `drive.gd:58` `forward_speed > 0.5` while
      `DriveTuning.BRAKE_SPEED_ON := 0.5` exists unused — use it; `car_visual.gd:228-229`
      0.28 / 0.1, `:243-244` `half.z * 0.8`, `:271/:273` 0.7, `:300` 0.9; `car_flight.gd:87` and
      `car_air.gd:186` `maxf(height, 0.1)`.
   d. Dead code: unused `LaneTuning.LANE_EXIT_MAX_TIME` and `VisualTuning.PLACEHOLDER_WHEEL_W`;
      `car_flight.gd:115-116` still claims "the Jolt space state ignores a query with the 'all
      layers' mask" — the claim you withdrew in R2 9a. Delete both.

## SHOULD-FIX
- Sky-lane glide touchdown (`car_flight.gd:101`): `landed` reports `thruster.airtime` after the
  contact tick has reset it — test_sky_lane log: `{"airtime": 0.0, "impact": 3.14, …}` after a
  15 m glide — and the quality is always `clean`. Report the glide time and judge the alignment
  like `car_air._on_landing()` (the HUD and a future "long airtime" stunt read it).
- One formula, one place: the cushion deceleration is written twice (`car_flight.gd:84-91`,
  `car_air.gd:181-189`) → one helper; `car_visual._ease()` and `sky_flight.gd:194` → the built-in
  `smoothstep(0.0, 1.0, t)`.
- Placeholder (`car_visual.gd:219-302`): `_library_material()` re-implements
  `MaterialLibrary.lookup()` — call the core API; `tyre.roughness = 0.9` would mutate a shared,
  cached library resource; the tyre is a plain untextured colour (ART §5) — use the library
  `assets/textures/Plastic006` (diff/nor_gl/rough) or the roadster tyre maps, with a normal map.
- `car_lights._apply()` (ShaderMaterial branch) sets three guessed uniform names; read
  `get_shader_uniform_list()` and set the real one (or none).
- Defaults that copy spec numbers (`wheel.gd:42-49` 1900 / 70000 / 4600 / 6300 / 300000 / 60000 /
  0.41 / 0.20, `drift.gd:48` 3200) → 0.0, set by `setup`; the `-100.0` sentinels
  (`car_events.gd:30`, `rewards.gd:13`) → `BodyTuning.TIME_NEVER`.
- `test_sky_lane.gd:76` calls `lane.frame_at(car.sky.offset)` past the lane end and prints
  `ERROR: The transform's origin and target can't be equal` (core `sky_lane.gd:43`): clamp the
  offset to `lane.length()` in the test (a passing test must not print engine errors).
- Headlights: the glb has `Light_Front` / `Light_Rear` markers and nobody lights the wet road in
  front of the player car; if the lead gives it to you, one shadowless SpotLight (#D9E8FF) at
  `Light_Front` and a small red OmniLight at `Light_Rear` that follows the brake level, player only.

## Verified OK
- `tools/godot.sh check --only=res://vehicle/modules/,…/tuning/,…/specs/,…/tests/,…/cars/,…/demo/`
  → `CHECK 77 files, 0 failed, 0 engine errors, 0 warnings`.
- All 26 tests: **386 checks, 0 failures** (batch logs `tmp/review/veh3/logs/test_*.log`).
- feel_report: 0-100 2.42 s; launch 0.81 s; top 250.0; N₂ 300.4; caps W 272.0 / C 300.0 / CW
  306.6 / WCW 308.8 / CWW 317.6 / WCWW 319.8; brake 27.4 m; drift β 26.4 / 32.2 / 47.4°, gauge
  104 N₂ at 32°; hop 2.98 m / Big Hop 7.58 m (standstill — see MUST-FIX 4); roll 360° in 0.70 s;
  landing drift 0.000 m; 300 km/h roll 2.3°; lane 7.27 m; charge 200 N₂ / 1.00; CPU **44 µs**
  (`_integrate_forces`) + 49 µs (frame) per tick (budget 250).
- R2 items closed: 1 (nitro key at speed = nitro; launch only from a standstill — my main.tscn
  run: nitro tap at 110 km/h → `boost=nitro`, 299 km/h, ends after 3.0 s, N₂ 100 → 0), 2 (probe D,
  player keys, W held: hop and Big Hop touch down at 0.0° pitch, `clean`), 3 (test_heading
  1.272 g at every heading), 4 (test_suspension, all 12 presets; worker sheet: tyres in the
  arches), 5a–d (bank 31.5° into the move, one `landed` at 0.05 m / 3.1 m/s, 落地喷 window,
  `boost_ended` at +3.000 s in the lane), 6 (no toast left in `game/vehicle`, trick as a stunt),
  7a (no `set_instance_shader_parameter` on a material), 8a/8b, the tuning split (12 files ≤ 148
  lines), every file ≤ 318 lines, static typing everywhere (no untyped var/param/return found).
- Lead notes: V-INT1 satisfied (road and lane); note 1 (test_menu_input) and note 3 (test_rewards,
  R2 probe) satisfied; note 2 satisfied in `arcade_car.gd` only (MUST-FIX 7).
- Left/right symmetry: probe D drift right and left → β 32.2° both, 104 N₂ both.
- motor_load returns to 0 when coasting and braking (probe A).
- main.tscn with the real units: the player car drives (216 km/h at 4.5 s, 299 km/h on the
  nitro), **0** errors from `res://vehicle/` (82 rendering `uniform_set` errors + world warnings
  belong to other units). No background Godot runs in this round's job log; `tmp/vehicle/` gone.

## Evidence
- `tools/godot.sh check …` → `CHECK 77 files, 0 failed, 0 engine errors, 0 warnings`.
- `tmp/review/veh3/run_tests.sh <tests>` (= `tools/godot.sh test` per test) → 26 × `RESULT n checks,
  0 failures`; `tools/godot.sh test res://vehicle/tests/feel_report.gd` → table above.
- Probe A: `neutral t+5s state=drift beta=35.8 yaw=-1.30 speed=243 turned=374 deg`, `left the
  drift after -1.00 s`; `counter left the drift after 0.28 s`; `lights braking: bar=20.00
  box=10.00`, `idle: bar=8.00 box=0.00`. Probe B: the β series of MUST-FIX 2. Probe C: the stunt
  lists of MUST-FIX 5. Probe D: `hop (W held): apex 2.75 m … touchdown pitch -0.0, clean`,
  `big hop (W held): apex 6.91 m`. Probe E: the apex table of MUST-FIX 4. Probe F: β 32.3 → 16.7°.
- `tools/godot.sh drive --timeline=…/tl_main.json --scene=res://main.tscn --skip-menu --debug
  --shots=4.5,7.2,10.8 --log=…/main.csv` → `drift` from 6.8 s to 12.0 s with the keys released at
  7.6 s; `captures/review/vehicle/r3_main_sheet.jpg`.
- `tools/godot.sh drive --timeline=…/tl_rear.json --scene=res://vehicle/demo/demo_car.tscn
  --shots=4.3,5.0 --rearcam` → `review_vehicle_r3_rear_t4_3.jpg` (idle, 70 km/h coasting),
  `_t5_0.jpg` (braking); `r3_rear_idle_brake_vs_ref.jpg` (vs refs 34, 19), `r3_rear_bar_zoom.jpg`;
  barscan output quoted in MUST-FIX 6.
- `tl_drift_exit.json` in demo_car → `r3_drift_exit_sheet.jpg` + `drift_exit.csv` (the chase
  camera turns with the car, so use the CSV/β numbers, not the picture, for the slip).
- Worker evidence reviewed: `captures/review/vehicle/r3_worker_sheet_a.jpg`, `_b.jpg`.
- glb JSON (`tmp/review/veh3/glb_mats.py`, `glb_nodes.py`): the light materials and boxes quoted
  in MUST-FIX 6.

## Notes for the lead (other units, not counted against vehicle)
- car_model: the canopy still reads as a see-through block of brown/grey squares from behind
  (`r3_rear_bar_zoom.jpg`, top centre), not the black arrowhead canopy.
- Nobody owns real head/tail lights at `Light_Front`/`Light_Rear` (see the last SHOULD-FIX).
- audio maps a stunt `&"airtime"` (voice 超长滞空！) that no unit emits (SPEC §3 "long airtime").
- core: `SkyLane.frame_at()` errors for an offset > length + 2 m; clamping there would be safer.
