class_name TrafficCar
extends TrafficCarModes
## One AI traffic car.
##
## The longitudinal behaviour is the IDM (see res://ai/common/idm.gd); the lane logic lives in
## the shared LaneFollower, so the police and the rivals can reuse the same pieces. The physics
## of the body is in the base class (see traffic_car_physics.gd), the modes of the car in
## traffic_car_modes.gd.
##
## A car that drives on a new road takes the speed limit of that road (times the personal
## factor of its driver), so a car that comes down a ramp does not drive 80 km/h on the street.
## The audio unit connects to this (the car is in the group "traffic") to play a horn.
signal horn_requested(car: VehicleBase)

## When true, the physics callback measures its own cost. The performance test turns it on.
static var measure_cost: bool = false
## The time the physics of all the near cars took in the last tick (ms).
static var integrate_total_ms: float = 0.0

# --- distances and speeds ------------------------------------------------------------------------
const FAR_NEAR_DISTANCE := 200.0   ## m: beyond this a far car is updated every fourth tick
const FAR_NEAR_PERIOD := 1         ## ticks between two updates of a far car near the player
const FAR_UPDATE_PERIOD := 8       ## ticks between two updates of a far car far away
const FAR_LEADER_RANGE := 150.0    ## m: how far a far car looks for a car in front of it
const DRIVER_FACTOR_MIN := 0.9     ## the personal speed factor of a driver
const DRIVER_FACTOR_MAX := 1.1
const START_SPEED_FACTOR := 0.7    ## the car starts slower than its limit
const DEFAULT_SPEED_LIMIT := 25.0  ## m/s: the limit of a lane without one
const SHADOW_SCALE := 1.15         ## x the footprint: the size of the blob shadow
const SHADOW_ALPHA := 0.6          ## how dark the blob shadow is
const SHADOW_RANGE := 70.0         ## m: only the cars this close to the player get a shadow
const COLLISION_LAYER := 1 << 1    ## the traffic drives on this layer
const COLLISION_MASK := 0b10111    ## what the traffic hits

## The lamps of the car (head, tail, brake, indicators).
var lamps: TrafficLamps = TrafficLamps.new()
## The lane change of the car (MOBIL-lite) and its reaction to the player.
var lane_change: TrafficLaneChange = TrafficLaneChange.new()
## The longitudinal behaviour of the car (the IDM step, the lights, the junction).
var _driving: TrafficCarDriving = TrafficCarDriving.new()
var model_id: StringName = &"sedan_ev"
var body_colour: Color = Color.WHITE
## The width of the body, used for the gaps and the collider.
var car_width: float = 1.85
## The speed the IDM aims for.
var desired_speed: float = 20.0
## True when the car was placed by the prefill of the ring: it may have appeared in view.
var prefill: bool = false
## Seconds the car has been out of sight (the director removes it after two).
var off_screen_time: float = 0.0
## Seconds before this car may report another near miss.
var near_miss_cooldown: float = 0.0
## Seconds before this car may honk again.
var horn_cooldown: float = 0.0
## The distance to the player, set by the director every tick.
var player_distance: float = 1000000.0
## True when the car may light the road: only the few cars nearest to the player may.
var head_light_allowed: bool = false
## When true the car brakes no matter what is in front of it. The capture scene uses it to show
## the brake lamps.
var brake_override: bool = false

var _far_counter: int = 0
var _visual: Node3D = null
var _shape: CollisionShape3D = null
var _shadow: Decal = null
## The acceleration of the last tick (m/s^2), used by the brake lamps.
var _accel: float = 0.0
## The personal speed factor of the driver of this car.
var driver_factor: float = 1.0
## The lane entry the car has already taken the speed limit of.
var _lane_serial: int = -1
## The time the last tick of the car covered (a far car covers several ticks at once).
var last_dt: float = 0.0
## The speed the car drove with in the last tick: it is the distance it was allowed to make.
var step_speed: float = 0.0


## Builds the car and puts it on a lane.
func setup(context: DriveContext, model: StringName, colour: Color, lane: int, distance: float,
		seed_value: int) -> void:
	build(context, model, colour, seed_value)
	place(lane, distance)


## Builds the car once: the body, the visual and the lamps. The car is not on a road yet.
func build(context: DriveContext, model: StringName, colour: Color, seed_value: int) -> void:
	ctx = context
	model_id = model
	body_colour = colour
	var aabb := TrafficVisual.body_aabb(model)
	car_length = aabb.size.z
	car_width = aabb.size.x
	mass = TrafficFleet.mass_of(model)
	max_health = TrafficFleet.health_of(model)
	health = max_health
	telemetry.health_norm = 1.0
	driver_factor = context.rng.randf_range(DRIVER_FACTOR_MIN, DRIVER_FACTOR_MAX)
	lane_change.start(context.rng)
	_build_body(aabb)
	_build_visual()


## Puts the car on a lane: the lane state, the speed and the place on the road.
func place(lane: int, distance: float) -> void:
	follower = LaneFollower.new()
	follower.setup(ctx.graph, lane, distance, ctx.rng.randi())
	_driving.ctx = ctx
	_driving.follower = follower
	_driving.car_length = car_length
	_lane_serial = -1
	desired_speed = _lane_speed_limit() * driver_factor
	speed = desired_speed * START_SPEED_FACTOR
	mode = Mode.FAR
	stopped = false
	despawn = false
	off_screen_time = 0.0
	wreck_time = 0.0
	_accel = 0.0
	_contact_times.clear()
	_reset_physics()
	place_on_lane()
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	visible = true
	collision_layer = COLLISION_LAYER
	collision_mask = COLLISION_MASK


## Puts the paint of the car in another colour.
func set_colour(colour: Color) -> void:
	if colour == body_colour:
		return
	body_colour = colour
	TrafficVisual.apply_colour(_visual, colour)


## Switches the car on and off: a car that waits in the pool is invisible and cannot be hit.
func set_active(active: bool) -> void:
	visible = active
	collision_layer = COLLISION_LAYER if active else 0
	collision_mask = COLLISION_MASK if active else 0
	if active:
		return
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	stopped = true
	despawn = true


## The physics of a car that drives: no grip, so the lane change is not fought by the tyres.
func _reset_physics() -> void:
	var material := PhysicsMaterial.new()
	material.friction = 0.0
	material.rough = false
	physics_material_override = material
	linear_damp = 0.0
	angular_damp = 0.5
	continuous_cd = false
	gravity_scale = 0.0
	axis_lock_angular_x = true
	axis_lock_angular_z = true


## The collider: one box the size of the car body, and the physics setup of an AI body.
func _build_body(aabb: AABB) -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(aabb.size.x, aabb.size.y, aabb.size.z)
	_shape = get_node_or_null(^"Collision") as CollisionShape3D
	if _shape == null:
		_shape = CollisionShape3D.new()
		_shape.name = "Collision"
		add_child(_shape)
	_shape.shape = box
	# The box stands on the origin of the car: the origin is the road, not the bottom of the
	# bodywork (the bodywork of the models starts a little above the ground, the wheels fill
	# the gap). A car whose collider starts above its origin would float over the road and
	# sink into it as soon as it is a wreck.
	_shape.position = Vector3(0.0, aabb.size.y * 0.5, 0.0)
	collision_layer = COLLISION_LAYER
	collision_mask = COLLISION_MASK
	contact_monitor = true
	max_contacts_reported = 6
	# The car drives on the lane, not on the ground: the lane holds it up. A wreck gets the
	# gravity back, so it falls and tumbles.
	gravity_scale = 0.0
	# The traffic moves at lane speed (a car covers 0.2 m per tick), so it does not need the
	# continuous collision detection the player car uses.
	continuous_cd = false
	# The car is steered by its velocity, so it must never fall asleep in a queue.
	can_sleep = false
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, aabb.position.y + aabb.size.y * 0.35, 0.0)
	# The car is driven by its velocity, not by grip: a tyre friction would fight the lane
	# change and the lateral correction.
	_reset_physics()


## The meshes of the car, its lamps and the blob shadow under it.
func _build_visual() -> void:
	_visual = TrafficVisual.build(model_id, body_colour)
	add_child(_visual)
	# Every car gets its own phase for the indicator blink, so they do not blink in sync.
	lamps.setup(_visual, model_id, car_length, self, ctx.rng.randf() * TrafficLamps.BLINK_PERIOD)
	_build_shadow()


## The blob shadow of the car: a soft dark patch on the road under the car, so the car is
## grounded even when there is no light around it. It is hidden while the car tumbles.
func _build_shadow() -> void:
	_shadow = Decal.new()
	_shadow.name = "Shadow"
	_shadow.texture_albedo = TrafficMaterials.shadow_texture()
	_shadow.size = Vector3(car_width * SHADOW_SCALE, 1.0, car_length * SHADOW_SCALE)
	_shadow.modulate = Color(0.0, 0.0, 0.0, SHADOW_ALPHA)
	_shadow.position = Vector3(0.0, 0.05, 0.0)
	_shadow.upper_fade = 0.1
	_shadow.lower_fade = 0.0
	add_child(_shadow)


## The speed limit of the lane in m/s.
func _lane_speed_limit() -> float:
	var graph := ctx.graph
	if graph == null or graph.lane_count() == 0:
		return DEFAULT_SPEED_LIMIT
	var index := clampi(follower.lane, 0, graph.lane_count() - 1)
	return graph.lanes[index].speed_limit_kmh / 3.6


## One tick of the AI. The director calls this for every car, in a fixed order.
##
## A car near the player moves along its lane EVERY tick, so its body never jumps. A far car
## only moves every few ticks: nobody can see the difference at that distance, and it saves
## the frame budget (dossier 7.7). Its body and its lane distance always move together, so
## the switch to the dynamic mode never snaps.
static var t_plan: float = 0.0
static var t_speed: float = 0.0
static var t_lane: float = 0.0
static var t_think: float = 0.0
static var t_move: float = 0.0
static var t_lamp: float = 0.0
static var t_calls: int = 0


func tick(dt: float) -> void:
	if ctx == null or ctx.graph == null or follower == null:
		return
	var _t0 := Time.get_ticks_usec()
	if mode == Mode.WRECK:
		tick_wreck(dt)
		return
	var full := true
	if mode == Mode.FAR:
		_far_counter += 1
		var period := FAR_NEAR_PERIOD if player_distance <= FAR_NEAR_DISTANCE else FAR_UPDATE_PERIOD
		if _far_counter % period != 0:
			return
		dt *= float(period)
		full = player_distance <= FAR_NEAR_DISTANCE
	last_dt = dt
	# A far car on a road that is empty around it does not have to think about the traffic at
	# all (dossier 7.7): it only moves along its lane.
	if not full and _far_alone():
		step_speed = speed
		if follower.advance(speed * dt) < 0:
			stop_at_dead_end()
			return
		_update_lane_entry()
		place_on_lane()
		return
	# Every car looks ahead to the next lane, also the far ones: a far car that is close to the
	# end of its lane has to brake for the car that is already on the next one.
	var _a := Time.get_ticks_usec()
	follower.plan_next()
	var _b := Time.get_ticks_usec()
	_update_speed(dt)
	var _c := Time.get_ticks_usec()
	follower.tick(dt)
	if full:
		lane_change.update(dt, ctx, follower, speed, desired_speed, car_length, global_position)
		lane_change.check_stuck(dt, follower, lane_error())
	var _d := Time.get_ticks_usec()
	TrafficCar.t_plan += float(_b - _a)
	TrafficCar.t_speed += float(_c - _b)
	TrafficCar.t_lane += float(_d - _c)
	step_speed = speed
	var _t1 := Time.get_ticks_usec()
	if follower.advance(speed * dt) < 0:
		stop_at_dead_end()
		return
	# The car may have driven onto a new road in this tick: it takes the limit of that road.
	_update_lane_entry()
	if mode == Mode.FAR:
		place_on_lane()
	var _t2 := Time.get_ticks_usec()
	if full:
		lamps.update(dt, _accel, lane_change.indicator_side, ctx.time, mode == Mode.NEAR,
				player_distance, head_light_allowed)
		_update_shadow()
	var _t3 := Time.get_ticks_usec()
	TrafficCar.t_think += float(_t1 - _t0)
	TrafficCar.t_move += float(_t2 - _t1)
	TrafficCar.t_lamp += float(_t3 - _t2)
	TrafficCar.t_calls += 1


## True when the car drives on a road that is empty around it: no car in front of it and far
## enough from the end of its lane that it does not have to look into the next one.
func _far_alone() -> bool:
	if ctx.hash.leader_distance(follower.lane, follower.s) < FAR_LEADER_RANGE:
		return false
	return ctx.graph.lane_length(follower.lane) - follower.s > LaneFollower.PLAN_DISTANCE


## The IDM step: the leader in the lane, the leader in the lane the car will continue into, the
## traffic light at the end of the lane and the reaction to the player all end up in one
## acceleration.
func _update_speed(dt: float) -> void:
	_update_lane_entry()
	_accel = _driving.acceleration(speed, desired_speed, lane_change.reaction_brake,
			brake_override)
	speed = clampf(speed + _accel * dt, 0.0, desired_speed * 1.2)


## The car drove onto a new road: it takes the speed limit of that road.
func _update_lane_entry() -> void:
	if follower.lane_serial == _lane_serial:
		return
	_lane_serial = follower.lane_serial
	desired_speed = _lane_speed_limit() * driver_factor


## The blob shadow is only drawn for the cars near the player: a decal is a draw call, and 90 of
## them would cost more than they are worth.
func _update_shadow() -> void:
	if _shadow == null:
		return
	var want := mode == Mode.NEAR and player_distance < SHADOW_RANGE
	if _shadow.visible != want:
		_shadow.visible = want


## Sounds the horn. The audio unit listens for `horn_requested` and plays the sound (0.6 s).
func horn() -> void:
	horn_requested.emit(self)


## A one line dump of the state, for the tests.
func debug_state() -> String:
	var entry := ctx.hash.leader_entry(follower.lane, follower.index_s())
	var gap := INF
	if not entry.is_empty():
		gap = float(entry[0]) - follower.index_s() - car_length
	return "mode %d lane %d s %.1f lateral %.2f err %.2f/%.2f speed %.1f v0 %.1f gap %.1f pdist %.0f phys %s" % [
		mode, follower.lane, follower.s, follower.lateral, body_lateral, body_vertical, speed,
		desired_speed, gap, player_distance, str(linear_velocity)]


## The distance of the body from the lane centre (m).
##
## The number is measured on the body, not on the target of the lane: a car that has drifted
## (a lane change that was given up, a bump) has to show it, or it can never be frozen again.
func lane_error() -> float:
	return absf(body_lateral)


## The physics step of a NEAR car: the lane velocity is steered into the body, the yaw follows
## the lane and a hit switches the car to WRECK.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not TrafficCar.measure_cost:
		integrate(state)
		return
	var started := Time.get_ticks_usec()
	integrate(state)
	var cost := float(Time.get_ticks_usec() - started) / 1000.0
	TrafficCar.integrate_total_ms += cost
