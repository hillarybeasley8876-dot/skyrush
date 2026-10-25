extends Node
## Extra cases for the job "a hop must not be pulled down by the drift assist".
## The lead's acceptance test (test_hop_drift_accept.gd) owns the four design cases; this file
## owns the extra ones: a hop from the recover state, a hop at 100 km/h in a drift, a drift off
## a crest (the car leaves the ground while it drifts) and the vertical trace that shows that
## nothing pulls the car down while the car flies.
##
## Run: python tools/gd.py test res://vehicle/tests/test_hop_drift_cases.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const BoostTuning := preload("res://vehicle/tuning/boost_tuning.gd")

const SPEED_KMH := 200.0
const DRIFT_TIME := 1.5
## The biggest downward acceleration the flight may have on top of the gravity (m/s^2).
const MAX_EXTRA_PULL := 6.0
## The biggest turn of the velocity direction the flight may have (degrees).
const MAX_FLIGHT_TURN := 3.0
## The gravity of the world (m/s^2).
const GRAVITY := 9.81
## True while the hop prints its trace (the probe of the diagnosis).
var _trace: bool = false


## What one flight did: the apex, the roll at the touchdown, the extra downward pull of the
## flight (on top of the gravity) and the turn of the velocity while the car was in the air.
class HopTrace:
	var apex: float = 0.0
	var roll: float = 0.0
	var extra_pull: float = 0.0
	var turn: float = 0.0
	var flew: bool = false
	## The drift state at the take-off.
	var takeoff_state: StringName = &""


## The horizontal direction of a velocity.
func _flat_dir(v: Vector3) -> Vector3:
	var flat: Vector3 = v - Vector3.UP * v.dot(Vector3.UP)
	if flat.length() < 0.001:
		return Vector3.FORWARD
	return flat.normalized()


## Traces the flight of the car until it lands (or the time is up). The trace shows the
## vertical acceleration (the gravity is 2 g in the air) and the turn of the velocity: the
## drift assist must not work while the car flies.
func _flight(t: T, car: ArcadeCar, ground: float, seconds: float) -> HopTrace:
	var tr: HopTrace = HopTrace.new()
	var prev_vy: float = car.linear_velocity.y
	var first_dir: Vector3 = Vector3.FORWARD
	for i in int(seconds * Engine.physics_ticks_per_second):
		await t.step()
		var v: Vector3 = car.linear_velocity
		var accel: float = (v.y - prev_vy) * Engine.physics_ticks_per_second
		prev_vy = v.y
		tr.apex = maxf(tr.apex, car.global_position.y - ground)
		if not car.telemetry.airborne:
			if tr.flew:
				tr.roll = absf(rad_to_deg(car.global_transform.basis.get_euler().z))
				break
			continue
		if not tr.flew:
			tr.flew = true
			tr.takeoff_state = car.drift.state
			first_dir = _flat_dir(v)
			continue
		tr.extra_pull = maxf(tr.extra_pull, -(accel) - 2.0 * GRAVITY)
		tr.turn = maxf(tr.turn, rad_to_deg(_flat_dir(v).angle_to(first_dir)))
		if _trace and i % 6 == 0:
			print("TRACE t=%.2f grounded=%d vy=%.2f ay=%.1f state=%s beta=%.1f assist=%.0f pull=%.1f" % [
					float(i) / Engine.physics_ticks_per_second, car.telemetry.grounded_wheels, v.y, accel, car.drift.state,
					rad_to_deg(car.drift.beta), car.drift.assist_accel, tr.extra_pull])
	return tr


## Fires a hop (a tap or a Big Hop) and traces the flight.
func _hop(t: T, car: ArcadeCar, big: bool) -> HopTrace:
	var ground: float = car.global_position.y
	car.boost.n2 = BoostTuning.N2_MAX
	car.thruster.hop_held = true
	car.thruster.hop_pressed = true
	await t.step()
	car.thruster.hop_pressed = false
	if big:
		for i in Engine.physics_ticks_per_second / 3:
			await t.step()
	car.thruster.hop_held = false
	car.thruster.hop_released = true
	await t.step()
	car.thruster.hop_released = false
	return await _flight(t, car, ground, 4.0)


## A fresh car that drifts to the right at the given speed.
func _drifting_car(t: T, kmh: float) -> ArcadeCar:
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
	await t.run(0.5)
	t.set_speed(car, kmh)
	car.set_controls(1.0, 0.0, 1.0, false)
	car.set_drift(true)
	await t.run(DRIFT_TIME)
	return car


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()

	# The probe: a hop in a held drift, with the trace of the flight.
	var car: ArcadeCar = await _drifting_car(t, SPEED_KMH)
	_trace = true
	var probe: HopTrace = await _hop(t, car, false)
	_trace = false
	print("PROBE hop in a held drift: apex=%.3f pull=%.1f turn=%.2f" % [
			probe.apex, probe.extra_pull, probe.turn])
	car.queue_free()

	# A hop from the recover state (the drift was released and the car is straightening).
	car = await _drifting_car(t, SPEED_KMH)
	car.set_drift(false)
	car.set_controls(1.0, 0.0, -1.0, false)
	await t.run_until(func() -> bool: return car.drift.state == &"recover", 1.5)
	t.check("the drift ended in the recover state", car.drift.state == &"recover",
			"= %s" % car.drift.state)
	var rec: HopTrace = await _hop(t, car, false)
	t.check("the hop was fired in the recover state", rec.takeoff_state == &"recover",
			"= %s" % rec.takeoff_state)
	t.check_range("hop from the recover state", rec.apex, 2.8, 3.4)
	t.check("nothing pulls the car down in the air (extra pull <= %.0f m/s^2)" % MAX_EXTRA_PULL,
			rec.extra_pull <= MAX_EXTRA_PULL, "= %.1f m/s^2" % rec.extra_pull)
	t.check("the velocity does not turn in the air (<= %.0f deg)" % MAX_FLIGHT_TURN,
			rec.turn <= MAX_FLIGHT_TURN, "= %.2f deg" % rec.turn)
	car.queue_free()

	# A hop at 100 km/h in a held drift.
	car = await _drifting_car(t, 100.0)
	var slow: HopTrace = await _hop(t, car, false)
	t.check_range("hop at 100 km/h in a held drift", slow.apex, 2.8, 3.4)
	car.queue_free()

	# A drift off a crest: the car leaves the ground while it drifts.
	car = await _drifting_car(t, SPEED_KMH)
	var ground: float = car.global_position.y
	car.linear_velocity.y = 8.0
	var crest: HopTrace = await _flight(t, car, ground, 2.0)
	t.check("the car really left the ground", crest.flew, "")
	t.check("nothing pulls the car down over a crest (extra pull <= %.0f m/s^2)" % MAX_EXTRA_PULL,
			crest.extra_pull <= MAX_EXTRA_PULL, "= %.1f m/s^2" % crest.extra_pull)
	t.check("the velocity does not turn in the air (<= %.0f deg)" % MAX_FLIGHT_TURN,
			crest.turn <= MAX_FLIGHT_TURN, "= %.2f deg" % crest.turn)
	car.queue_free()

	t.finish()
