extends Node
## The pursuit mode (dossier 3.4-3.5): the police start at heat 2-3, the player escapes them
## or takes them down.
##
## The test drives the mode through the event bus: the police unit is not loaded here, so the
## mode has to work from `Events.pursuit_state_changed` and `Events.takedown` alone.

const SANDBOX := "res://core/sandbox/sandbox.tscn"
const PLAYER_CAR := "res://vehicle/player_car.tscn"
const MODE_DIRECTOR := "res://modes/mode_director.tscn"

var _failures: int = 0
var _modes: ModeDirector = null
var _results: Dictionary = {}


func _ready() -> void:
	var world := (load(SANDBOX) as PackedScene).instantiate()
	add_child(world)
	var car := (load(PLAYER_CAR) as PackedScene).instantiate()
	add_child(car)
	Game.player = car
	_modes = (load(MODE_DIRECTOR) as PackedScene).instantiate() as ModeDirector
	add_child(_modes)
	await _test_escape()
	await _test_takedowns()
	await _test_timeout()
	print("PURSUIT MODE TESTS OK (%d failures)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


## The escape goal: the police lose the player and the pursuit ends.
func _test_escape() -> void:
	_results = {}
	var ok := _modes.start_mode(&"pursuit", {"goal": "escape", "time": 60.0})
	_expect(ok, "the pursuit starts")
	_expect(Game.mode == &"pursuit", "the game mode is pursuit")
	var session := _modes.session as PursuitSession
	_expect(session != null, "the pursuit session exists")
	_expect(session.heat >= 2 and session.heat <= 3, "the pursuit starts at heat 2-3 (%d)" % session.heat)
	session.finished.connect(func(results: Dictionary) -> void: _results = results)
	Events.pursuit_state_changed.emit(&"escaped")
	await get_tree().process_frame
	_expect(String(_results.get("result", "")) == "escaped", "the escape ends the pursuit")
	_expect(int(_results.get("takedowns", -1)) == 0, "no takedown was counted")


## The takedowns goal: the player wrecks N police cars in time.
func _test_takedowns() -> void:
	_results = {}
	_modes.start_mode(&"pursuit", {"goal": "takedowns", "count": 2, "time": 60.0})
	var session := _modes.session as PursuitSession
	session.finished.connect(func(results: Dictionary) -> void: _results = results)
	Events.takedown.emit(Game.player, &"police")
	await get_tree().process_frame
	_expect(_results.is_empty(), "one takedown is not enough")
	Events.takedown.emit(Game.player, &"police")
	await get_tree().process_frame
	_expect(String(_results.get("result", "")) == "success", "the second takedown wins")
	_expect(int(_results.get("takedowns", 0)) == 2, "the takedowns are counted")


## The time limit: the pursuit ends when the clock runs out.
func _test_timeout() -> void:
	_results = {}
	_modes.start_mode(&"pursuit", {"goal": "escape", "time": 1.0})
	var session := _modes.session as PursuitSession
	session.finished.connect(func(results: Dictionary) -> void: _results = results)
	await get_tree().create_timer(1.6).timeout
	_expect(String(_results.get("result", "")) == "timeout", "the pursuit times out")


## Counts one failed expectation.
func _expect(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition:
		_failures += 1
