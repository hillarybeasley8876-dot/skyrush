class_name PursuitSession
extends Node
## The police pursuit (dossier 3.4-3.5): the police start at heat 2-3 and the player either
## escapes them (the cooldown runs out) or takes them down.
##
## The goal is chosen with the options of the mode: "escape" (the default) or "takedowns"
## with a number of units and a time limit.

enum Goal { ESCAPE, TAKEDOWNS }
enum Result { RUNNING, ESCAPED, BUSTED, SUCCESS, TIMEOUT }

## The mode is over.
signal finished(results: Dictionary)

## The goal of the pursuit.
var goal: int = Goal.ESCAPE
## The number of police cars to take down (the TAKEDOWNS goal).
var target_takedowns: int = 3
## The time the player has (s).
var time_limit: float = 180.0
## The heat the pursuit starts at.
var heat: int = 3
## The state of the pursuit.
var result: int = Result.RUNNING
## The police cars the player has wrecked.
var takedowns: int = 0
## The time the pursuit lasted (s).
var elapsed: float = 0.0

var _police: Node = null
var _player: VehicleBase = null


## Starts the pursuit.
func setup(options: Dictionary) -> void:
	goal = Goal.TAKEDOWNS if String(options.get("goal", "escape")) == "takedowns" else Goal.ESCAPE
	target_takedowns = maxi(1, int(options.get("count", 3)))
	time_limit = maxf(1.0, float(options.get("time", 180.0)))
	heat = clampi(int(options.get("heat", 3)), 1, 5)
	result = Result.RUNNING
	takedowns = 0
	elapsed = 0.0
	_player = Game.player
	Events.pursuit_state_changed.connect(_on_pursuit_state_changed)
	Events.takedown.connect(_on_takedown)
	_start_police()


## Raises the heat and lets the police come after the player.
##
## The police unit is optional: the chase starts with an offence (the way it starts in the
## free roam) and the heat is set on the director of the police unit.
func _start_police() -> void:
	_police = PoliceLink.director(get_tree())
	if not PoliceLink.start_pursuit(_police, heat):
		# The police unit has no start_at: the offence starts the chase the free roam way.
		if _player != null:
			Events.infraction.emit(_player, &"speeding")
		PoliceLink.set_heat(_police, heat)
	Events.heat_changed.emit(heat)
	Events.toast.emit("警方追捕！ PURSUIT", &"danger")


func _process(delta: float) -> void:
	if result != Result.RUNNING:
		return
	elapsed += delta
	if elapsed >= time_limit:
		_finish(Result.TIMEOUT)


## The police unit reports the state of the pursuit.
func _on_pursuit_state_changed(state: StringName) -> void:
	match state:
		&"escaped":
			_finish(Result.ESCAPED)
		&"busted":
			_finish(Result.BUSTED)


## A police car was wrecked: the takedowns goal counts them.
func _on_takedown(_victim: VehicleBase, kind: StringName) -> void:
	if kind != &"police" or result != Result.RUNNING:
		return
	takedowns += 1
	if goal == Goal.TAKEDOWNS and takedowns >= target_takedowns:
		_finish(Result.SUCCESS)


## Ends the pursuit and reports the result.
func _finish(new_result: int) -> void:
	if result != Result.RUNNING:
		return
	result = new_result
	var text := "被捕 BUSTED"
	var style := &"danger"
	match result:
		Result.ESCAPED:
			text = "成功逃脱！ ESCAPED"
			style = &"good"
		Result.SUCCESS:
			text = "全部击破！ ALL CLEAR"
			style = &"great"
		Result.TIMEOUT:
			text = "超时！ TIME UP"
			style = &"info"
	if result == Result.SUCCESS or result == Result.TIMEOUT:
		# The pursuit is won or over: the police go back to their stations, so the chase does
		# not go on in the background. A bust and an escape are left to the police unit: it
		# shows its own aftermath and resets itself.
		PoliceLink.stop_pursuit(_police)
	Events.toast.emit(text, style)
	finished.emit(build_results())


## The result of the pursuit.
func build_results() -> Dictionary:
	return {
		"kind": "pursuit",
		"result": _result_name(),
		"takedowns": takedowns,
		"target": target_takedowns,
		"time": elapsed,
		"heat": heat,
	}


## The name of the result.
func _result_name() -> String:
	match result:
		Result.ESCAPED:
			return "escaped"
		Result.BUSTED:
			return "busted"
		Result.SUCCESS:
			return "success"
		Result.TIMEOUT:
			return "timeout"
	return "running"
