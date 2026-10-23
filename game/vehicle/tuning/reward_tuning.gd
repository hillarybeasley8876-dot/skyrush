extends RefCounted
## The N2 rewards: the takedown, the near miss and the trick.
## SI units: metres, kilograms, seconds, m/s (km/h only for the HUD).
## Every hard-coded number of the arcade car lives in one of the files of vehicle/tuning/:
## change a value here and write the reason in status/vehicle.md - never inline a number in a
## logic file.
##
## Axis convention (lead decision): forward is -Z, right is +X, up is +Y.


# --- rewards (dossier 5.2)

## A takedown fills the N2 tank: +50 and +25 more per streak step.
const TAKEDOWN_N2 := 50.0

const TAKEDOWN_STREAK_N2 := 25.0

## The takedown streak window (dossier TL;DR #23).
const TAKEDOWN_STREAK_WINDOW := 10.0

## A near miss (traffic within 1.2 m at 60 km/h or more) is worth 5.
const NEAR_MISS_N2 := 5.0

## A clean landing after a Big Hop or a barrel roll is worth 15.
const TRICK_N2 := 15.0

## A roll has to end this long before the touchdown to count as a clean trick.
const TRICK_ROLL_CLEARANCE := 0.15


# --- the stunts (SPEC section 3: the stunts give score and boost)

## The N2 of the stunt kinds that pay out. The kinds that pay on their own (the trick, the
## takedown, the escape, the breaker) are not in the table: they never pay twice.
const STUNT_N2 := {
	&"fly_over_gas": 40.0,
	&"fly_over_toll": 40.0,
	&"fly_over_traffic": 40.0,
	&"fly_over_barrier": 40.0,
	&"airtime": 20.0,
	&"drift_chain": 20.0,
}

## A jump has to last this long to be a long airtime (滞空).
const AIRTIME_MIN := 2.0

## The score of a barrel roll (桶滚).
const BARREL_ROLL_POINTS := 200

## The score of a drift chain (连续漂移).
const DRIFT_CHAIN_POINTS := 300

## A drift has to last this long to count in a chain.
const DRIFT_CHAIN_MIN_DURATION := 1.0

## Two drifts of a chain may be this far apart (s).
const DRIFT_CHAIN_WINDOW := 12.0

## The number of the drifts of a chain.
const DRIFT_CHAIN_COUNT := 3
