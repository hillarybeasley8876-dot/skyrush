extends Node
## Test of the results screen and of the settings that write through to the other units.
##
## The results come from the modes unit (the session that ran the mode); the settings write
## through to the environment's weather controller.
##
## Run: tools/godot.sh test res://ui/menu/tests/test_results.gd

## A stand-in for the modes unit's session.
class FakeSession extends Node:
	signal finished(results: Dictionary)

	var payload: Dictionary = {"kind": "free", "score": 1234, "stunts": 7, "near_misses": 12,
		"wrecks": 2, "takedowns": 1, "time": 95.5, "best_score": 2000.0}

	func build_results() -> Dictionary:
		return payload


## A stand-in for the modes unit's director.
class FakeDirector extends Node:
	var session: FakeSession = null
	var records: FakeRecords = null
	## The options of the last start (the retry has to pass them on again).
	var last_options: Dictionary = {}

	func start_mode(_mode: StringName, options: Dictionary) -> bool:
		last_options = options.duplicate()
		session = FakeSession.new()
		add_child(session)
		return true


## A stand-in for the modes unit's records.
class FakeRecords extends RefCounted:
	func best_time(_route_id: String) -> float:
		return 91.5

	func best_lap(_route_id: String) -> float:
		return 44.25

	func best_score() -> float:
		return 2000.0


## A stand-in for the environment unit's weather controller.
class FakeWeather extends Node:
	var raining: bool = false

	func _ready() -> void:
		add_to_group(&"weather")

	func set_rain(active: bool) -> void:
		raining = active

	func is_raining() -> bool:
		return raining


## The preferences file of the test (the player's own file is never touched).
const TEST_PREFS := "user://test_skyrush_menu.cfg"

var _fails: int = 0
var _menu: Node = null
var _director: FakeDirector = null
var _weather: FakeWeather = null


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# A clean preferences file of the test: the rain defaults to on. The player's own file is
	# never touched.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PREFS))
	_director = FakeDirector.new()
	_director.records = FakeRecords.new()
	add_child(_director)

	_weather = FakeWeather.new()
	add_child(_weather)

	_menu = _make_menu(&"main")
	await get_tree().process_frame

	await _test_pursuit_results()
	await _test_pursuit_subtitles()
	await _test_free_results()
	await _test_retry_keeps_the_options()
	await _test_rain_toggle()

	print("RESULTS TEST %s (%d failures)" % ["FAIL" if _fails > 0 else "PASS", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


## A pursuit that ran out of time shows its result.
func _test_pursuit_results() -> void:
	_menu.call("_start_mode", &"pursuit", {})
	await get_tree().process_frame
	_expect(_director.session != null, "the modes unit started a session")
	_director.session.payload = {
		"kind": "pursuit", "result": "timeout", "takedowns": 2, "target": 3,
		"time": 180.0, "heat": 3,
	}
	_director.session.emit_signal("finished", _director.session.payload)
	await get_tree().process_frame
	var screen: Node = _menu.call("debug_screen", "results")
	_expect(screen != null, "the pursuit result opens the results screen")
	if screen == null:
		return
	var text := _result_text(screen)
	_expect(text.contains("时间到"), "a timeout is shown as 时间到")
	_expect(text.contains("2 / 3"), "the takedowns and the goal are shown")
	_expect(text.contains("3:00.00"), "the time is shown")
	await _key(KEY_ESCAPE)
	await get_tree().process_frame


## Every pursuit result has its own subtitle.
func _test_pursuit_subtitles() -> void:
	var subtitles: Dictionary = {
		"escaped": "甩开了追捕",
		"busted": "被警察拦下",
		"success": "目标达成",
		"timeout": "时间到",
	}
	for result: String in subtitles:
		_director.session.payload = {
			"kind": "pursuit", "result": result, "takedowns": 1, "target": 3,
			"time": 60.0, "heat": 2,
		}
		_director.session.emit_signal("finished", _director.session.payload)
		await get_tree().process_frame
		var screen: Node = _menu.call("debug_screen", "results")
		if screen == null:
			_expect(false, "the pursuit result opens the results screen")
			continue
		var subtitle := screen.get("subtitle") as Label
		var text := subtitle.text if subtitle != null else ""
		_expect(text.contains(String(subtitles[result])),
				"the pursuit subtitle of %s is %s" % [result, subtitles[result]])
		await _key(KEY_ESCAPE)
		await get_tree().process_frame


## The free-roam summary shows the score of the modes unit.
func _test_free_results() -> void:
	_director.session.payload = {"kind": "free", "score": 1234, "stunts": 7, "near_misses": 12,
		"wrecks": 2, "takedowns": 1, "time": 95.5, "best_score": 2000.0}
	_director.session.emit_signal("finished", _director.session.payload)
	await get_tree().process_frame
	var screen: Node = _menu.call("debug_screen", "results")
	_expect(screen != null, "the free result opens the results screen")
	if screen == null:
		return
	var text := _result_text(screen)
	_expect(text.contains("本局总结"), "the free roam summary is shown")
	_expect(text.contains("1234"), "the score of the modes unit is shown")
	_expect(text.contains("2000"), "the high score of the modes unit is shown")
	await _key(KEY_ESCAPE)
	await get_tree().process_frame


## The retry of a race starts it with the same route, laps and difficulty.
func _test_retry_keeps_the_options() -> void:
	var options: Dictionary = {"route": "r_b", "laps": 3, "difficulty": "hard"}
	_menu.call("_start_mode", &"race", options)
	await get_tree().process_frame
	_director.session.payload = {
		"kind": "race",
		"results": [{"name": "Roadster", "time": 95.0, "position": 1, "is_player": true,
			"finished": true}],
		"route": "r_b", "route_title": "高架冲刺",
	}
	_director.session.emit_signal("finished", _director.session.payload)
	await get_tree().process_frame
	var screen: Node = _menu.call("debug_screen", "results")
	_expect(screen != null, "the race result opens the results screen")
	if screen == null:
		return
	# The first row is 重试 (retry).
	await _key(KEY_ENTER)
	await get_tree().process_frame
	var last: Dictionary = _director.last_options
	_expect(String(last.get("route", "")) == "r_b", "the retry keeps the route")
	_expect(int(last.get("laps", 0)) == 3, "the retry keeps the laps")
	_expect(String(last.get("difficulty", "")) == "hard", "the retry keeps the difficulty")


## The rain row writes through to the weather controller.
func _test_rain_toggle() -> void:
	_menu.call("open_screen", &"settings")
	await get_tree().process_frame
	var screen: Node = _menu.call("debug_screen", "settings")
	_expect(screen != null, "the settings are open")
	if screen == null:
		return
	_expect(_weather.raining, "the saved rain preference is applied when the menu starts")
	# The rows: quality, four volumes, rain, motion blur, controls, back.
	for i in 5:
		await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	await get_tree().process_frame
	_expect(not _weather.raining, "the rain row switches the weather off")
	await _key(KEY_ENTER)
	await get_tree().process_frame
	_expect(_weather.raining, "the rain row switches the weather on")


## --- helpers --------------------------------------------------------------------------------------

func _make_menu(screen: StringName) -> Node:
	var packed := load("res://ui/menu/menu.tscn") as PackedScene
	var menu := packed.instantiate()
	menu.set("demo_screen", screen)
	menu.set("prefs_path", TEST_PREFS)
	get_tree().root.add_child(menu)
	return menu


## The heading and the text of every row of the results table.
func _result_text(screen: Node) -> String:
	var out := ""
	var heading := screen.get("heading") as Label
	if heading != null:
		out += heading.text + "|"
	return out + _rows_text(screen)


## The text of every row of the results table.
func _rows_text(screen: Node) -> String:
	var table: VBoxContainer = screen.get("table") as VBoxContainer
	if table == null:
		return ""
	var out := ""
	for row in table.get_children():
		for label in row.get_children():
			if label is Label:
				out += (label as Label).text + "|"
	return out


func _key(code: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.physical_keycode = code
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		_fails += 1
		print("FAIL ", label)
