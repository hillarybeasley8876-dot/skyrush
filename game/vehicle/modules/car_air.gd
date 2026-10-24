extends RefCounted
## The air part of the car: the thrusters (hop, hover, barrel roll), the landing cushion and the
## air control (auto level, yaw and the gated pitch). The force solver (car_dynamics.gd) owns
## this helper and hands it the state of the tick; the results come back in the public fields.

const AirTuning := preload("res://vehicle/tuning/air_tuning.gd")
const DriveTuning := preload("res://vehicle/tuning/drive_tuning.gd")
const SuspensionTuning := preload("res://vehicle/tuning/suspension_tuning.gd")
const ThrusterMod := preload("res://vehicle/modules/thruster.gd")
const WheelMod := preload("res://vehicle/modules/wheel.gd")
const BoostMod := preload("res://vehicle/modules/boost.gd")
const CushionMod := preload("res://vehicle/modules/car_cushion.gd")

var spec: CarSpec = null
var thruster: ThrusterMod = null
var boost: BoostMod = null
## The wheels of the car (the landing alignment uses the normals of the contact points).
var wheels: Array[WheelMod] = []

## The input of the tick.
var throttle: float = 0.0
var brake: float = 0.0
var steer: float = 0.0
## The number of wheels on the ground (the last tick).
var grounded: int = 0
## The height of the ground under the car (the landing cushion needs it).
var ground_y: float = 0.0

# The results of the tick.
## True while the car is off the ground.
var airborne: bool = false
## True while the air gravity (2 g) should be applied.
var air_gravity: bool = false
## Set on the tick the car touches the ground.
var landed: bool = false
var landing_quality: StringName = &"clean"
var landing_airtime: float = 0.0
var landing_impact: float = 0.0
## True on the tick a hop fired.
var hopped: bool = false
## The landing damper (the force solver reads it).
var landing_damp: float = 0.0
## True while the car is in the take-off of a hop (the damper is off until it is in the air).
var hop_flight: bool:
	get:
		return _hop_flight

var _air_time: float = 0.0
var _was_airborne: bool = false
var _prev_airtime: float = 0.0
var _prev_vy: float = 0.0
var _roll_active: bool = false
var _roll_basis: Basis = Basis.IDENTITY
var _hop_fx: float = 0.0
var _land_fx: float = 0.0
## The air pitch gate: the keys that were down at the take-off, the fresh press and the hold.
var _air_pressed_prev: bool = false
var _air_pitch_candidate: bool = false
var _air_pitch_ready: bool = false
var _air_pitch_hold: float = 0.0
## True while the landing cushion may brake the descent (the car left the ground on its own).
var _cushion_armed: bool = false
## True while the car is in the take-off of a hop (the air gravity is 2 g from the impulse).
var _hop_flight: bool = false


## The thrusters: hop, hover, barrel roll, the landing and the air control.
func apply(state: PhysicsDirectBodyState3D, basis: Basis, up: Vector3,
		velocity: Vector3, dt: float) -> void:
	hopped = false
	landed = false
	_prev_airtime = thruster.airtime
	_prev_vy = velocity.y
	# The body touches something: the car is not flying (a car on its roof rests on its roof).
	var touching: bool = state.get_contact_count() > 0
	thruster.tick(dt, grounded, velocity.y, touching)
	thruster.hop_pressed = false
	thruster.hop_released = false
	# The hop impulse.
	var hopped_now: bool = false
	if thruster.pending_impulse_vy > 0.0:
		# The thruster module already charged the N2 when the spool started.
		var vy: float = thruster.pending_impulse_vy
		thruster.pending_impulse_vy = 0.0
		state.apply_central_impulse(Vector3.UP * spec.mass * (vy - minf(velocity.y, 0.0)))
		air_gravity = true
		_air_time = 0.0
		_cushion_armed = true
		hopped_now = true
		_hop_flight = true
		_hop_fx = AirTuning.HOP_FX_TIME if thruster.last_hop == &"hop" else AirTuning.BIG_HOP_FX_TIME
		hopped = true
	if _hop_flight and grounded > 0 and state.linear_velocity.y <= 0.0:
		# The hop did not get the car off the ground (a ceiling): back to the normal state.
		_hop_flight = false
	# The hover.
	if thruster.hovering:
		if boost.spend_n2(AirTuning.HOVER_COST_PER_S * dt):
			var g_air: float = AirTuning.AIR_GRAVITY * AirTuning.AIR_GRAVITY_SCALE
			state.apply_force(Vector3.UP * AirTuning.HOVER_LIFT * g_air * spec.mass,
					basis * spec.center_of_mass)
	# The barrel roll. A roll that meets the ground (a wheel or the body) is over: the roll went on turning the car on the road and
	# put it on its side.
	if thruster.rolling and _roll_active and (grounded > 0 or touching):
		thruster.abort_roll()
	if thruster.rolling:
		if not _roll_active:
			_roll_active = true
			_roll_basis = state.transform.basis
		_cushion_armed = true
		var axis: Vector3 = -state.transform.basis.z
		state.angular_velocity = axis * thruster.roll_rate()
		var dodge_accel: float = 2.0 * AirTuning.ROLL_DODGE / (AirTuning.ROLL_TIME * AirTuning.ROLL_TIME)
		var dodge: Vector3 = state.transform.basis.x * float(thruster.roll_dir)
		state.apply_force(dodge * spec.mass * dodge_accel, basis * spec.center_of_mass)
	elif _roll_active:
		_roll_active = false
		state.transform = Transform3D(_roll_basis, state.transform.origin)
		# the spin of the roll goes with it
		var roll_axis: Vector3 = -_roll_basis.z
		state.angular_velocity -= roll_axis * roll_axis.dot(state.angular_velocity)
	# The ground state. The hop is a take-off: the car flies from the tick of the impulse, so
	# the air gravity (2 g) is there from the start and the apex is the dossier's 3.1 m.
	airborne = (grounded == 0 and not touching) or _hop_flight
	if _was_airborne and not airborne:
		_on_landing(state)
	if airborne and not _was_airborne:
		_latch_air_input()
	_was_airborne = airborne
	if airborne:
		_air_time += dt
		if _air_time > AirTuning.AIRBORNE_TIME:
			air_gravity = true
		_update_air_pitch(dt)
		_apply_landing_cushion(state, velocity)
		_apply_air_control(state, up)
	else:
		_air_time = 0.0
		air_gravity = false
		_air_pitch_ready = false
		_air_pitch_candidate = false


## The take-off latches the keys that were already down: a throttle that was held through the
## take-off must be released and pressed again before it may dive the nose (dossier 4.8).
func _latch_air_input() -> void:
	_air_pressed_prev = _pitch_key_down()
	_air_pitch_candidate = false
	_air_pitch_ready = false
	_air_pitch_hold = 0.0


## True while the throttle or the brake is down far enough to ask for an air pitch.
func _pitch_key_down() -> bool:
	return throttle > DriveTuning.THROTTLE_ON or brake > DriveTuning.THROTTLE_ON


## The air pitch needs a fresh press that is held for a moment: a tap in the air is the 空喷.
func _update_air_pitch(dt: float) -> void:
	var pressed: bool = _pitch_key_down()
	var fresh: bool = pressed and not _air_pressed_prev
	_air_pressed_prev = pressed
	if _air_pitch_ready:
		return
	if fresh:
		_air_pitch_candidate = true
		_air_pitch_hold = 0.0
	if not _air_pitch_candidate:
		return
	if not pressed:
		# Released before the hold time: the next press starts over.
		_air_pitch_candidate = false
		return
	_air_pitch_hold += dt
	if _air_pitch_hold >= AirTuning.AIR_PITCH_HOLD:
		_air_pitch_ready = true


## The landing cushion (the P1-P4 jets): the descent of a hop is braked in the last metres, so
## a Big Hop lands softly instead of at 17 m/s. Only a car that left the ground with its own
## thrusters gets the cushion: a plain fall keeps its impact (dossier 5.5).
func _apply_landing_cushion(state: PhysicsDirectBodyState3D, velocity: Vector3) -> void:
	if not _cushion_armed or velocity.y >= 0.0:
		return
	var height: float = state.transform.origin.y - ground_y
	if height > AirTuning.LAND_CUSHION_HEIGHT:
		return
	var v0: float = -velocity.y
	if v0 <= AirTuning.LAND_CUSHION_SINK:
		return
	# The deceleration that brings the descent to the sink speed at the touchdown.
	var gravity: float = AirTuning.AIR_GRAVITY * AirTuning.AIR_GRAVITY_SCALE
	var accel: float = CushionMod.accel(v0, AirTuning.LAND_CUSHION_SINK, height, gravity,
			AirTuning.LAND_CUSHION_MAX_ACCEL)
	state.apply_force(Vector3.UP * spec.mass * accel, state.transform.basis * spec.center_of_mass)
	_land_fx = AirTuning.LAND_FX_TIME


## Auto level, air yaw and air pitch (dossier 4.8).
func _apply_air_control(state: PhysicsDirectBodyState3D, up: Vector3) -> void:
	if thruster.rolling:
		# The auto level would fight the barrel roll (dossier 5.4).
		return
	var inertia: float = (spec.inertia.x + spec.inertia.z) * 0.5
	var av: Vector3 = state.angular_velocity
	# The auto level keeps its full strength until the player really asks for an air pitch: a
	# throttle that was held through the take-off must not fight the car (dossier 4.8).
	var input_scale: float = AirTuning.AIR_INPUT_SCALE if (absf(steer) > AirTuning.AIR_INPUT_ON \
			or _air_pitch_ready) else 1.0
	# Auto level towards the world up.
	var torque: Vector3 = up.cross(Vector3.UP) * (AirTuning.AIR_LEVEL_K * inertia * input_scale)
	torque -= (av - up * av.dot(up)) * (AirTuning.AIR_LEVEL_D * inertia * input_scale)
	state.apply_torque(torque)
	# Air yaw: the steer input turns the car.
	var target_yaw: float = -steer * AirTuning.AIR_YAW_RATE
	state.apply_torque(up * (spec.inertia.y * AirTuning.AIR_YAW_K * (target_yaw - av.y)))
	# Air pitch: the throttle dives, the brake flares - but only after a fresh press.
	if not _air_pitch_ready:
		return
	var target_pitch: float = (-throttle + brake) * AirTuning.AIR_PITCH_RATE
	state.apply_torque(state.transform.basis.x * (spec.inertia.x * AirTuning.AIR_PITCH_K * (target_pitch - av.x)))


## The touchdown: the landing quality, the damper and the event data.
func _on_landing(state: PhysicsDirectBodyState3D) -> void:
	var up: Vector3 = state.transform.basis.y
	var n: Vector3 = Vector3.UP
	for w in wheels:
		if w.contact:
			n += w.contact_normal
	n = n.normalized()
	var quality: StringName = judge_landing(up, n)
	thruster.report_landing(quality)
	landing_damp = SuspensionTuning.LAND_DAMP_TIME
	# The cushion only belongs to the jump the car made itself.
	_cushion_armed = false
	_hop_flight = false
	# The landing cushion only fires for a real landing (dossier 5.5): a one tick wheel loss
	# or a gentle touchdown does not fire the jets.
	if _prev_airtime >= AirTuning.LAND_CUSHION_MIN_AIRTIME or _prev_vy < AirTuning.LAND_CUSHION_MIN_VY:
		_land_fx = AirTuning.LAND_FX_TIME
	if quality == &"wobble":
		var v: Vector3 = state.linear_velocity
		var flat: Vector3 = Vector3(v.x, 0.0, v.z) * AirTuning.LAND_WOBBLE_KEEP
		state.linear_velocity = Vector3(flat.x, v.y, flat.z)
	landed = true
	landing_quality = quality
	landing_airtime = _prev_airtime
	landing_impact = absf(_prev_vy)



## The quality of a landing: &"clean", &"wobble" or &"crash". The angle between the car's up
## axis and the ground normal decides it (dossier 4.8).
static func judge_landing(up: Vector3, normal: Vector3) -> StringName:
	var misalign: float = rad_to_deg(acos(clampf(up.dot(normal), -1.0, 1.0)))
	if misalign > AirTuning.LAND_ALIGN_WOBBLE_DEG:
		return &"crash"
	if misalign > AirTuning.LAND_ALIGN_OK_DEG:
		return &"wobble"
	return &"clean"


## The FX timers of the thrusters (the hop spike and the landing cushion).
func tick_effects(delta: float) -> void:
	_hop_fx = maxf(_hop_fx - delta, 0.0)
	_land_fx = maxf(_land_fx - delta, 0.0)
	landing_damp = maxf(landing_damp - delta, 0.0)


## 1.0 while the hop jet is firing.
func hop_fx() -> float:
	return _hop_fx


## 1.0 while the landing cushion is firing.
func land_fx() -> float:
	return _land_fx
