extends RefCounted
## The force solver: everything the car body applies to the physics state in one tick
## (dossier 4.9). The car body owns this helper and hands it the spec, the wheels and the
## modules; the helper returns the results through its public fields.

const AirTuning := preload("res://vehicle/tuning/air_tuning.gd")
const BodyTuning := preload("res://vehicle/tuning/body_tuning.gd")
const DriftTuning := preload("res://vehicle/tuning/drift_tuning.gd")
const DriveTuning := preload("res://vehicle/tuning/drive_tuning.gd")
const SuspensionTuning := preload("res://vehicle/tuning/suspension_tuning.gd")
const TyreTuning := preload("res://vehicle/tuning/tyre_tuning.gd")
const WheelMod := preload("res://vehicle/modules/wheel.gd")
const DriveMod := preload("res://vehicle/modules/drive.gd")
const DriftMod := preload("res://vehicle/modules/drift.gd")
const BoostMod := preload("res://vehicle/modules/boost.gd")
const ThrusterMod := preload("res://vehicle/modules/thruster.gd")
const PowerMod := preload("res://vehicle/modules/power.gd")
const ImpactMod := preload("res://vehicle/modules/impact.gd")
const AirMod := preload("res://vehicle/modules/car_air.gd")

var spec: CarSpec = null
## The car turns itself back onto its wheels (the car of the player, see ArcadeCar.self_righting).
var righting: bool = false
var wheels: Array[WheelMod] = []
var drive: DriveMod = null
var drift: DriftMod = null
var boost: BoostMod = null
var thruster: ThrusterMod = null
var power: PowerMod = null
var impact: ImpactMod = null
## The air part: the thrusters, the landing cushion and the air control.
var air: AirMod = AirMod.new()
## The contact patches (from the origin of the body) and the lateral caps (N) of the wheels in this tick (the tyre solver).
var _tyre_offsets := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
var _tyre_caps := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])

# The input of this tick.
var throttle: float = 0.0
var brake: float = 0.0
var steer: float = 0.0
var drift_held: bool = false
## True when the steering input has to be ramped (the keyboard ramps, the stick does not).
var steer_ramp: bool = true
## The height of the ground under the car (the landing cushion needs it).
var ground_y: float = 0.0

# The results of the tick.
## Wheels on the ground.
var grounded: int = 0
## The speed cap in m/s that the battery and the boosts allow.
var speed_cap: float = 0.0
## Set on the tick the car touches the ground.
var landed: bool:
	get:
		return air.landed
var landing_quality: StringName:
	get:
		return air.landing_quality
var landing_airtime: float:
	get:
		return air.landing_airtime
var landing_impact: float:
	get:
		return air.landing_impact
## The instant speed kick of a perfect mini boost (m/s).
var perfect_kick: float = 0.0
## True while the car is off the ground.
var airborne: bool:
	get:
		return air.airborne
## True while the air gravity (2 g) should be applied.
var air_gravity: bool:
	get:
		return air.air_gravity
## The linear damping the engine applies on top of the body value (the project default).
var engine_damp: float = 0.0
## The body-frame lateral velocity of the last tick.
var lateral_speed: float = 0.0
## The forward speed of the last tick (m/s).
var forward_speed: float = 0.0
## True on the tick a hop fired.
var hopped: bool:
	get:
		return air.hopped


## Applies every force of one physics tick.
func apply(state: PhysicsDirectBodyState3D, dt: float) -> void:
	var basis: Basis = state.transform.basis
	var up: Vector3 = basis.y
	var fwd: Vector3 = -basis.z
	var right: Vector3 = basis.x
	var velocity: Vector3 = state.linear_velocity
	forward_speed = velocity.dot(fwd)
	lateral_speed = velocity.dot(right)
	var speed: float = velocity.length()
	var com_offset: Vector3 = basis * spec.center_of_mass
	# The perfect mini boost: an instant kick along the forward axis.
	if perfect_kick > 0.0:
		state.apply_central_impulse(fwd * spec.mass * perfect_kick)
		perfect_kick = 0.0
	# 1. the wheel probes are cast outside the physics step; count the contacts.
	grounded = 0
	for w in wheels:
		if w.contact:
			grounded += 1
	# The share of the wheels that touch the ground. Everything that works through the wheels
	# (the motor, the brake, the downforce, the drift yaw and the drift assist) is scaled with
	# it: a car that leaves the ground does not get the ground forces any more.
	var ground_share: float = float(grounded) / float(maxi(wheels.size(), 1))
	# 2. the suspension and the anti roll bars
	_apply_suspension(state, basis, up)
	_apply_anti_roll(state, basis, up)
	# 3. the tyre lateral forces
	_apply_tyres(state, basis, up, right, dt)
	# 4. drive, brake, coast
	speed_cap = power.speed_cap(boost.speed_cap)
	drive.update_steer(steer, dt, forward_speed, steer_ramp)
	drive.update_drive(forward_speed, throttle, brake, speed_cap, dt)
	# The motor and the brake only work through the wheels that touch the ground: in the air
	# the car keeps its speed (the 空喷 is the only air speed source, dossier 4.8).
	var accel: float = (drive.drive_accel + boost.boost_accel()) * _drive_contact_scale()
	if forward_speed >= speed_cap:
		# The cap is the top speed: no power above it, the soft pull-back brings the car back.
		accel = 0.0
	if accel != 0.0:
		state.apply_force(fwd * spec.mass * accel, com_offset)
	var brake_force: float = drive.brake_force * _brake_contact_scale()
	if brake_force > 0.0:
		state.apply_force(-fwd * brake_force, com_offset)
	if speed > BodyTuning.MIN_DRAG_SPEED:
		var drag_dir: Vector3 = velocity / speed
		if grounded > 0 and throttle < DriveTuning.IDLE_INPUT and brake < DriveTuning.IDLE_INPUT:
			# The coast drag is the resistance of the drivetrain: in the air there is none.
			state.apply_force(-drag_dir * spec.mass * drive.coast_accel(speed), com_offset)
		state.apply_force(-drag_dir * drive.aero_drag(speed), com_offset)
	if grounded > 0 and speed < BodyTuning.PARK_SPEED \
			and throttle < DriveTuning.IDLE_INPUT and brake < DriveTuning.IDLE_INPUT:
		# The park rule: the car does not creep (dossier 4.7). Only the ground-plane velocity
		# is zeroed: the vertical part still settles the suspension, and the pitch and the roll
		# rates are never touched.
		state.linear_velocity = Vector3.UP * velocity.dot(Vector3.UP)
	# The engine adds the project default linear damping to the body value; the dossier wants
	# no engine damping (the coast drag is explicit), so the drag is cancelled here.
	if engine_damp > 0.0:
		# Only the horizontal part: the air gravity has to stay exact for the hop apex.
		var flat_v: Vector3 = velocity - up * velocity.dot(up)
		state.apply_force(flat_v * (engine_damp * spec.mass), com_offset)
	# 5. the drift assists
	_apply_drift(state, basis, up, speed, ground_share, dt)
	# The wall glance assist: the car is pulled along the wall for a moment.
	if impact.glancing:
		state.apply_torque(up * impact.glance_torque)
	# 6. the speed cap
	if forward_speed > speed_cap:
		state.apply_force(fwd * spec.mass * (-DriveTuning.CAP_PULL * (forward_speed - speed_cap)),
				com_offset)
	# 7. downforce, upright torque, yaw damping
	# The downforce is the downforce of the fan car: it needs the ground under it, so it is
	# scaled with the share of the wheels that touch the ground (a hop is not pulled down).
	state.apply_force(-up * BodyTuning.DOWNFORCE_K * speed * speed * ground_share, com_offset)
	_apply_upright(state, up)
	# 8. the thrusters and the air control
	air.grounded = grounded
	air.ground_y = ground_y
	air.throttle = throttle
	air.brake = brake
	air.steer = steer
	air.apply(state, basis, up, velocity, dt)


## The normal of the ground under the car: the mean of the contact normals of the wheels that touch it, or zero when
## fewer than two wheels do (the car is in the air or on one wheel).
func ground_normal() -> Vector3:
	if grounded < 2:
		return Vector3.ZERO
	var n: Vector3 = Vector3.ZERO
	for w in wheels:
		if w.contact:
			n += w.contact_normal
	return n.normalized() if n.length() > 0.001 else Vector3.ZERO


## True while the car's own hop is under way (its impulse is not a solver spike).
func own_kick() -> bool:
	return air.hop_flight or air.hopped


## The share of the driven wheels that touch the ground: the motor can only push through them.
func _drive_contact_scale() -> float:
	var driven: int = 0
	var touching: int = 0
	for i in wheels.size():
		if not spec.is_driven(i):
			continue
		driven += 1
		if wheels[i].contact:
			touching += 1
	if driven == 0:
		return 0.0
	return float(touching) / float(driven)


## The share of the wheels that touch the ground: the brake can only bite through them.
func _brake_contact_scale() -> float:
	return float(grounded) / float(maxi(wheels.size(), 1))


## The spring and damper forces of the four wheels.
func _apply_suspension(state: PhysicsDirectBodyState3D, basis: Basis, up: Vector3) -> void:
	# During the take-off of a hop the wheels leave the ground: the rebound damper would eat
	# the launch, so it is off until the car is in the air.
	var damp_mult: float = 0.0 if air.hop_flight else \
		(SuspensionTuning.LAND_DAMP_MULT if air.landing_damp > 0.0 else 1.0)
	for w in wheels:
		if not w.contact:
			w.load = 0.0
			continue
		var v_mount: Vector3 = state.get_velocity_at_local_position(basis * w.mount)
		var f: float = w.suspension_force(v_mount, up, damp_mult)
		w.load = f
		if f > 0.0:
			state.apply_force(w.contact_normal * f, basis * w.mount)


## The anti roll bars: the more compressed side is pushed up (dossier 4.4).
func _apply_anti_roll(state: PhysicsDirectBodyState3D, basis: Basis, up: Vector3) -> void:
	var front: float = spec.arb_front * (wheels[0].compression - wheels[1].compression)
	var rear: float = spec.arb_rear * (wheels[2].compression - wheels[3].compression)
	state.apply_force(up * front, basis * wheels[0].mount)
	state.apply_force(up * -front, basis * wheels[1].mount)
	state.apply_force(up * rear, basis * wheels[2].mount)
	state.apply_force(up * -rear, basis * wheels[3].mount)


## The lateral tyre forces, applied at the contact patch (the same point where the slip is
## measured).
## The lateral forces of the tyres. The two axles are solved together: the impulse of one axle changes the lateral speed at the
## other through the turn and the roll of the body (its inverse mass and inverse inertia), so the slip at the contacts goes away
## within one tick whatever the length of the tick, and every wheel gives at most its grip (mu x load x the grip curve of its
## slip). The law before took the slip of every wheel away for a quarter of the mass, as if the body did not turn: the rear
## over-corrected, at 60 Hz its slip changed its sign every tick and the cornering fell 9-18 %.
func _apply_tyres(state: PhysicsDirectBodyState3D, basis: Basis, up: Vector3, right: Vector3,
		dt: float) -> void:
	var com: Vector3 = state.center_of_mass
	# The contact patches were found by the probes of the last tick (the probes are cast outside the step): the car has driven on
	# since, and they lie behind the wheels by its speed times a tick (0.19 m at 80 km/h at 120 Hz). The grip of the tuning holds
	# the lag of a tick of TyreTuning.REFERENCE_STEP: at another rate the patches are moved by the difference of the two ticks, so
	# the car corners as it was tuned (with the lag of its own tick the full wheel turned the car 9-18 % less at 60 Hz, 5-10 % more
	# at 240 Hz: the forces of the front axle lose their lever when the patches lie further back, the rear axle gains it).
	var lag: Vector3 = state.linear_velocity * (dt - TyreTuning.REFERENCE_STEP)
	# The lateral axis of each axle: the steered one of the front, the axis of the body at the rear.
	var dir_f: Vector3 = right.rotated(up, -drive.steer_angle)
	var dir_r: Vector3 = right
	# Per axle: the mean contact point, the sum of the caps of its wheels (N), the wheels that grip.
	var arm_f := Vector3.ZERO
	var arm_r := Vector3.ZERO
	var cap_f := 0.0
	var cap_r := 0.0
	var n_f := 0
	var n_r := 0
	for i in wheels.size():
		var w: WheelMod = wheels[i]
		_tyre_caps[i] = 0.0
		if not w.contact:
			w.slip = 0.0
			continue
		var front: bool = i < 2
		var wheel_right: Vector3 = dir_f if front else dir_r
		# The steered forward axis of this wheel: the slip angle is measured along it, so the
		# grip does not depend on the compass heading of the car.
		var wheel_fwd: Vector3 = up.cross(wheel_right).normalized()
		# The tyre force is applied at the contact patch, the same point where the slip is
		# measured. Applying it at a different height would pump energy into the roll mode
		# (the force and the slip would not cancel each other's work).
		var offset: Vector3 = w.contact_point + lag - state.transform.origin
		_tyre_offsets[i] = offset
		var v_pt: Vector3 = state.get_velocity_at_local_position(offset)
		var mu: float = spec.mu_front if front else spec.mu_rear * drift.rear_mu
		mu *= drift.tyre_scale
		# The slip angle of this tyre, before the force (the grip curve, the squeal and the smoke).
		var v_long: float = v_pt.dot(wheel_fwd)
		w.slip = rad_to_deg(atan2(absf(v_pt.dot(wheel_right)),
				maxf(absf(v_long), TyreTuning.SLIP_MIN_FWD)))
		var cap: float = w.lateral_cap(w.slip, mu)
		_tyre_caps[i] = cap
		if cap > 0.0:
			if front:
				arm_f += offset
				cap_f += cap
				n_f += 1
			else:
				arm_r += offset
				cap_r += cap
				n_r += 1
		# The visual wheel spin.
		w.travel += v_long * dt
		w.spin = -w.travel / maxf(w.radius, TyreTuning.SPIN_MIN_RADIUS)
	if n_f == 0 and n_r == 0:
		return
	# The lateral speed at the contacts of an axle (its mean point, from the centre of mass), and what an impulse along the
	# lateral axis of one axle does to it at the other: K = 1/m t_a.t_b + (r_b x t_b).I^-1 (r_a x t_a).
	var inv_mass: float = state.inverse_mass
	var inv_inertia: Basis = state.inverse_inertia_tensor
	var v: Vector3 = state.linear_velocity
	var spin: Vector3 = state.angular_velocity
	if n_f > 0:
		arm_f = arm_f / float(n_f) - com
	if n_r > 0:
		arm_r = arm_r / float(n_r) - com
	var turn_f: Vector3 = arm_f.cross(dir_f)
	var turn_r: Vector3 = arm_r.cross(dir_r)
	var vel_f: float = dir_f.dot(v) + turn_f.dot(spin)
	var vel_r: float = dir_r.dot(v) + turn_r.dot(spin)
	var k_ff: float = inv_mass + turn_f.dot(inv_inertia * turn_f)
	var k_rr: float = inv_mass + turn_r.dot(inv_inertia * turn_r)
	var k_fr: float = inv_mass * dir_f.dot(dir_r) + turn_f.dot(inv_inertia * turn_r)
	# The impulses of this tick (N s): the most an axle gives is its cap for the length of the tick.
	var most_f: float = cap_f * dt
	var most_r: float = cap_r * dt
	var lam_f := 0.0
	var lam_r := 0.0
	if n_f > 0 and n_r > 0:
		var det: float = k_ff * k_rr - k_fr * k_fr
		if det > TyreTuning.SOLVE_MIN_DET:
			lam_f = (k_fr * vel_r - k_rr * vel_f) / det
			lam_r = (k_fr * vel_f - k_ff * vel_r) / det
		if absf(lam_f) > most_f or absf(lam_r) > most_r:
			# An axle at its grip gives its grip: the other one is solved again with it.
			lam_f = clampf(lam_f, -most_f, most_f)
			for k in TyreTuning.SOLVE_PASSES:
				lam_r = clampf(-(vel_r + k_fr * lam_f) / k_rr, -most_r, most_r)
				lam_f = clampf(-(vel_f + k_fr * lam_r) / k_ff, -most_f, most_f)
	elif n_f > 0:
		lam_f = clampf(-vel_f / k_ff, -most_f, most_f)
	else:
		lam_r = clampf(-vel_r / k_rr, -most_r, most_r)
	# Every wheel takes the share of its cap of the impulse of its axle, at its own contact patch.
	for i in wheels.size():
		var cap_i: float = _tyre_caps[i]
		if cap_i <= 0.0:
			continue
		if i < 2:
			state.apply_force(dir_f * (lam_f * cap_i / cap_f / dt), _tyre_offsets[i])
		else:
			state.apply_force(dir_r * (lam_r * cap_i / cap_r / dt), _tyre_offsets[i])


## The drift: yaw torque, lateral assist and the speed loss. The recover shares the path: the
## yaw torque and the lateral assist straighten the car, so the nose is straight before the
## 小喷 window opens (dossier 4.6, the RECOVER row).
## The drift works through the wheels: the yaw torque and the assist are scaled with the share
## of the wheels that touch the ground, so they stop as soon as the car leaves the ground (a
## hop, a crest or a ramp is not pulled down by the drift). The yaw in the air belongs to
## car_air._apply_air_control.
func _apply_drift(state: PhysicsDirectBodyState3D, basis: Basis, up: Vector3, speed: float,
		ground_share: float, dt: float) -> void:
	var fwd: Vector3 = -basis.z
	drift.update(dt, drive.steer_value(), drift_held, forward_speed, speed, grounded,
			state.angular_velocity.y, lateral_speed, forward_speed)
	if drift.yaw_kick != 0.0:
		state.apply_torque(up * drift.yaw_kick)
		drift.yaw_kick = 0.0
	var drifting: bool = drift.state == &"drift"
	if drifting or drift.state == &"recover":
		state.apply_torque(up * drift.yaw_torque * ground_share)
		var com: Vector3 = state.transform.basis * spec.center_of_mass
		var velocity: Vector3 = state.linear_velocity
		if drift.assist_accel > 0.0 and velocity.length() > DriftTuning.DRIFT_ASSIST_MIN_SPEED:
			# The velocity steering: perpendicular to the velocity, towards the nose. It turns
			# the velocity onto the nose without taking energy out of the car. The assist is
			# built in the ground plane (the flat velocity and the flat nose), so it never has
			# a component along the up axis: it can never pull a hopping car down.
			var v_flat: Vector3 = velocity - up * velocity.dot(up)
			var f_flat: Vector3 = fwd - up * fwd.dot(up)
			if v_flat.length() > TyreTuning.MIN_VECTOR and f_flat.length() > TyreTuning.MIN_VECTOR:
				var v_dir: Vector3 = v_flat.normalized()
				var f_dir: Vector3 = f_flat.normalized()
				var to_nose: Vector3 = f_dir - v_dir * f_dir.dot(v_dir)
				if to_nose.length() > TyreTuning.MIN_VECTOR:
					var assist: float = drift.assist_accel * ground_share
					state.apply_force(to_nose.normalized() * spec.mass * assist, com)
		if drifting and velocity.length() > DriftTuning.DRIFT_ASSIST_MIN_SPEED:
			state.apply_force(-velocity.normalized() * spec.mass * drift.loss_accel, com)


## Keeps the body level and damps the yaw in grip (dossier 4.7). A car with fewer than two wheels down that leans on its body is
## turned back onto its wheels (_apply_righting).
func _apply_upright(state: PhysicsDirectBodyState3D, up: Vector3) -> void:
	if grounded < 2:
		_apply_righting(state, up)
		return
	var n: Vector3 = Vector3.UP
	for w in wheels:
		if w.contact:
			n += w.contact_normal
	n = n.normalized()
	var inertia: float = (spec.inertia.x + spec.inertia.z) * 0.5
	var torque: Vector3 = up.cross(n) * (BodyTuning.UPRIGHT_K * inertia)
	var av: Vector3 = state.angular_velocity
	torque -= (av - up * av.dot(up)) * (BodyTuning.UPRIGHT_D * inertia)
	# The rollover guard: a big roll gets extra upright torque.
	var roll_deg: float = absf(rad_to_deg(acos(clampf(up.dot(n), -1.0, 1.0))))
	if roll_deg > BodyTuning.ROLLOVER_DEG:
		torque *= BodyTuning.ROLLOVER_MULT
	state.apply_torque(torque)
	if drift.state == &"grip":
		state.apply_torque(up * (-spec.inertia.y * BodyTuning.YAW_DAMP_GRIP * av.y))


## The righting (BodyTuning.RIGHTING_*): a car that touches something with its body, with fewer than two wheels on the ground and
## a tilt of 30 degrees or more, is turned back towards the vertical. In the air the auto level of car_air does it, and a barrel
## roll is a stunt that turns the car on purpose. Only the car of the player has it (`righting`).
func _apply_righting(state: PhysicsDirectBodyState3D, up: Vector3) -> void:
	if not righting or state.get_contact_count() == 0 or (thruster != null and thruster.rolling):
		return
	var tilt: float = acos(clampf(up.dot(Vector3.UP), -1.0, 1.0))
	if tilt < deg_to_rad(BodyTuning.RIGHTING_MIN_DEG):
		return
	var axis: Vector3 = up.cross(Vector3.UP)
	if axis.length() < 0.001:
		# on its roof exactly: it turns about its own length
		axis = -state.transform.basis.z
	axis = axis.normalized()
	var inertia: float = (spec.inertia.x + spec.inertia.z) * 0.5
	var av: Vector3 = state.angular_velocity
	var torque: Vector3 = axis * (BodyTuning.RIGHTING_K * inertia * tilt)
	torque -= (av - up * av.dot(up)) * (BodyTuning.RIGHTING_D * inertia)
	state.apply_torque(torque)


## The FX timers of the thrusters (the hop spike and the landing cushion).
func tick_effects(delta: float) -> void:
	air.tick_effects(delta)


## 1.0 while the hop jet is firing.
func hop_fx() -> float:
	return air.hop_fx()


## 1.0 while the landing cushion is firing.
func land_fx() -> float:
	return air.land_fx()
