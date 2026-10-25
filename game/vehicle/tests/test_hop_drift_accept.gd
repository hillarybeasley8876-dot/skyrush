extends Node
## LEAD ACCEPTANCE TEST (not owned by any worker job): a hop must not be pulled down by the drift assist.
## Review vehicle-r4 MUST-FIX 1: a hop in a drift (or <= 0.37 s after its release) reached only 1.2 / 0.9 m and a
## Big Hop 2.3 m instead of 3.1 / 7.8 m, because the drift/recover assist kept working in the air and pointed down.
##
## 200 km/h, drift held 1.5 s, then: a tap hop, a Big Hop; and a tap hop 0.05 s and 0.30 s after releasing the drift.
## The straight hop at the same speed is the reference (it must keep passing).
## Run: python tools/gd.py test res://vehicle/tests/test_hop_drift_accept.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const BoostTuning := preload("res://vehicle/tuning/boost_tuning.gd")

const SPEED_KMH := 200.0
const DRIFT_TIME := 1.5


## Fires a hop (tap or Big Hop) and returns [apex height above the take-off, |roll| in degrees at touchdown].
func _hop(t: T, car: ArcadeCar, big: bool) -> Array:
	car.boost.n2 = BoostTuning.N2_MAX
	var ground: float = car.global_position.y
	var apex: float = 0.0
	var flew: bool = false
	var roll: float = 0.0
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
	for i in Engine.physics_ticks_per_second * 4:
		await t.step()
		apex = maxf(apex, car.global_position.y - ground)
		if car.telemetry.airborne:
			flew = true
		elif flew and car.telemetry.grounded_wheels >= 3:
			roll = absf(rad_to_deg(car.global_transform.basis.get_euler().z))
			break
	return [apex, roll]


## A fresh car at 200 km/h that has been drifting to the right for DRIFT_TIME seconds.
func _drifting_car(t: T) -> ArcadeCar:
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
	await t.run(0.5)
	t.set_speed(car, SPEED_KMH)
	car.set_controls(1.0, 0.0, 1.0, false)
	car.set_drift(true)
	await t.run(DRIFT_TIME)
	return car


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()

	# Reference: the same hop on a straight at the same speed.
	var ref: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
	await t.run(0.5)
	t.set_speed(ref, SPEED_KMH)
	ref.set_controls(0.2, 0.0, 0.0, false)
	await t.run(0.3)
	ref.set_controls(0.0, 0.0, 0.0, false)
	var straight: Array = await _hop(t, ref, false)
	t.check_range("reference: hop on a straight at 200 km/h", float(straight[0]), 2.8, 3.4)
	ref.queue_free()

	# A tap hop while the drift key is still held.
	var car: ArcadeCar = await _drifting_car(t)
	t.check("the car really is drifting before the hop", absf(rad_to_deg(car.drift.beta)) > 12.0,
			"= %.1f deg" % rad_to_deg(car.drift.beta))
	var held: Array = await _hop(t, car, false)
	t.check_range("hop in a held drift", float(held[0]), 2.8, 3.4)
	t.check("touchdown after the drift hop is level (|roll| < 5 deg)", float(held[1]) < 5.0, "= %.1f deg" % float(held[1]))
	car.queue_free()

	# A Big Hop while the drift key is still held.
	car = await _drifting_car(t)
	var big: Array = await _hop(t, car, true)
	t.check_range("Big Hop in a held drift", float(big[0]), 7.4, 8.2)
	car.queue_free()

	# A tap hop 0.05 s and 0.30 s after the drift was released (the state is still "drift").
	for delay: float in [0.05, 0.30]:
		car = await _drifting_car(t)
		car.set_drift(false)
		car.set_controls(1.0, 0.0, 0.0, false)
		await t.run(delay)
		var late: Array = await _hop(t, car, false)
		t.check_range("hop %.2f s after the drift release" % delay, float(late[0]), 2.8, 3.4)
		car.queue_free()
	t.finish()
