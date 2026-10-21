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
