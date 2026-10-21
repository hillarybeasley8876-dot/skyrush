extends Node
## The brake: 100 km/h to a standstill in less than 35 m (dossier 8.1: 16 m/s^2).
## Run: tools/godot.sh test res://vehicle/tests/test_brake.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
	await t.run(0.5)
	# Roll up to 100 km/h.
	car.set_controls(1.0, 0.0, 0.0, false)
	for i in 120 * 8:
		await t.step()
		if car.telemetry.forward_speed_kmh >= 100.0:
			break
	t.check_range("the roll up to 100 km/h", car.telemetry.forward_speed_kmh, 100.0, 115.0)
	# Brake.
	var start: Vector3 = car.global_position
	var brake_time: float = 0.0
	car.set_controls(0.0, 1.0, 0.0, false)
	for i in 120 * 6:
		await t.step()
		brake_time += 1.0 / 120.0
		if car.telemetry.forward_speed_kmh <= 1.0:
			break
	var distance: float = t.distance_travelled(start, car.global_position)
	t.check("the car stopped", car.telemetry.forward_speed_kmh <= 1.0,
			"= %.2f km/h" % car.telemetry.forward_speed_kmh)
	t.check("the brake distance", distance <= 35.0, "= %.2f m" % distance)
	t.check_range("the brake time", brake_time, 1.2, 2.4)
	t.finish()
