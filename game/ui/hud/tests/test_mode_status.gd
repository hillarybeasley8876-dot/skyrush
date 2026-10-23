extends Node
## The HUD draws the state of the running mode (tools/godot.sh test
## res://ui/hud/tests/test_mode_status.gd).
##
## The modes unit says what is going on on the bus (`Events.mode_status`); the HUD only draws it:
## the free-roam score, the pursuit goal and countdown and the laps / place of a race.
##
## The labels are found by their node name, so a missing node prints a FAIL line instead of
## breaking the test.

const HudScene := preload("res://ui/hud/hud.tscn")

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	await _test_free_score()
	await _test_no_mode()
	await _test_pursuit()
	await _test_race()
	await _test_switch()
	print("HUD STATUS TESTS %s (%d failures)" % ["FAILED" if _failures > 0 else "OK", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## Free roam: the score is on screen and it follows the bus.
func _test_free_score() -> void:
	var hud := await _make_hud()
	Events.mode_status.emit(&"free", {"score": 1250})
	await _frames(2)
	var score := _label(hud, "ScoreLabel")
	if score != null:
		_check(score.is_visible_in_tree(), "the score shows in free roam")
		_check(score.text.contains("1250"), "the score shows 1250 (%s)" % score.text)
	Events.mode_status.emit(&"free", {"score": 3000})
	await _frames(2)
	if score != null:
		_check(score.text.contains("3000"), "the score follows the new value (%s)" % score.text)
	_free_hud(hud)


## No mode: nothing of the mode is drawn.
func _test_no_mode() -> void:
	var hud := await _make_hud()
	Events.mode_status.emit(&"free", {"score": 1250})
	await _frames(2)
	Events.mode_status.emit(&"none", {})
	await _frames(2)
	var score := _label(hud, "ScoreLabel")
	if score != null:
		_check(not score.is_visible_in_tree(), "the score hides when there is no mode")
	var goal := _label(hud, "GoalLabel")
	var time := _label(hud, "TimeLabel")
	if goal != null:
		_check(not goal.is_visible_in_tree(), "the goal hides when there is no mode")
	if time != null:
		_check(not time.is_visible_in_tree(), "the countdown hides when there is no mode")
	_free_hud(hud)


## A pursuit: the goal of the mode and the countdown.
func _test_pursuit() -> void:
	var hud := await _make_hud()
	Events.mode_status.emit(&"pursuit", {"takedowns": 1, "target": 3, "time_left": 83.2})
	await _frames(2)
	var goal := _label(hud, "GoalLabel")
	var time := _label(hud, "TimeLabel")
	if goal != null:
		_check(goal.is_visible_in_tree(), "the goal shows in a pursuit")
		_check(goal.text.contains("1") and goal.text.contains("3"),
			"the goal shows the takedowns and the target (%s)" % goal.text)
	if time != null:
		_check(time.is_visible_in_tree(), "the countdown shows in a pursuit")
		_check(time.text.contains("01:23"), "the countdown shows 01:23 (%s)" % time.text)
	# No time limit: the countdown is gone.
	Events.mode_status.emit(&"pursuit", {"takedowns": 1, "target": 3, "time_left": -1.0})
	await _frames(2)
	if time != null:
		_check(not time.is_visible_in_tree(), "no time limit hides the countdown")
	# No goal: the takedown goal is gone.
	Events.mode_status.emit(&"pursuit", {"takedowns": 1, "target": 0, "time_left": 83.2})
	await _frames(2)
	if goal != null:
		_check(not goal.is_visible_in_tree(), "no goal hides the takedown goal")
	# A negative time is never drawn.
	Events.mode_status.emit(&"pursuit", {"takedowns": 1, "target": 3, "time_left": -5.0})
	await _frames(2)
	if time != null:
		_check(not time.is_visible_in_tree(), "a negative time never shows")
		_check(not time.text.contains("-"), "the countdown never shows a negative time (%s)" % time.text)
	_free_hud(hud)


## A race: the laps of the race that runs (not of the first route) and the place of the player.
func _test_race() -> void:
	var hud := await _make_hud()
	Events.mode_status.emit(&"race", {"lap": 2, "laps": 3, "position": 4, "racers": 6})
	await _frames(2)
	var events: Object = hud.get("events")
	_check(events != null, "the HUD has its bus state")
	if events != null:
		_check(int(events.get("laps")) == 3, "the lap counter says 3 laps (%s)" %
			str(events.get("laps")))
		_check(int(events.get("lap")) == 2, "the lap counter says lap 2 (%s)" % str(events.get("lap")))
	var panel: Object = hud.get("race_panel")
	_check(panel != null, "the HUD has a race panel")
	if panel != null:
		_check(str(panel.get("_rank_text")).contains("4"),
			"the race panel shows the 4th place (%s)" % str(panel.get("_rank_text")))
	_free_hud(hud)


## Switching the mode hides what belongs to the other mode.
func _test_switch() -> void:
	var hud := await _make_hud()
	Events.mode_status.emit(&"free", {"score": 500})
	await _frames(2)
	var score := _label(hud, "ScoreLabel")
	if score != null:
		_check(score.is_visible_in_tree(), "the score shows in free roam")
	Events.mode_status.emit(&"pursuit", {"takedowns": 0, "target": 3, "time_left": 30.0})
	await _frames(2)
	if score != null:
		_check(not score.is_visible_in_tree(), "a pursuit hides the free roam score")
	_free_hud(hud)


## The label of the readout, or null (and a FAIL line) when the HUD does not have it.
func _label(hud: CanvasLayer, node_name: String) -> Label:
	var node := hud.find_child(node_name, true, false)
	if node == null:
		_check(false, "the HUD has a %s" % node_name)
		return null
	return node as Label


## Build a HUD instance with a faked telemetry.
func _make_hud() -> CanvasLayer:
	var hud := HudScene.instantiate() as CanvasLayer
	add_child(hud)
	await _frames(2)
	hud.set("telemetry_override", CarTelemetry.new())
	return hud


func _free_hud(hud: CanvasLayer) -> void:
	hud.queue_free()
	await _frames(2)
