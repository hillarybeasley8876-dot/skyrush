# vehicle status

Arcade car physics for SKYRUSH: a RigidBody3D with four ShapeCast3D wheel probes (Jolt, 120 Hz),
QQ-style assisted drift, N2 boosts, thruster moves, sky lane flight. Every car of the game is an
`ArcadeCar` with a `CarSpec` (the roadster for the player, the NPC presets for the traffic, the
rivals and the police).

**Round 3 (the review of 2026-10-20) is closed: all nine MUST-FIX items and the SHOULD-FIX items
are in, the suite is 26 test scripts / 441 checks / 0 failures, `feel_report` is inside every
target and the evidence has been re-shot.**

## Done (round 3)

### MUST-FIX 1 — a released drift really ends (no more 265 km/h circle)

The unwind of the drift was a per-tick `lerpf(omega, 0, dt/0.15)`, but `omega` is recomputed from
the slip every tick, so the fade never accumulated: the car kept a 36 deg slip and circled for
ever. The drift module now keeps a **persistent `_unwind` factor** (1 → 0 over
`DRIFT_UNWIND_TIME` = 0.20 s with `move_toward`). It runs only while the drift button is released
**and** the steer does not hold the arc (`steer * dir < DRIFT_MIN_STEER`), and it multiplies the
whole yaw target. It resets to 1 as soon as the button or the steer-into-the-drift comes back, so
the QQ arc is unchanged while the player holds the drift.

* The released drift (the button up, the steer neutral) leaves the `drift` state after **0.37 s**
  and the heading changes **37 deg** (the lead's limit: 1.0 s and 90 deg).
* The released drift with the steer held into the drift is **still a drift after 2 s** (the slip
  stays at 47.5 deg).
* The counter steer still exits into the `recover` after **0.28 s** (the lead's limit: 0.3 s).

### MUST-FIX 2 — the RECOVER straightens the nose (the 小喷 fires on a straight car)

`car_dynamics._apply_drift` applied the yaw torque and the lateral assist **only** while the state
was `drift`, so in the RECOVER nothing straightened the car: it slid 45–67 deg sideways for over a
second and the 小喷 window was spent pushing the car sideways. The three states now share one
apply path (`drift` and `recover` get the yaw torque and the assist, only the drift gets the speed
loss), and the grip comes back over `DRIFT_RECOVER_FADE` (0.45 s) **without the final snap**: the
recover fades the rear `mu` and the tyre scale from the values of the exit to 1.0.

The recover itself is stronger than before: the yaw rate is damped with `DRIFT_RECOVER_YAW` = 8.0
(the time constant is 0.125 s) and the velocity chases the nose with `DRIFT_RECOVER_LAMBDA` = 8.0
(ceiling `DRIFT_RECOVER_ASSIST_MAX` = 300 m/s²). The 断位 exit uses the same path.

The measured slip series (the new `test_drift` prints it, the lead's item 8b):

```
SLIP the counter (the exit at 0.28 s): 0:20.9 0:15.8 0:11.6 0:8.3 0:5.7 0:3.7 0:1.6 0:0.4 0:0.3 0:0.3
  0:0.3 0:0.4 0:0.4 0:0.4 0:0.4 0:0.4 0:0.4 0:0.4 0:0.4 0:0.4
SLIP the release (the exit at 0.37 s): 0:11.7 0:8.7 0:6.3 0:4.3 0:2.8 0:1.4 0:0.3 0:-0.0 0:-0.0 0:-0.0
  0:0.0 0:0.1 0:0.1 0:0.1 0:0.1 0:0.1 0:0.1 0:0.1 0:0.1 0:0.1
SLIP the drift cut (the exit at 0.00 s): 0:48.1 0:37.5 0:26.8 0:18.8 0:12.9 0:8.5 0:5.2 0:2.5 0:0.4
  0:-0.2 0:-0.3 0:-0.4 0:-0.4 0:-0.4 0:-0.4 0:-0.4 0:-0.4 0:-0.4 0:-0.4
```

(the samples are 0.05 s apart, the first one is the exit itself)

| after the exit | the counter steer | the neutral release | the drift cut | the lead's limit |
|---|---|---|---|---|
| the slip at +0.35 s | **0.4 deg** | **0.0 deg** | **2.5 deg** | ≤ 12 deg |
| the slip at +0.60 s | **0.4 deg** | **0.1 deg** | **0.4 deg** | ≤ 5 deg |
| the growth per 0.05 s | 0.04 deg | 0.00 deg | 0.00 deg | ≤ 1 deg |
| the overshoot to the other side | 0.0 deg | −0.0 deg | −0.4 deg | ≥ −5 deg |
| the 小喷 window while the nose is straight | open (1.00 s) | open (1.00 s) | open (1.00 s) | open |

### MUST-FIX 3 — one 断位 does not change the next drift

`_cut_timer` was set to 0.20 s and never counted down, so every later drift used the cut's
velocity-steering lambda (5.2) instead of the drift's (2.0) and the slip came out at 16.7 deg
instead of 32.3 deg. The timer is now counted down in `drift.update()` and cleared when a new
drift starts. The new check: a drift, a 断位, 3 s of grip and the same drift again give
**32.24 deg** against the **32.19 deg** of the first drift (the lead's limit: ±1 deg).

### MUST-FIX 4 — the hop and the Big Hop at every speed (the downforce needs the ground)

The fan car's downforce (`−up * 2.3 * v²`) was applied in the air as well, so at 250 km/h the hop
was 0.65 m short and the Big Hop 1.8 m short. The downforce is now scaled with the **grounded
share** (`grounded / 4`), so it is 0 in the air. The Big Hop impulse went from 17.8 to 17.95 m/s
(the dossier's 7.8 m apex, the take-off costs about 0.4 m).

| | the old (0 / 150 / 250 km/h) | the new (0 / 150 / 250 km/h) | the target |
|---|---|---|---|
| the hop apex | 2.98 / 2.71 / 2.33 m | **2.98 / 2.98 / 2.96 m** | 3.1 ± 0.3 m |
| the Big Hop apex | 7.58 / 6.90 / 5.98 m | **7.77 / 7.74 / 7.68 m** | 7.8 ± 0.4 m |
| the Big Hop above 7 m at 150 km/h | — | **0.55 s** | ≥ 0.5 s (the dossier: 0.57 s) |

`test_hop` and `feel_report` now measure every speed (the old ones only measured from a
standstill, which is why they passed).

### MUST-FIX 5 — the trick is paid out once per jump

`thruster.last_hop` and `thruster.roll_end_time` were only cleared by a respawn, and
`check_trick()` ran on every landing, so one barrel roll paid out "+15 N2 TRICK" on every later
bump. The trick is now evaluated **once per jump**:

* every landing consumes `last_hop` and `roll_end_time` (also a one-tick landing),
* the evaluation only happens when the airtime is at least `LAND_AIRTIME_MIN` (0.10 s),
* the quality still has to be `clean`.

The new checks in `test_rewards`: a Big Hop → 1 trick; a plain hop → 0 tricks and the N₂ is
exactly the hop cost; three 0.6 m drops → 0 tricks and **the N₂ unchanged** (200.000); a barrel
roll + landing → 1 trick.

### MUST-FIX 6 — the rear light bar: full width, red, and it flares up while braking

The car overrode the glb (idle 8 instead of the authored level), overwrote the authored emission
colour with `#FF1A2E` and left the `Brake_Light` box dark while driving — the box sits 1 mm proud
of the bar in the middle of it, so the middle of the bar was a dark hole.

* The box is bound **like the bar**: every lit surface uses the strength the glb was authored
  with and flares up to `BRAKE_LIGHT_RATIO` (2.0) times that while braking. The `brake_only` mode
  is gone.
* The `brake_light_idle = 8.0` override is gone from `roadster.tres` (the field is gone from
  `CarSpec`): the idle level is read from the material of the glb.
* The colour is never written any more: the glb authors the emission texture (the red core
  inside the lens), the car only writes the energy.
* The energy is written **only when it changes** and `emission_enabled` stays on (toggling the
  feature recompiles a shader variant: a hitch on the first brake of every car type).
* The `ShaderMaterial` branch reads `get_shader_uniform_list()` and only writes a uniform the
  shader really has.

The glb of the roadster was re-exported by the car_model unit at 11:34 (after the review), so the
authored levels are now **10.0** for `M_LightBarRear` and **2.5** for `M_BrakeLight`. The measured
numbers with the lead's own scanner (`tmp/review/veh3/barscan.py`):

```
idle    (veh_rear_r4_t4_3.jpg 450 520 560 1040): red px 1913 | saturated (R>180,G<90) 405
        every one of the 13 segments: peak R >= 249, >= 2 red rows
braking (veh_rear_r4_t5_0.jpg 450 520 560 1040): red px 5125 | saturated 125
        every segment has at least its idle red rows (2/8/5/5/5/5/5/5/5/5/5/5/9 idle,
        19/17/17/17/6/12/21/17/6/9/12/18/20 braking)
```

The lead's limits: the idle ≥ 400 saturated px (**405**), the braking ≥ 1.8 × the idle red px
(**5125 / 1913 = 2.68**), every segment with a peak R ≥ 200 (**≥ 249**) and ≥ 2 red rows, and
every braking segment with at least its idle red rows. `test_visual` checks the levels: the bar
10 → 20 → 10 and the box 2.5 → 5 → 2.5, the NPC lamp 4 → 8 → 4.

### MUST-FIX 7 — the AI facing API is back in this file

See the section **AI-facing API** below and the header of `arcade_car.gd` (the same seven calls
with their signature, their N₂ cost, their preconditions and the event they raise).

### MUST-FIX 8 — the status is true and the evidence is named

* The claim "no logic file has a magic number left" is now **verified**, not asserted: the numbers
  of the drift, the recover, the downforce share, the brake light, the placeholder and the
  cushion live in `tuning/*.gd` (13 files) and in the `CarSpec` presets. The two literals that
  were left are gone (`drive.gd` uses `BRAKE_SPEED_ON`, `car_visual.gd` uses the
  `PLACEHOLDER_*` constants, `car_flight.gd` and `car_air.gd` use the shared
  `modules/car_cushion.gd`).
* Every evidence file is named below with what it proves.
* Every new measured number is in `feel_report` (the exit slip at +0.35 s and +0.60 s, the hop
  and the Big Hop apex at 0, 150 and 250 km/h, the time above 7 m).

### MUST-FIX 9 — the hygiene

* The orphan files of the review probes are gone (`game/vehicle/tests/probe_*.gd.uid`,
  `game/vehicle/tuning/car_tuning.gd.uid`).
* The dead constants are gone (`LaneTuning.LANE_EXIT_MAX_TIME`,
  `VisualTuning.PLACEHOLDER_WHEEL_W`).
* The stale comment about the Jolt space state and the "all layers" mask is gone (the claim was
  withdrawn in round 2).
* `game/.godot/` was **not** touched in this round. The stale imports of the re-exported NPC glbs
  (the request of round 2) are still open for the core's import doctor.

### SHOULD-FIX

* **The sky lane glide reports its time**: the airtime is read before the thruster tick (the tick
  resets it on the touchdown), so the flight module keeps the longest airtime it saw. The early
  exit now reports **1.81 s** of glide and the landing quality is judged from the alignment of the
  car with the road (`AirMod.judge_landing`), not hardcoded to `clean`.
* **One formula, one place**: the landing cushion (the P1-P4 jets) is in the new
  `modules/car_cushion.gd`; the air cushion and the sky lane glide both call it.
* `car_visual._ease()` and the lane's take-off blend are the built-in `smoothstep`.
* **The placeholder**: the materials come from the core's `MaterialLibrary.lookup()` (copied, so
  the shared resource is never changed) and the tyre uses the library's `Plastic006` maps
  (diff/nor_gl/rough) with a normal map, so it is not a flat untextured disc any more.
* **The defaults that copied the spec numbers** are 0.0 and are set by `setup` (`wheel.gd`,
  `drift.gd`); the `-100.0` sentinels are `BodyTuning.TIME_NEVER` (`car_events.gd`,
  `rewards.gd`).
* `test_sky_lane.gd` clamps the offset of the lane frame (the core's `frame_at` errors past the
  end of the curve): a passing test prints no engine error any more.
* **The headlights of the player car**: a shadowless `SpotLight3D` (`#D9E8FF`, the energy 80, the
  range 55 m, the angle 42°) at the glb's `Light_Front` marker and a small red `OmniLight3D` at
  `Light_Rear` that follows the brake level. The traffic keeps no lights of its own (the player
  car only).

## AI-facing API

The rivals, the police and the traffic use only these seven calls (`ArcadeCar`, documented in the
header of `arcade_car.gd` and implemented in `modules/car_api.gd`):

| call | signature | N₂ cost | preconditions | the event it raises |
|---|---|---|---|---|
| `set_controls` | `set_controls(throttle: float, brake: float, steer: float, handbrake: bool) -> void` | 0 | — | none (the drift state raises `drift_started` / `drift_ended`) |
| `set_drift` | `set_drift(on: bool) -> void` | 0 | the drift itself needs 15 m/s, a steer of 0.3 and 3 wheels on the ground | none (the state change raises `drift_started` / `drift_ended`) |
| `use_nitro` | `use_nitro() -> bool` | **100** (a full slot) | the tank holds 100 N₂ | `Events.boost_started(vehicle, &"nitro")` |
| `request_hop` | `request_hop(big: bool = false) -> bool` | **25** (a tap) / **50** (a Big Hop) | ≥ 2 wheels on the ground, 3 m of clearance above the car, the 0.6 s cooldown over, the tank not empty | `Events.hop(vehicle, &"hop" / &"big_hop")` |
| `request_roll` | `request_roll(direction: int) -> bool` | **20** | the car is airborne, at most 2 rolls per jump, the tank not empty | `Events.barrel_roll(vehicle, direction)` |
| `request_launch` | `request_launch() -> bool` | 0 | a standstill (< 5 km/h), ≥ 3 wheels on the ground, the throttle above `THROTTLE_ON`, ≥ 50 N₂ | `Events.boost_started(vehicle, &"launch")` |
| `get_n2` | `get_n2() -> float` | 0 | — | none |

Every call that spends N₂ raises exactly one event on the Events bus. The launch is a **standing
start**: at speed the request is refused, so the nitro key stays the nitro.

## How to test (exact commands)

```
tools/godot.sh check --only=res://vehicle/modules/,res://vehicle/tuning/,res://vehicle/specs/,res://vehicle/tests/,res://vehicle/cars/,res://vehicle/demo/
tools/godot.sh test res://vehicle/specs/gen_specs.gd      # rewrites the NPC presets from the glbs
tools/godot.sh test res://vehicle/tests/<name>.gd         # one test
tools/godot.sh test res://vehicle/tests/feel_report.gd    # the table of all the measured numbers
tools/godot.sh drive --timeline=res://vehicle/demo/timeline_bighop.json --scene=res://vehicle/demo/demo_car.tscn --shots=5.8 --out=veh_bighop150 --sidecam --debug
tools/godot.sh drive --timeline=/Users/minimax/m/skyrush/tmp/review/veh3/tl_rear.json --scene=res://vehicle/demo/demo_car.tscn --shots=4.3,5.0 --out=veh_rear_r4 --rearcam
tools/godot.sh drive --timeline=/Users/minimax/m/skyrush/tmp/review/veh3/tl_main.json --scene=res://main.tscn --skip-menu --debug --shots=4.5,7.2,10.8 --out=veh_main_r4
python3 tmp/review/veh3/barscan.py captures/veh_rear_r4_t4_3.jpg 450 520 560 1040   # the idle bar
python3 tmp/review/veh3/barscan.py captures/veh_rear_r4_t5_0.jpg 450 520 560 1040   # the braking bar (the same region)
```

The test names: `test_ai_api`, `test_air_boosts`, `test_air_pitch`, `test_boost_caps`,
`test_boost_events`, `test_brake`, `test_charge`, `test_drift`, `test_heading`, `test_hop`,
`test_impact`, `test_landing`, `test_launch`, `test_menu_input`, `test_nitro`, `test_respawn`,
`test_rewards`, `test_roll`, `test_sky_lane`, `test_specs`, `test_stability`, `test_suspension`,
`test_telemetry`, `test_thrusters`, `test_top_speed`, `test_visual`, plus `feel_report.gd`.

## Evidence

**The suite: 26 test scripts, 441 checks, 0 failures** (`RESULT n checks, 0 failures` per
script, the logs in `tmp/vehicle/logs/`).

| test | result |
|---|---|
| test_drift | 37 checks: the slip band 26.4 / 32.2 / 47.4 deg, the gauge 104 N₂, the released drift ends after 0.37 s with 37 deg of heading change, the held steer keeps the drift, the counter steer exits after 0.28 s, the slip at +0.35 s 0.4 deg and at +0.60 s 0.4 deg (the neutral release 0.0 / 0.1 deg, the 断位 2.5 / 0.4 deg), the slip after a cut 32.24 against 32.19 |
| test_hop | 24 checks: the hop 2.99 / 2.98 / 2.96 m and the Big Hop 7.77 / 7.74 / 7.68 m at 0 / 150 / 250 km/h, 0.55 s above 7 m at 150 km/h, the touchdown level at every speed, the hop under a ceiling refused |
| test_rewards | 22 checks: the Big Hop → 1 trick, the plain hop → 0, the three 0.6 m drops → 0 and the N₂ unchanged, the barrel roll → 1 trick, one hard landing toast |
| test_visual | 26 checks: the bar 10 → 20 → 10, the box 2.5 → 5 → 2.5, the NPC lamp 4 → 8 → 4, the placeholder with normals, UVs and the library materials |
| test_sky_lane | 22 checks: the bank 31.5 deg, the glide time 1.81 s, the landing quality judged, the frame offset clamped (no engine error) |
| test_specs | 121 checks: every preset matches its glb |
| test_top_speed / test_boost_caps | 250.0 km/h, the N₂ 300.4, the caps 272/300/306.6/308.8/317.6/319.8 |
| test_suspension | 36 checks: 12 presets, ≥ 95 % of the weight after 1.0 s, the wheel centres within 3 mm of the glb |
| test_landing / test_roll / test_ai_api / test_nitro / test_heading | unchanged from round 2, all green |

`feel_report.gd`: 0-100 2.42 s, the launch 0.81 s, the top speed 250.0 km/h, the N₂ top speed
300.4 km/h, the brake 27.5 m, the drift 26.4°/32.2°/47.4° with 104 N₂ at 32°, the drift exit
(counter) 0.28 s and (release) 0.37 s with the slip 0.4 deg at +0.35 s and 0.4 deg at +0.60 s, the
hop 2.98/2.98/2.96 m and the Big Hop 7.77/7.74/7.68 m at 0/150/250 km/h, the barrel roll 360° in
0.70 s, the landing drift 0.000 m, the stability 2.3° of roll at 300 km/h, the sky lane 7.27 m
off the centre, the charge bay 200 N₂ and **36-47 µs of physics CPU per tick** (the budget is
250 µs; the frame work is 39-53 µs; the number depends on what the other units do on the
machine).

The windowed runs: `tools/godot.sh run res://vehicle/demo/demo_car.tscn 10` → 0 errors, 0
warnings. In `main.tscn` the vehicle unit raises **no error** (the 82 `uniform_set` errors of that
scene belong to the other units' materials).

Screenshots (`captures/`):

| file | what it proves |
|---|---|
| `veh_rear_r4_t4_3.jpg` | the rear at 70 km/h coasting: the **full-width red bar**, the middle is lit (the brake box is bound like the bar), no dark hole |
| `veh_rear_r4_t5_0.jpg` | the rear while braking: the bar is twice as bright and the halo is red |
| `veh_rear_r4_vs_ref.jpg` | the crops of the two shots next to the refs 19 and 34 |
| `veh_bighop150_t5_8.jpg` | the Big Hop at 150 km/h with the side camera: the overlay reads `air true`, `alt 7.7 m` (the lead wants ≥ 7.4 m) |
| `veh_main_r4_t4_5.jpg`, `_t7_2.jpg`, `_t10_8.jpg` | the main scene: the nitro to 299 km/h, the drift, the hop and the brake — the drift leaves the `drift` state at 8.0 s (the keys are released at 7.6 s) and the car drives on instead of circling |
| `veh_head_r4_t4_0.jpg` | the player car at 139 km/h: the headlight lights the road in front of it (the fan of light on the wet asphalt) |
| `veh_nitro_t8_0.jpg`, `veh_hopW_t4_4.jpg`, `veh_lane_t7_0.jpg`, `veh_presets_row1_row1.jpg` | the evidence of round 2 (unchanged) |

The main scene timeline (`tl_main.json`, the keys released at 7.6 s): the drift from 7.0 s, the
`recover` at 8.0 s and the `grip` from 8.5 s; the car then drives from x −56 to x −292 in a
straight line (it circled before the fix).

## Known issues / decisions that differ from the dossier

1. The drift angle is commanded between 0.50 and 0.90 rad (29°..52°), not 0.45..0.90: the tyres
   take about 4° off the commanded angle.
2. The drift is entered to the right and the *held* steer then decides the angle.
3. The tyre lateral force is applied at the contact patch, not at the height of the centre of
   mass (at the CoM height the force and the slip do not cancel each other's work).
4. The lateral assist ceiling is 200 m/s² in the drift and 300 m/s² in the recover (at 200 km/h a
   drift needs v·ω = 100 m/s² to hold the arc; the dossier's 50 lets the slip run away).
5. The tyre model's lateral force is scaled to 5 % while drifting; the drift's own speed loss
   model (1.5 + 8 sin β) is the only sink during a drift.
6. `center_of_mass_mode = CUSTOM` needs `inertia` to be set explicitly.
7. The wheel probes are cast in `_physics_process`, not in `_integrate_forces`: a shape cast
   inside the physics step re-enters the physics server and the simulation stalls.
8. The car knows that it touches something (`state.get_contact_count() > 0`): a car on its roof is
   not flying, so the auto level does not turn it upright and the respawn rule can fire.
9. The ground ray uses the world contract (`WorldBase.ground_height`) first and a ray as the
   fallback. The mask of the ray is the world layer, but the default mask works too.
10. The landing is aligned by the upright torque, not by a separate 0.12 s snap-align.
11. A hop needs 3 m of clear space above the car (dossier 5.3).
12. The hop is a take-off from the tick of the impulse: the air gravity (2 g) is on from the
    start, so the apex is the dossier's 3.1 m. The rebound damper is off during the take-off.
13. The air pitch authority is 7.0 (the dossier's target of 1.5 rad/s needs it against the auto
    level).
14. The bank of the sky lane follows the lateral speed the player commands (not the measured
    one): the car keeps the lean while it slides along the wall of the tube.
15. The soft edge of the tube is 150 m/s² per metre (the dossier's 30 cannot stop a 9 m/s
    lateral speed inside the 0.5 m margin).
16. The NPC collision boxes are the `Body` AABB of the glb; the presets are regenerated whenever
    the car model unit re-exports a glb.
17. The brake lights of the glb are not re-coloured: the car only writes the energy, so the red
    of the bar is the red the car model unit authored in the emission texture.
18. The drift exit is a **fade**, not a snap: the slip needs ~0.3 s to go from 45° to 0 in the
    recover. The counter steer pulls the nose straight (the yaw damping is 8.0), the neutral
    release unwinds the arc over 0.20 s.

## Requests (to core / other units)

**Open:**
* **car_model:** the roadster's rear bar is authored at an emissive strength of **10** in the glb
  of 11:34 (your status says 3.2), the brake box at 2.5. The car now uses the authored level, so
  the glb decides how the bar looks: at 10 the bar reads salmon in the game (the peak is
  255/110/98 and only 406 px pass R > 180 & G < 90), at 3.2 the core stays red. Please author the
  bar at the strength that reads red in the game's night exposure — the car follows it.
* **car_model:** the canopy of the roadster still reads as a see-through block of brown/grey
  squares from behind (the lead's round 2 note).
* **npc_cars:** the bus, the truck and the van have no `NPC_lamp_brake` surface; the car binds
  the brake lamp of the eight NPC cars that have one and brightens `NPC_lamp_rear` for the three
  that do not.
* **core:** `physics/3d/default_linear_damp = 0` (and the angular one) in `project.godot`: the
  engine adds the project default to the body value and the car has to cancel that drag by hand.
* **core:** the sandbox ground is a single 2 400 m box and the stunt features (the elevated deck
  at z = 100, the gas station at x = −60) sit in the infield: a test that drives far enough flies
  over the deck. The tests spawn the cars clear of the features.
* **core/shaders:** there is no `SH_tyre` in the shared library, so the placeholder wheels use the
  library's `Plastic006` maps instead.
* **core:** `SkyLane.frame_at()` errors for an offset > length + 2 m ("The transform's origin and
  target can't be equal"). The vehicle clamps the offset, but the lane should clamp it itself.
* **core:** after the car model unit re-exports the NPC glbs, the import cache keeps the old
  `.scn` files (the models do not load at all). `tools/godot.sh import` (the core's import
  doctor) should heal it — the vehicle unit does not touch `game/.godot/` any more.
* **fx_thrusters:** the car writes `telemetry.thrusters[&"Nozzle_R1".."Nozzle_R4"]` (the rear
  boost) and `[&"Nozzle_P1".."Nozzle_P6"]` (the lift and the yaw jets) every tick. The P1-P4
  also fire during the landing cushion now.
* **camera:** the chase camera has to keep the car in frame during a 3 m hop and a 27 m sky lane
  flight; the demo scene (`game/vehicle/demo/demo_car.tscn`) has a chase camera, a rear camera
  (`--rearcam`) and a side camera (`--sidecam`) for reference.
* **audio:** a stunt `&"airtime"` (voice 超长滞空！) is mapped, but no unit emits it. The vehicle
  unit reports the airtime of every landing in `Events.landed(vehicle, airtime, impact, quality)`.

## 2026-10-24: the car that flew (kerbs, walls, out of bounds)

The owner saw the Roadster lying on its side against a building at 174 km/h, "floating". Reproduced and measured in the real
city (random drives, and 40 passes at 190-245 km/h over the planter kerb at (-199, 126)): three causes, three rules. The new
car is not the cause (the old one flew the same), its wider track only made the first one likelier.

* **The wheels counted walls as road.** A probe that hit a facade, a ceiling or the back face of a surface gave the
  suspension a contact (up to 60 kN per wheel) and the upright torque aligned the car to the wall.
  `SuspensionTuning.MIN_GROUND_NORMAL_Y = 0.35` (slope 70 deg): a contact whose normal points less up is no ground.
  Test: `test_wall_not_ground.gd`. (The wheel track of the new Roadster, 1.95 m against 1.56 m, puts the probes 7 cm inside
  the box, 19 cm before: they reached walls sooner.)
* **A kerb at the height of the box launched the car.** The wheels are probes, so a 15-17 cm kerb meets the lower front edge
  of the collision box (it starts 0.22 m above the road, the downforce presses the car 5-6 cm down at top speed). The grazing
  contact gives the solver an ambiguous normal and it turned a third of the speed into vertical speed in one tick (31 m/s,
  pitch 85 deg, 25-30 m high, 30 launches in 40 passes over the planter kerb). The solver spike guard (`impact.gd`,
  `_guard_solver_spike`): when a car that stands on its wheels (two or more) and touches something with its BOX is given
  more than `ImpactTuning.SOLVER_SPIKE = 6` m/s of speed AWAY from the ground (along the normal of the ground under its wheels:
  the kerb gave 10 m/s in the first tick, 31 in the third), the guard holds for `SOLVER_HOLD = 0.3` s: that speed is cut to
  `SOLVER_KICK_UP = 1.5` m/s and the spin to `SOLVER_SPIN = 3.5` rad/s. A car that drives on its wheels has no box contact, so
  the tests that throw the car up with `linear_velocity` and a ramp are not touched (the speed of a car on a ramp runs
  along the ramp, not away from it); the hop is exempt (`dynamics.own_kick()`); a car in a sky lane resets the impact module
  every tick. Result: 0 launches in 40 passes (worst pitch 13 deg), a 17 cm kerb at 240 km/h is a 0.6 m hop. Tests:
  `test_kerb_graze.gd`. (`damage/tests/test_budget.gd` spawned its eight cars in ONE spot and got its damage from the push
  that threw them apart: they are side by side now.)
* **Tried and dropped: raising the box to 0.30 m** (superseded the same day, see "The box floor and the bump stop" below).
* **Out of bounds.** `spawn_placer.closest_lane` assigned `range()` to an `Array[int]`: a script error whenever the car was
  further than 96 m from every lane, so the put-back after a fall placed it at 1 m over the spot where it fell. Fixed, with a
  check in `test_world_api.gd`.
* Not done: the Bund street runs within a car width of the landmark colliders in ~750 of 152 000 lane samples (the old
  and the new car alike).

## 2026-10-24 (2): the box floor and the bump stop

The fuzz drive (`game/tools/fuzz_drive.gd`, a flight recorder for every odd drive) caught a launch the guard did not stop:
the Lujiazui ring road has a median of 6 x 1 m concrete strips, 15 cm above the road. At 250 km/h the lower front edge of the
box (22 cm above the road at rest, 17 cm at speed) meets a strip's side: Jolt resolves the edge-edge contact with a diagonal
normal, takes 70 % of the speed in two ticks (250 -> 72 km/h), throws the car up at 33 m/s in ONE tick (the guard acts on the
next tick: it is too late) and the damage module counts the lost speed as a crash (hp 0 in 4 passes of 24). The measure
(`zz_probe_graze`, flat world, slab kerbs 10-26 cm, 150/200/250 km/h): from 17 cm up, every kerb stopped the car dead, whatever
its width. A kerb of 15-17 cm was the edge between "a bump" and "a wall", decided by the pitch of the car.

* **The wheels climb kerbs, the box must not meet them.** `SuspensionTuning.MIN_BOX_BOTTOM = 0.34` m: `car_setup.build_body`
  puts the floor of the collision box at least this high (the top of the box stays where the spec has it). Kerbs up to 26 cm:
  speed loss 0 km/h, vertical speed <= 1.7 m/s, pitch <= 2.5 deg, at 150 and 250 km/h. A wall of 55 cm still stops the car.
* **The bump stop springs and damps.** The floor of the box used to take the hard landings (inelastic: no bounce); out of
  reach of the road it does not, and an undamped bump stop gave the landing back as a bounce (`test_air_boosts`: the landing
  mini fired as an air mini, the car was in the air again). `SuspensionTuning.BUMPSTOP_DAMP_TIME = 0.06` s: the stop damps
  with `BUMPSTOP_K * 0.06` N*s/m in both directions while it is engaged. Drops of 0.3-15 m at 0, 120 and 250 km/h: no bounce
  above the old values (a drop of 2 m is taken by the suspension alone now, 0.5 s to settle against 0.3 s; from 4 m the floor
  of the box still takes it, 0.12 m deeper).
* Tests: `test_kerb_climb.gd` (kerbs 10-24 cm x 1 and 6 m wide x 150/250 km/h, the wall, the landing; fails on the old tuning
  with a loss of 250 km/h). All 34 vehicle tests, damage 12/12, police 20/20, modes 7/7, fx 3/3 pass.
* Telemetry for the tools: `impact.seen_contacts/seen_away/seen_holding` (what the guard saw on its last tick).
* Not changed: a landing from a drop of 0.5 m at 250 km/h in the test host still counts as a crash for the damage module (the
  impulse of a hit is `mass * |dv|` of ONE tick, and a landing changes the horizontal speed a little too): the fuzz start was
  lowered (`--lift`) instead. To look at: the damage of a normal landing at top speed.
