class_name TrafficCarPhysics
extends VehicleBase
## The physics of one AI traffic car: the lane velocity is steered into the body, a hard hit
## switches the car to a wreck and a wreck tumbles and comes to a stop.
##
## This is the base class of TrafficCar (see traffic_car.gd). It holds the state the physics
## needs and the methods that belong to the physics, so that the traffic car file stays
## readable.
##
## Modes (dossier 6.1):
##   FAR   - more than NEAR_RADIUS from every player/rival/police car: the body is frozen
##           kinematic and moved by setting its transform along the lane. Cheap, and the player
##           never hits an infinite-mass wall, because the car turns dynamic long before the
##           contact.
##   NEAR  - within NEAR_RADIUS: the body is dynamic, the axis locks keep it upright and the lane
##           velocity is steered in `integrate` (the IDM speed along the tangent, the lateral error
##           corrected at LATERAL_GAIN, the height of the lane followed at VERTICAL_GAIN). The
##           player hits a real 1.5 t mass.
##   WRECK - after a hard hit: the axes are unlocked, the car tumbles and is removed when it has
##           been out of sight for a while.
##
## The car drives on the lane, not on the ground: it has no weight (gravity_scale 0) and the lane
## holds it up. That is why the body has to follow the height of the lane itself - a car that
## keeps a vertical velocity (from a push or a bump) would climb away from the road for ever.

enum Mode { FAR, NEAR, WRECK }

const WRECK_SPEED := 6.0           ## m/s: the closing speed that wrecks a car (dossier 6.1)
const TOUCH_SPEED := 0.5           ## m/s: below this a contact is a nudge, not a hit
const SHOVE_IMPULSE := 1.2         ## x the mass: the nudge a light contact gives
const CONTACT_INTERVAL := 0.25     ## s: how often the same collider may report a hit
const WRECK_FRICTION := 0.10       ## the friction of a wreck (it slides, but it comes to a stop)
const WRECK_BOUNCE := 0.15         ## the bounce of a wreck
const WRECK_LINEAR_DAMP := 0.8     ## the linear damping of a wreck
const WRECK_ANGULAR_DAMP := 0.35    ## the angular damping of a wreck
## rad/s per m/s of closing speed and per metre of lever arm: the spin of a hit that misses the
## centre of the car. A rear hit 0.6 m off the centre at 15 m/s turns the car about 2 rad/s.
const WRECK_YAW_PER_SPEED := 0.25
## rad/s per m/s and per metre: the roll of a hit along the side of the car.
const WRECK_ROLL_PER_SPEED := 0.35
const WRECK_SPIN_MAX := 2.5         ## rad/s: the cap of the spin of a wreck
const WRECK_LIFETIME := 8.0        ## s: how long a wreck stays on the road
const LATERAL_GAIN := 3.0          ## 1/s: how hard the car pulls back onto its lane centre
const LATERAL_MAX := 6.0           ## m/s: cap on the sideways correction
const VERTICAL_GAIN := 8.0         ## 1/s: how hard the car follows the height of the lane
const VERTICAL_MAX := 3.0          ## m/s: cap on the vertical correction
const VERTICAL_SNAP := 0.5         ## m: beyond this the car is put back on the lane
const YAW_GAIN := 2.2              ## 1/s: the heading error gain
const YAW_MAX := 2.5               ## rad/s: cap on the yaw rate
const FOLLOW_SEARCH := 6.0         ## m: how far the body is searched on its lane
## m: the floor of the collision box above the road while the car drives. The lane holds the car up and the kerbs and median strips
## of the city (15 cm) cross some lanes: a box that starts on the road was held by them for ever (7 jams in 14 sites of the
## traffic soak). A wreck lies on the road with the whole box (set_box_floor(0)).
const DRIVING_FLOOR := 0.34
## cos(45 deg): a contact whose normal is steeper than this is the road under the car.
const GROUND_COS := 0.7071

var mode: Mode = Mode.FAR
## The shared per-tick state (graph, lane hash, player, world).
var ctx: DriveContext = null
## The lane state of this car.
var follower: LaneFollower = null
## The speed along the lane (m/s).
var speed: float = 0.0
## The length of the body, used for the gaps and the collider.
var car_length: float = 4.6
## True when the road ended under the car: it must not drive on any more.
var stopped: bool = false
## Seconds since the car was wrecked.
var wreck_time: float = 0.0
## The lateral error of the body from the lane centre (m, positive = right of the lane).
var body_lateral: float = 0.0
## The height of the body above the lane centre (m).
var body_vertical: float = 0.0
## The heading error of the body (rad).
var body_yaw: float = 0.0
## The last time every collider reported a hit (instance id -> seconds).
var _contact_times: Dictionary = {}


## The physics of a car that drives near the player.
##
## The lane holds the car up (it has no weight), so the body has to follow the lane in all three
## directions: sideways (the lateral error), along the road (the IDM speed) and in height (the
## grade of the road). A car that kept a vertical velocity would climb away from the deck.
func integrate(state: PhysicsDirectBodyState3D) -> void:
	if mode != Mode.NEAR or stopped:
		return
	var graph := ctx.graph
	var pos := state.transform.origin
	# While the car drives through a junction it is on the connector curve, not on a lane: the
	# lane distance is then left alone and the connector drives the position.
	if not follower.on_connector():
		follower.s = graph.closest_offset_near(follower.lane, pos, follower.s, FOLLOW_SEARCH)
	var tangent := follower.direction()
	var right := _flat_right(tangent)
	var centre := follower.position()
	# The errors of the body against the lane it drives. They decide when the car may be frozen
	# again (see TrafficModes) and they are the numbers the tests look at.
	var lateral := (pos - centre).dot(right)
	body_lateral = lateral - follower.lateral
	body_vertical = pos.y - centre.y
	var forward := -state.transform.basis.z
	body_yaw = AISteering.heading_error(forward, tangent)
	var lateral_v := follower.lateral_rate \
			- clampf(body_lateral * LATERAL_GAIN, -LATERAL_MAX, LATERAL_MAX)
	var wanted := tangent * speed + right * lateral_v
	wanted.y = follower.slope() * speed \
			+ clampf(-body_vertical * VERTICAL_GAIN, -VERTICAL_MAX, VERTICAL_MAX)
	state.linear_velocity = wanted
	if absf(body_vertical) > VERTICAL_SNAP:
		# The car is too far from the road to be driven back: it is put on the lane.
		var lifted := state.transform
		lifted.origin.y = centre.y
		state.transform = lifted
	state.angular_velocity = Vector3(0.0,
			AISteering.yaw_rate(forward, tangent, YAW_GAIN, YAW_MAX), 0.0)
	check_contacts(state)


## The right-hand side of a direction on the ground (the lanes are flat, the cars stay upright).
func _flat_right(tangent: Vector3) -> Vector3:
	var right := tangent.cross(Vector3.UP)
	right.y = 0.0
	if right.length_squared() < 0.0001:
		return Vector3.RIGHT
	return right.normalized()


## Looks for a contact with another car.
##
## The road under the car is not a hit: the car drives on it, and a contact with the deck must
## not shove the car up, report it to the damage unit or wreck it. A wall is a wall: the car
## slides along it, but the road is still not an opponent - only another car can hit a traffic
## car.
##
## Only a real hit wrecks the car (dossier 6.1: a closing speed of at least 6 m/s). A nudge -
## the player brushes a traffic car, another car taps it - is reported to the damage unit and
## shoves the car, but the car keeps driving.
##
## The report is rate limited per collider, so a scrape does not fire an event (and does not
## drain the health of the damage unit) on every physics tick. When a car touches another one
## with several points, the point the cars really meet at is the one the furthest to the side:
## that is the one that turns the car around.
func check_contacts(state: PhysicsDirectBodyState3D) -> void:
	var count := state.get_contact_count()
	if count == 0:
		return
	var right := _flat_right(-state.transform.basis.z)
	var hit: Node3D = null
	var hit_closing := 0.0
	var hit_push := Vector3.ZERO
	var hit_point := Vector3.ZERO
	var hit_impulse := 0.0
	for i in count:
		var collider := state.get_contact_collider_object(i) as Node3D
		if collider == null or collider == self:
			continue
		var normal := state.get_contact_local_normal(i)
		if normal.length_squared() < 0.0001:
			continue
		normal = normal.normalized()
		if not _is_opponent(collider):
			# The road under the car: nothing to do. A wall: the car slides along it.
			if absf(normal.y) <= GROUND_COS:
				_slide_along(state, normal)
			continue
		# The speed of the two cars BEFORE the hit. The physics has already resolved the
		# contact when the callback runs, so the velocities of the bodies are the ones after
		# the crash: the closing speed has to come from the speeds the cars drove with.
		var v_rel := _own_velocity() - _velocity_of(collider)
		var closing := absf(v_rel.dot(normal))
		if closing < TOUCH_SPEED:
			continue
		if closing > hit_closing:
			hit = collider
			hit_closing = closing
			hit_push = v_rel
			hit_point = state.get_contact_collider_position(i)
			hit_impulse = state.get_contact_impulse(i).length()
	if hit == null:
		return
	# The point of the hit is the centre of the impulse of the whole contact patch, not the
	# first manifold point: a hit that misses the centre of the car turns it around.
	hit_point = _centre_of_the_hit(state, hit, right)
	if not _may_report(hit):
		return
	Events.vehicle_collided.emit(self, hit, mass * hit_closing, hit_point, hit_push)
	if hit_closing >= WRECK_SPEED:
		become_wreck(state, hit, hit_point, hit_push, hit_closing)
	else:
		# A nudge: the car is pushed aside, but it keeps driving.
		state.apply_central_impulse(-hit_push.normalized() * mass * SHOVE_IMPULSE)


## The centre of the contact patch of `collider`, weighted by the impulse of every point.
func _centre_of_the_hit(state: PhysicsDirectBodyState3D, collider: Node3D,
		right: Vector3) -> Vector3:
	var sum := Vector3.ZERO
	var weight := 0.0
	var best_point := Vector3.ZERO
	var best_lateral := -1.0
	for i in state.get_contact_count():
		if state.get_contact_collider_object(i) != collider:
			continue
		var impulse := state.get_contact_impulse(i).length()
		var point := state.get_contact_collider_position(i)
		sum += point * impulse
		weight += impulse
		var lateral := absf((point - state.transform.origin).dot(right))
		if lateral > best_lateral:
			best_lateral = lateral
			best_point = point
	if weight <= 0.0001:
		return best_point
	return sum / weight


## The velocity the car drives with (the AI speed along its lane).
func _own_velocity() -> Vector3:
	if follower == null:
		return Vector3.ZERO
	return follower.direction() * speed


## The velocity of the body that touches the car: a traffic car drives with the speed of its
## lane, every other body with its own velocity.
func _velocity_of(collider: Node3D) -> Vector3:
	if collider is TrafficCar:
		var other := collider as TrafficCar
		if other.follower == null:
			return Vector3.ZERO
		return other.follower.direction() * other.speed
	if collider is RigidBody3D:
		return (collider as RigidBody3D).linear_velocity
	return Vector3.ZERO


## True when the collider can hit the car: a body that moves. The road, the walls and the frozen
## cars of the traffic are the world - they are not opponents and they are not reported.
func _is_opponent(collider: Node3D) -> bool:
	var body := collider as RigidBody3D
	return body != null and not body.freeze


## A car that drives into a wall slides along it instead of into it.
func _slide_along(state: PhysicsDirectBodyState3D, normal: Vector3) -> void:
	var flat := Vector3(normal.x, 0.0, normal.z)
	if flat.length_squared() < 0.0001:
		return
	flat = flat.normalized()
	var into := state.linear_velocity.dot(flat)
	if into < 0.0:
		state.linear_velocity -= flat * into


## True when the same collider may report a hit again (once every CONTACT_INTERVAL seconds).
func _may_report(collider: Node3D) -> bool:
	var key := collider.get_instance_id()
	var now := float(Time.get_ticks_msec()) / 1000.0
	var last := float(_contact_times.get(key, -1000.0))
	if now - last < CONTACT_INTERVAL:
		return false
	_contact_times[key] = now
	return true


## The car has been hit hard: it stops driving, tumbles and stays on the road as an obstacle.
##
## The spin comes from the lever arm of the hit: a car that is hit beside its centre turns
## around, a car that is hit in the middle is pushed straight on. No extra momentum is added on
## top of the solver's own answer - the car that hit this one pushes it.
func become_wreck(state: PhysicsDirectBodyState3D, other: Node3D, point: Vector3,
		push: Vector3, closing: float) -> void:
	if mode == Mode.WRECK:
		return
	mode = Mode.WRECK
	set_box_floor(0.0)
	wreck_time = 0.0
	speed = 0.0
	freeze = false
	axis_lock_angular_x = false
	axis_lock_angular_z = false
	apply_wreck_physics()
	wreck(other)
	# The direction the car is pushed: the way it moves relative to the body that hit it.
	var direction := -push
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		direction = -state.transform.basis.z
		direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	direction = direction.normalized()
	# The lever arm: how far the hit landed from the centre of the car.
	var centre := state.transform * center_of_mass
	var lever := point - centre
	lever.y = 0.0
	var torque := lever.cross(direction)
	var yaw := torque.dot(Vector3.UP) * WRECK_YAW_PER_SPEED * closing
	var forward := -state.transform.basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		forward = forward.normalized()
	var roll := torque.dot(forward) * WRECK_ROLL_PER_SPEED * closing
	state.angular_velocity += Vector3.UP * clampf(yaw, -WRECK_SPIN_MAX, WRECK_SPIN_MAX)
	state.angular_velocity += forward * clampf(roll, -WRECK_SPIN_MAX, WRECK_SPIN_MAX)


## The physics of a wreck: no grip left, so it slides, it rolls and it comes to a stop.
func apply_wreck_physics() -> void:
	gravity_scale = 1.0
	var material := PhysicsMaterial.new()
	material.friction = WRECK_FRICTION
	material.bounce = WRECK_BOUNCE
	physics_material_override = material
	linear_damp = WRECK_LINEAR_DAMP
	angular_damp = WRECK_ANGULAR_DAMP
	continuous_cd = true


## Puts the floor of the collision box `floor_y` metres above the origin of the car (the road). TrafficCar knows its box.
func set_box_floor(_floor_y: float) -> void:
	pass
