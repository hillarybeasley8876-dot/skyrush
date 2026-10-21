extends Node
## Capture rig for the menu screens.
##
## Boots the real game (so the title screen has the city and the car behind it) and then either
## opens one screen directly or drives the menu with scripted key presses:
##
##   tools/godot.sh shot --scene=res://ui/menu/demo/menu_demo.tscn --out=menu_title \
##       --menu-screen=title --menu-delay=2.5 --outdir=$PWD/captures/menu --times=2
##
##   tools/godot.sh shot --scene=res://ui/menu/demo/menu_demo.tscn --out=menu_race \
##       --menu-keys=ENTER,DOWN,ENTER --outdir=$PWD/captures/menu --times=5
##
## `--menu-screen=` accepts loading / title / main / race_setup / pursuit_setup / settings /
## controls / pause / results. `pause` and `results` are opened as overlays.
## `--menu-keys=` is a comma separated list of key names (ENTER, DOWN, UP, ESC, BACKSPACE); the
## presses start once the title screen is up, 0.35 s apart.
## `--menu-size=2200x943` changes the window size (the aspect ratios), `--menu-delay=2.0` the wait
## before a screen is opened directly.
## `--menu-perf` measures the frame rate against a baseline and watches the traffic.
## `--menu-beats=N` previews N candidate beats of the title stage (one after the other), so a
## good framing can be found in a single run.
## `--menu-load=0.4` holds the loading screen at that fraction, `--menu-result=free` picks the
## kind of the results screen.

const Bridge := preload("res://ui/menu/bridge.gd")
const Menu := preload("res://ui/menu/menu.gd")
const LoadingScreen := preload("res://ui/menu/screens/loading_screen.gd")
const OVERLAYS: Array[StringName] = [&"pause", &"results"]

## How long the performance measurement runs.
const PERF_SECONDS := 10.0
## The gap between two scripted key presses.
const KEY_GAP := 0.35
## The title screen has to be up before the scripted keys are sent. The world is built over
## half a minute here, so the wait is long.
const TITLE_TIMEOUT := 240.0

var _screen: StringName = &"title"
## The kind of the results the capture rig opens ("race", "free" or "pursuit").
var _result: StringName = &"race"
## The fraction the loading screen is held at (0 = the real progress of the world).
var _load: float = 0.0
## The number of candidate beats of the title stage to preview (0 = the authored ones).
var _beats: int = 0
var _delay: float = 2.0
var _size: Vector2i = Vector2i.ZERO
var _perf: bool = false
## The scripted key presses: [key, time or -1].
var _keys: Array = []
## The closest a traffic car came to the parked car.
var _traffic_distance: float = INF


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--menu-screen="):
			_screen = StringName(arg.trim_prefix("--menu-screen="))
		elif arg.begins_with("--menu-delay="):
			_delay = float(arg.trim_prefix("--menu-delay="))
		elif arg.begins_with("--menu-size="):
			var parts := arg.trim_prefix("--menu-size=").split("x")
			if parts.size() == 2:
				_size = Vector2i(int(parts[0]), int(parts[1]))
		elif arg.begins_with("--menu-result="):
			_result = StringName(arg.trim_prefix("--menu-result="))
		elif arg.begins_with("--menu-beats="):
			_beats = int(arg.trim_prefix("--menu-beats="))
		elif arg.begins_with("--menu-load="):
			_load = float(arg.trim_prefix("--menu-load="))
		elif arg == "--menu-perf":
			_perf = true
		elif arg.begins_with("--menu-keys="):
			for entry in arg.trim_prefix("--menu-keys=").split(",", false):
				var spec := entry.split("@")
				if spec.size() == 1:
					_keys.append([_key_from_name(spec[0]), -1.0])
				elif spec.size() == 2:
					_keys.append([_key_from_name(spec[0]), float(spec[1])])
	if _size != Vector2i.ZERO:
		DisplayServer.window_set_size(_size)
	var game := load("res://main.tscn") as PackedScene
	add_child(game.instantiate())
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(_delay).timeout
	var menu := _find_menu(self)
	if menu == null:
		push_error("menu demo: the menu unit was not found in the scene")
		return
	if not _keys.is_empty():
		# The keys drive the menu from the title screen.
		await _wait_for_title(menu)
		await _press_keys()
	elif _beats > 0:
		# The candidate beats of the title stage, one after the other.
		await _wait_for_title(menu)
		_preview_beats(menu)
	elif _screen == &"title":
		# The title comes up on its own when the world is built: the beats start there.
		await _wait_for_title(menu)
	elif _screen in OVERLAYS:
		# The overlays sit on top of the game, not on top of the front end.
		menu.close_front_end()
		menu.open_overlay(_screen, _payload())
		Game.set_paused(true)
	else:
		menu.open_screen(_screen)
	if _screen == &"loading":
		# The capture rig holds the loading screen open, so the capture can happen whenever the
		# world is built.
		var screen := menu.debug_screen("loading") as LoadingScreen
		if screen != null:
			screen.hold = true
		_fake_loading()
	_report(menu)
	if _perf:
		_measure()


## Puts the candidate beats on the title stage (the capture rig looks for a good framing).
func _preview_beats(menu: Menu) -> void:
	var front: Variant = menu.get("front_end")
	if front == null:
		return
	var stage: Variant = front.get("stage")
	if stage == null:
		return
	stage.set("beat_override", CANDIDATE_BEATS)
	stage.set("beat_seconds_override", CANDIDATE_BEAT_SECONDS)
	print("DEMO t=%.1fs %d candidate beats" % [Time.get_ticks_msec() * 0.001, CANDIDATE_BEATS.size()])


## Prints what is on the screen and when it happened (the capture times are scheduled from it).
func _report(menu: Menu) -> void:
	var state: Dictionary = menu.debug_state()
	if Game.player != null:
		print("DEMO player=%.1f, %.1f, %.1f" % [Game.player.global_position.x,
			Game.player.global_position.y, Game.player.global_position.z])
	var front: Variant = menu.get("front_end")
	if front != null:
		var stage: Variant = front.get("stage")
		if stage != null and stage.get("camera") != null:
			var cam: Camera3D = stage.get("camera")
			print("DEMO camera=%.1f, %.1f, %.1f spot=%s" % [cam.global_position.x,
				cam.global_position.y, cam.global_position.z, str(stage.get("parking_spot"))])
	print("DEMO t=%.1fs screen=%s front=%s overlay=%s" % [
		Time.get_ticks_msec() * 0.001, _screen, str(state.get("front", [])),
		str(state.get("overlay", []))])


## The name of a key ("ENTER", "DOWN", ...).
func _key_from_name(name: String) -> Key:
	match name.to_upper():
		"ENTER", "RETURN":
			return KEY_ENTER
		"DOWN":
			return KEY_DOWN
		"UP":
			return KEY_UP
		"LEFT":
			return KEY_LEFT
		"RIGHT":
			return KEY_RIGHT
		"ESCAPE", "ESC":
			return KEY_ESCAPE
		"BACKSPACE":
			return KEY_BACKSPACE
	return KEY_ENTER


## Waits until the world is built and the title screen is the front screen.
func _wait_for_title(menu: Menu) -> void:
	var deadline := Time.get_ticks_msec() + int(TITLE_TIMEOUT * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not Game.world_built():
			continue
		var state: Dictionary = menu.debug_state()
		var front: Array = state["front"]
		if front.size() > 0 and String(front.back()) == "ScreenTitle":
			print("DEMO t=%.1fs title up" % (Time.get_ticks_msec() * 0.001))
			return
	print("DEMO t=%.1fs the title did not come up in %d s" % [
		Time.get_ticks_msec() * 0.001, int(TITLE_TIMEOUT)])


## Sends the scripted key events (the menu listens to the events, not to the state).
func _press_keys() -> void:
	for entry: Array in _keys:
		var wait := KEY_GAP
		if float(entry[1]) >= 0.0:
			wait = float(entry[1])
		while wait > 0.0:
			await get_tree().process_frame
			wait -= get_process_delta_time()
		print("DEMO t=%.1fs key=%d" % [Time.get_ticks_msec() * 0.001, entry[0]])
		_send_key(entry[0])


## Sends a real key event (a press and a release).
func _send_key(code: Key) -> void:
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


## The candidate beats of the title stage (the capture rig previews them one after the other).
const CANDIDATE_BEATS: Array[Dictionary] = [
	{"name": "a", "offset": Vector3(0.0, 1.7, 11.0), "aim": Vector3(-0.5, 1.0, -5.0),
		"fov": 44.0, "dolly": 0.0},
	{"name": "b", "offset": Vector3(2.0, 1.1, 7.0), "aim": Vector3(-1.0, 0.9, -2.0),
		"fov": 48.0, "dolly": 0.0},
	{"name": "c", "offset": Vector3(-1.0, 3.0, 14.0), "aim": Vector3(0.0, 1.2, -6.0),
		"fov": 40.0, "dolly": 0.0},
	{"name": "d", "offset": Vector3(6.0, 2.0, 9.0), "aim": Vector3(-2.0, 1.1, -3.0),
		"fov": 44.0, "dolly": 0.0},
	{"name": "e", "offset": Vector3(-6.0, 1.5, 9.0), "aim": Vector3(2.0, 1.0, -3.0),
		"fov": 46.0, "dolly": 0.0},
	{"name": "f", "offset": Vector3(0.0, 0.8, 5.0), "aim": Vector3(0.0, 0.7, 0.0),
		"fov": 52.0, "dolly": 0.0},
]
## How long a candidate beat lasts.
const CANDIDATE_BEAT_SECONDS := 3.0

## The phases of the build, as the world reports them (the menu maps them to Chinese).
const PHASES: Array[String] = ["terrain", "roads", "blocks", "lanes", "furniture", "signals",
		"sites", "读取城市数据", "就绪"]

## Fakes the world loading so the loading screen has something to show. The progress never
## reaches 100 %, so the screen stays up (the capture can happen whenever the world is built).
## With --menu-load= the screen is held at that fraction.
func _fake_loading() -> void:
	var events := get_tree().root.get_node_or_null("Events")
	if events == null:
		return
	var world := Game.world
	var step := 0
	while true:
		var fraction: float = _load
		if fraction <= 0.0:
			var steps: Array[float] = [0.25, 0.40, 0.55, 0.70]
			fraction = steps[step % steps.size()]
		var phase: String = PHASES[step % PHASES.size()]
		if world != null:
			world.set("loading_fraction", 0.1)
		events.emit_signal("loading_progress", fraction, phase)
		step += 1
		await get_tree().create_timer(1.2).timeout


## The cost of the menu: the game without the front end and the game with it, measured in the
## same run (the frame rate alone says little when other units are building the city).
func _measure() -> void:
	var menu := _find_menu(self)
	if menu == null:
		return
	menu.close_front_end()
	await get_tree().process_frame
	var baseline := await _sample(PERF_SECONDS * 0.4)
	menu.open_screen(_screen)
	await get_tree().process_frame
	var with_menu := await _sample(PERF_SECONDS * 0.4)
	print("PERF baseline fps_avg=%.1f fps_min=%.1f draws=%d prims=%d" % [
		baseline["fps"], baseline["fps_min"], baseline["draws"], baseline["prims"]])
	print("PERF menu     fps_avg=%.1f fps_min=%.1f draws=%d prims=%d" % [
		with_menu["fps"], with_menu["fps_min"], with_menu["draws"], with_menu["prims"]])
	print("PERF delta draws=%d prims=%d process_ms=%.2f physics_ms=%.2f mem_mb=%.1f" % [
		int(with_menu["draws"]) - int(baseline["draws"]),
		int(with_menu["prims"]) - int(baseline["prims"]),
		float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0,
		float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0,
		float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0])


## The frame rate and the render counters over a while.
func _sample(seconds: float) -> Dictionary:
	var samples: Array[float] = []
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		samples.append(float(Performance.get_monitor(Performance.TIME_FPS)))
		_watch_traffic()
	var average := 0.0
	var lowest := 9999.0
	for value in samples:
		average += value
		lowest = minf(lowest, value)
	average /= maxf(float(samples.size()), 1.0)
	return {
		"fps": average,
		"fps_min": lowest,
		"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"prims": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
	}


## The closest a traffic car came to the parked car (the title stage keeps it off the lanes).
func _watch_traffic() -> void:
	var player := Game.player
	if player == null:
		return
	for node in get_tree().get_nodes_in_group("traffic"):
		var car := node as Node3D
		if car == null:
			continue
		_traffic_distance = minf(_traffic_distance, car.global_position.distance_to(
				player.global_position))
	if _traffic_distance < INF:
		print("PERF traffic_closest=%.2f m" % _traffic_distance)


## The menu of the scene (the menu unit is the only one with that script).
func _find_menu(node: Node) -> Menu:
	return Bridge.find_by_script(node, "res://ui/menu/menu.gd") as Menu


func _payload() -> Dictionary:
	if _screen == &"results":
		return _results_payload()
	return {"mode": &"free", "options": {}}


## The payload of the results screen (the kind is chosen with --menu-result=).
func _results_payload() -> Dictionary:
	match _result:
		&"free":
			return {
				"kind": "free",
				"score": 4820, "best_score": 3900, "stunts": 17, "near_misses": 63,
				"wrecks": 4, "takedowns": 2, "time": 214.6,
			}
		&"pursuit":
			return {
				"kind": "pursuit",
				"result": "escaped", "heat": 3, "takedowns": 2, "target": 3, "time": 96.4,
			}
	return {
		"kind": "race",
		"route": "bund_sprint",
		"route_title": "外滩冲刺",
		"best_time": 92.4,
		"best_lap": 45.1,
		"options": {"route": "bund_sprint", "difficulty": "normal", "laps": 2},
		"results": [
			{"name": "浦江闪电", "time": 94.81, "position": 1, "is_player": false, "finished": true},
			{"name": "Roadster", "time": 96.12, "position": 2, "is_player": true, "finished": true},
			{"name": "外滩幽灵", "time": 97.44, "position": 3, "is_player": false, "finished": true},
			{"name": "南浦小子", "time": 101.05, "position": 4, "is_player": false, "finished": true},
			{"name": "龙柱车神", "time": 103.77, "position": 5, "is_player": false, "finished": true},
			{"name": "静安快车", "time": 106.30, "position": 6, "is_player": false, "finished": false},
		],
	}
