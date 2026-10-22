extends SceneTree
## Scripted play-through for feel reviews, E2E tests and trailer capture (core-owned).
##   tools/godot.sh drive --timeline=res://path/timeline.json [--scene=res://main.tscn]
##        [--shots=1.5,4,8] [--outdir=...] [--out=name] [--log=telemetry csv path] + game options
## Timeline JSON: [{"t": 0.0, "press": ["accelerate"]}, {"t": 2.5, "release": ["accelerate"]},
##                 {"t": 3.0, "tap": ["hop"]}, {"t": 9.0, "end": true}]
## "tap" presses for 3 frames. Prints "DRIVE t=.. speed=.. n2=.." every 0.5 s and writes a telemetry
## CSV (t, x, y, z, speed_kmh, drift_state, n2, airborne, flying, boost_kind, health) if --log is
## set. Exit 1 on engine errors. For video use tools/godot.sh movie (same options + --movie=out.avi).

const ErrorCounter := preload("res://tools/error_counter.gd")
const InputSetup := preload("res://core/input_setup.gd")

var _opts: Dictionary = {}
var _counter: ErrorCounter
var _events: Array = []
var _next: int = 0
var _t: float = 0.0
var _end_t: float = 30.0
var _taps: Dictionary = {}  # action -> frames left
var _shots: PackedFloat64Array = []
var _log: FileAccess
var _next_print: float = 0.0
var _world_waited: float = 0.0
const WORLD_WAIT_MAX := 120.0


func _initialize() -> void:
	_counter = ErrorCounter.new()
	OS.add_logger(_counter)
	InputSetup.register_actions()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var eq := arg.find("=")
			_opts[arg.substr(2, eq - 2) if eq > 0 else arg.substr(2)] = arg.substr(eq + 1) if eq > 0 else "true"
	_events = _load_timeline(String(_opts.get("timeline", "")))
	for s in String(_opts.get("shots", "")).split(",", false):
		_shots.append(float(s))
	if _opts.has("log"):
		_log = FileAccess.open(String(_opts["log"]), FileAccess.WRITE)
		if _log != null:
			_log.store_line("t,x,y,z,speed_kmh,drift_state,n2,airborne,flying,boost_kind,health")
	var packed := load(String(_opts.get("scene", "res://main.tscn"))) as PackedScene
	root.add_child(packed.instantiate())


func _load_timeline(path: String) -> Array:
	if path == "":
		push_error("drive: --timeline=res://... required")
		return []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Array:
		push_error("drive: timeline is not a JSON array: " + path)
		return []
	for ev: Dictionary in (data as Array):
		if ev.get("end", false):
			_end_t = float(ev["t"])
	return data as Array


func _process(delta: float) -> bool:
	if not _world_ready(delta):
		return false
	_t += delta
	while _next < _events.size() and float((_events[_next] as Dictionary)["t"]) <= _t:
		_apply(_events[_next] as Dictionary)
		_next += 1
	for action: StringName in _taps.keys():
		_taps[action] = int(_taps[action]) - 1
		if int(_taps[action]) <= 0:
			Input.action_release(action)
			_taps.erase(action)
	if not _shots.is_empty() and _t >= _shots[0]:
		_shots.remove_at(0)
		_shot.call_deferred(_t)
	_telemetry()
	if _t >= _end_t:
		_finish()
		return true
	return false


func _apply(ev: Dictionary) -> void:
	for a: String in ev.get("press", []):
		Input.action_press(StringName(a))
	for a: String in ev.get("release", []):
		Input.action_release(StringName(a))
	for a: String in ev.get("tap", []):
		Input.action_press(StringName(a))
		_taps[StringName(a)] = 3


func _telemetry() -> void:
	# Autoloads are not compile-time identifiers inside a SceneTree script: look the node up.
	# No class_name types here either: a SceneTree script is compiled before autoloads exist.
	var game := root.get_node_or_null(^"Game")
	var car: Node3D = game.get(&"player") as Node3D if game != null else null
	if car == null:
		return
	var tl: Object = car.get(&"telemetry")
	if _log != null:
		var p := car.global_position
		_log.store_line("%.3f,%.2f,%.2f,%.2f,%.1f,%s,%.1f,%s,%s,%s,%.0f" % [_t, p.x, p.y, p.z, tl.get(&"speed_kmh"),
				String(tl.get(&"drift_state")), tl.get(&"n2"), str(tl.get(&"airborne")), str(tl.get(&"flying")),
				String(tl.get(&"boost_kind")), car.get(&"health")])
	if _t >= _next_print:
		_next_print += 0.5
		print("DRIVE t=%.1f speed=%.0f drift=%s n2=%.0f air=%s fly=%s boost=%s" % [_t, tl.get(&"speed_kmh"),
				String(tl.get(&"drift_state")), tl.get(&"n2"), str(tl.get(&"airborne")), str(tl.get(&"flying")),
				String(tl.get(&"boost_kind"))])


func _shot(at: float) -> void:
	await RenderingServer.frame_post_draw
	var dir := String(_opts.get("outdir", ProjectSettings.globalize_path("res://captures")))
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("%s_t%s.jpg" % [String(_opts.get("out", "drive")), str(snappedf(at, 0.1)).replace(".", "_")])
	root.get_viewport().get_texture().get_image().save_jpg(path, 0.85)
	print("DRIVE shot -> ", path)


func _finish() -> void:
	if _log != null:
		_log.close()
	for line in _counter.first_errors:
		print("DRIVE ERROR ", line)
	print("DRIVE done t=%.1f errors=%d warnings=%d" % [_t, _counter.errors, _counter.warnings])
	quit(1 if _counter.errors > 0 else 0)


## The timeline starts once the world is built (the real world builds for several seconds while the
## player is held frozen). Scenes without a world start at once; a stuck build after WORLD_WAIT_MAX s.
func _world_ready(delta: float) -> bool:
	if _world_waited < 0.0:
		return true
	_world_waited += delta
	var game := root.get_node_or_null("Game")
	if game == null or game.get("world") == null or bool(game.call("world_built")) \
			or _world_waited > WORLD_WAIT_MAX:
		print("DRIVE world ready after %.1f s" % _world_waited)
		_world_waited = -1.0
		if _opts.has("spawn") and game != null:
			_apply_spawn(game)
		return true
	return false


## --spawn=x,y,z,yaw(deg): the game's own free-roam start puts the car on the default spawn after
## main.gd applied the option, so the option is applied again here, once the world is built.
func _apply_spawn(game: Node) -> void:
	var car: Node3D = game.get(&"player") as Node3D
	var parts := String(_opts["spawn"]).split(",", false)
	if car == null or parts.size() < 3:
		return
	var yaw := deg_to_rad(float(parts[3])) if parts.size() >= 4 else 0.0
	var xform := Transform3D(Basis(Vector3.UP, yaw), Vector3(float(parts[0]), float(parts[1]), float(parts[2])))
	car.call(&"reset_to", xform)
	print("DRIVE spawn applied at %s" % str(xform.origin))

