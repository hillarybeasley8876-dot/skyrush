extends RefCounted
## Impact detection and the wall glance assist (dossier 7.2). The vehicle unit only *reports*
## impacts - the damage unit decides what a hit costs. Jolt contact impulses are estimates, so
## the hit is detected from the velocity change per tick (dossier 6.5) and the contact list
## supplies the other body, the point and the normal.
##
## The impulse that goes to the damage unit is mass * the change of the speed of the car in
## the step of the hit, so it is the real momentum change and not the closing speed of the two
## cars: a car that meets a slow car head-on only loses the part of the speed that the other
## car did not take.

const BodyTuning := preload("res://vehicle/tuning/body_tuning.gd")
const ImpactTuning := preload("res://vehicle/tuning/impact_tuning.gd")
const DriftMod := preload("res://vehicle/modules/drift.gd")

## True on the tick a hit was detected.
var hit: bool = false
## The other body of the hit.
var other: Node3D = null
## The momentum the hit took from the car (N*s).
var impulse: float = 0.0
## World point and normal of the contact.
var point: Vector3 = Vector3.ZERO
var normal: Vector3 = Vector3.UP
## 0 = a scrape, 1 = head on.
var impact: float = 0.0
## The yaw torque the car body applies for the glance assist (N*m).
var glance_torque: float = 0.0
## True while the glance assist is running.
var glancing: bool = false
## How many solver spikes the guard has cut (a test reads it).
var spikes: int = 0
## What the guard saw on the last tick (the fuzz drive records it): the box contacts, the speed away from the ground and
## whether the guard was holding.
var seen_contacts: int = 0
var seen_away: float = 0.0
var seen_holding: bool = false

var _prev_velocity: Vector3 = Vector3.ZERO
## The seconds the solver spike guard still holds after a spike.
var _spike_hold: float = 0.0
var _last_report: Dictionary = {}
var _glance_timer: float = 0.0
var _glance_torque: float = 0.0
var _clock: float = 0.0


## Detects the hits of this tick.
## car: the vehicle (for the event bus and the mass).
## state: the physics state of the body.
## drift: the drift module (a hard hit cancels the drift reward), may be null.
func tick(dt: float, car: VehicleBase, state: PhysicsDirectBodyState3D, mass: float,
		drift: DriftMod, ground_normal: Vector3 = Vector3.ZERO, own_kick: bool = false) -> void:
	_clock += dt
	hit = false
	other = null
	impulse = 0.0
	impact = 0.0
	if _glance_timer > 0.0:
		_glance_timer = maxf(_glance_timer - dt, 0.0)
		glancing = _glance_timer > 0.0
		glance_torque = _glance_torque if glancing else 0.0
	var velocity: Vector3 = state.linear_velocity
	velocity = _guard_solver_spike(state, velocity, ground_normal, own_kick, dt)
	var dv: Vector3 = velocity - _prev_velocity
	# The velocity before this step: the hit is measured with it, not with what is left after
	# the bounce.
	var before: Vector3 = _prev_velocity
	_prev_velocity = velocity
	if dv.length() < ImpactTuning.IMPACT_MIN_DV:
		return
	# Pick the contact that best explains the velocity change.
	var best_index: int = -1
	var best_score: float = ImpactTuning.IMPACT_SCORE_MIN
	var count: int = state.get_contact_count()
	for i in count:
		var n: Vector3 = state.get_contact_local_normal(i)
		var score: float = (-dv).normalized().dot(n)
		if score > best_score:
			best_score = score
			best_index = i
	if best_index < 0:
		return
	var contact_normal: Vector3 = state.get_contact_local_normal(best_index)
	var contact_point: Vector3 = state.get_contact_local_position(best_index)
	var collider: Object = state.get_contact_collider_object(best_index)
	var other_v: Vector3 = Vector3.ZERO
	if collider is RigidBody3D:
		other_v = (collider as RigidBody3D).linear_velocity
	var v_rel: Vector3 = before - other_v
	var v_n: float = maxf(0.0, -v_rel.dot(contact_normal))
	var rel_len: float = maxf(v_rel.length(), ImpactTuning.IMPACT_MIN_REL)
	var ratio: float = clampf(v_n / rel_len, 0.0, 1.0)
	# A floor touch (the normal points up) is only a crash when it is fast.
	var up_dot: float = contact_normal.dot(state.transform.basis.y)
	if up_dot > ImpactTuning.FLOOR_CONTACT_NORMAL and v_n < ImpactTuning.IMPACT_FLOOR_MIN:
		return
	hit = true
	other = collider as Node3D
	# The impulse the hit took from the car: the momentum that was really transferred. It is
	# the change of the speed of the car in the step of the hit and not the closing speed of
	# the two cars: a car that is pushed along keeps its speed, and the closing speed would
	# score the hit like a head-on (a car that meets a slow car head-on would pay for the
	# speed of the other car).
	impulse = mass * dv.length()
	point = contact_point
	normal = contact_normal
	impact = ratio
	if drift != null:
		drift.on_impact(ratio)
	# The arcade wall rule (dossier 7.2): a scrape keeps 95 % of the tangential speed, a hit
	# keeps (1 - 0.45 * impact) and bounces off at 0.25.
	if not (collider is RigidBody3D):
		_apply_wall_response(state, contact_normal, v_rel, ratio)
		# The response just changed the speed of the car. The next tick must not read that
		# change as a new hit: the rule of a graze would be applied to the crash and would
		# give the speed back (the car would drive away from the wall faster than it hit it).
		_prev_velocity = state.linear_velocity
	# One report per contact pair every IMPACT_COOLDOWN seconds.
	if other != null:
		var key: int = other.get_instance_id()
		var last: float = float(_last_report.get(key, BodyTuning.TIME_NEVER))
		if _clock - last >= ImpactTuning.IMPACT_COOLDOWN:
			_last_report[key] = _clock
			Events.vehicle_collided.emit(car, other, impulse, point, normal)
	_prune_reports()


## The solver spike guard (ImpactTuning.SOLVER_SPIKE): a car that stands on its wheels moves along the ground; the speed it
## has AWAY from the ground (along the normal of the ground under its wheels) is a bounce of a few m/s. When the solver
## gives it a spike of more than SOLVER_SPIKE (the edge of a kerb gave 10 m/s in the first tick and 31 m/s in the third) the
## guard holds for SOLVER_HOLD seconds: the speed away from the ground is cut to SOLVER_KICK_UP and the spin is limited. The
## small pushes of two cars that overlap are left alone. A ramp is not touched: the speed of a car on a ramp runs along
## the ramp, not away from it. Only a car that touches something with its BOX is looked at (the wheels are probes: a car
## that drives on them has no contact). `ground_normal` is zero when fewer than two wheels touch the ground (a car in the
## air is not looked at: a landing stops a fall, a lane has its own speed) and `own_kick` is true while the car's own hop is
## under way. Returns the velocity.
func _guard_solver_spike(state: PhysicsDirectBodyState3D, velocity: Vector3, ground_normal: Vector3,
		own_kick: bool, dt: float) -> Vector3:
	_spike_hold = maxf(_spike_hold - dt, 0.0)
	seen_contacts = state.get_contact_count()
	seen_away = velocity.dot(ground_normal)
	seen_holding = _spike_hold > 0.0
	if own_kick or ground_normal == Vector3.ZERO or state.get_contact_count() == 0:
		return velocity
	var away: float = velocity.dot(ground_normal)
	if away > ImpactTuning.SOLVER_SPIKE:
		_spike_hold = ImpactTuning.SOLVER_HOLD
	if _spike_hold <= 0.0 or away <= ImpactTuning.SOLVER_KICK_UP:
		return velocity
	velocity -= ground_normal * (away - ImpactTuning.SOLVER_KICK_UP)
	state.linear_velocity = velocity
	state.angular_velocity = state.angular_velocity.limit_length(ImpactTuning.SOLVER_SPIN)
	spikes += 1
	return velocity


## Removes the contacts that were not seen for a while.
func _prune_reports() -> void:
	var stale: Array = []
	for key: int in _last_report:
		if _clock - float(_last_report[key]) > ImpactTuning.IMPACT_REPORT_PRUNE:
			stale.append(key)
	for key: int in stale:
		_last_report.erase(key)


## The arcade wall response (dossier 7.2): the scrape keeps 95 % of the tangential speed and
## the car is yawed along the wall, a hit keeps (1 - 0.45 * impact) and bounces off at 0.25.
func _apply_wall_response(state: PhysicsDirectBodyState3D, contact_normal: Vector3,
		v_rel: Vector3, ratio: float) -> void:
	var n: Vector3 = contact_normal
	var vn: float = v_rel.dot(n)
	var tangent: Vector3 = v_rel - n * vn
	if tangent.length() < ImpactTuning.SCRAPE_MIN_TANGENT:
		return
	if ratio < ImpactTuning.IMPACT_SCRAPE:
		# A glance: keep the speed and pull the car along the wall.
		state.linear_velocity = tangent * ImpactTuning.SCRAPE_KEEP
		_apply_glance_yaw(state, tangent)
	else:
		# A hit: the arcade rule of the QQ clone.
		state.linear_velocity = tangent * (1.0 - ImpactTuning.HIT_TANGENTIAL_KEEP * ratio) \
				- n * vn * ImpactTuning.HIT_BOUNCE


## Yaws the car towards the wall tangent for a moment, so a glance does not spin the car.
func _apply_glance_yaw(state: PhysicsDirectBodyState3D, tangent: Vector3) -> void:
	var forward: Vector3 = -state.transform.basis.z
	var flat_forward: Vector3 = Vector3(forward.x, 0.0, forward.z)
	var flat_tangent: Vector3 = Vector3(tangent.x, 0.0, tangent.z)
	if flat_forward.length() < ImpactTuning.SCRAPE_MIN_TANGENT \
			or flat_tangent.length() < ImpactTuning.SCRAPE_MIN_TANGENT:
		return
	flat_forward = flat_forward.normalized()
	flat_tangent = flat_tangent.normalized()
	var cross: float = flat_forward.cross(flat_tangent).y
	var error: float = clampf(asin(clampf(cross, -1.0, 1.0)), -ImpactTuning.SCRAPE_YAW, ImpactTuning.SCRAPE_YAW)
	_glance_timer = ImpactTuning.SCRAPE_TIME
	_glance_torque = -error * ImpactTuning.SCRAPE_TORQUE
	glancing = true
	glance_torque = _glance_torque


## Clears the hit history (a respawn).
func reset() -> void:
	_prev_velocity = Vector3.ZERO
	_spike_hold = 0.0
	_last_report.clear()
	_glance_timer = 0.0
	_glance_torque = 0.0
	glancing = false
	glance_torque = 0.0
