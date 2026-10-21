extends RefCounted
## One contact of a car with something else: where it happened, in the world and in the local
## space of the car that was hit. A class, not a dictionary, so the type is checked.

## The point of the contact in the world.
var world_point: Vector3 = Vector3.ZERO
## The point of the contact in the local space of the car that was hit.
var local_point: Vector3 = Vector3.ZERO
## The normal in the local space of the car: it points out of the other body, towards the car.
var local_normal: Vector3 = Vector3.UP
## The normal in the world.
var world_normal: Vector3 = Vector3.UP
## The zone of the car that was hit (Parts.Zone).
var zone: int = 0
## The closing speed along the normal (m/s).
var closing: float = 0.0
## The impact ratio: 0 = a scrape, 1 = a head-on.
var impact: float = 0.0
## The direction the car slid, in the world.
var slide: Vector3 = Vector3.ZERO


## The dent direction: the panel is pushed in against the normal.
func push_direction() -> Vector3:
	return -local_normal
