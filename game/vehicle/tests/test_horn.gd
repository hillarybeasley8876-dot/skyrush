extends Node
## The horn of the player's car: H (R3) sends Events.horn once per press, at most every 0.25 s.
## Run: python tools/gd.py test res://vehicle/tests/test_horn.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")

var _horns: int = 0
var _car: ArcadeCar = null


func _ready() -> void:
	_run.call_deferred()


func _on_horn(vehicle: VehicleBase) -> void:
	if vehicle == _car:
		_horns += 1


## Presses the horn key for two physics ticks.
func _tap(t: T) -> void:
	Input.action_press(&"horn")
	await t.step()
	await t.step()
	Input.action_release(&"horn")
	await t.step()


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	_car = await t.spawn_car(t.roadster(), Vector3(0.0, 0.3, 0.0), 0.0)
	_car.player_controlled = true
	t.check("the event bus has a horn signal", Events.has_signal(&"horn"))
	if Events.has_signal(&"horn"):
		Events.connect(&"horn", _on_horn)
	await t.run(0.5)
	t.check("no horn without a key", _horns == 0)
	await _tap(t)
	await t.step()
	t.check("one press is one horn", _horns == 1, "= %d" % _horns)
	await t.run(0.05)
	await _tap(t)
	t.check("a second press 0.1 s later is the same horn", _horns == 1, "= %d" % _horns)
	await t.run(0.4)
	await _tap(t)
	t.check("a press after the cooldown is a new horn", _horns == 2, "= %d" % _horns)
	await t.run(0.4)
	Input.action_press(&"horn")
	await t.run(1.0)
	Input.action_release(&"horn")
	t.check("a held key is one horn, not a siren", _horns == 3, "= %d" % _horns)
	_car.player_controlled = false
	await t.run(0.4)
	await _tap(t)
	t.check("a car that nobody drives does not honk", _horns == 3, "= %d" % _horns)
	t.finish()
