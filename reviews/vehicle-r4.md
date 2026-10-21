# vehicle review round 4 — VERDICT: FAIL

Reviewer: lead/art director (Opus), 2026-10-20 (last round). Every number below was measured by me
on the current files (`roadster.glb` of 13:17: `M_LightBarRear` strength 10, `M_BrakeLight` 2.5).
Probes (Node tests): `tmp/review/veh4/probe_g.gd`, `probe_h.gd`, run with
`tools/godot.sh test /Users/minimax/m/skyrush/tmp/review/veh4/probe_h.gd`; logs `tmp/review/veh4/logs/`;
meters `tmp/review/veh3/barscan.py`, `tmp/review/veh4/pinkscan.py`; sheets `tmp/review/veh4/sheet.py`.

## Scores (0-10)
- function: **7** — R3's nine MUST-FIX items are really fixed (441/441 checks; in main.tscn the
  released drift goes drift → recover → grip in 0.6 s and the car drives on straight; hop 2.93 m).
  One new regression from R3 #2: a hop or Big Hop during a drift (or ≤ 0.37 s after the release)
  is pulled down by the drift assist — 1.21 m / 2.27 m instead of 3.1 / 7.8 m, for 25 / 50 N₂.
- visual/feel: **5** — the bar is full width with no dark hole and the drift exit feels right, but
  the new headlight (energy 80) burns anything 9–12 m ahead to white, braking turns the hero bar
  pink-white (pink-white px 400 → 1,700) and the tail lamp burns a hot spot into the white panel.
- code: **8** — static typing everywhere, ≤ 367 lines per file, the R3 magic numbers, dead constants,
  orphan `.uid` files and the stale Jolt comment are gone; left: false "authored at 3.2" comments,
  placeholder tangents, one spec-number default, scratch copied to `/tmp`.

## MUST-FIX
Order 1 → 2 → 3. Re-run all tests + feel_report and re-shoot the evidence named in each item.

1. **A hop in a drift is 60–70 % short (regression of R3 #2, the shared drift/recover apply path).**
   `car_dynamics.gd:257-268` applies the drift/recover yaw torque and the velocity-steering assist
   (ceiling 200 m/s² drift, 300 m/s² recover) with no wheel on the ground, and the direction
   `to_nose = fwd − v̂·(fwd·v̂)` is 3-D: after the hop impulse v.y = +11…18 m/s, so ≈ 31 % of the
   assist points DOWN (β 30°, 200 km/h). At take-off the drift is lost (`drift.gd:186`) → RECOVER
   at up to 300 m/s². Probe H (200 km/h, drift held 1.5 s, then the hop; vy/state/assist per 0.05 s):
   Big Hop `17.9/drift/104 14.8/recover/300 10.3/recover/300 6.2/recover/220 3.3/recover/162` →
   apex **2.27 m** (straight: 7.69 m); hop `10.4/drift/101 7.8/recover/300 4.8/recover/274
   2.4/recover/200` → apex **1.21 m** (straight: 2.93 m). Probe G: the hop 0.05 s / 0.30 s after
   the release (state still `drift`) → **0.91 / 0.93 m**; 0.60 s after (recover, β small) → 2.90 m.
   Dossier §5.3: "tap hop while ≥ 2 wheels grounded … apex 3.1 m" — no drift exception; Space with
   Shift held is the natural move over traffic in a corner, and a drift off a ramp or a crest is
   pulled down the same way. The API charges the full N₂ for the short hop.
   Do: (a) build the assist in the ground plane: `v_flat = velocity − up * velocity.dot(up)`,
   `to_nose` from `v_flat` and `fwd` projected on that plane — never a component along `up`;
   (b) scale the drift/recover yaw torque and the assist by the grounded share
   `grounded / wheels.size()` (0 in the air), the same rule as the R3 #4 downforce fix; the air yaw
   stays with `car_air._apply_air_control`.
   Verify: `tools/godot.sh test /Users/minimax/m/skyrush/tmp/review/veh4/probe_g.gd` and `probe_h.gd`:
   the hop in a held drift and at +0.05 / +0.30 s after the release **3.1 ± 0.3 m**, the Big Hop in a
   held drift **7.8 ± 0.4 m**, touchdown `clean`, |roll| < 5°. Copy the cases into `test_hop.gd` and add
   feel_report rows "hop from a drift (200 km/h)" and "Big Hop from a drift"; the test_drift β series
   must stay as today (counter +0.35 s ≤ 12°, +0.60 s ≤ 5°, no overshoot > 5°).

2. **The headlight blows out everything 5–20 m in front of the car (new this round; ART §2, §10.6).**
   `VisualTuning.HEADLIGHT_ENERGY` 80, `HEADLIGHT_RANGE` 55, `HEADLIGHT_ANGLE` 42, aimed level from
   `Light_Front` (0, 0.44, −2.3). My sandbox shot (spawn 265,0.2,−90,0; the parked row 9–11 m ahead,
   mid-blue boxes, HSV value 0.7): the lit faces render white-lavender with bloom — **12,652
   near-white px, 795 fully clipped** (`captures/review_vehicle_r4_head_behind.jpg`, `_side.jpg`, sheet
   `captures/review/vehicle/r4_headlight.jpg`). A white traffic car, rival or police car ahead of the
   player becomes the brightest object in frame, above the player's own bar and plumes (ART §2 tier 4
   belongs to them); the near-road pool in front of the nose also clips
   (`review_vehicle_r4_static_front34.jpg`, 937 clipped px in the lower half).
   Do: energy **80 → 8** (tune 6–10), `spot_angle` **42 → 28°**, `spot_angle_attenuation` **2.0**
   (a soft edge), pitch the spot **4° down** (rotate the light about its local X) so the beam lands
   8–35 m ahead, range **55 → 40 m**, colour stays `#D9E8FF`; every value in `visual_tuning.gd`.
   Verify: `tools/godot.sh shot --scene=res://vehicle/demo/demo_car.tscn --spawn=265,0.2,-90,0
   --out=veh_head_r5 --warm=90 --cams="behind:266.5,2.6,-80.5:265,0.8,-100:55;side:276,1.6,-93:263,0.8,-97:55"`
   → **0** px with all three channels ≥ 250 and the boxes keep their blue hue; in main.tscn (the static
   cam `road` of the Evidence) the pool still reads on the wet road ahead; test_visual checks the four
   headlight values on the built `SpotLight3D`.

3. **Braking turns the hero bar pink-white and the tail lamp burns a hot spot (R3 #6d: "the halo
   stays red"; SPEC pillar 1, ART §3 light bar `#FF1A2E`).** My `tl_rear.json --rearcam` shots,
   `python3 tmp/review/veh4/pinkscan.py <jpg> y0 y1 520 1080` (rows ±50 px around the bar):
   idle `review_vehicle_r4_rear_t4_3.jpg` (440 540): pink-white (R>240 & G>140) **400**, deep red
   (R>180 & G<90) **406**, per 40-px column `[0,4,77,80,36,0,0,0,0,36,80,85,2,0]`;
   braking `_t5_0.jpg` (470 570): pink-white **1,700**, deep red **197**,
   `[11,149,157,131,53,54,282,276,49,46,164,160,156,12]`. Two causes:
   (a) the centre columns (x 760–840, 558 px) are the `TailLamp` OmniLight: it sits at `Light_Rear`
   (0, 0.85, 2.10), 6 mm behind the bar face (z 2.094), so the white panel right above the bar gets a
   point-blank light and renders (254,179,174) at x 800, y 511;
   (b) the outer bar, authored 10, × `BRAKE_LIGHT_RATIO` 2.0 = 20 → ends (255,186,180). The middle
   `Brake_Light` box (2.5 → 5) stays red (columns 4, 5, 8, 9: 46–54 px).
   Sheet: `captures/review/vehicle/r4_rear_vs_ref.jpg` — refs 19 and 34 show a deep red bar and a red
   glow on the ground, not a pink core.
   Do: (a) move the tail lamp off the panel: `Light_Rear` + (0, −0.30, +0.40) (behind and below the
   bar) so it lights the road and the diffuser — the red ground glow of ref 34 — energy ≤ 0.8, range
   3.5 m; (b) split the flare: `BRAKE_BAR_RATIO` **1.25** for `LightBar_Rear`, `BRAKE_BOX_RATIO`
   **2.4** for `Brake_Light` (2.5 → 6.0 stays red under AgX); (c) the comments that say the bar is
   "authored at 3.2" (`car_lights.gd:7`, `visual_tuning.gd:28-30`) are false (the glb says 10), and
   the status line "the halo is red" for `veh_rear_r4_t5_0.jpg` is false today — correct both.
   Verify: re-shoot `tools/godot.sh drive --timeline=/Users/minimax/m/skyrush/tmp/review/veh3/tl_rear.json
   --scene=res://vehicle/demo/demo_car.tscn --shots=4.3,5.0 --out=veh_rear_r5 --rearcam`, then pinkscan
   (rows ±50 px around the bar in each shot): braking pink-white **≤ 600** (now 1,700) with no 40-px
   column > 160 (now 282), braking deep red **≥ 350** (now 197; idle 406), braking red px ≥ 1.8 × idle
   (now 8,145 / 1,916 — keep); barscan: every segment ≥ its idle red rows; test_visual: the bar
   10 → 12.5 → 10, the box 2.5 → 6 → 2.5; save the crops next to refs 19 and 34 as
   `captures/veh_rear_r5_vs_ref.jpg`.

## SHOULD-FIX
- Placeholder normal maps: `car_visual._wheel_mesh()` rotates `ARRAY_VERTEX` and `ARRAY_NORMAL` of the
  CylinderMesh but not `ARRAY_TANGENT`, so the new Plastic006 normal map shades with a tangent frame
  90° off; `_wedge_mesh()` commits without tangents (call `st.generate_tangents()` before `commit()`)
  while the library paint uses a normal/flake map. Check with a placeholder shot (a test spec whose
  visual path is missing): the tyre and the body light from the same side.
- Leftover literals: `wheel.gd:15 var radius: float = 0.36` copies a spec number (R3 asked for 0.0,
  set by `setup`); `drift.gd:72 maxf(absf(v_fwd), 1.0)` and `drift.gd:186 grounded < 2` → named
  constants in `drift_tuning.gd`; `car_events.gd` `thruster.roll_end_time = -1.0` →
  `BodyTuning.TIME_NEVER` (the other sentinels already use it).
- `test_drift.gd:86` `maxf(car.boost.mini_window, car.telemetry.mini_window)` mixes a float with a
  bool, so the log prints "= 1.00 s" for "open"; print the seconds left of the window.
- `test_ai_api` and `feel_report` print `WARNING: Jolt Physics job system exceeded the maximum number
  of jobs` (my run); free the cars of a finished case before the next spawn and keep the count of
  live cars per test small.
- Hygiene: the session copied `feel_report.gd` to `/tmp/fr_backup.gd` (scratch belongs in
  `tmp/vehicle/`; it was deleted afterwards); `tmp/vehicle/rear_sheet.py` and `run_tests.sh` are left
  (the logs may stay as evidence).

## Verified OK
- `tools/godot.sh check --only=res://vehicle/` → `CHECK 108 files, 0 failed, 0 engine errors, 0 warnings`.
- All 26 tests: **441 checks, 0 failures** (`tmp/review/veh4/run_tests.sh`, logs `tmp/review/veh4/logs/`).
- feel_report: 0-100 2.42 s; launch 0.81 s; top 250.0; N₂ 300.4; caps W 272.0 / C 300.0 / CW 306.6 /
  WCW 308.8 / CWW 317.6 / WCWW 319.8; brake 27.5 m; drift β 26.4 / 32.2 / 47.4°, gauge 104 N₂ at 32°;
  exit counter 0.28 s / release 0.37 s, β at +0.35 s 0.4 / 0.0°, at +0.60 s 0.4 / 0.1°; hop 2.98 /
  2.98 / 2.96 m and Big Hop 7.77 / 7.74 / 7.68 m at 0 / 150 / 250 km/h, 0.55 / 0.53 s above 7 m; roll
  360° in 0.70 s; landing drift 0.000 m; 300 km/h roll 2.3°; lane 7.27 m; charge 200 N₂ / 1.00;
  CPU **41 µs** forces + 47 µs frame per tick (budget 250).
- R3 #1 in the real game (my main.tscn run, keys released at 7.6 s): `drift` 7.65 s → `recover`
  7.85 s → `grip` 8.25 s, then a straight line x −60 → −157, z 47 → 118 at 188–203 km/h (no circle);
  run 2 (no crash): `recover` 8.1 s, `grip` 8.5 s, then x −70 → −209 with z 96.7 → 99.7 at 250 km/h.
- R3 #2/#3: the β series match the status (counter 20.9 → 0.4° at +0.35 s, release 0.0°, cut 2.5° →
  0.4°, overshoot ≥ −0.4°); a drift after a cut 32.24° vs 32.19°.
- R3 #4: main.tscn hop at 197 km/h: y −0.05 → 2.93 m (run 2 at 250 km/h: 3.04 m), airtime ≈ 1.0 s;
  probe G: a straight hop at 200 km/h rolls 0.0°, with full steer 3.8°, touchdowns `clean`.
- R3 #5: test_rewards (Big Hop → 1 trick, plain hop → 0, three 0.6 m drops → 0 and N₂ unchanged,
  roll → 1).
- R3 #6 (idle part): full-width bar, all 13 segments peak R ≥ 249 with ≥ 2 red rows, 406 deep-red px
  (≥ 400), no dark hole; the box is bound like the bar, the colour is never written, the energy is
  written only on a change, `emission_enabled` stays on. Braking = MUST-FIX 3.
- R3 #7: the AI-facing API (7 calls, costs, preconditions, events) in the status and in the header of
  `arcade_car.gd`. R3 #8/#9: evidence named per file; orphan `.uid`, dead constants and the stale Jolt
  comment gone; the round's job log shows every write inside `game/vehicle/**` + `status/vehicle.md`,
  no `game/.godot/` command, no background run.
- R3 SHOULD-FIX: glide time 1.81 s and judged quality (test_sky_lane); one cushion helper
  (`car_cushion.gd`); `smoothstep`; `MaterialLibrary.lookup()` + Plastic006 tyre; the shader uniform
  list; `TIME_NEVER`; the lane offset clamp (no engine error); headlight + tail lamp built (their tuning
  = MUST-FIX 2/3).
- Lead notes: V-INT1 (main: nitro tap at 3.0 s, `boost=nitro` to 298 km/h, ended by 6.6 s); note 1
  (test_menu_input 6/6); note 2 (above); note 3 (main: second takedown "+75 连击 x2", N₂ 39 → 115).
- NPC presets: the lineup loads every glb (no placeholder), police light bars lit, tyres on the
  ground (`captures/review/vehicle/r4_presets.jpg`).
- Code: static types on every var/param/return; largest file `car_visual.gd` 367 lines; tuning split
  over 13 files; 0 errors from `res://vehicle/` in main.tscn (run 2: `DRIVE done errors=0`) and in the
  demo runs.

## Evidence
- `tools/godot.sh check --only=res://vehicle/` (above); `tmp/review/veh4/run_tests.sh <26 tests> feel_report`.
- Probes: `probe_g.gd` (`straight 200: apex 2.93 m, max roll 0.0`; `drift exit +0.05: apex 0.91 m`;
  `+0.30: 0.93 m`; `+0.60: 2.90 m`; `in drift (held): 1.21 m`), `probe_h.gd` (`BIG straight 200: apex
  7.69 m`; `BIG in drift (held): apex 2.27 m`, vy traces quoted in MUST-FIX 1).
- `tools/godot.sh drive --timeline=/Users/minimax/m/skyrush/tmp/review/veh3/tl_rear.json
  --scene=res://vehicle/demo/demo_car.tscn --shots=4.3,5.0 --out=review_vehicle_r4_rear --rearcam`
  → barscan idle (450 520 560 1040) `red 1916 | saturated 406`, braking (440 540 520 1080) `red 7524 |
  saturated 110`; pinkscan numbers in MUST-FIX 3; sheet `captures/review/vehicle/r4_rear_vs_ref.jpg`.
- `tools/godot.sh drive --timeline=/Users/minimax/m/skyrush/tmp/review/veh3/tl_main.json --scene=res://main.tscn
  --skip-menu --debug --shots=2.0,4.5,7.2,8.6,10.8 --out=review_vehicle_r4_main
  --log=/Users/minimax/m/skyrush/tmp/review/veh4/main.csv` (run 2: `--out=review_vehicle_r4_main2`,
  `main2.csv`, log `tmp/review/veh4/logs/main2.log`) → sheets
  `captures/review/vehicle/r4_main_sheet_s.jpg`, `r4_main_crops.jpg` (a crash into traffic at 6.9 s and
  a respawn at 7.45 s are other units' game play; the vehicle part is quoted above).
- `tools/godot.sh shot --scene=res://main.tscn --skip-menu --env-only --out=review_vehicle_r4_static
  --warm=90 --cams="front34:-116.17,1.3,-245.76:-114.44,0.6,-250.89:50;rear34:-113.07,1.2,-255.40:
  -114.44,0.6,-250.89:50;wheel:-116.22,0.59,-248.33:-114.83,0.34,-249.33:40;road:-116.0,3.0,-256.69:
  -110.54,0.0,-236.4:62"` → `captures/review/vehicle/r4_static_sheet.jpg`, `r4_static_zoom.jpg`.
- Headlight: the shot command of MUST-FIX 2 with `--out=review_vehicle_r4_head`.
- Presets: `tools/godot.sh shot --scene=res://vehicle/demo/preset_lineup.tscn --out=review_vehicle_r4_presets
  --warm=120 --cams="front:0,4,-22:0,1,4:60;rear:0,4,30:0,1,0:60"`.
- glb: `python3 tmp/review/veh3/glb_mats.py` / `glb_nodes.py game/assets/cars/roadster/roadster.glb`
  (bar 10, box 2.5, `Light_Rear` (0, 0.85, 2.1), bar face z 2.094).

## Notes for the lead (other units; not counted against vehicle)
- car_model: `M_LightBarRear` authored at 10 → the idle bar core is salmon (255,110,99) under AgX (ref
  `#FF1A2E`); at ≤ 3.2 it stays red (their own status). Close up (`r4_static_sheet.jpg`, "wheel FR")
  the body shows flat-shaded facets and an olive cast at 1.5 m, and the canopy still reads as a
  see-through block of brown squares from behind (`r4_rear_vs_ref.jpg`).
- fx: `fx/fx_car_rig.gd:179` raises a typed-array error every physics tick in main.tscn, and the
  file (edited 13:29) prints `DBG pp vehicle=…` every tick.
- ai/rivals: `ai/rivals/rival_avoid.gd:74` parse error ("distance" not declared) → `rival_car.gd`
  fails to compile in main.tscn.
- Unverified: in main.tscn a white glare sits on the player's rear panel at the spawn (static
  `rear34`, ≈ 980 near-white px); the sandbox shows none, so it comes from the world (a traffic
  headlight or a lamp reflection) — whoever owns the traffic lamps should check their spot range.
