extends Node
## The stability at 300 km/h: lane changes must not tunnel through the road and must not roll
## the car over (dossier 4.7, 10).
## Run: tools/godot.sh test res://vehicle/tests/test_stability.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const BoostTuning := preload("res://vehicle/tuning/boost_tuning.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
	await t.run(0.5)
	# The base speed first, then the nitro on top of it.
	car.set_controls(1.0, 0.0, 0.0, false)
	for i in Engine.physics_ticks_per_second * 12:
		await t.step()
		if i % 60 == 0:
			t.keep_on_ground(car)
	car.boost.n2 = BoostTuning.N2_MAX
	t.check("the nitro fires", car.use_nitro())
	var top: float = 0.0
	for i in Engine.physics_ticks_per_second * 3:
		await t.step()
		top = maxf(top, car.telemetry.forward_speed_kmh)
		if i % 60 == 0:
			t.keep_on_ground(car)
	t.check_range("the speed", top, 290.0, 310.0)
	var max_roll: float = 0.0
	var max_pitch: float = 0.0
	var min_y: float = 99.0
	var max_y: float = -99.0
	# Two lane changes: left and right. The car is put back on the straight once, so the
	# tunnelling check runs without a teleport every half second.
	t.keep_on_ground(car)
	for steer: float in [0.8, -0.8, 0.0]:
		car.set_controls(1.0, 0.0, steer, false)
		for i in Engine.physics_ticks_per_second * 2:
			await t.step()
			max_roll = maxf(max_roll, absf(car.telemetry.roll_deg))
			max_pitch = maxf(max_pitch, absf(car.telemetry.pitch_deg))
			min_y = minf(min_y, car.global_position.y)
			max_y = maxf(max_y, car.global_position.y)
	t.check("no roll over", max_roll < 25.0, "= %.1f deg" % max_roll)
	t.check("no flip", max_pitch < 25.0, "= %.1f deg" % max_pitch)
	t.check("no tunnelling", min_y > -0.5, "= %.3f m" % min_y)
	t.check("the car stayed on the ground", max_y < 1.0, "= %.3f m" % max_y)
	t.check("the car is still driving", car.telemetry.forward_speed_kmh > 200.0,
			"= %.1f km/h" % car.telemetry.forward_speed_kmh)
	t.finish()
