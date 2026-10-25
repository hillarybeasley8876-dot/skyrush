extends RefCounted
## Drive, brake, coast and steering (dossier 4.5). Holds the numbers the car body applies:
## it never touches the physics engine itself.

const DriveTuning := preload("res://vehicle/tuning/drive_tuning.gd")

## Longitudinal acceleration in m/s^2 along the car's forward axis (drive minus coast drag).
var drive_accel: float = 0.0
## Brake force in newtons, already split into the front and rear share.
var brake_force: float = 0.0
## Steer angle of the front wheels in radians.
var steer_angle: float = 0.0
## 0..1 motor load for the sound.
var motor_load: float = 0.0

var _steer: float = 0.0
## The steering assist (DriveTuning.STEER_GRIP_*) is on: the car of the player. The AI cars keep the linear fall of the wheel angle
## their drivers were tuned with (the police and the rivals turn a wanted side force or a heading error into an input with it).
var assist: bool = false
var _spec: CarSpec


func setup(spec: CarSpec) -> void:
	_spec = spec


## Smoothed steering input. The keyboard turns the wheel in at STEER_RAMP /s and brings it back towards
## the centre at STEER_RETURN /s; the gamepad curve is applied before this (player_input.gd) and the
## stick is not ramped at all (dossier 4.5). The keyboard of the player (`assist`) also swaps sides
## through the centre at STEER_RETURN: the swap took the slow rate all the way, 0.5 s from lock to lock
## instead of 0.42 s. The AI drivers keep the slow swap: their steering was tuned with it (with the quick
## one a rival needed the marshal at the start of rivals/test_real_start).
## ramp: false for the gamepad stick, true for the keyboard and the AI.
func update_steer(steer_input: float, dt: float, speed: float, ramp: bool = true) -> void:
	var target: float = clampf(steer_input, -1.0, 1.0)
	if ramp:
		var swap: bool = assist and target * _steer < 0.0
		var returning: bool = absf(target) <= absf(_steer) or swap
		var rate: float = DriveTuning.STEER_RETURN if returning else DriveTuning.STEER_RAMP
		var diff: float = target - _steer
		var step: float = rate * dt
		_steer += clampf(diff, -step, step)
	else:
		_steer = target
	motor_load = 0.0
	steer_angle = deg_to_rad(max_steer_deg(speed, assist)) * _steer


## The angle of the full wheel at a speed (m/s): the linear fall from 32 deg at rest to 7 deg at the top speed, and with the
## steering assist (`assist`, the car of the player) at most the angle where the front tyres give the most
## (DriveTuning.STEER_GRIP_*).
static func max_steer_deg(speed: float, assist: bool = true) -> float:
	var t: float = clampf(absf(speed) / DriveTuning.V_TOP, 0.0, 1.0)
	var linear: float = lerpf(DriveTuning.STEER_MAX_DEG, DriveTuning.STEER_MIN_DEG, t)
	if not assist:
		return linear
	var kmh: float = maxf(absf(speed) * DriveTuning.KMH, 1.0)
	var grip: float = DriveTuning.STEER_GRIP_DEG + DriveTuning.STEER_GRIP_ADD \
			* pow(DriveTuning.STEER_GRIP_KMH / kmh, DriveTuning.STEER_GRIP_POW)
	return minf(linear, grip)


## The smoothed steering value in [-1, 1].
func steer_value() -> float:
	return _steer


## Updates the drive/brake numbers.
## forward_speed: signed speed along the car's forward axis (m/s).
## speed_cap: the current speed cap in m/s (base 69.44, boost 83.3, stacked boosts higher).
func update_drive(forward_speed: float, throttle: float, brake: float, speed_cap: float, dt: float) -> void:
	var v: float = maxf(forward_speed, 0.0)
	drive_accel = 0.0
	brake_force = 0.0
	if brake > 0.0:
		# Brake and reverse share the same key: above BRAKE_SPEED_ON forward it is a brake.
		if forward_speed > DriveTuning.BRAKE_SPEED_ON:
			brake_force = _spec.mass * _spec.brake_accel * clampf(brake, 0.0, 1.0)
		elif forward_speed > -DriveTuning.REVERSE_TOP:
			drive_accel = -DriveTuning.REVERSE_ACCEL * clampf(brake, 0.0, 1.0)
		return
	if throttle <= 0.0:
		return
	# Base power decays from 1.0x to A_FLOOR as the car approaches its speed cap.
	var ratio: float = 1.0 - (1.0 - DriveTuning.A_FLOOR) * clampf(v / maxf(speed_cap, 1.0), 0.0, 1.0)
	if v >= speed_cap:
		ratio = 0.0
	drive_accel = _spec.accel * ratio * clampf(throttle, 0.0, 1.0)
	motor_load = clampf(throttle, 0.0, 1.0)


## Coasting drag in m/s^2 (no throttle, no brake).
func coast_accel(speed: float) -> float:
	return DriveTuning.COAST + DriveTuning.COAST_V2 * speed * speed


## Aerodynamic drag in newtons, always applied (coasting feel only).
func aero_drag(speed: float) -> float:
	return DriveTuning.AERO_DRAG * speed * speed
