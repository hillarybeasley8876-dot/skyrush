extends RefCounted
## The camera's collision rig: the sphere cast that keeps the camera out of walls, decks
## and elevated roads, and the pull-in that lifts it over the car when there is no room
## behind it. The pull-in is instant (the camera is never inside a wall for a frame) and
## only eases back out. The one allocation per cast (the query parameters and the sphere)
## is made once and reused.

const CameraMath := preload("res://vehicle/camera/camera_math.gd")

## World (1) + props (3).
const WALL_MASK := 0b101

var _sphere := SphereShape3D.new()
var _params := PhysicsShapeQueryParameters3D.new()
## How much of the ideal distance the camera may use (0 = right on the car, 1 = free).
var scale: float = 1.0
var _close: bool = false
var _leaving: bool = false
var _spot: Vector3 = Vector3.ZERO
var _spot_valid: bool = false


func _init() -> void:
	_sphere.radius = CameraMath.COLLISION_RADIUS
	_params.shape = _sphere
	_params.collision_mask = WALL_MASK
	_params.collide_with_areas = false


## The camera position that is safe: `to` pulled in towards `from` so that the camera
## sphere never touches a wall. `fallback` (a spot above the car) is used when the pull-in
## would put the camera inside the car; the two spots are eased between, with hysteresis.
func resolve(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, dt: float,
		fallback: Vector3) -> Vector3:
	var fraction := cast_fraction(space, from, to)
	if fraction < scale:
		scale = fraction
	else:
		scale = CameraMath.damp(scale, fraction, CameraMath.PULL_OUT_RATE, dt)
	var length := from.distance_to(to)
	var normal := from.lerp(to, scale)
	var want_close := _close
	if scale * length < CameraMath.CLOSE_SPOT_MIN_DIST:
		want_close = true
	elif scale * length > CameraMath.CLOSE_SPOT_EXIT_DIST:
		want_close = false
	if want_close and cast_fraction(space, from, fallback) >= 1.0:
		_close = true
		_leaving = false
		if not _spot_valid:
			_spot = normal
			_spot_valid = true
		_spot = CameraMath.damp_vec(_spot, fallback, CameraMath.CLOSE_SPOT_LAMBDA, dt)
		return _spot
	if _close:
		_close = false
		_leaving = true
	if _leaving:
		_spot = CameraMath.damp_vec(_spot, normal, CameraMath.CLOSE_SPOT_LAMBDA, dt)
		if _spot.distance_to(normal) <= 0.05:
			_leaving = false
			_spot = normal
		return _spot
	_spot = normal
	_spot_valid = true
	return normal


## The camera position that is clear of the walls, without touching the rig's state: the
## safety pass uses it, so the physics result is never scaled twice.
func clamp_to_clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Vector3:
	return from.lerp(to, cast_fraction(space, from, to))


## How far along the motion from `from` to `to` the camera sphere can travel.
func cast_fraction(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> float:
	_params.transform = Transform3D(Basis.IDENTITY, from)
	_params.motion = to - from
	var result := space.cast_motion(_params)
	if result.is_empty():
		return 1.0
	return clampf(float(result[0]), 0.0, 1.0)


func reset() -> void:
	scale = 1.0
	_close = false
	_leaving = false
	_spot = Vector3.ZERO
	_spot_valid = false
