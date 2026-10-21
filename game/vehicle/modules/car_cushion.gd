extends RefCounted
## The landing cushion formula: the P1-P4 jets brake a descent in the last metres, so a Big Hop
## lands softly instead of at 17 m/s. The air cushion (car_air.gd) and the sky lane glide
## (car_flight.gd) share it, so there is only one formula.

const CushionTuning := preload("res://vehicle/tuning/cushion_tuning.gd")


## The deceleration that brings a descent of v0 m/s to the sink speed at the touchdown.
## v0: the descent speed (m/s, positive). sink: the descent speed at the touchdown (m/s).
## height: the height of the car above the ground (m).
static func decel(v0: float, sink: float, height: float) -> float:
	return (v0 * v0 - sink * sink) / (2.0 * maxf(height, CushionTuning.CUSHION_MIN_HEIGHT))


## The upward acceleration the cushion applies: the deceleration plus the gravity that is
## still pulling the car down, capped so the jets cannot launch the car.
## gravity: the gravity that acts on the car (m/s^2). max_accel: the ceiling (m/s^2).
static func accel(v0: float, sink: float, height: float, gravity: float, max_accel: float) -> float:
	return minf(decel(v0, sink, height) + gravity, max_accel)
