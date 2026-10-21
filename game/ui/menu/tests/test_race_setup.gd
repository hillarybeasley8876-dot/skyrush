extends Node
## Test of the race setup: the route the player picks is the route the race starts with.
##
## The review found that the cursor could only ever start the last route it passed; now Enter (or
## A) on a route row picks that route (a check mark and a bar that stays lit) and jumps to
## 开始比赛. The length of a route is the length of its racing line.
##
## Run: tools/godot.sh test res://ui/menu/tests/test_race_setup.gd

## A world with three routes and known racing lines.
class FakeWorld extends WorldBase:
	var routes: Array[RaceRoute] = []

	func _init() -> void:
		routes.append(_route(&"r_a", "外滩冲刺", 800.0, 2))
		routes.append(_route(&"r_b", "高架冲刺", 1600.0, 1))
		routes.append(_route(&"r_c", "滨江环线", 2400.0, 3))

	func get_route_ids() -> PackedStringArray:
		var ids := PackedStringArray()
		for route in routes:
			ids.append(String(route.id))
		return ids

	func get_route(id: StringName) -> RaceRoute:
		for route in routes:
			if route.id == id:
				return route
		return null

	## A route with a straight racing line of the given length.
	func _route(id: StringName, title: String, length: float, laps: int) -> RaceRoute:
		var route := RaceRoute.new()
		route.id = id
		route.title = title
		route.laps = laps
		var line := Curve3D.new()
		line.add_point(Vector3.ZERO)
		line.add_point(Vector3(0.0, 0.0, -length))
		route.racing_line = line
		return route


## The preferences file of the test (the player's own file is never touched).
const TEST_PREFS := "user://test_skyrush_menu.cfg"

var _fails: int = 0
var _menu: Node = null
var _world: FakeWorld = null


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# A clean preferences file of the test: the route of the last race must not be preselected.
	# The player's own file is never touched.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PREFS))
	_world = FakeWorld.new()
	add_child(_world)
	Game.world = _world

	_menu = _make_menu(&"race_setup")
	await get_tree().process_frame

	await _test_walk_to_start_keeps_the_first_route()
	await _test_enter_picks_a_route()
	await _test_length_comes_from_the_racing_line()

	print("RACE SETUP TEST %s (%d failures)" % ["FAIL" if _fails > 0 else "PASS", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


## Walking from the first row down to 开始比赛 must start the first route.
func _test_walk_to_start_keeps_the_first_route() -> void:
	var screen := _screen()
	_expect(screen != null, "the race setup is open")
	if screen == null:
		return
	# The list: three routes, the difficulty, the laps, 开始比赛 and 返回.
	var rows: int = screen.get("list").get("rows").size()
	_expect(rows == 7, "the list has three routes and four rows")
	for i in 5:
		await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	_expect(_started_route() == "r_a", "walking to the start keeps the first route")


## Enter on a route row picks that route.
func _test_enter_picks_a_route() -> void:
	_menu.call("open_screen", &"race_setup")
	await get_tree().process_frame
	_menu.call("open_screen", &"race_setup")
	var screen := _screen()
	if screen == null:
		return
	# The route of the last race is preselected and the cursor jumps to 开始比赛.
	_expect(int(screen.get("_picked")) == 0, "the route of the last race is preselected")
	_expect(int(screen.get("list").get("selected_index")) == 5, "the cursor jumps to 开始比赛")
	# Move the cursor up to the third route and pick it.
	await _key(KEY_UP)
	await _key(KEY_UP)
	await _key(KEY_UP)
	_expect(int(screen.get("_preview")) == 2, "the cursor previews the third route")
	await _key(KEY_ENTER)
	_expect(int(screen.get("_picked")) == 2, "enter picks the third route")
	_expect(int(screen.get("list").get("selected_index")) == 5, "the cursor jumps to 开始比赛")
	await _key(KEY_ENTER)
	_expect(_started_route() == "r_c", "the picked route is the one the race starts with")


## The length of a route is the length of its racing line, per lap.
func _test_length_comes_from_the_racing_line() -> void:
	_menu.call("open_screen", &"race_setup")
	await get_tree().process_frame
	var screen := _screen()
	if screen == null:
		return
	var label := screen.get("route_length") as Label
	_expect(label != null, "the route info has a length label")
	if label == null:
		return
	var picked := int(screen.get("_picked"))
	var route := _world.routes[picked] as RaceRoute
	var lap_km := route.racing_line.get_baked_length() / 1000.0
	var laps := int(screen.get("_laps"))
	_expect(label.text.contains("%.2f km" % lap_km), "the length comes from the racing line")
	var total := screen.get("route_total") as Label
	_expect(total != null and total.text.contains("%.2f km" % (lap_km * float(laps))),
			"the total is the lap length times the laps")


## --- helpers --------------------------------------------------------------------------------------

func _make_menu(screen: StringName) -> Node:
	var packed := load("res://ui/menu/menu.tscn") as PackedScene
	var menu := packed.instantiate()
	menu.set("demo_screen", screen)
	menu.set("prefs_path", TEST_PREFS)
	get_tree().root.add_child(menu)
	return menu


func _screen() -> Node:
	return _menu.call("debug_screen", "race_setup")


## The route of the last race the menu asked for.
func _started_route() -> String:
	var options: Dictionary = _menu.get("_current_options")
	return String(options.get("route", ""))


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
