extends RefCounted
## The sky lane flight of one car: the car follows the lane frame, the N2 rings refill the tank
## and the exit descends back onto the road (dossier 5.6).
##
## The car body owns this helper: it hands over the modules and the input, and the helper moves
## the car along the lane.

const AirTuning := preload("res://vehicle/tuning/air_tuning.gd")
const BoostTuning := preload("res://vehicle/tuning/boost_tuning.gd")
const LaneTuning := preload("res://vehicle/tuning/lane_tuning.gd")
const VisualTuning := preload("res://vehicle/tuning/visual_tuning.gd")
const SkyFlightMod := preload("res://vehicle/modules/sky_flight.gd")
const DriveMod := preload("res://vehicle/modules/drive.gd")
const BoostMod := preload("res://vehicle/modules/boost.gd")
const ReadoutMod := preload("res://vehicle/modules/car_readout.gd")
const DynamicsMod := preload("res://vehicle/modules/car_dynamics.gd")
const ApiMod := preload("res://vehicle/modules/car_api.gd")
const ThrusterMod := preload("res://vehicle/modules/thruster.gd")
const WheelMod := preload("res://vehicle/modules/wheel.gd")
const CushionMod := preload("res://vehicle/modules/car_cushion.gd")
const AirMod := preload("res://vehicle/modules/car_air.gd")

var car: VehicleBase = null
var sky: SkyFlightMod = null
var drive: DriveMod = null
var boost: BoostMod = null
var readout: ReadoutMod = null
var dynamics: DynamicsMod = null
var api: ApiMod = null
var thruster: ThrusterMod = null
var wheels: Array[WheelMod] = []
## The time the car was in the air (the flight and the glide). The thruster resets its airtime
## on the touchdown, so the flight keeps the longest one it saw.
var _flight_airtime: float = 0.0


## Wires the helper to the car and its modules.
func setup(vehicle: VehicleBase, sky_module: SkyFlightMod, drive_module: DriveMod,
		boost_module: BoostMod, readout_module: ReadoutMod, dynamics_module: DynamicsMod,
		api_module: ApiMod, thruster_module: ThrusterMod, wheel_list: Array[WheelMod]) -> void:
	car = vehicle
	sky = sky_module
	drive = drive_module
	boost = boost_module
	readout = readout_module
	dynamics = dynamics_module
	api = api_module
	thruster = thruster_module
	wheels = wheel_list


## One tick of the flight: the car is placed on the lane frame and the rings are collected.
func tick(state: PhysicsDirectBodyState3D, dt: float, steer: float, throttle: float,
		brake: float) -> void:
	if sky.gliding:
		_glide(state, dt)
		return
	drive.update_steer(steer, dt, sky.speed)
	var ground: float = ground_y()
	readout.ground_y = ground
	sky.update(dt, drive.steer_value(), throttle, brake, boost.n2, boost.kind, ground)
	state.transform = sky.pose()
	state.linear_velocity = sky.velocity()
	state.angular_velocity = Vector3.ZERO
	car.gravity_scale = 0.0
	# The airtime runs during the flight, so the landing window (落地喷) opens on the
	# touchdown and not one tick later.
	thruster.tick(dt, 0, state.linear_velocity.y, false)
	_flight_airtime = maxf(_flight_airtime, thruster.airtime)
	boost.spend_n2(LaneTuning.LANE_COST_PER_S * dt)
	if sky.ring_collected:
		boost.n2 = minf(boost.n2 + LaneTuning.LANE_RING_N2, BoostTuning.N2_MAX)
		Events.n2_ring.emit(car, sky.lane)
	readout.write_telemetry(car.telemetry, state.transform, state.linear_velocity)
	if sky.landed:
		_touchdown(state, absf(state.linear_velocity.y), thruster.airtime)
	elif sky.released:
		# Past the end of the lane and still in the air: the car falls the rest on its wheels.
		end_flight()


## The glide outside the rails (the early exit): the car keeps its speed, the gravity is a
## third of the normal one and the P1-P4 cushion holds the sink rate in the last metres
## (dossier 5.6). The landing is the normal wheel touchdown, never a timer.
func _glide(state: PhysicsDirectBodyState3D, dt: float) -> void:
	var ground: float = ground_y()
	readout.ground_y = ground
	var velocity: Vector3 = state.linear_velocity
	# The glide time is read before the tick: the tick resets the airtime on the touchdown.
	# The glide time is read before the tick: the tick resets the airtime on the touchdown.
	var glide_time: float = maxf(_flight_airtime, thruster.airtime)
	thruster.tick(dt, 0, velocity.y, state.get_contact_count() > 0)
	car.gravity_scale = LaneTuning.LANE_GLIDE_GRAVITY
	sky.cushioning = false
	var height: float = state.transform.origin.y - ground
	if height < LaneTuning.LANE_CUSHION_HEIGHT and velocity.y < -LaneTuning.LANE_CUSHION_SINK:
		var v0: float = -velocity.y
		var gravity: float = AirTuning.AIR_GRAVITY * LaneTuning.LANE_GLIDE_GRAVITY
		var accel: float = CushionMod.accel(v0, LaneTuning.LANE_CUSHION_SINK, height, gravity,
				LaneTuning.LANE_CUSHION_MAX_ACCEL)
		state.apply_force(Vector3.UP * car.mass * accel, Vector3.ZERO)
		sky.cushioning = true
	readout.write_telemetry(car.telemetry, state.transform, velocity)
	# The touchdown: the wheels reach the ground.
	if height <= LaneTuning.LANE_EXIT_EPS:
		_touchdown(state, absf(velocity.y), glide_time)


## The wheels touch the ground: the flight ends and the landing is reported once.
## airtime: the time the car was in the air (the glide time). The quality is judged from the
## alignment of the car with the road, like a normal landing (dossier 4.8).
func _touchdown(state: PhysicsDirectBodyState3D, impact: float, airtime: float) -> void:
	sky.landed = false
	var quality: StringName = AirMod.judge_landing(state.transform.basis.y, Vector3.UP)
	Events.landed.emit(car, airtime, impact, quality)
	end_flight()


## The height of the ground under the car: the wheels when they touch, a ray when the car is in
## the air.
func ground_y() -> float:
	for w in wheels:
		if w.contact:
			return w.contact_point.y
	return _ground_ray()


## The ground below the car, found with a ray. The world contract knows the ground of the
## world; the ray is the fallback. The mask is the world layer (the default mask works too).
func _ground_ray() -> float:
	var world: WorldBase = Game.world
	if world != null:
		var height: float = world.ground_height(car.global_position)
		if not is_nan(height):
			return height
	var space: PhysicsDirectSpaceState3D = car.get_world_3d().direct_space_state
	var from: Vector3 = car.global_position
	var query := PhysicsRayQueryParameters3D.create(from,
			from + Vector3.DOWN * VisualTuning.ALTITUDE_RAY_LENGTH, VisualTuning.GROUND_RAY_MASK)
	query.exclude = [car.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return car.global_position.y
	return (hit["position"] as Vector3).y


## Leaves the sky lane: the car keeps its speed and drops back onto the road.
func end_flight() -> void:
	if not sky.flying:
		return
	api.end_flight(car)
	car.gravity_scale = 1.0
	_flight_airtime = 0.0
