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

## A car that leans on its body (its side on a kerb or a planter, its roof on the road) with fewer than two wheels down is turned
## back onto its wheels: the upright torque above needs two wheels on the ground, so a car on its side next to a kerb (the probes
## of its wheels met the face of the kerb, not the road) lay there until the player found the reset key. The torque turns the up
## of the car towards the vertical from a tilt of RIGHTING_MIN_DEG on (rad/s^2 per rad of tilt, and a damping of the turn).
const RIGHTING_MIN_DEG := 30.0
const RIGHTING_K := 14.0
const RIGHTING_D := 3.0

## Yaw damping in grip.
const YAW_DAMP_GRIP := 0.8

## Park rule: below this speed with no throttle the car is stopped dead.
const PARK_SPEED := 0.5

## The car on its roof (the up axis below this) respawns after UPSIDE_DOWN_TIME.
const UPSIDE_DOWN_DOT := -0.3

const UPSIDE_DOWN_TIME := 1.5

## The vertical speed below which the car counts as lying still.
const UPSIDE_DOWN_REST_SPEED := 1.0

## The player car that is stuck goes back on the road after STUCK_TIME: it is slower than STUCK_SPEED and it does not stand on its
## wheels (fewer than two touch the ground) or it leans more than STUCK_TILT_DEG, and it does not fly, hover or roll. The roof rule
## above only knew a car on its roof (a tilt over 107 degrees), and the out-of-bounds rule of the modes only a car 15 m from every
## lane: a car that hung on the wall of a house next to the road, or lay on its side in the street, stayed there until the player
## found the reset key.
const STUCK_SPEED := 1.5
const STUCK_TILT_DEG := 50.0
const STUCK_TIME := 2.0

## The timestamp of "never" (far in the past).
const TIME_NEVER := -100.0

## The speed below which the aero drag and the coast are not applied.
const MIN_DRAG_SPEED := 0.1
