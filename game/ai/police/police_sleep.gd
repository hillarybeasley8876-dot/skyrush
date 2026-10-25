class_name PoliceSleep
extends RefCounted
## The FAR / NEAR modes of a police unit.
##
## A unit that is far from the player does not get the full car physics: it drives its target as
## a ghost (the body is frozen and moved), so a dozen police cars do not cost a frame. When the
## player comes close, the dispatcher wakes the unit up and it drives for real.

## The time a ghost waits between two moves (s).
const GHOST_STEP := 0.1

var near: bool = true


## Puts the unit to sleep (frozen on its lane) or wakes it up.
func put_to_sleep(car: RigidBody3D, asleep: bool) -> void:
	near = not asleep
	car.freeze = asleep
	if not asleep:
		return
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO


## Moves the ghost along its own lane.
##
## The ghost does NOT cut through the blocks: it follows the lane graph (the straightest
## successor), so it drives on the road like every other car. A ghost that slides on a straight
## 3D line would be a shortcut no real car has (dossier §6.3: the catch-up is "fairness, not
## cheating").
func roll_lane(car: RigidBody3D, follower: LaneFollower, speed: float, dt: float) -> void:
	if car == null or follower == null or follower.graph == null:
		return
	car.freeze = true
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	var distance := maxf(speed, 0.0) * dt
	# The straightest successor: the ghost does not turn into a side street.
	follower.planned_next = -1
	if follower.advance(distance, 0.0) < 0:
		# The road ends: the ghost waits at the end of its lane.
		car.linear_velocity = Vector3.ZERO
		return
	var frame := follower.frame()
	var position: Vector3 = frame[0]
	var direction: Vector3 = frame[1]
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		direction = Vector3.FORWARD
	direction = direction.normalized()
	var yaw := atan2(-direction.x, -direction.z)
	car.global_transform = Transform3D(Basis(Vector3.UP, yaw), position)
	car.linear_velocity = direction * maxf(speed, 0.0)
	car.angular_velocity = Vector3.ZERO
