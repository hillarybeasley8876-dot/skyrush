extends Node
## The flash charge bay (申城闪充): driving through it refills the N2, the battery and 20 HP.
## Run: tools/godot.sh test res://vehicle/tests/test_charge.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const BoostTuning := preload("res://vehicle/tuning/boost_tuning.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	# The sandbox charge lane is at (-420, 0, -224) and is 14 m long along X.
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(-450.0, 0.3, -224.0), -PI * 0.5)
	await t.run(0.4)
	car.boost.n2 = 20.0
	car.power.battery = 0.4
	car.health = 50.0
	car.telemetry.health_norm = 0.5
	# 100 km/h towards +X.
	t.set_speed(car, 100.0)
	var charged: bool = false
	for i in Engine.physics_ticks_per_second * 4:
		await t.step()
		if car.boost.n2 >= BoostTuning.N2_MAX:
			charged = true
			break
	t.check("the bay refilled the tank", charged, "= %.1f N2" % car.boost.n2)
	t.check_close("the tank is full", car.boost.n2, BoostTuning.N2_MAX, 0.5)
	t.check_close("the battery is full", car.power.battery, 1.0, 0.01)
	t.check("the car got 20 HP", car.health > 50.0, "= %.1f HP" % car.health)
	t.check("the charge boost runs", car.telemetry.boost_kind == &"charge",
			"= %s" % car.telemetry.boost_kind)
	t.finish()
