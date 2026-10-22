# vehicle-drift-hop — a hop must not be pulled down by the drift assist

Job: review `vehicle-r4.md` MUST-FIX 1. The thruster hop in a drift (or up to 0.37 s after the
release) reached only 1.25 m / 2.31 m instead of 2.98 m / 7.69 m, because the drift/recover
assist kept working in the air and pointed down.

## Plan
1. Baseline: `python tools/gd.py test res://vehicle/tests/test_hop_drift_accept.gd` -> expect `RESULT 7 checks, 4 failures`.
2. Probe: a trace in the new test `res://vehicle/tests/test_hop_drift_cases.gd` (grounded, v.y, the vertical
   acceleration, the drift state, the assist) -> confirm the review's diagnosis with numbers.
3. Fix (a): build the drift/recover assist in the ground plane (v_flat, f_flat), never a component along up.
4. Fix (b): scale the drift/recover yaw torque and the assist by the grounded share (grounded/wheels.size()).
5. Own extra cases: hop from the recover state, hop at 100 km/h in a drift, a drift off a crest.
6. Guard tests: `test_drift.gd`, `test_landing.gd`, `test_roll.gd`, `test_air_pitch.gd`, `test_hop.gd`, `feel_report.gd`.
7. `python tools/gd.py check --only=res://vehicle/` -> `CHECK ... 0 failed, 0 engine errors`.
8. `python tools/run_tests.py --filter res://vehicle/tests/ --jobs 3 --out F:/dev/skyrush-out/tmp/vehicle-drift-hop/tests` -> `, 0 failed or timed out`.

## Done
Steps 1-8. The fix is in `game/vehicle/modules/car_dynamics.gd` only (no tuning constant was
touched, the hop code does not know about the drift):
- (a) the velocity-steering assist is built in the ground plane: `v_flat = velocity - up*velocity.dot(up)`
  and `f_flat = fwd - up*fwd.dot(up)`; `to_nose = f_dir - v_dir*(f_dir.dot(v_dir))` from the flat parts.
  The assist therefore has no component along the up axis and can never pull a hopping car down.
- (b) the drift/recover yaw torque and the assist are scaled with `ground_share = grounded/wheels.size()`
  (the same rule as the downforce): they are 0 while no wheel touches the ground, so the assist also
  stops when the car leaves the ground for any reason (a hop, a crest, a ramp). The yaw in the air
  belongs to `car_air._apply_air_control`.
The `ground_share` is now computed once in `apply()` (step 1) and shared by the downforce, the drift
yaw and the drift assist.

## In progress / next
Nothing. The job is finished: the oracle passes, the whole vehicle test folder passes and the check is clean.

## How to test (exact commands)
- python tools/gd.py test res://vehicle/tests/test_hop_drift_accept.gd
- python tools/gd.py test res://vehicle/tests/test_hop_drift_cases.gd
- python tools/gd.py check --only=res://vehicle/
- python tools/run_tests.py --filter res://vehicle/tests/ --jobs 3 --out F:/dev/skyrush-out/tmp/vehicle-drift-hop/tests

## Evidence (key output lines)
**Baseline (before the fix)** — `python tools/gd.py test res://vehicle/tests/test_hop_drift_accept.gd`:
```
PASS reference: hop on a straight at 200 km/h  = 2.980 (want 2.800..3.400)
FAIL hop in a held drift  = 1.252   (want 2.800..3.400)
FAIL Big Hop in a held drift  = 2.312   (want 7.400..8.200)
FAIL hop 0.05 s after the drift release  = 0.932
FAIL hop 0.30 s after the drift release  = 1.006
RESULT 7 checks, 4 failures
```

**The probe (before the fix)** — the trace of a tap hop in a held drift at 200 km/h
(`test_hop_drift_cases.gd`): `grounded=0` (in the air), the state is `recover`, the assist is at its
ceiling (300 m/s^2) and the vertical acceleration is -63 m/s^2 where the gravity alone is -19.6 m/s^2:
```
TRACE t=0.15 grounded=0 vy=7.27 ay=-63.3 state=recover beta=40.7 assist=300 pull=44.2
TRACE t=0.20 grounded=0 vy=4.27 ay=-54.8 state=recover beta=30.0 assist=253 pull=44.2
TRACE t=0.25 grounded=0 vy=2.02 ay=-38.6 state=recover beta=21.9 assist=185 pull=44.2
PROBE hop in a held drift: apex=1.252 pull=44.2 turn=61.65
```
The same test failed 6 of its 7 checks before the fix (the extra pull over a crest was 24.3 m/s^2,
the velocity turned by 61.6 deg in the air).

**After (a) alone** (the ground-plane assist): the oracle already passed
(`RESULT 7 checks, 0 failures`, hop in a held drift 2.961, Big Hop 7.700).

**After (a) and (b)** — `python tools/gd.py test res://vehicle/tests/test_hop_drift_accept.gd`:
```
PASS reference: hop on a straight at 200 km/h  = 2.980 (want 2.800..3.400)
PASS the car really is drifting before the hop  = 47.2 deg
PASS hop in a held drift  = 2.958 (want 2.800..3.400)
PASS touchdown after the drift hop is level (|roll| < 5 deg)  = 0.0 deg
PASS Big Hop in a held drift  = 7.706 (want 7.400..8.200)
PASS hop 0.05 s after the drift release  = 2.959 (want 2.800..3.400)
PASS hop 0.30 s after the drift release  = 2.966 (want 2.800..3.400)
RESULT 7 checks, 0 failures
```

**The own cases** — `python tools/gd.py test res://vehicle/tests/test_hop_drift_cases.gd`:
```
PROBE hop in a held drift: apex=2.958 pull=1.1 turn=0.00
PASS the drift ended in the recover state  = recover
PASS the hop was fired in the recover state  = recover
PASS hop from the recover state  = 2.969 (want 2.800..3.400)
PASS nothing pulls the car down in the air (extra pull <= 6 m/s^2)  = 1.1 m/s^2
PASS the velocity does not turn in the air (<= 3 deg)  = 0.00 deg
PASS hop at 100 km/h in a held drift  = 2.978 (want 2.800..3.400)
PASS the car really left the ground
PASS nothing pulls the car down over a crest (extra pull <= 6 m/s^2)  = 0.7 m/s^2
PASS the velocity does not turn in the air (<= 3 deg)  = 0.00 deg
RESULT 9 checks, 0 failures
```
(the pull is 1.1 m/s^2 = the gravity alone, and the velocity does not turn in the air at all)

**The guard tests** (the drift feel did not change):
- `test_drift.gd` -> `RESULT 37 checks, 0 failures` (the release: +0.35 s 0.0 deg, +0.60 s 0.0 deg,
  no overshoot -0.1 deg; the counter: +0.35 s 0.4 deg, +0.60 s 0.4 deg)
- `test_hop.gd` -> `RESULT 24 checks, 0 failures`; `test_landing.gd` -> `RESULT 7 checks, 0 failures`;
  `test_roll.gd` -> `RESULT 8 checks, 0 failures`; `test_air_pitch.gd` -> `RESULT 7 checks, 0 failures`
- `feel_report.gd` (the same numbers as the r4 review, so the drift feel is untouched):
  drift slip 26.4 / 32.2 / 47.4 deg, gauge 104 N2, exit counter 0.28 s / release 0.37 s,
  slip at +0.35 s 0.4 / 0.0 deg, at +0.60 s 0.4 / 0.0 deg, hop 2.98 / 2.98 / 2.96 m,
  Big Hop 7.77 / 7.74 / 7.68 m, barrel roll 360 deg in 0.70 s, landing drift 0.000 m,
  300 km/h roll 2.3 deg, sky lane 7.27 m.

**The acceptance commands**
- `python tools/gd.py check --only=res://vehicle/` -> `CHECK 110 files, 0 failed, 0 engine errors, 0 warnings`
- `python tools/gd.py test res://vehicle/tests/test_hop_drift_accept.gd` -> `RESULT 7 checks, 0 failures`
- `python tools/run_tests.py --filter res://vehicle/tests/ --jobs 3 --out F:/dev/skyrush-out/tmp/vehicle-drift-hop/tests`
  -> `28 tests, 28 passed, 0 failed or timed out`

## Known issues
- The drift speed loss (`drift.loss_accel`) is still applied along the full 3-D velocity, so on the
  take-off tick it pulls down by about 0.4 m/s^2. It is not in the scope of the review's fix (it
  only names the yaw torque and the assist) and the effect is below the measurement noise: the hop
  in a drift reaches 2.958 m against 2.980 m on a straight. Say the word and I will scale it with
  the same grounded share.
- In the air the yaw now belongs to `car_air._apply_air_control` only (as the review asks). With the
  steer held, the car yaws in the air at the air-yaw rate (1.8 rad/s) during a drift hop; before the
  fix the (ground-only) recover torque damped that. The landing stays level (|roll| 0.0 deg) and the
  velocity does not turn.

## Requests
- `reviews/vehicle-r4.md` MUST-FIX 1 also asks to copy the drift hop cases into `game/vehicle/tests/test_hop.gd`
  and to add the rows "hop from a drift (200 km/h)" and "Big Hop from a drift" to
  `game/vehicle/tests/feel_report.gd`. Both files are read-only for this job; the cases live in
  `game/vehicle/tests/test_hop_drift_cases.gd` instead. Please copy them over (or tell me to own
  those two files).
