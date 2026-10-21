extends RefCounted
## Writes the CarTelemetry snapshot (the contract the HUD, the audio and the FX read) and
## drives the visual: the wheels with the suspension, the wing pose and the brake light.

const AirTuning := preload("res://vehicle/tuning/air_tuning.gd")
const BodyTuning := preload("res://vehicle/tuning/body_tuning.gd")
const BoostTuning := preload("res://vehicle/tuning/boost_tuning.gd")
const DriveTuning := preload("res://vehicle/tuning/drive_tuning.gd")
const VisualTuning := preload("res://vehicle/tuning/visual_tuning.gd")
const WheelMod := preload("res://vehicle/modules/wheel.gd")
const DriveMod := preload("res://vehicle/modules/drive.gd")
const DriftMod := preload("res://vehicle/modules/drift.gd")
const BoostMod := preload("res://vehicle/modules/boost.gd")
const ThrusterMod := preload("res://vehicle/modules/thruster.gd")
const PowerMod := preload("res://vehicle/modules/power.gd")
const SkyFlightMod := preload("res://vehicle/modules/sky_flight.gd")
const DynamicsMod := preload("res://vehicle/modules/car_dynamics.gd")

var spec: CarSpec = null
var wheels: Array[WheelMod] = []
var drive: DriveMod = null
var drift: DriftMod = null
var boost: BoostMod = null
var thruster: ThrusterMod = null
var power: PowerMod = null
var sky: SkyFlightMod = null
var dynamics: DynamicsMod = null
## The "Visual" node of the car scene.
var visual: Node3D = null
## True while the car flies in a sky lane.
var flying: bool = false
## The height of the ground under the car (the telemetry altitude is measured from it).
var ground_y: float = 0.0

## The nozzle keys, allocated once: the telemetry dictionary is reused every tick.
const NOZZLE_R: Array[StringName] = [&"Nozzle_R1", &"Nozzle_R2", &"Nozzle_R3", &"Nozzle_R4"]
const NOZZLE_P: Array[StringName] = [&"Nozzle_P1", &"Nozzle_P2", &"Nozzle_P3", &"Nozzle_P4"]

## The wheel states of the visual: the centres and the spin angles, filled every tick.
var _centres: PackedVector3Array = PackedVector3Array()
var _spins: PackedFloat32Array = PackedFloat32Array()
var _thrusters: Dictionary = {}


func _init() -> void:
	_centres.resize(4)
	_spins.resize(4)
	for key: StringName in NOZZLE_R:
		_thrusters[key] = 0.0
	for key: StringName in NOZZLE_P:
		_thrusters[key] = 0.0
	_thrusters[&"Nozzle_P5"] = 0.0
	_thrusters[&"Nozzle_P6"] = 0.0


## Fills the telemetry snapshot for this tick.
func write_telemetry(telemetry: CarTelemetry, xform: Transform3D, velocity: Vector3) -> void:
	var basis: Basis = xform.basis
	var speed: float = velocity.length()
	telemetry.speed_kmh = speed * DriveTuning.KMH
	telemetry.forward_speed_kmh = dynamics.forward_speed * DriveTuning.KMH
	telemetry.throttle = dynamics.throttle
	telemetry.brake = dynamics.brake
	telemetry.steer = drive.steer_value()
	telemetry.motor_load = drive.motor_load
	telemetry.grounded_wheels = dynamics.grounded
	telemetry.airborne = thruster.airborne
	telemetry.airtime = thruster.airtime
	telemetry.slip_angle_deg = rad_to_deg(drift.beta)
	telemetry.rear_slip = clampf(maxf(wheels[2].slip, wheels[3].slip) / VisualTuning.REAR_SLIP_FULL, 0.0, 1.0)
	telemetry.drift_state = drift.state
	telemetry.drift_time = drift.time
	telemetry.n2 = boost.n2
	telemetry.n2_pending = drift.gauge * BoostTuning.N2_SLOT
	telemetry.boost_kind = boost.kind
	telemetry.boost_time_left = boost.time_left
	# The HUD shows the 小喷 prompt for the drift window and for the landing window.
	telemetry.mini_window = boost.mini_window > 0.0 or thruster.landing_window_open()
	telemetry.hop_charge = thruster.hop_charge
	telemetry.hovering = thruster.hovering
	telemetry.rolling = thruster.rolling
	telemetry.battery = power.battery
	telemetry.flying = flying
	telemetry.sky_lane_progress = sky.progress()
	# The altitude is the height above the ground, not the world height.
	telemetry.altitude_m = maxf(xform.origin.y - ground_y, 0.0)
	telemetry.pitch_deg = rad_to_deg(asin(clampf(-basis.z.y, -1.0, 1.0)))
	telemetry.roll_deg = rad_to_deg(asin(clampf(basis.x.y, -1.0, 1.0)))
	telemetry.downforce_kg = BodyTuning.DOWNFORCE_K * speed * speed / AirTuning.AIR_GRAVITY
	# The g load: the downforce adds to the weight of the car.
	telemetry.g_load = 1.0 + telemetry.downforce_kg / maxf(spec.mass, 1.0)
	telemetry.thrusters = thruster_outputs()


## The nozzle outputs for the FX and the audio (0..1 per marker).
func thruster_outputs() -> Dictionary:
	var rear: float = 0.0
	match boost.kind:
		&"nitro", &"launch":
			rear = 1.0
		&"charge":
			rear = VisualTuning.NOZZLE_CHARGE
		&"air_mini":
			rear = VisualTuning.NOZZLE_AIR_MINI
		&"mini", &"landing":
			rear = VisualTuning.NOZZLE_MINI
	var lift: float = 0.0
	if dynamics.hop_fx() > 0.0:
		lift = 1.0
	elif thruster.hovering:
		lift = VisualTuning.HOVER_THRUST
	elif dynamics.land_fx() > 0.0:
		lift = VisualTuning.LAND_CUSHION
	elif flying and sky.transitioning:
		lift = 1.0
	elif flying and sky.cushioning:
		lift = 1.0
	# The yaw nozzles only fire in the air: P5 pushes the nose right, P6 to the left.
	var yaw_right: float = 0.0
	var yaw_left: float = 0.0
	if thruster.rolling:
		if thruster.roll_dir >= 0:
			yaw_right = 1.0
		else:
			yaw_left = 1.0
	elif thruster.airborne or flying:
		var steer: float = drive.steer_value()
		if steer > 0.0:
			yaw_right = clampf(steer, 0.0, 1.0)
		elif steer < 0.0:
			yaw_left = clampf(-steer, 0.0, 1.0)
	for i in NOZZLE_R.size():
		_thrusters[NOZZLE_R[i]] = rear
	for i in NOZZLE_P.size():
		_thrusters[NOZZLE_P[i]] = lift
	_thrusters[&"Nozzle_P5"] = yaw_right
	_thrusters[&"Nozzle_P6"] = yaw_left
	return _thrusters


## Moves the visual wheels, poses the wing and lights the brake bar.
func update_visual(delta: float, speed_kmh: float, braking: bool) -> void:
	if visual == null or not visual.has_method("update"):
		return
	for i in wheels.size():
		var w: WheelMod = wheels[i]
		_centres[i] = w.mount + Vector3(0.0, -w.susp_length, 0.0)
		_spins[i] = w.spin
	var cornering: float = clampf(absf(dynamics.lateral_speed) / VisualTuning.CORNERING_FULL, 0.0, 1.0)
	if drift.state == &"drift":
		cornering = 1.0
	visual.call("update", delta, _centres, _spins, drive.steer_angle, speed_kmh, cornering,
			braking, drift.visual_counter)
