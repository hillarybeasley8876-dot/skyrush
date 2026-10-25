extends Node
## The landing: a drop from 8 m at 150 km/h must not flip the car and must not make it drift
## sideways (dossier 4.8).
## Run: tools/godot.sh test res://vehicle/tests/test_landing.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	# The straight drop.
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 8.0, 0.0), 0.0)
	await t.run(0.2)
	t.set_speed(car, 150.0)
	var start: Vector3 = car.global_position
	var landed: bool = false
	for i in Engine.physics_ticks_per_second * 4:
		await t.step()
		if car.telemetry.grounded_wheels >= 3 and car.telemetry.airtime == 0.0:
			landed = true
			break
	t.check("the car landed", landed, "= %d wheels" % car.telemetry.grounded_wheels)
	t.check_range("the car is upright", absf(car.telemetry.pitch_deg), 0.0, 20.0)
	t.check_range("the car is level", absf(car.telemetry.roll_deg), 0.0, 20.0)
	# The lateral drift: the car must not slide sideways.
	var end: Vector3 = car.global_position
	var forward: Vector3 = -car.global_transform.basis.z
	var along: Vector3 = Vector3(end.x - start.x, 0.0, end.z - start.z)
	var lateral: float = along.dot(Vector3(forward.z, 0.0, -forward.x))
	t.check("the lateral drift", absf(lateral) < 0.3, "= %.3f m (along %.1f m)" % [lateral, along.length()])
	t.check("the speed is kept", car.telemetry.forward_speed_kmh > 100.0,
			"= %.1f km/h" % car.telemetry.forward_speed_kmh)
	# The misaligned drop: 10 degrees of roll, the car must not flip over.
	var car2: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(60.0, 8.0, 0.0), 0.0)
	await t.run(0.2)
	t.set_speed(car2, 150.0)
	# The roll is about the car's own forward axis, the position stays where it is.
	var basis: Basis = car2.global_transform.basis * Basis(Vector3(0.0, 0.0, -1.0), deg_to_rad(10.0))
	car2.global_transform = Transform3D(basis, car2.global_position)
	for i in Engine.physics_ticks_per_second * 8:
		await t.step()
		if car2.telemetry.grounded_wheels >= 3 and car2.telemetry.airtime == 0.0:
			break
	t.check("the misaligned landing", car2.telemetry.grounded_wheels >= 3,
			"= %d wheels" % car2.telemetry.grounded_wheels)
	t.check_range("the car did not flip", absf(car2.telemetry.roll_deg), 0.0, 45.0)
	t.finish()
