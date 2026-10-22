# Job: a hop must not be pulled down by the drift assist (flight feel: hop, Big Hop, hover entry)

Read `briefs/improve/_godot-common.md` first (how to run tests, rules, the loop). The unit is `vehicle` (`game/vehicle/`, not the camera folder).

## Goal
The thruster hop is the start of every flight stunt. In a drift (or up to 0.37 s after releasing it) the hop is 60 to 70 % too low: the player cannot hop over traffic in a corner.
Required apex heights (design numbers, `SPEC.md` section 5, measured on a straight at 200 km/h: 2.98 m / 7.69 m):

| situation (200 km/h) | today | required |
|---|---|---|
| tap hop, drift key still held | 1.25 m | 2.8 to 3.4 m |
| Big Hop, drift key still held | 2.31 m | 7.4 to 8.2 m |
| tap hop 0.05 s after the drift release | 0.93 m | 2.8 to 3.4 m |
| tap hop 0.30 s after the drift release | 1.01 m | 2.8 to 3.4 m |

## Evidence
The lead's acceptance test reproduces it: `python tools/gd.py test res://vehicle/tests/test_hop_drift_accept.gd` ends with `RESULT 7 checks, 4 failures`. Read it: it is your oracle and you may not edit it.
The previous reviewer's diagnosis is in `reviews/vehicle-r4.md`, MUST-FIX 1; in short:

## Cause (found by the reviewer; verify it yourself with prints before you change anything)
`vehicle/modules/car_dynamics.gd` (around lines 257-268) applies the drift and recover yaw torque and the **velocity-steering assist** (ceiling 200 m/s^2 in a drift, 300 m/s^2 in recover) **with no wheel on the ground**,
and the direction `to_nose = fwd - v_hat * (fwd . v_hat)` is **three-dimensional**: after the hop impulse the car has `v.y = +11..18 m/s`, so about 31 % of the assist points **down**. At take-off the drift state is lost
(`modules/drift.gd`, around line 186) and RECOVER applies up to 300 m/s^2 for the first airborne tenths of a second. The vertical speed traces from the review (Big Hop in a held drift):
`17.9 m/s (drift, assist 104)`, `14.8 (recover, 300)`, `10.3 (recover, 300)`, `6.2 (recover, 220)`, `3.3 (recover, 162)`: the apex collapses to 2.27 m (straight: 7.69 m).

## Fix to implement (two parts, from the review)
(a) Build the assist in the **ground plane**: `v_flat = velocity - up * velocity.dot(up)`; compute `to_nose` from `v_flat` and the forward vector projected on that plane. Never apply a component along `up`.
(b) Scale the drift and recover yaw torque **and** the assist by the grounded share `grounded_wheels / wheels.size()` (0 in the air). The same rule already exists for the downforce (look for how `car_dynamics.gd`
    treats `grounded`); the yaw in the air stays with `car_air._apply_air_control`.
Do not change tuning constants (`tuning/*.gd`) to compensate, and do not special-case the hop code: the cause is the assist.

## Files you own
`game/vehicle/modules/**`, `game/vehicle/tuning/**`, `game/vehicle/arcade_car.gd`, `game/vehicle/tests/test_hop_drift_cases.gd` (a NEW test file for your own extra cases: for example hop from the recover state, hop at 100 km/h in a drift,
a drift off a crest). Everything else, including `game/vehicle/tests/test_hop_drift_accept.gd`, is read-only for you.

## Plan
1. Run the oracle and the existing hop, drift and air tests to see the baseline (`run_tests.py --filter res://vehicle/tests/` takes a few minutes).
2. Add a few `print`s (or a probe test) in `car_dynamics.gd` showing `grounded`, `v.y` and the assist direction during a drift hop; confirm the diagnosis above with numbers. Write the numbers into your status file.
3. Implement (a), run the oracle; implement (b), run the oracle again.
4. The drift must not get worse: `test_drift.gd` (the beta series after a release: +0.35 s <= 12 deg, +0.60 s <= 5 deg, no overshoot > 5 deg), `test_landing.gd`, `test_roll.gd`, `test_air_pitch.gd`, `test_hop.gd` must keep passing.
5. Run the acceptance commands, update the status file, report.

## Acceptance (the runner executes these itself, in order)
1. `python tools/gd.py check --only=res://vehicle/` prints `CHECK ... 0 failed, 0 engine errors`.
2. `python tools/gd.py test res://vehicle/tests/test_hop_drift_accept.gd` prints `RESULT 7 checks, 0 failures`.
3. `python tools/run_tests.py --filter res://vehicle/tests/ --jobs 3 --out F:/dev/skyrush-out/tmp/vehicle-drift-hop/tests` ends with `, 0 failed or timed out`.

## Pitfalls
- "Fixing" it with a hop boost that grows when a drift is detected: the straight hop must stay at 2.8 to 3.4 m and nothing in the hop code may know about drift.
- Disabling the assist during hops only: the assist must also stop acting when the car leaves the ground for any reason (crest, ramp, bump), that is what makes the drift off a ramp work.
- Breaking the drift exit (the straightening after the release is the same code path); the drift test series guards it.
- Editing the oracle test or the existing tests to make numbers pass.
