extends RefCounted
## The sky lane flight: the tube, the bank, the exit and the rings.
## SI units: metres, kilograms, seconds, m/s (km/h only for the HUD).
## Every hard-coded number of the arcade car lives in one of the files of vehicle/tuning/:
## change a value here and write the reason in status/vehicle.md - never inline a number in a
## logic file.
##
## Axis convention (lead decision): forward is -Z, right is +X, up is +Y.


# --- the sky lane (dossier 5.6)

## The take-off blends into the lane over this time.
const LANE_TRANSITION_TIME := 0.4

## The soft edge: the spring back into the tube (m/s^2 per metre outside the tube). The
## dossier says 30, but at the 9 m/s of lateral speed of the tube the car needs 81 m/s^2 to
## stop inside the margin, so it would ride the hard clamp.
const LANE_EDGE_ACCEL := 150.0

## The hard limit of the lateral offset (the tube half width plus half a metre).
const LANE_EDGE_MARGIN := 0.5

## The exit: the car descends at 3 m/s until the ground.
const LANE_EXIT_DESCENT := 3.0

const LANE_BANK_DEG := 3.5

const LANE_BANK_MAX_DEG := 35.0

## The pitch: 2.5 degrees per m/s of vertical speed.
const LANE_PITCH_DEG := 2.5

## The glide when the N2 tank is empty: 0.35 g.
const LANE_GLIDE_GRAVITY := 0.35

## The N2 boost raises the lane speed to 300 km/h.
const LANE_BOOST_SPEED := 83.33

## How fast the lane speed follows the target.
const LANE_SPEED_ACCEL := 4.0

## How close to the ground the exit counts as landed.
const LANE_EXIT_EPS := 0.05

const LANE_COST_PER_S := 10.0

const LANE_RING_N2 := 40.0

const LANE_LATERAL_SPEED := 9.0

const LANE_VERTICAL_SPEED := 6.0

const LANE_RESPONSE := 6.0

## The glide (the early exit): the P1-P4 cushion holds the sink rate in the last metres.
const LANE_CUSHION_HEIGHT := 3.0

## The sink rate the cushion holds in the glide (m/s).
const LANE_CUSHION_SINK := 4.0

## The ceiling of the glide cushion acceleration (m/s^2).
const LANE_CUSHION_MAX_ACCEL := 40.0
