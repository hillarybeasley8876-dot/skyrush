extends Node
## The thruster hop: 3.1 m apex for a tap, 7.8 m for a Big Hop, at every speed (the downforce
## of the fan car needs the ground under it, so a hop is not pulled down in the air), and a
## clean landing.
## Run: tools/godot.sh test res://vehicle/tests/test_hop.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const BoostTuning := preload("res://vehicle/tuning/boost_tuning.gd")

## The hop events of the car.
var _hops: Array[StringName] = []
## The car of the current part of the test (the hop handler reads it).
var _car: ArcadeCar = null


## Fires a hop and returns the apex height, the time above 7 m and the landing quality.
func _hop(t: T, car: ArcadeCar, big: bool) -> Array:
	car.boost.n2 = BoostTuning.N2_MAX
	var ground: float = car.global_position.y
	var apex: float = 0.0
	var above: float = 0.0
	var flew: bool = false
	_hops.clear()
	car.thruster.hop_held = true
	car.thruster.hop_pressed = true
	await t.step()
	car.thruster.hop_pressed = false
	if big:
		# Hold the key for the Big Hop charge and release it.
		for i in Engine.physics_ticks_per_second / 3:
			await t.step()
	car.thruster.hop_held = false
	car.thruster.hop_released = true
	await t.step()
	car.thruster.hop_released = false
	for i in Engine.physics_ticks_per_second * 3:
		await t.step()
		var height: float = car.global_position.y - ground
		apex = maxf(apex, height)
		if height > 7.0:
			above += 1.0 / Engine.physics_ticks_per_second
		if car.telemetry.airborne:
			flew = true
		elif flew and car.telemetry.grounded_wheels >= 3:
			break
	return [apex, above]


## Puts the car on the road at the given speed.
func _at_speed(t: T, car: ArcadeCar, kmh: float) -> void:
	await t.run(0.6)
	if kmh > 0.0:
		t.set_speed(car, kmh)
		car.set_controls(0.2, 0.0, 0.0, false)
		await t.run(0.2)
		car.set_controls(0.0, 0.0, 0.0, false)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	var events: Node = t.events()
	events.hop.connect(func(v: VehicleBase, kind: StringName) -> void:
		if v == _car:
			_hops.append(kind))
	# The hop and the Big Hop at every speed: the apex must not depend on the speed (the
	# downforce of the fan car needs the ground under it).
	for kmh: float in [0.0, 150.0, 250.0]:
		var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
		_car = car
		await _at_speed(t, car, kmh)
		var res: Array = await _hop(t, car, false)
		t.check_range("the hop apex at %d km/h" % int(kmh), float(res[0]), 2.8, 3.4)
		t.check("the hop was a tap at %d km/h" % int(kmh),
				_hops.size() == 1 and _hops[0] == &"hop", "= %s" % str(_hops))
		car.queue_free()
		await t.run(0.3)
	for kmh: float in [0.0, 150.0, 250.0]:
		var car2: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 60.0), 0.0)
		_car = car2
		await _at_speed(t, car2, kmh)
		var res2: Array = await _hop(t, car2, true)
		t.check_range("the Big Hop apex at %d km/h" % int(kmh), float(res2[0]), 7.4, 8.2)
		t.check("the Big Hop kind at %d km/h" % int(kmh),
				_hops.size() == 1 and _hops[0] == &"big_hop", "= %s" % str(_hops))
		if is_equal_approx(kmh, 150.0):
			# The dossier 5.7: a Big Hop at 150 km/h spends 0.57 s above 7 m.
			t.check("the Big Hop is above 7 m for half a second at 150 km/h",
					float(res2[1]) >= 0.5, "= %.2f s" % float(res2[1]))
		# The landing is clean: the car is back on the ground and upright.
		t.check("the car landed at %d km/h" % int(kmh), car2.telemetry.grounded_wheels >= 3,
				"= %d wheels" % car2.telemetry.grounded_wheels)
		t.check_range("the car is upright at %d km/h" % int(kmh),
				absf(car2.telemetry.pitch_deg), 0.0, 12.0)
		t.check_range("the car is level at %d km/h" % int(kmh),
				absf(car2.telemetry.roll_deg), 0.0, 12.0)
		car2.queue_free()
		await t.run(0.3)
	# A hop under a ceiling is refused (dossier 5.3).
	var car3: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 300.0), 0.0)
	await t.run(0.6)
	var ceiling := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 0.4, 8.0)
	shape.shape = box
	ceiling.add_child(shape)
	ceiling.position = Vector3(0.0, 1.6, 300.0)
	get_tree().root.add_child(ceiling)
	await t.step()
	car3.boost.n2 = BoostTuning.N2_MAX
	var before: float = car3.boost.n2
	t.check("the hop under a ceiling is refused", not car3.request_hop())
	t.check_close("the refused hop costs nothing", before - car3.boost.n2, 0.0, 0.01)
	t.finish()
