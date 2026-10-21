extends RefCounted
## QQ-style assisted drift: GRIP -> DRIFT -> RECOVER -> GRIP (dossier 4.6). Pure logic: it turns
## the car's state into a yaw torque, a lateral assist, a speed loss and the drift gauge
## (集气). The car body applies the forces; this module never touches the engine.

const DriftTuning := preload("res://vehicle/tuning/drift_tuning.gd")
const DriveTuning := preload("res://vehicle/tuning/drive_tuning.gd")
const ImpactTuning := preload("res://vehicle/tuning/impact_tuning.gd")
const TyreTuning := preload("res://vehicle/tuning/tyre_tuning.gd")

## &"grip", &"drift", &"recover".
var state: StringName = &"grip"
## +1 = drifting right, -1 = drifting left.
var dir: int = 1
## Seconds the current drift has been running.
var time: float = 0.0
## Signed slip angle in radians (positive = the nose points right of the velocity).
var beta: float = 0.0
## Yaw torque the car body must apply (N*m, about the body up axis).
var yaw_torque: float = 0.0
## Magnitude of the lateral assist in m/s^2. The car body applies it perpendicular to the
## velocity, towards the nose: that rotates the velocity onto the nose without doing any work
## on the car (an assist along the body axis would brake the car while it drifts).
var assist_accel: float = 0.0
## Speed loss in m/s^2 (the car body applies it along the velocity).
var loss_accel: float = 0.0
## Grip multiplier for the rear tyres (0.45 while drifting).
var rear_mu: float = 1.0
## How much of the tyre model's lateral force is kept while drifting.
var tyre_scale: float = 1.0
## Gauge gained in the current drift, in slots.
var gauge: float = 0.0
## True while the drift can still end cleanly.
var clean: bool = true
## Set when the drift ends: the gauge to commit and whether the exit was clean.
var exit_clean: bool = false
var exit_gauge: float = 0.0
## Cosmetic counter-steer for the front wheels.
var visual_counter: float = 0.0
## Set on the tick the drift starts, so the car body can apply the yaw kick.
var yaw_kick: float = 0.0

var _yaw_rate: float = 0.0
var _released_at: float = -1.0
var _cut_timer: float = 0.0
var _recover_timer: float = 0.0
var _clock: float = 0.0
var _inertia_yaw: float = 0.0
## The persistent unwind factor (1 = the full drift arc, 0 = the arc is gone). It only runs
## while the drift button is released and the steer does not hold the arc, so a released
## drift really ends instead of circling for ever.
var _unwind: float = 1.0
## The grip of the rear tyres and of the tyre model at the moment the drift ended: the recover
## fades them back to 1.0 (no snap).
var _recover_mu: float = 1.0
var _recover_tyre: float = 1.0


func setup(inertia_yaw: float) -> void:
	_inertia_yaw = inertia_yaw


## Advances the state machine by one tick.
## steer: smoothed steering in [-1, 1] (+1 = right).
## v_lat: body-frame lateral velocity (m/s, +right), v_fwd: forward speed (m/s).
func update(dt: float, steer: float, drift_held: bool, forward_speed: float, speed: float,
		grounded: int, yaw_rate: float, v_lat: float, v_fwd: float) -> void:
	_clock += dt
	_yaw_rate = yaw_rate
	# The drift cut only lives for its own window: a later drift is a normal drift again.
	_cut_timer = maxf(_cut_timer - dt, 0.0)
	beta = atan2(-v_lat, maxf(absf(v_fwd), 1.0))
	yaw_torque = 0.0
	assist_accel = 0.0
	loss_accel = 0.0
	visual_counter = -beta * DriftTuning.DRIFT_COUNTER_FACTOR
	match state:
		&"grip":
			_update_grip(dt, steer, drift_held, forward_speed, grounded)
		&"drift":
			_update_drift(dt, steer, drift_held, forward_speed, speed, grounded, v_fwd)
		&"recover":
			_update_recover(dt, speed)


func _update_grip(dt: float, steer: float, drift_held: bool, forward_speed: float, grounded: int) -> void:
	rear_mu = 1.0
	tyre_scale = 1.0
	time = 0.0
	gauge = 0.0
	if not drift_held:
		return
	if absf(steer) < DriftTuning.DRIFT_MIN_STEER:
		return
	if forward_speed < DriftTuning.DRIFT_MIN_SPEED:
		return
	if grounded < DriftTuning.DRIFT_MIN_WHEELS:
		return
	# Enter the drift.
	state = &"drift"
	dir = 1 if steer > 0.0 else -1
	time = 0.0
	gauge = 0.0
	clean = true
	# A new drift is a normal drift: the cut of the last one is over.
	_cut_timer = 0.0
	_unwind = 1.0
	# Yaw kick (torque impulse = up * I_yaw * 1.1 * dir). With -Z forward a right drift needs a
	# negative yaw impulse.
	yaw_kick = -float(dir) * DriftTuning.DRIFT_YAW_KICK * _inertia_yaw


func _update_drift(dt: float, steer: float, drift_held: bool, forward_speed: float, speed: float,
		grounded: int, v_fwd: float) -> void:
	# The drift cut (断位): release and re-press inside the window snaps the car straight.
	if drift_held and _released_at >= 0.0 and _clock - _released_at <= DriftTuning.DRIFT_CUT_WINDOW \
			and time >= DriftTuning.DRIFT_MIN_TIME:
		_cut_timer = DriftTuning.DRIFT_CUT_TIME
		_end_drift(true)
		return
	if not drift_held and _released_at < 0.0:
		_released_at = _clock
	if drift_held:
		_released_at = -1.0
	time += dt
	# Rear grip multiplier fades in over DRIFT_REAR_MU_FADE.
	rear_mu = lerpf(rear_mu, TyreTuning.DRIFT_REAR_MU, clampf(dt / DriftTuning.DRIFT_REAR_MU_FADE, 0.0, 1.0))
	tyre_scale = lerpf(tyre_scale, TyreTuning.DRIFT_TYRE_SCALE, clampf(dt / DriftTuning.DRIFT_REAR_MU_FADE, 0.0, 1.0))
	# The yaw target: the slip angle the player asks for (the steer into the drift) converted
	# into a yaw rate, plus a correction that keeps the real slip on target.
	var k: float = (steer * float(dir) + 1.0) * 0.5
	var beta_target: float = lerpf(DriftTuning.DRIFT_BETA_CMD_MIN, DriftTuning.DRIFT_BETA_CMD_MAX,
			clampf(k, 0.0, 1.0))
	var omega: float = beta_target * DriftTuning.DRIFT_VEL_LAMBDA
	# The correction works on the magnitude of the slip: a left drift has a negative beta.
	omega += DriftTuning.DRIFT_BETA_K * (beta_target - absf(beta))
	# The yaw rate cannot exceed what the lateral forces can deliver: at 200 km/h an
	# unrestricted 1.8 rad/s would need 10 g and the slip would run away.
	var a_max: float = DriftTuning.DRIFT_ASSIST_MAX + DriftTuning.DRIFT_TYRE_ACCEL
	omega = minf(omega, a_max / maxf(absf(v_fwd), 1.0))
	omega = clampf(omega, DriftTuning.DRIFT_OMEGA_MIN, DriftTuning.DRIFT_OMEGA_MAX)
	# The unwind: the button is released and the steer does not hold the arc any more, so the
	# arc fades out and the drift really ends. The factor is persistent (it is not recomputed
	# from the slip every tick), so a released drift does not circle for ever.
	var holding: bool = steer * float(dir) >= DriftTuning.DRIFT_MIN_STEER
	if not drift_held and not holding:
		_unwind = move_toward(_unwind, 0.0, dt / DriftTuning.DRIFT_UNWIND_TIME)
	else:
		_unwind = 1.0
	omega *= _unwind
	var omega_target_y: float = -float(dir) * omega
	yaw_torque = _inertia_yaw * DriftTuning.DRIFT_TORQUE_K * (omega_target_y - _yaw_rate)
	# Slip clamp: pull the nose back when the car is sideways beyond 66 deg.
	var slip_excess: float = absf(rad_to_deg(beta)) - DriftTuning.DRIFT_SLIP_CLAMP_DEG
	if slip_excess > 0.0:
		# The clamp pulls the nose back towards the velocity (the other way than the drift).
		yaw_torque += float(dir) * _inertia_yaw * DriftTuning.DRIFT_SLIP_CLAMP_K * deg_to_rad(slip_excess)
	# Spin-out guard.
	if absf(_yaw_rate) > DriftTuning.DRIFT_SPIN_LIMIT:
		yaw_torque += -signf(_yaw_rate) * _inertia_yaw * DriftTuning.DRIFT_SPIN_DAMP \
				* (absf(_yaw_rate) - DriftTuning.DRIFT_SPIN_LIMIT)
	# Velocity steering: the velocity direction chases the nose at lambda per second. The
	# released drift (the unwind) and the recover pull harder, so the nose is straight again
	# before the 小喷 window is used.
	var lambda: float = DriftTuning.DRIFT_VEL_LAMBDA
	var ceiling: float = DriftTuning.DRIFT_ASSIST_MAX
	if _cut_timer > 0.0:
		lambda = DriftTuning.DRIFT_CUT_LAMBDA
	elif _unwind < 1.0:
		lambda = DriftTuning.DRIFT_RECOVER_LAMBDA
		ceiling = DriftTuning.DRIFT_RECOVER_ASSIST_MAX
	# The assist uses the total speed: the rotation rate of the velocity is the assist / speed.
	assist_accel = clampf(speed * lambda * absf(beta), 0.0, ceiling)
	# Speed loss (1.5 + 8 sin beta) m/s^2, before the maintain-speed assist.
	var b_deg: float = absf(rad_to_deg(beta))
	var raw_loss: float = DriftTuning.DRIFT_LOSS_BASE + DriftTuning.DRIFT_LOSS_SIN * sin(deg_to_rad(minf(b_deg, 90.0)))
	loss_accel = raw_loss * (1.0 - _maintain_share(b_deg))
	# Gauge: max(0.015 * km/h lost this tick, 0.10 * dt) slots.
	var kmh_lost: float = raw_loss * dt * DriveTuning.KMH
	gauge += maxf(DriftTuning.GAUGE_PER_KMH_LOST * kmh_lost, DriftTuning.GAUGE_FLOOR_PER_S * dt)
	# Exit: the button is released and the car is straight (or the player counter-steers).
	if not drift_held and (absf(rad_to_deg(beta)) < DriftTuning.DRIFT_EXIT_BETA_DEG \
			or steer * float(dir) < DriftTuning.DRIFT_EXIT_COUNTER):
		_end_drift(true)
		return
	if forward_speed < DriftTuning.DRIFT_LOST_SPEED or grounded < 2:
		# Too slow or airborne: the drift is lost, no reward.
		_end_drift(false)


func _update_recover(dt: float, speed: float) -> void:
	_recover_timer = maxf(_recover_timer - dt, 0.0)
	# The grip comes back over the fade time: the rear tyres and the tyre model return to 1.0
	# without a snap on the last tick.
	var t: float = 1.0 - clampf(_recover_timer / DriftTuning.DRIFT_RECOVER_FADE, 0.0, 1.0)
	rear_mu = lerpf(_recover_mu, 1.0, t)
	tyre_scale = lerpf(_recover_tyre, 1.0, t)
	# Straighten quickly: the yaw rate is damped hard and the velocity chases the nose at
	# lambda 8 /s, so the slip is gone before the 小喷 window opens.
	assist_accel = clampf(speed * DriftTuning.DRIFT_RECOVER_LAMBDA * absf(beta),
			0.0, DriftTuning.DRIFT_RECOVER_ASSIST_MAX)
	yaw_torque = -_inertia_yaw * DriftTuning.DRIFT_RECOVER_YAW * _yaw_rate
	if _recover_timer <= 0.0:
		state = &"grip"
		rear_mu = 1.0
		tyre_scale = 1.0


## Called when a contact happens during a drift: a hard hit cancels the reward.
func on_impact(impact: float) -> void:
	if state == &"drift" and impact > ImpactTuning.IMPACT_CLEAN:
		clean = false


## True when a drift is running.
func is_drifting() -> bool:
	return state == &"drift"


func _end_drift(with_reward: bool) -> void:
	exit_clean = with_reward and clean and time >= DriftTuning.DRIFT_MIN_TIME
	exit_gauge = gauge if exit_clean else gauge * DriftTuning.DRIFT_DIRTY_GAUGE
	state = &"recover"
	_recover_timer = DriftTuning.DRIFT_RECOVER_FADE
	# The recover fades the grip back to 1.0 from here.
	_recover_mu = rear_mu
	_recover_tyre = tyre_scale


## Clears the drift state (a respawn).
func reset() -> void:
	state = &"grip"
	dir = 1
	time = 0.0
	beta = 0.0
	yaw_torque = 0.0
	assist_accel = 0.0
	loss_accel = 0.0
	rear_mu = 1.0
	tyre_scale = 1.0
	gauge = 0.0
	clean = true
	exit_clean = false
	exit_gauge = 0.0
	yaw_kick = 0.0
	visual_counter = 0.0
	_released_at = -1.0
	_cut_timer = 0.0
	_recover_timer = 0.0
	_unwind = 1.0


## The share of the drift speed loss that the maintain-speed assist cancels.
func _maintain_share(beta_deg: float) -> float:
	if beta_deg >= DriftTuning.DRIFT_MAINTAIN_LO and beta_deg <= DriftTuning.DRIFT_MAINTAIN_HI:
		return DriftTuning.DRIFT_MAINTAIN
	if beta_deg < DriftTuning.DRIFT_MAINTAIN_LO:
		return DriftTuning.DRIFT_MAINTAIN * clampf((beta_deg - DriftTuning.DRIFT_MAINTAIN_LO)
			/ DriftTuning.DRIFT_MAINTAIN_LO, 0.0, 1.0)
	var span: float = DriftTuning.DRIFT_SLIP_CLAMP_DEG - DriftTuning.DRIFT_MAINTAIN_HI
	return DriftTuning.DRIFT_MAINTAIN * clampf(
			(DriftTuning.DRIFT_SLIP_CLAMP_DEG - beta_deg) / span, 0.0, 1.0)
