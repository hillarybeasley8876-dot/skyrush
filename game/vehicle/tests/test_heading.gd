extends Node
## The grip does not depend on the compass heading (the round 2 review): the slip angle of a
## tyre is measured along the steered wheel, not along the world axes, so a car that drives
## east has the same grip as a car that drives north.
## Run: tools/godot.sh test res://vehicle/tests/test_heading.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const SuspensionTuning := preload("res://vehicle/tuning/suspension_tuning.gd")

## The headings of the test: north (-Z), north-east, east and south.
const YAWS: Array[float] = [0.0, -PI * 0.25, -PI * 0.5, PI]


func _ready() -> void:
	_run.call_deferred()


## The cornering grip of a car at the given heading, in g.
func _grip(t: T, yaw: float) -> float:
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), yaw)
	await t.run(0.6)
	t.set_speed(car, 120.0)
	car.set_controls(0.35, 0.0, 0.6, false)
	var sum: float = 0.0
	var samples: int = 0
	for i in Engine.physics_ticks_per_second * 4:
		await t.step()
		if i < Engine.physics_ticks_per_second * 3:
			continue
		var v: Vector3 = car.linear_velocity
		v.y = 0.0
		# The centripetal acceleration of the corner: v * omega.
		var accel: float = v.length() * absf(car.angular_velocity.y)
		sum += accel
		samples += 1
	car.queue_free()
	await t.run(0.2)
	return sum / maxf(float(samples), 1.0) / SuspensionTuning.GRAVITY


## The slip angle and the gauge of a three second drift at the given heading.
func _drift(t: T, yaw: float) -> Dictionary:
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), yaw)
	await t.run(0.6)
	car.set_controls(1.0, 0.0, 0.0, false)
	for i in Engine.physics_ticks_per_second * 12:
		await t.step()
		if car.telemetry.forward_speed_kmh >= 200.0:
			break
	car.boost.n2 = 0.0
	car.set_drift(true)
	car.set_controls(1.0, 0.0, 1.0, false)
	for i in Engine.physics_ticks_per_second * 3 / 10:
		await t.step()
	var beta_sum: float = 0.0
	var samples: int = 0
	for i in Engine.physics_ticks_per_second * 3:
		await t.step()
		if i >= Engine.physics_ticks_per_second:
			beta_sum += absf(car.telemetry.slip_angle_deg)
			samples += 1
	car.set_drift(false)
	car.set_controls(1.0, 0.0, -1.0, false)
	for i in Engine.physics_ticks_per_second * 3:
		await t.step()
		if car.telemetry.drift_state == &"grip":
			break
	var out: Dictionary = {"beta": beta_sum / maxf(float(samples), 1.0), "gauge": car.boost.n2}
	car.queue_free()
	await t.run(0.2)
	return out


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	# The cornering grip has to be the same for every heading.
	var reference: float = 0.0
	for i in YAWS.size():
		var grip: float = await _grip(t, YAWS[i])
		if i == 0:
			reference = grip
			t.check("the grip at the first heading", grip > 0.5, "= %.3f g" % grip)
		else:
			t.check_range("the grip at the heading %d" % i, grip,
					reference * 0.98, reference * 1.02)
	# The drift is the same for every heading too.
	var north: Dictionary = await _drift(t, 0.0)
	var east: Dictionary = await _drift(t, -PI * 0.5)
	t.check_range("the drift slip to the north", float(north["beta"]), 26.0, 52.0)
	t.check_range("the drift slip to the east", float(east["beta"]), 26.0, 52.0)
	t.check_range("the slip difference", absf(float(north["beta"]) - float(east["beta"])),
			0.0, 1.0)
	t.check_range("the gauge difference", absf(float(north["gauge"]) - float(east["gauge"])),
			0.0, 2.0)
	t.finish()
