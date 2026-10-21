extends Node
## The AI facing API: the exact N2 cost and the events of every call (the rivals, the police and
## the traffic use only this).
## Run: tools/godot.sh test res://vehicle/tests/test_ai_api.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")
const BoostTuning := preload("res://vehicle/tuning/boost_tuning.gd")

var _started: Array[StringName] = []
var _hops: Array[StringName] = []
var _rolls: Array[int] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	var events: Node = t.events()
	events.boost_started.connect(func(_v: VehicleBase, k: StringName) -> void: _started.append(k))
	events.hop.connect(func(_v: VehicleBase, k: StringName) -> void: _hops.append(k))
	events.barrel_roll.connect(func(_v: VehicleBase, d: int) -> void: _rolls.append(d))
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
	await t.run(0.6)
	# The nitro: a full slot.
	car.boost.n2 = BoostTuning.N2_MAX
	var before: float = car.boost.n2
	t.check("the nitro fires", car.use_nitro())
	t.check_close("the nitro costs 100 N2", before - car.boost.n2, 100.0, 0.01)
	t.check("one boost_started", _started.size() == 1 and _started[0] == &"nitro",
			"= %s" % str(_started))
	# The hop: 25 N2 and one hop event.
	_started.clear()
	_hops.clear()
	car.boost.n2 = BoostTuning.N2_MAX
	before = car.boost.n2
	t.check("the hop starts", car.request_hop())
	for i in 20:
		await t.step()
	t.check_close("the hop costs 25 N2", before - car.boost.n2, 25.0, 1.0)
	t.check("one hop event", _hops.size() == 1 and _hops[0] == &"hop", "= %s" % str(_hops))
	# The Big Hop: 50 N2 (the hop cooldown has to be over).
	_hops.clear()
	for i in 150:
		await t.step()
	car.boost.n2 = BoostTuning.N2_MAX
	before = car.boost.n2
	t.check("the Big Hop starts", car.request_hop(true))
	for i in 20:
		await t.step()
	t.check_close("the Big Hop costs 50 N2", before - car.boost.n2, 50.0, 1.0)
	t.check("one big hop event", _hops.size() == 1 and _hops[0] == &"big_hop", "= %s" % str(_hops))
	# The barrel roll: 20 N2 and one roll event, only in the air.
	_rolls.clear()
	for i in 300:
		await t.step()
		if car.telemetry.grounded_wheels >= 3:
			break
	car.boost.n2 = BoostTuning.N2_MAX
	before = car.boost.n2
	t.check("the roll needs the air", not car.request_roll(1))
	t.check_close("the refused roll costs nothing", before - car.boost.n2, 0.0, 0.01)
	car.thruster.hop_held = true
	car.thruster.hop_pressed = true
	await t.step()
	car.thruster.hop_pressed = false
	car.thruster.hop_held = false
	car.thruster.hop_released = true
	await t.step()
	car.thruster.hop_released = false
	for i in 60:
		await t.step()
		if car.telemetry.airborne:
			break
	t.check("the car is airborne", car.telemetry.airborne)
	before = car.boost.n2
	t.check("the roll starts", car.request_roll(1))
	t.check_close("the roll costs 20 N2", before - car.boost.n2, 20.0, 0.01)
	t.check("one roll event", _rolls.size() == 1 and _rolls[0] == 1, "= %s" % str(_rolls))
	# The standing launch: it needs a standstill, the throttle and half a tank. It costs
	# nothing.
	for i in 300:
		await t.step()
		if car.telemetry.grounded_wheels >= 3 and not car.telemetry.airborne:
			break
	_started.clear()
	car.boost.n2 = BoostTuning.N2_MAX * 0.5
	before = car.boost.n2
	# The launch is a standing start: the car has to stand still first.
	t.set_speed(car, 0.0)
	car.set_controls(0.0, 0.0, 0.0, false)
	await t.step()
	t.check("the launch needs the throttle", not car.request_launch())
	car.set_controls(1.0, 0.0, 0.0, false)
	await t.step()
	t.check("the launch starts", car.request_launch())
	t.check_close("the launch costs nothing", before - car.boost.n2, 0.0, 0.01)
	t.check("one launch event", _started.size() == 1 and _started[0] == &"launch",
			"= %s" % str(_started))
	# At speed the launch is refused: the nitro key is the nitro, not a free boost.
	_started.clear()
	t.set_speed(car, 150.0)
	await t.step()
	t.check("the launch is refused at speed", not car.request_launch())
	t.check("no launch event at speed", _started.is_empty(), "= %s" % str(_started))
	car.set_controls(0.0, 0.0, 0.0, false)
	# The N2 getter.
	t.check_close("get_n2", car.get_n2(), car.boost.n2, 0.01)
	t.finish()
