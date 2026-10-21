extends RefCounted
## The rigid body: the damping, the friction, the downforce, the upright torque and the park rule.
## SI units: metres, kilograms, seconds, m/s (km/h only for the HUD).
## Every hard-coded number of the arcade car lives in one of the files of vehicle/tuning/:
## change a value here and write the reason in status/vehicle.md - never inline a number in a
## logic file.
##
## Axis convention (lead decision): forward is -Z, right is +X, up is +Y.


# --- body (dossier 4.3, lead decision)

const LINEAR_DAMP := 0.0

## The friction of the car body: the tyre model does the grip, the walls do not brake the car.
const BODY_FRICTION := 0.05

const ANGULAR_DAMP := 0.5

## Godot adds the project default (physics/3d/default_linear_damp) to the per body value, so the
## engine keeps a 0.1 * v drag the dossier does not want. The car cancels that drag with an
## explicit force; the value is read from the project settings at runtime (see ArcadeCar).
const ENGINE_DAMP_FALLBACK := 0.1

# --- downforce / stability (dossier 4.7)

const DOWNFORCE_K := 2.3

## Upright torque: k * (body_up x ground_normal) and the angular damping.
const UPRIGHT_K := 8.0

const UPRIGHT_D := 2.5

## Rollover guard: extra upright torque above this roll angle.
const ROLLOVER_DEG := 55.0

const ROLLOVER_MULT := 3.0

## Yaw damping in grip.
const YAW_DAMP_GRIP := 0.8

## Park rule: below this speed with no throttle the car is stopped dead.
const PARK_SPEED := 0.5

## The car on its roof (the up axis below this) respawns after UPSIDE_DOWN_TIME.
const UPSIDE_DOWN_DOT := -0.3

const UPSIDE_DOWN_TIME := 1.5

## The vertical speed below which the car counts as lying still.
const UPSIDE_DOWN_REST_SPEED := 1.0

## The timestamp of "never" (far in the past).
const TIME_NEVER := -100.0

## The speed below which the aero drag and the coast are not applied.
const MIN_DRAG_SPEED := 0.1
