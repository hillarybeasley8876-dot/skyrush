extends Node
## The telemetry the HUD reads: the altitude is the height above the ground (not the world
## height) and the g load stays in a sane range at the top speed (dossier 8.2).
## Run: tools/godot.sh test res://vehicle/tests/test_telemetry.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const BoostTuning := preload("res://vehicle/tuning/boost_tuning.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	# The elevated deck of the sandbox is 9 m above the ground: the car drives on it and the
	# altitude still reads the height above the road.
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(80.0, 9.2, 100.0), 0.0)
	await t.run(1.0)
	t.check("the car is on the deck", car.telemetry.grounded_wheels >= 3,
			"= %d wheels" % car.telemetry.grounded_wheels)
	t.check("the altitude is the height above the road", car.telemetry.altitude_m < 0.5,
			"= %.2f m" % car.telemetry.altitude_m)
	# In the air the altitude grows.
	car.boost.n2 = BoostTuning.N2_MAX
	car.thruster.hop_held = true
	car.thruster.hop_pressed = true
	await t.step()
	car.thruster.hop_pressed = false
	car.thruster.hop_held = false
	car.thruster.hop_released = true
	await t.step()
	car.thruster.hop_released = false
	var air_alt: float = 0.0
	for i in 60:
		await t.step()
		air_alt = maxf(air_alt, car.telemetry.altitude_m)
	t.check("the altitude grows in the air", air_alt > 1.0, "= %.2f m" % air_alt)
	# The g load at the top speed: the downforce is a share of the weight, not a multiple of it.
	var car2: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
	await t.run(0.5)
	car2.set_controls(1.0, 0.0, 0.0, false)
	for i in 120 * 13:
		await t.step()
		if i % 60 == 0:
			t.keep_on_ground(car2)
	t.check_range("the g load at 250 km/h", car2.telemetry.g_load, 1.0, 2.0)
	t.check("the speed", car2.telemetry.forward_speed_kmh > 240.0,
			"= %.1f km/h" % car2.telemetry.forward_speed_kmh)
	t.finish()
