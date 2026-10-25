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

## The most the car may be off the centre line of the lane at the take-off (m, across and above): the offset fades
## out over the blend. A pad that is not in line with the first metres of the lane puts the car further off.
const LANE_ENTRY_MAX := 6.0

## The soft edge: the spring back into the tube (m/s^2 per metre outside the tube). The
## dossier says 30, but at the 9 m/s of lateral speed of the tube the car needs 81 m/s^2 to
## stop inside the margin, so it would ride the hard clamp.
const LANE_EDGE_ACCEL := 150.0

## The hard limit of the lateral offset (the tube half width plus half a metre).
const LANE_EDGE_MARGIN := 0.5

## The exit: the car descends at 3 m/s until the ground.
const LANE_EXIT_DESCENT := 3.0

## The last metres of a lane bring the car back to its centre line (the lane ends 1 m over a lane of
## the road), and a car that has not touched the road this far past the end of the lane leaves the
## rails and falls the rest (the road under the end may curve away from the last tangent).
const LANE_EXIT_FADE := 60.0

const LANE_EXIT_MAX_DISTANCE := 25.0

const LANE_BANK_DEG := 3.5

const LANE_BANK_MAX_DEG := 35.0

## The turn of the lane banks the car into it, like an aircraft: the bank of a coordinated turn
## (the lift tilted so that it holds the turn) times this scale, at most LANE_TURN_BANK_MAX. A
## full coordinated bank is near 80 degrees in the tight turns of the city lanes.
const LANE_TURN_BANK_SCALE := 0.6

const LANE_TURN_BANK_MAX := 50.0

## The turn bank follows the turn this fast (1/s) and never rolls faster than LANE_TURN_ROLL_RATE
## (deg/s: the reversal of the S bend of the century canyon, 85 degrees, takes 0.6 s); the turn is
## read this many seconds ahead, so the roll begins before the turn, as an aircraft rolls into it.
const LANE_TURN_BANK_RESPONSE := 5.0

const LANE_TURN_ROLL_RATE := 150.0

const LANE_TURN_BANK_LEAD := 0.4

## The most the car banks in the lane: the turn and the player's move together.
const LANE_BANK_TOTAL_MAX := 60.0

## The fastest the car turns in the lane (deg/s): a turn too tight for the speed slows the car
## before it, braking at LANE_TURN_BRAKE (m/s^2). The tightest turns of the city lanes (44 m)
## allow 194 km/h.
const LANE_YAW_LIMIT_DEG := 70.0

const LANE_TURN_BRAKE := 12.0

## The turn of the lane is the change of its heading over this many metres before and after a
## point, read every LANE_PROFILE_STEP metres.
const LANE_TURN_SPAN := 4.0

const LANE_PROFILE_STEP := 4.0

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

# --- the obstacles of the lane (dossier 5.6)

## The damage of an obstacle hit in the lane (dossier 5.6: 15 HP, no wreck).
const FLIGHT_HIT_DAMAGE := 15.0

## The share of the speed the car keeps after an obstacle hit (0.7 = 30 % lost).
const FLIGHT_HIT_SPEED := 0.7

## The speed of the lane never falls below this after an obstacle hit (km/h). The speed of the
## lane itself is in m/s, but this one is a car speed, like the entry speed of the contract.
const FLIGHT_HIT_MIN_KMH := 120.0

## One obstacle that overlaps the car for several ticks counts once.
const FLIGHT_HIT_IMMUNITY := 1.0

## The refused take-off is explained at most once per this time (the toast throttle).
const LANE_REFUSAL_TOAST_INTERVAL := 3.0
