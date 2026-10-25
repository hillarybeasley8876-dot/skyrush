extends Node
## The nitro key at speed is the nitro, not a free launch (the review of round 2): the standing
## launch (完美起步) needs a standstill, the throttle held and half a tank of N2.
## The key path is driven through the InputMap, not through the AI API.
## Run: tools/godot.sh test res://vehicle/tests/test_nitro.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const BoostTuning := preload("res://vehicle/tuning/boost_tuning.gd")
const DriveTuning := preload("res://vehicle/tuning/drive_tuning.gd")

var _started: Array[StringName] = []


func _ready() -> void:
	_run.call_deferred()


## Presses a key for two ticks (the edge is seen by the input module).
func _press(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	var events: Node = t.events()
	events.boost_started.connect(func(_v: VehicleBase, k: StringName) -> void: _started.append(k))
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
	Game.player = car
	await t.run(0.6)
	# The car drives at 150 km/h (the accelerate key: the player car reads the InputMap).
	Input.action_press(&"accelerate")
	for i in Engine.physics_ticks_per_second * 12:
		await t.step()
		if car.telemetry.forward_speed_kmh >= 150.0:
			break
	t.check_range("the speed before the nitro", car.telemetry.forward_speed_kmh, 145.0, 165.0)
	# The nitro key at speed: one nitro, no launch.
	car.boost.n2 = 150.0
	_started.clear()
	await _press(&"nitro")
	t.check("one boost event", _started.size() == 1, "= %s" % str(_started))
	t.check("the boost is the nitro", _started.size() == 1 and _started[0] == &"nitro",
			"= %s" % str(_started))
	t.check_close("the nitro costs 100 N2", car.boost.n2, 50.0, 1.0)
	t.check_close("the cap after the nitro", car.boost.speed_cap * DriveTuning.KMH, 300.0, 1.0)
	# A second press is refused: the tank is too empty.
	_started.clear()
	await _press(&"nitro")
	t.check("the second nitro is refused", _started.is_empty(), "= %s" % str(_started))
	# The car reaches the cap of the nitro.
	var top: float = 0.0
	for i in Engine.physics_ticks_per_second * 10:
		await t.step()
		top = maxf(top, car.telemetry.forward_speed_kmh)
	t.check_range("the top speed with the nitro", top, 292.0, 308.0)
	Input.action_release(&"accelerate")
	# The AI API refuses the launch at speed too.
	_started.clear()
	t.check("the launch is refused at speed", not car.request_launch())
	t.check("no launch event at speed", _started.is_empty(), "= %s" % str(_started))
	# The standing launch: the accelerate and the nitro together from a standstill.
	var car2: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 400.0), 0.0)
	Game.player = car2
	await t.run(0.6)
	car2.boost.n2 = 100.0
	_started.clear()
	Input.action_press(&"accelerate")
	await t.step()
	await _press(&"nitro")
	t.check("the launch fires", _started.size() == 1 and _started[0] == &"launch",
			"= %s" % str(_started))
	# 0-100 km/h with the launch.
	var clock: float = 0.0
	var to_100: float = -1.0
	for i in Engine.physics_ticks_per_second * 8:
		await t.step()
		clock += 1.0 / Engine.physics_ticks_per_second
		if to_100 < 0.0 and car2.telemetry.forward_speed_kmh >= 100.0:
			to_100 = clock
	Input.action_release(&"accelerate")
	t.check_range("0-100 with the launch", to_100, 0.7, 1.1)
	t.check("the launch is free", car2.boost.n2 > 90.0, "= %.1f N2" % car2.boost.n2)
	Game.player = null
	t.finish()
