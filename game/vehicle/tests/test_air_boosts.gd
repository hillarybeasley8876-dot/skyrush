extends Node
## The air mini boost (空喷) and the landing mini boost (落地喷): dossier 5.3.
## Run: tools/godot.sh test res://vehicle/tests/test_air_boosts.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const BoostTuning := preload("res://vehicle/tuning/boost_tuning.gd")
const PlayerInputMod := preload("res://vehicle/player_input.gd")

var _started: Array[StringName] = []


func _ready() -> void:
	_run.call_deferred()


## Hops the car and returns when it is in the air.
func _hop(t: T, car: ArcadeCar) -> void:
	car.boost.n2 = BoostTuning.N2_MAX
	car.thruster.hop_held = true
	car.thruster.hop_pressed = true
	await t.step()
	car.thruster.hop_pressed = false
	car.thruster.hop_held = false
	car.thruster.hop_released = true
	await t.step()
	car.thruster.hop_released = false
	for i in Engine.physics_ticks_per_second / 2:
		await t.step()
		if car.telemetry.airborne:
			return


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	var events: Node = t.events()
	events.boost_started.connect(func(_v: VehicleBase, k: StringName) -> void: _started.append(k))
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
	await t.run(0.6)
	# The air mini boost: a tap in the air gives a 6 m/s forward impulse, once per jump.
	await _hop(t, car)
	t.check("the car is in the air", car.telemetry.airborne)
	var before: float = car.telemetry.forward_speed_kmh
	_started.clear()
	# The action is fired through the input module: the mini key.
	car.actions.handle(car, _mini_press())
	t.check("the air mini fires", _started.size() == 1 and _started[0] == &"air_mini",
			"= %s" % str(_started))
	await t.run(0.2)
	t.check("the air mini gives speed", car.telemetry.forward_speed_kmh > before,
			"= %.1f km/h (was %.1f)" % [car.telemetry.forward_speed_kmh, before])
	# A second tap in the same jump is refused.
	_started.clear()
	car.actions.handle(car, _mini_press())
	t.check("a second air mini is refused", _started.is_empty(), "= %s" % str(_started))
	# The landing mini boost: a tap 0.3 s after the touchdown.
	for i in Engine.physics_ticks_per_second * 3:
		await t.step()
		if car.telemetry.grounded_wheels >= 3 and not car.telemetry.airborne:
			break
	t.check("the car landed", car.telemetry.grounded_wheels >= 3,
			"= %d wheels" % car.telemetry.grounded_wheels)
	t.check("the landing window is open", car.telemetry.mini_window,
			"= %s" % str(car.telemetry.mini_window))
	_started.clear()
	for i in Engine.physics_ticks_per_second * 3 / 10:
		await t.step()
	car.actions.handle(car, _mini_press())
	t.check("the landing mini fires", _started.size() == 1 and _started[0] == &"landing",
			"= %s" % str(_started))
	# Too late: the window is closed.
	_started.clear()
	for i in Engine.physics_ticks_per_second:
		await t.step()
	car.actions.handle(car, _mini_press())
	t.check("a late landing mini is refused", _started.is_empty(), "= %s" % str(_started))
	t.finish()


## A snapshot with the mini boost key pressed.
func _mini_press() -> PlayerInputMod.Snapshot:
	var s: PlayerInputMod.Snapshot = PlayerInputMod.Snapshot.new()
	s.mini_pressed = true
	return s
