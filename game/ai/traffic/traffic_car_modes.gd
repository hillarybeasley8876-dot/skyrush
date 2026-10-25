class_name TrafficCarModes
extends TrafficCarPhysics
## The simulation modes of a traffic car: FAR (frozen on its lane), NEAR (dynamic) and WRECK.
##
## The switch between FAR and NEAR must not be seen. The body of a far car is put on its lane
## every time it is updated, so it is already on the lane when it turns dynamic - and a car that
## has drifted (a lane change that was given up, a bump) stays dynamic until it is back on the
## lane, so the switch never snaps.
##
## This is the middle layer of the traffic car: the body and the physics are in
## traffic_car_physics.gd, the driving (the IDM, the lane change, the lamps) is in
## traffic_car.gd.

## m: how far the body may be from the lane centre before the car may be frozen again.
const FREEZE_LATERAL := 0.15
## m: how far the body may be above or below the lane before the car may be frozen again.
const FREEZE_VERTICAL := 0.10
## rad (3 deg): how far the body may point away from the lane before it may be frozen again.
const FREEZE_YAW := 0.052
## m: how far a wreck is searched on its lane.
const WRECK_LANE_SEARCH := 25.0

## Set when the road ended under the car: it must not drive on any more.
var despawn: bool = false


## Switches the simulation mode. FAR freezes the body, NEAR releases it and WRECK unlocks the
## axes so the car tumbles.
func set_mode(new_mode: Mode) -> void:
	if new_mode == mode:
		return
	mode = new_mode
	match mode:
		Mode.FAR:
			freeze = true
			freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			axis_lock_angular_x = true
			axis_lock_angular_z = true
			# The lane distance follows the body: the body of a car that was dynamic is a
			# little ahead of its lane, and putting it back would jerk it backwards.
			_sync_lane_to_body()
		Mode.NEAR:
			# The car takes over from the frozen body: it is put on the lane first, so it does
			# not have to catch up with the lane it is driving on. The vertical velocity is not
			# carried over: the car starts on the road, not in the air.
			place_on_lane()
			freeze = false
			axis_lock_angular_x = true
			axis_lock_angular_z = true
			linear_velocity = ctx.graph.tangent_at(follower.lane, follower.s) * speed
		Mode.WRECK:
			freeze = false
			axis_lock_angular_x = false
			axis_lock_angular_z = false
			apply_wreck_physics()


## The lane distance of the car follows its body: the body of a dynamic car is a little ahead
## of the lane it drives (the physics moves it in the step after the lane was measured).
func _sync_lane_to_body() -> void:
	if follower == null or ctx == null or ctx.graph == null:
		return
	if follower.on_connector():
		return
	follower.s = ctx.graph.closest_offset_near(follower.lane, global_position, follower.s,
			TrafficCarPhysics.FOLLOW_SEARCH)


## True when the body is on its lane again: only then may the car be frozen.
func can_freeze() -> bool:
	if follower != null and follower.is_changing():
		return false
	return absf(body_lateral) <= FREEZE_LATERAL \
			and absf(body_vertical) <= FREEZE_VERTICAL \
			and absf(body_yaw) <= FREEZE_YAW


## Puts the car on its path, facing along it. While the car drives through a junction the path
## is the connector curve, not the lane.
func place_on_lane() -> void:
	global_transform = follower.transform()
	reset_physics_interpolation()     # from the parking place under the world: no streak


## The road ends here: the car stops at the end of the lane and waits. The director takes it
## away when it is out of sight.
func stop_at_dead_end() -> void:
	stopped = true
	despawn = true
	speed = 0.0
	linear_velocity = Vector3.ZERO
	# The body is put on the end of the lane, or it would lag behind and snap when the car
	# is frozen again.
	place_on_lane()


## A wreck: it slides, it rolls and it comes to a stop. The lane distance follows the body, so
## the car behind it brakes for the wreck and not for the place where it was hit.
func tick_wreck(dt: float) -> void:
	wreck_time += dt
	speed = 0.0
	if follower == null or ctx == null or ctx.graph == null:
		return
	follower.s = ctx.graph.closest_offset_near(follower.lane, global_position, follower.s,
			WRECK_LANE_SEARCH)
