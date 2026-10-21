extends Node
## The mode switch: the police come back on, the pursuit starts at heat 3, the player waits on
## the grid through the countdown and the perfect start still works.

const SANDBOX := "res://core/sandbox/sandbox.tscn"
const PLAYER_CAR := "res://vehicle/player_car.tscn"
const RIVAL_DIRECTOR := "res://ai/rivals/rival_director.tscn"
const POLICE_DIRECTOR := "res://ai/police/police_director.tscn"
const MODE_DIRECTOR := "res://modes/mode_director.tscn"
const GO_WAIT := 1.0   ## s: the time the police need to come after the player

var _failures: int = 0
var _modes: ModeDirector = null
var _police: Node = null


func _ready() -> void:
	var world := (load(SANDBOX) as PackedScene).instantiate()
	add_child(world)
	var car := (load(PLAYER_CAR) as PackedScene).instantiate()
	add_child(car)
	Game.player = car
	add_child((load(RIVAL_DIRECTOR) as PackedScene).instantiate())
	_police = (load(POLICE_DIRECTOR) as PackedScene).instantiate()
	add_child(_police)
	_modes = (load(MODE_DIRECTOR) as PackedScene).instantiate() as ModeDirector
	add_child(_modes)
	await _test_police_switch()
	await _test_pursuit_heat()
	await _test_countdown_freeze()
	print("MODE SWITCH TESTS OK (%d failures)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


## A race switches the police off, free roam and pursuit switch them back on.
func _test_police_switch() -> void:
	_modes.start_mode(&"race", {"route": "sandbox_loop", "laps": 1})
	_expect(not bool(_police.get("spawn_enabled")), "a race switches the police off")
	_modes.start_mode(&"free", {})
	_expect(bool(_police.get("spawn_enabled")), "free roam switches the police back on")
	_modes.start_mode(&"race", {"route": "sandbox_loop", "laps": 1})
	_expect(not bool(_police.get("spawn_enabled")), "the second race switches the police off")
	_modes.start_mode(&"pursuit", {})
	_expect(bool(_police.get("spawn_enabled")), "a pursuit switches the police back on")


## The pursuit starts at heat 3 and the police chase the player.
func _test_pursuit_heat() -> void:
	_modes.start_mode(&"pursuit", {})
	await get_tree().create_timer(GO_WAIT).timeout
	var pursuit: Object = _police.get("pursuit")
	var heat := int(pursuit.get("heat"))
	var state := String(pursuit.get("state"))
	_expect(heat == 3, "the pursuit starts at heat 3 (%d)" % heat)
	_expect(state == "chase", "the police chase the player (%s)" % state)


## The player waits on the grid through the countdown, even when something unfreezes it, and
## the perfect start still fires.
func _test_countdown_freeze() -> void:
	_modes.start_mode(&"race", {"route": "sandbox_loop", "laps": 1})
	var session := _modes.session as RaceSession
	# The menu unfreezes the car right after it starts the mode.
	Game.player.freeze = false
	var held := true
	var frames := 0
	while session.state == RaceSession.State.COUNTDOWN and frames < 600:
		await get_tree().process_frame
		frames += 1
		# The first frame is the one where the session has not taken the car back yet.
		if frames > 1 and session.state == RaceSession.State.COUNTDOWN and not Game.player.freeze:
			held = false
	_expect(held, "the player is held on the grid through the countdown")
	_expect(not Game.player.freeze, "the player is released at the green light")
	await _test_perfect_start()


## The perfect start: the throttle is pressed (an edge, not a hold) a frame before the light.
func _test_perfect_start() -> void:
	_modes.start_mode(&"race", {"route": "sandbox_loop", "laps": 1})
	var session := _modes.session as RaceSession
	var pressed := false
	while session.state == RaceSession.State.COUNTDOWN:
		await get_tree().process_frame
		if pressed:
			Input.action_release(&"accelerate")
			pressed = false
		else:
			Input.action_press(&"accelerate")
			pressed = true
	Input.action_press(&"accelerate")
	await get_tree().process_frame
	var boost: Object = (Game.player as ArcadeCar).boost
	var kind := String(boost.get("kind"))
	_expect(kind == "launch", "the perfect start fires (%s)" % kind)
	Input.action_release(&"accelerate")


## Counts one failed expectation.
func _expect(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition:
		_failures += 1
