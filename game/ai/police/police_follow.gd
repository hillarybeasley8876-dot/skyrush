class_name PoliceFollow
extends RefCounted
## The car following of a police unit (the traffic unit's IDM, game/ai/common/idm.gd).
##
## A police car looks ahead on the vehicle layer and keeps the gap to the car in front, so a
## unit never pushes another car: the car in front sets the speed. A patrol drives its lane
## like the traffic, and a pursuing unit stops behind the player instead of shoving him down
## the road.
##
## The unit asks the car for the speed of the IDM and the driver is a proportional controller,
## so the unit converges on the speed of the IDM without hunting.

## How far the unit looks ahead (m).
const PROBE_RANGE := 60.0
## The distance the probe starts in front of the car (m).
const PROBE_OFFSET := 1.2
## The height of the probe above the road (m): the body of a car.
const PROBE_HEIGHT := 0.8
## The physics layer of the vehicles (the bit mask value of layer 2).
const VEHICLE_MASK := 2
## The front overhang of a police car (m): the gap is bumper to bumper.
const CAR_FRONT := 2.4
## The minimum gap to the player (m): the unit stops right behind a stopping player.
const PLAYER_S0 := 1.0
## The lateral distance at which the player is beside a unit and not in front of it (m).
const PLAYER_BESIDE := 2.2
## The time headway of the police (s). The traffic unit uses 1.2 s: a police car that waits a
## second and a half before it reaches the car in front is too far away to bust a player.
const TIME_HEADWAY := 0.4
## The smallest speed the IDM is asked for (m/s): below this the unit coasts to a stop.
const MIN_TARGET := 0.5
## The acceleration of the model (m/s^2). The traffic unit uses 2.0: a police car pulls 7 m/s^2,
## and a model that needs three seconds to reach its target speed is a unit that arrives late.
const ACCEL_MAX := 6.0


## The car in front of `car` on the vehicle layer.
##
## Returns {"gap": float, "speed": float, "body": Node3D}; the gap is INF when the road is
## clear and the body is null then.
static func leader(space: PhysicsDirectSpaceState3D, car: RigidBody3D) -> Dictionary:
	var out := {"gap": INF, "speed": 0.0, "body": null}
	if space == null or car == null:
		return out
	var forward := -car.global_transform.basis.z
	var from := car.global_position + forward * PROBE_OFFSET + Vector3.UP * PROBE_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(from, from + forward * PROBE_RANGE,
			VEHICLE_MASK)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return out
	var other := hit.get("collider") as RigidBody3D
	# The ray starts in front of the middle of the car, so the distance it measures is longer
	# than the gap between the bumpers by the front overhang.
	#
	# The distance of a ray hit is measured from the two places: the answer of intersect_ray
	# has no "distance" key, so the gap was the length of the probe for every leader.
	var distance := from.distance_to(hit["position"] as Vector3)
	out["gap"] = maxf(distance - (CAR_FRONT - PROBE_OFFSET), 0.1)
	out["speed"] = other.linear_velocity.dot(forward) if other != null else 0.0
	out["body"] = other
	return out


## The IDM acceleration with a minimum gap of its own (m/s^2).
##
## The IDM of the traffic unit has a fixed minimum gap of 2.5 m. The police need a smaller one
## for the player: a unit that stops 2.5 m behind a standing player still nudges him.
static func acceleration(v: float, v0: float, gap: float, dv: float, s0: float) -> float:
	if v0 <= 0.1 or gap <= 0.1:
		return -IDM.EMERGENCY
	var s_star := s0 + v * TIME_HEADWAY + v * dv / (2.0 * sqrt(ACCEL_MAX * IDM.B_COMF))
	var free := 1.0 - pow(clampf(v / v0, 0.0, 4.0), IDM.V_DELTA)
	var interaction := pow(s_star / gap, 2.0)
	return clampf(ACCEL_MAX * (free - interaction), -IDM.EMERGENCY, ACCEL_MAX)
