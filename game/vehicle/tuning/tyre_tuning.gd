extends RefCounted
## The tyre model: the drift grip and the grip curve.
## SI units: metres, kilograms, seconds, m/s (km/h only for the HUD).
## Every hard-coded number of the arcade car lives in one of the files of vehicle/tuning/:
## change a value here and write the reason in status/vehicle.md - never inline a number in a
## logic file.
##
## Axis convention (lead decision): forward is -Z, right is +X, up is +Y.


# --- tyre (dossier 4.5)

const DRIFT_REAR_MU := 0.45

## How much of the tyre model's lateral force stays on while drifting. The drift's own speed
## loss model (1.5 + 8 sin beta) is the only sink during a drift: with the full tyre force the
## saturated tyres eat the whole speed in a second and the drift dies.
const DRIFT_TYRE_SCALE := 0.05

## Lateral grip curve, slip in degrees -> normalised grip.
## Lateral grip curve: the slip in degrees -> the grip factor (dossier 4.5).
const GRIP_CURVE: Array[Vector2] = [
	Vector2(0.0, 1.00), Vector2(4.0, 1.00), Vector2(8.0, 1.00), Vector2(12.0, 0.92),
	Vector2(20.0, 0.80), Vector2(35.0, 0.70), Vector2(90.0, 0.65),
]

## The lateral solver of the two axles (car_dynamics._apply_tyres): the passes that settle the impulses when an axle is at its
## grip, and the smallest determinant of the 2x2 system that is solved (a body with no rotational freedom has none).
const SOLVE_PASSES := 3
const SOLVE_MIN_DET := 1.0e-12
## s: the physics tick the cornering was tuned with (120 Hz). The contact patches of the probes are a tick old when the forces are
## applied, so they lie behind the wheels by the speed times a tick: at another tick rate they are moved to the lag of this one
## (car_dynamics._apply_tyres), and the cornering does not depend on the tick rate.
const REFERENCE_STEP := 1.0 / 120.0

## The smallest forward speed the slip angle is computed with (a standstill has no slip).
const SLIP_MIN_FWD := 1.0

## The smallest length of a direction vector before it is used (the drift assist).
const MIN_VECTOR := 0.01

## The smallest radius the wheel spin is divided by (the guard of the division).
const SPIN_MIN_RADIUS := 0.05
