extends RefCounted
## The air control, the thruster moves (hop, hover, barrel roll) and the landing.
## SI units: metres, kilograms, seconds, m/s (km/h only for the HUD).
## Every hard-coded number of the arcade car lives in one of the files of vehicle/tuning/:
## change a value here and write the reason in status/vehicle.md - never inline a number in a
## logic file.
##
## Axis convention (lead decision): forward is -Z, right is +X, up is +Y.


# --- the air control (dossier 4.8)

## The air gravity: 2 g.
const AIR_GRAVITY := 9.81

## The auto level: k * angle - d * rate.
## The air yaw and pitch authority.
const AIR_YAW_K := 4.0

## The authority of the air pitch. The dossier asks for a dive of 1.5 rad/s; with the auto
## level (the angle term of the level fights the dive) a weaker authority only reaches 1.07
## rad/s; 7.0 reaches the 1.2 rad/s the review asks for.
const AIR_PITCH_K := 7.0

## The car counts as airborne after this long without a wheel on the ground.
const AIRBORNE_TIME := 0.10

## The landing keeps this share of the speed when the car is misaligned.
const LAND_WOBBLE_KEEP := 0.85

## The hop jet and the landing cushion times (the FX timers).
const HOP_FX_TIME := 0.15

const BIG_HOP_FX_TIME := 0.30

const LAND_FX_TIME := 0.25

## The landing cushion only fires for a real landing: this airtime or a fast vertical speed.
const LAND_CUSHION_MIN_AIRTIME := 0.30

const LAND_CUSHION_MIN_VY := -4.0

# --- the air mini boost (空喷) and the landing mini boost (落地喷)

## The air mini boost gives a 6 m/s forward impulse over 0.5 s.
const AIR_MINI_IMPULSE := 6.0

const AIR_MINI_TIME := 0.5

# --- thrusters (dossier 5.3, 5.4)

const HOP_VY := 11.0

## The take-off costs about 1 m/s of the impulse (the suspension is still pushing), so the
## impulse is a little stronger than the dossier's 17.5 to reach the 7.8 m apex.
const BIG_HOP_VY := 17.95

const HOP_COST := 25.0

const BIG_HOP_COST := 50.0

const HOVER_COST_PER_S := 12.0

const HOVER_MAX_TIME := 3.0

## Fraction of the air gravity cancelled while hovering.
const HOVER_LIFT := 0.85

const ROLL_COST := 20.0

## A full 360 degree roll in 0.70 s: 0.12 s spin-up, 0.12 s spin-down.
const ROLL_TIME := 0.70

const ROLL_RAMP := 0.12

const ROLL_PEAK := 10.83

## Side dodge during the roll.
const ROLL_DODGE := 3.5

const ROLL_MAX_PER_AIR := 2

## Hop charge time: hold at least this long for a Big Hop.
const HOP_CHARGE_TIME := 0.25

## The thruster spool before the hop fires.
const HOP_SPOOL := 0.08

## The hop needs this much clear space above the car (dossier 5.3: no hop under a ceiling).
const HOP_CEILING_HEIGHT := 3.0

## The ceiling ray starts here (inside the car, the car is excluded from the query).
const HOP_CEILING_START := 0.2

const BIG_HOP_SPOOL := 0.15

const HOP_COOLDOWN := 0.60

## Air gravity multiplier while airborne.
const AIR_GRAVITY_SCALE := 2.0

## Air control.
const AIR_YAW_RATE := 1.8

const AIR_PITCH_RATE := 1.5

const AIR_LEVEL_K := 6.0

const AIR_LEVEL_D := 2.5

## Landing window (落地喷) after a touchdown.
const LAND_WINDOW := 0.45

const LAND_MIN_AIRTIME := 0.30

## A landing is only reported after this airtime (dossier 4.8: the airborne rule).
const LAND_AIRTIME_MIN := 0.10

## A vertical speed above this is a hard landing (dossier 4.8).
const LAND_VERTICAL_SAFE := 14.0

## Landing alignment bands.
const LAND_ALIGN_OK_DEG := 30.0

const LAND_ALIGN_WOBBLE_DEG := 70.0

## The air control is weaker while the player gives input.
const AIR_INPUT_SCALE := 0.3

## The input level from which the air control counts as "the player is steering".
const AIR_INPUT_ON := 0.1

## The hover only works below this vertical speed.
const HOVER_MAX_VY := 0.5

## The air pitch (the nose dive) only starts after a fresh press that is held this long: a tap
## in the air is the 空喷, not a dive (dossier 4.8: the assists never fight the player).
const AIR_PITCH_HOLD := 0.25

## The landing cushion (the P1-P4 jets) brakes the descent in the last metres, so a Big Hop
## lands softly instead of at 17 m/s.
const LAND_CUSHION_HEIGHT := 2.0

## The descent speed the cushion aims for at the touchdown (m/s).
const LAND_CUSHION_SINK := 10.0

## The ceiling of the cushion acceleration (m/s^2), so the jets cannot launch the car.
const LAND_CUSHION_MAX_ACCEL := 80.0
