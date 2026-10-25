extends Node
## The thruster launch (完美起步): 0-100 km/h in 0.9 +- 0.2 s, and only when the throttle was
## pressed (not just held) inside the 0.28 s window before the start.
## Run: tools/godot.sh test res://vehicle/tests/test_launch.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")


func _ready() -> void:
	_run.call_deferred()


## Drives from a standstill and returns the time to 100 km/h.
func _time_to_100(car: ArcadeCar, t: T) -> float:
	car.set_controls(1.0, 0.0, 0.0, false)
	var clock: float = 0.0
	for i in Engine.physics_ticks_per_second * 8:
		await t.step()
		clock += 1.0 / Engine.physics_ticks_per_second
		if car.telemetry.forward_speed_kmh >= 100.0:
			return clock
	return -1.0


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	var events: Node = t.events()
	t.check("the events bus is there", events != null)
	# The normal start.
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
	await t.run(0.5)
	var normal: float = await _time_to_100(car, t)
	t.check_range("0-100 normal", normal, 2.0, 2.6)
	# The perfect start: the throttle is pressed 0.2 s before the race starts.
	var car2: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 300.0), 0.0)
	await t.run(0.5)
	car2.set_controls(0.0, 0.0, 0.0, false)
	await t.step()
	car2.set_controls(1.0, 0.0, 0.0, false)
	await t.run(0.2)
	events.race_started.emit()
	await t.step()
	t.check("the launch boost runs", car2.telemetry.boost_kind == &"launch",
			"= %s" % car2.telemetry.boost_kind)
	var clock: float = 0.0
	var launch: float = -1.0
	for i in Engine.physics_ticks_per_second * 8:
		await t.step()
		clock += 1.0 / Engine.physics_ticks_per_second
		if launch < 0.0 and car2.telemetry.forward_speed_kmh >= 100.0:
			launch = clock
	t.check_range("0-100 with the launch", launch, 0.7, 1.1)
	t.check("the launch is faster", launch < normal - 0.8,
			"launch %.2f s vs normal %.2f s" % [launch, normal])
	# A throttle that was only held must not give a launch.
	var car3: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 600.0), 0.0)
	await t.run(0.5)
	car3.set_controls(1.0, 0.0, 0.0, false)
	await t.run(2.0)
	events.race_started.emit()
	await t.step()
	t.check("a held throttle is no launch", car3.telemetry.boost_kind != &"launch",
			"= %s" % car3.telemetry.boost_kind)
	t.finish()
