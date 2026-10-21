extends RefCounted
## The telemetry, the wing poses, the brake light and the placeholder car.
## SI units: metres, kilograms, seconds, m/s (km/h only for the HUD).
## Every hard-coded number of the arcade car lives in one of the files of vehicle/tuning/:
## change a value here and write the reason in status/vehicle.md - never inline a number in a
## logic file.
##
## Axis convention (lead decision): forward is -Z, right is +X, up is +Y.


# --- the telemetry and the visual (dossier 8.2)

## The rear slip is 1.0 at this slip angle.
const REAR_SLIP_FULL := 40.0

## The lateral speed that counts as full cornering.
const CORNERING_FULL := 8.0

## The hover thrusters and the landing cushion.
const HOVER_THRUST := 0.6

const LAND_CUSHION := 0.8

## The fallback idle emission energy of a brake light (the level the glb was authored with is
## used when the material has no emission).
const BRAKE_LIGHT_IDLE := 4.0

## The brake light energy: the idle level is the authored strength of the glb, the braking
## level is this multiple of it. The roadster's bar is authored at 3.2 (it turns pink under
## AgX above 3.6), so 2.0 gives 6.4 while braking.
const BRAKE_LIGHT_RATIO := 2.0

## The headlight of the player car: a shadowless spot at Light_Front that lights the wet road
## in front of the car, and a small red lamp at Light_Rear that follows the brake level.
const HEADLIGHT_COLOUR := Color(0.851, 0.910, 1.0)

const HEADLIGHT_ENERGY := 80.0

const HEADLIGHT_RANGE := 55.0

const HEADLIGHT_ANGLE := 42.0

## The red lamp at the rear: dark while driving, lit while braking.
const TAIL_LAMP_COLOUR := Color(1.0, 0.102, 0.18)

const TAIL_LAMP_ENERGY := 0.5

const TAIL_LAMP_RANGE := 2.0

## The wing: the pose change takes at most 0.25 s and a new pose waits 0.25 s.
const WING_POSE_TIME := 0.25

const WING_POSE_HOLD := 0.25

## The wing poses: the air brake above this speed while braking, the low drag above this speed.
const WING_AIRBRAKE_KMH := 150.0

## The air brake folds back in below this speed (the hysteresis of the deploy).
const WING_AIRBRAKE_RELEASE_KMH := 100.0

const WING_LOWDRAG_KMH := 60.0

## The cornering that counts as high downforce.
const WING_CORNERING := 0.25

## The placeholder wheels.
const PLACEHOLDER_WHEEL_R := 0.34

## The placeholder body tapers to this share of its width at the top.
const PLACEHOLDER_TAPER := 0.62

## The placeholder body tapers to this share of its length at the top.
const PLACEHOLDER_TAPER_Z := 0.8

## The plain fallback material of the placeholder: the roughness and the metallic share.
const PLACEHOLDER_ROUGHNESS := 0.28

const PLACEHOLDER_METALLIC := 0.1

## The share of the normal that wins in the box UV projection of the placeholder.
const PLACEHOLDER_UV_DOMINANT := 0.7

## The roughness of the placeholder tyre.
const PLACEHOLDER_TYRE_ROUGHNESS := 0.9

## The normal strength of the placeholder tyre.
const PLACEHOLDER_TYRE_NORMAL := 0.8

## The folder of the tyre texture of the placeholder (the shared plastic texture).
const TYRE_TEXTURE_DIR := "Plastic006"

## The altitude ray under the car.
const ALTITUDE_RAY_LENGTH := 200.0

## The collision layer of the ray under the car (the world layer).
const GROUND_RAY_MASK := 1

## The nozzle levels of the readout: the charge boost, the air boost and the mini boost.
const NOZZLE_CHARGE := 0.6
const NOZZLE_AIR_MINI := 0.5
const NOZZLE_MINI := 0.3

## The placeholder car (the glb is missing): the body, the cabin and the colours.
## The cabin of the placeholder: a share of the body box, its height above the body centre
## and how far it sits to the front.
const PLACEHOLDER_CABIN_SCALE := Vector3(0.77, 0.62, 0.43)
const PLACEHOLDER_CABIN_Y := 0.56
const PLACEHOLDER_CABIN_Z := -0.35
## The tyre of the placeholder: a share of the wheel radius.
const PLACEHOLDER_WHEEL_SCALE := 0.76
const PLACEHOLDER_PAINT := Color(0.92, 0.93, 0.96)
const PLACEHOLDER_GLASS := Color(0.05, 0.07, 0.10, 0.85)
const PLACEHOLDER_TYRE := Color(0.06, 0.06, 0.07)
