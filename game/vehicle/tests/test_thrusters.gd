extends Node
## The thruster telemetry (the brief): R1-R4 for the boost, P1-P4 for the lift (the hop, the
## hover, the landing cushion), P5/P6 for the yaw jets in the air and in a barrel roll, and
## nothing else while the car drives on four wheels.
## Run: tools/godot.sh test res://vehicle/tests/test_thrusters.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const BoostTuning := preload("res://vehicle/tuning/boost_tuning.gd")


func _ready() -> void:
	_run.call_deferred()


## The nozzle values of the car.
func _nozzles(car: ArcadeCar, key: StringName) -> float:
	return float(car.telemetry.thrusters.get(key, 0.0))


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
	await t.run(0.5)
	# On the ground the yaw jets never fire.
	car.set_controls(1.0, 0.0, 1.0, false)
	await t.run(0.5)
	t.check("no yaw jet on the ground", _nozzles(car, &"Nozzle_P5") == 0.0
			and _nozzles(car, &"Nozzle_P6") == 0.0,
			"= %.2f / %.2f" % [_nozzles(car, &"Nozzle_P5"), _nozzles(car, &"Nozzle_P6")])
	t.check("no boost on the ground", _nozzles(car, &"Nozzle_R1") == 0.0,
			"= %.2f" % _nozzles(car, &"Nozzle_R1"))
	# The hop: the lift jets fire for 0.15 s.
	car.boost.n2 = BoostTuning.N2_MAX
	car.thruster.hop_held = true
	car.thruster.hop_pressed = true
	await t.step()
	car.thruster.hop_pressed = false
	car.thruster.hop_held = false
	car.thruster.hop_released = true
	await t.step()
	car.thruster.hop_released = false
	var hop_fire: float = 0.0
	for i in Engine.physics_ticks_per_second / 2:
		await t.step()
		hop_fire = maxf(hop_fire, _nozzles(car, &"Nozzle_P1"))
	t.check("the hop fires the lift jets", hop_fire > 0.9, "= %.2f" % hop_fire)
	# In the air the yaw jets follow the steer: right is P5.
	var air_yaw: float = 0.0
	for i in Engine.physics_ticks_per_second * 5 / 12:
		await t.step()
		air_yaw = maxf(air_yaw, _nozzles(car, &"Nozzle_P5"))
	t.check("the air yaw fires P5", air_yaw > 0.5, "= %.2f" % air_yaw)
	t.check("P6 stays off", _nozzles(car, &"Nozzle_P6") == 0.0,
			"= %.2f" % _nozzles(car, &"Nozzle_P6"))
	# The barrel roll to the right: P5 fires, P6 does not.
	var roll_fire: float = 0.0
	t.check("the roll starts", car.request_roll(1))
	for i in Engine.physics_ticks_per_second * 3 / 4:
		await t.step()
		roll_fire = maxf(roll_fire, _nozzles(car, &"Nozzle_P5"))
	t.check("the roll fires P5", roll_fire > 0.9, "= %.2f" % roll_fire)
	t.check("the roll does not fire P6", _nozzles(car, &"Nozzle_P6") == 0.0,
			"= %.2f" % _nozzles(car, &"Nozzle_P6"))
	# A small bump (a short airtime) does not fire the landing cushion.
	var car2: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(40.0, 0.35, 0.0), 0.0)
	await t.run(1.0)
	var cushion: float = 0.0
	for i in Engine.physics_ticks_per_second:
		await t.step()
		if car2.dynamics.landed:
			cushion = _nozzles(car2, &"Nozzle_P1")
			break
	t.check("no cushion on a small bump", cushion < 0.5, "= %.2f" % cushion)
	# A real drop does.
	var car3: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(80.0, 8.0, 0.0), 0.0)
	await t.run(0.2)
	for i in Engine.physics_ticks_per_second * 2:
		await t.step()
		if car3.dynamics.landed:
			break
	cushion = _nozzles(car3, &"Nozzle_P1")
	t.check("the cushion fires on a real landing", cushion > 0.5, "= %.2f" % cushion)
	t.finish()
