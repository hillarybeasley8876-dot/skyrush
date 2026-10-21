extends RefCounted
## The single N2 resource, the nitro, the mini boost, the speed-cap stacking and the launch.
## SI units: metres, kilograms, seconds, m/s (km/h only for the HUD).
## Every hard-coded number of the arcade car lives in one of the files of vehicle/tuning/:
## change a value here and write the reason in status/vehicle.md - never inline a number in a
## logic file.
##
## Axis convention (lead decision): forward is -Z, right is +X, up is +Y.


# --- boost (dossier 1.4, 5.2, 8.1)

## N2 is one resource: 2 COPV slots of 100 units.
const N2_SLOT := 100.0

const N2_MAX := 200.0

const N2_TIME := 3.0

const N2_EXTRA_V := 13.89   # +50 km/h

const N2_ACCEL := 12.0

const MINI_TIME := 0.68

const MINI_EXTRA_V := 6.11   # +22 km/h

const MINI_ACCEL := 10.0

## The mini-boost window opens on a clean drift exit and lasts this long.
const MINI_WINDOW := 0.50

## Pressing inside this window is a perfect mini boost.
const MINI_PERFECT := 0.20

const MINI_PERFECT_KICK := 4.0

## Speed-cap stacking coefficients (QQ designer Q&A).
const STACK := {"CW": 0.3, "WCW": 0.4, "CWW": 0.8, "WCWW": 0.9}

## Stacking timing windows.
const CW_GAP_MAX := 0.25

const WW_GAP_MIN := 0.55

const WW_GAP_MAX := 0.85

## Self-refilling compressor: +3 /s while grounded, up to the first slot.
const SELF_REFILL_PER_S := 3.0

## Thruster launch (完美起步): extra accel for this long.
const LAUNCH_TIME := 0.90

const LAUNCH_ACCEL := 20.0

## Throttle must be pressed within this window before the race start.
const START_WINDOW := 0.28

## Charge bay boost.
const CHARGE_TIME := 0.60

const CHARGE_ACCEL := 6.0

## The charge bay repairs this much HP.
const CHARGE_HP := 20.0

## The standing launch (完美起步) needs at least this much N2 in the tank.
const LAUNCH_N2_MIN := 50.0

## The standing launch only works from a standstill: above this forward speed the nitro key is
## the nitro, not a launch (the launch is a standing start, not a free boost).
const LAUNCH_MAX_KMH := 5.0

## The standing launch needs at least this many wheels on the ground.
const LAUNCH_MIN_WHEELS := 3

## The throttle level that asks the launch to read the telemetry instead of a value
## (the AI path passes the level, the player path lets the car read it).
const THROTTLE_FROM_TELEMETRY := -1.0

## How many boost events the speed-cap stack remembers.
const STACK_MAX := 6

## A boost older than this is dropped from the stack (seconds).
const STACK_PRUNE := 4.0
