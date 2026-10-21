extends RefCounted
## The landing cushion: the jets that brake a descent in the last metres. The air cushion
## (car_air.gd) and the sky lane glide (car_flight.gd) share the formula (modules/car_cushion.gd).
##
## Axis convention (lead decision): forward is -Z, right is +X, up is +Y.

## The smallest height the cushion deceleration is computed with (the ground is never closer
## than this, so the deceleration cannot explode).
const CUSHION_MIN_HEIGHT := 0.1
