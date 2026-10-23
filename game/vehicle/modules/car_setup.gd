extends RefCounted
## Builds a car from its CarSpec: the rigid body setup, the collision box, the four wheel probes
## and the wiring of the modules. The car body (ArcadeCar) owns one of these and hands it the
## spec and the modules.

const BodyTuning := preload("res://vehicle/tuning/body_tuning.gd")
const SuspensionTuning := preload("res://vehicle/tuning/suspension_tuning.gd")
const BoostTuning := preload("res://vehicle/tuning/boost_tuning.gd")
const WheelMod := preload("res://vehicle/modules/wheel.gd")
const DriveMod := preload("res://vehicle/modules/drive.gd")
const DriftMod := preload("res://vehicle/modules/drift.gd")
const BoostMod := preload("res://vehicle/modules/boost.gd")
const ThrusterMod := preload("res://vehicle/modules/thruster.gd")
const SkyFlightMod := preload("res://vehicle/modules/sky_flight.gd")
const PowerMod := preload("res://vehicle/modules/power.gd")
const ImpactMod := preload("res://vehicle/modules/impact.gd")
const AirMod := preload("res://vehicle/modules/car_air.gd")
const DynamicsMod := preload("res://vehicle/modules/car_dynamics.gd")
const ReadoutMod := preload("res://vehicle/modules/car_readout.gd")
const ApiMod := preload("res://vehicle/modules/car_api.gd")
const RewardsMod := preload("res://vehicle/modules/rewards.gd")

var spec: CarSpec = null
var drive: DriveMod = null
var drift: DriftMod = null
var boost: BoostMod = null
var thruster: ThrusterMod = null
var sky: SkyFlightMod = null
var power: PowerMod = null
var impact: ImpactMod = null
var dynamics: DynamicsMod = null
var air: AirMod = null
var readout: ReadoutMod = null
var api: ApiMod = null
var rewards: RewardsMod = null
## The Visual node of the car scene.
var visual: Node3D = null
## The wheel probes, in the order FL, FR, RL, RR.
var wheels: Array[WheelMod] = []
## How long the car has been on its roof.
var _upside_down_time: float = 0.0


## Applies the spec to the rigid body.
func apply_spec(body: RigidBody3D) -> void:
	body.mass = spec.mass
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = spec.center_of_mass
	body.inertia = spec.inertia
	body.max_health = spec.max_health
	body.health = spec.max_health
	body.collision_layer = 1 << 1
	body.collision_mask = 0b111
	body.contact_monitor = true
	body.max_contacts_reported = 8
	body.continuous_cd = true
	body.can_sleep = false
	body.linear_damp = BodyTuning.LINEAR_DAMP
	body.angular_damp = BodyTuning.ANGULAR_DAMP
	body.gravity_scale = 1.0
	# The tyre model does the grip; the walls must not brake the car, so the body friction is low.
	var material := PhysicsMaterial.new()
	material.friction = BodyTuning.BODY_FRICTION
	material.bounce = 0.0
	body.physics_material_override = material


## Creates the body collision box.
func build_body(body: Node3D) -> void:
	var shape: CollisionShape3D = body.get_node_or_null(^"Body") as CollisionShape3D
	if shape == null:
		shape = CollisionShape3D.new()
		shape.name = "Body"
		body.add_child(shape)
	# The wheels are probes: they climb a kerb with their springs. The box must not meet a kerb at all (a kerb that meets
	# the lower edge of the box is a wall, not a step), so its floor is at least MIN_BOX_BOTTOM above the road.
	var top: float = spec.body_center_y + spec.body_size.y * 0.5
	var bottom: float = maxf(spec.body_center_y - spec.body_size.y * 0.5, SuspensionTuning.MIN_BOX_BOTTOM)
	var box := BoxShape3D.new()
	box.size = Vector3(spec.body_size.x, top - bottom, spec.body_size.z)
	shape.shape = box
	shape.position = Vector3(0.0, (top + bottom) * 0.5, 0.0)


## Creates the four wheel probes.
func build_wheels(body: Node3D) -> void:
	wheels.clear()
	for i in spec.wheel_mounts.size():
		var w: WheelMod = WheelMod.new()
		w.setup(body, spec, i)
		wheels.append(w)


## True when the car has been on its roof long enough to respawn (dossier 4.7).
## resting: the car lies still (it is not falling), so a car on its roof counts too.
func upside_down_time(up_dot: float, resting: bool, dt: float) -> float:
	if up_dot < -BodyTuning.UPSIDE_DOWN_DOT and resting:
		_upside_down_time += dt
	else:
		_upside_down_time = 0.0
	return _upside_down_time


## Clears the flight, the roll, the hover, the drift and the boost timers (a respawn).
func reset_state() -> void:
	sky.flying = false
	sky.reset()
	thruster.reset()
	drift.reset()
	boost.reset()
	_upside_down_time = 0.0


## Connects the modules to each other.
func wire(body: VehicleBase) -> void:
	drive.setup(spec)
	drift.setup(spec.inertia.y)
	boost.setup(spec.top_speed, BoostTuning.N2_SLOT)
	thruster.boost = boost
	power.battery = 1.0
	dynamics.spec = spec
	dynamics.wheels = wheels
	dynamics.drive = drive
	dynamics.drift = drift
	dynamics.boost = boost
	dynamics.thruster = thruster
	dynamics.power = power
	dynamics.impact = impact
	dynamics.air = air
	air.spec = spec
	air.thruster = thruster
	air.boost = boost
	air.wheels = wheels
	# Godot adds the project default linear damping to the per body value, so the engine keeps
	# a 0.1 * v drag the dossier does not want. The car cancels it with an explicit force.
	dynamics.engine_damp = float(ProjectSettings.get_setting("physics/3d/default_linear_damp",
			BodyTuning.ENGINE_DAMP_FALLBACK))
	readout.spec = spec
	readout.wheels = wheels
	readout.drive = drive
	readout.drift = drift
	readout.boost = boost
	readout.thruster = thruster
	readout.power = power
	readout.sky = sky
	readout.dynamics = dynamics
	readout.visual = visual
	api.setup(boost, thruster, sky)
	rewards.setup(body, boost)
