extends Node
## The top speed: 250 km/h on the base power, 300 km/h with the N2 boost, the 330 km/h hard cap
## and the battery cap at 180 km/h.
## Run: tools/godot.sh test res://vehicle/tests/test_top_speed.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const BoostTuning := preload("res://vehicle/tuning/boost_tuning.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
	await t.run(0.5)
	# The base top speed.
	car.set_controls(1.0, 0.0, 0.0, false)
	var top: float = 0.0
	for i in 120 * 13:
		await t.step()
		top = maxf(top, car.telemetry.forward_speed_kmh)
		if i % 60 == 0:
			t.keep_on_ground(car)
	t.check_range("the base top speed", top, 245.0, 255.0)
	# The N2 boost top speed: the nitro on top of the base speed.
	car.boost.n2 = BoostTuning.N2_MAX
	t.check("the nitro fires", car.use_nitro())
	var boosted: float = 0.0
	for i in 120 * 4:
		await t.step()
		boosted = maxf(boosted, car.telemetry.forward_speed_kmh)
		if i % 60 == 0:
			t.keep_on_ground(car)
	t.check_range("the N2 boost top speed", boosted, 292.0, 308.0)
	t.check("the hard cap holds", boosted <= 331.0, "= %.1f km/h" % boosted)
	# The nitro must not raise the top speed for good: 4 s later the car is back at 250.
	for i in 120 * 4:
		await t.step()
		if i % 60 == 0:
			t.keep_on_ground(car)
	t.check_range("the speed after the nitro", car.telemetry.forward_speed_kmh, 245.0, 252.0)
	# The battery: below 0.15 the car is capped at 180 km/h.
	car.power.battery = 0.10
	t.set_speed(car, 170.0)
	car.set_controls(1.0, 0.0, 0.0, false)
	await t.run_steady(car, 6.0)
	t.check_range("the battery cap", car.telemetry.forward_speed_kmh, 0.0, 181.0)
	t.finish()
