extends RefCounted
## The drive, the brake, the steering and the input thresholds.
## SI units: metres, kilograms, seconds, m/s (km/h only for the HUD).
## Every hard-coded number of the arcade car lives in one of the files of vehicle/tuning/:
## change a value here and write the reason in status/vehicle.md - never inline a number in a
## logic file.
##
## Axis convention (lead decision): forward is -Z, right is +X, up is +Y.


# --- drive / brake / steer (dossier 4.5)

## Base top speed (250 km/h) and the hard cap (330 km/h).
const V_TOP := 69.44

const V_CAP := 91.67

const A_FLOOR := 0.2

## Extra drag above the cap (m/s^2 per m/s of excess). The dossier says 0.4, but that takes
## 8 s to pull the car back from 300 to 250 km/h; 1.2 does it in 4 s.
const CAP_PULL := 1.2

const REVERSE_ACCEL := 6.0

const REVERSE_TOP := 11.11  # 40 km/h

## Coasting: constant term plus a quadratic term.
const COAST := 1.5

const COAST_V2 := 0.0004

## Aerodynamic drag in newtons (coasting feel only; the caps set the top speed).
const AERO_DRAG := 0.30

const STEER_MAX_DEG := 32.0

const STEER_MIN_DEG := 7.0

## The steering assist: the full wheel is the angle where the front tyres give the most. A keyboard only knows the full wheel, and
## the linear fall from 32 deg at rest to 7 deg at the top speed left the front tyres far past their grip (24 deg at 80 km/h, the
## grip curve falls after 8 deg of slip): the full wheel turned the car 20-24 % less than a third of it at 80-120 km/h
## (vehicle/tests/steer_report.gd). The full wheel is now STEER_GRIP_DEG + STEER_GRIP_ADD * (STEER_GRIP_KMH / speed)^1.5, at most
## the linear fall: 20 deg at 40 km/h, 11 at 80, 8.7 at 120, 7.3 at 200. The car of the player only (Drive.assist): the AI drivers
## turn a wanted side force or a heading error into an input with the linear fall.
const STEER_GRIP_DEG := 6.0

const STEER_GRIP_ADD := 14.0

const STEER_GRIP_KMH := 40.0

const STEER_GRIP_POW := 1.5

## Keyboard steer ramp: 4.0 /s toward the target, 6.0 /s back to centre.
const STEER_RAMP := 4.0

const STEER_RETURN := 6.0

const GAMEPAD_DEADZONE := 0.12

# --- the input and the shared numbers

## The throttle counts as pressed above this value (the 完美起步 window and the brake light).
const THROTTLE_ON := 0.5

## The brake counts as pressed above this value.
const BRAKE_ON := 0.1

## Below this throttle and brake level the car coasts (no motor, no brake, the park rule).
const IDLE_INPUT := 0.05

## Above this forward speed the brake key brakes; below it the same key reverses.
const BRAKE_SPEED_ON := 0.5

## The metres per second to kilometres per hour factor.
const KMH := 3.6
