extends SceneTree
## Windowed smoke run: loads --scene (default res://main.tscn), optionally holds --press actions,
## runs --seconds, prints mean/min fps and engine error count. Exit 1 on errors.

const ErrorCounter := preload("res://tools/error_counter.gd")
const InputSetup := preload("res://core/input_setup.gd")

var _counter: ErrorCounter
var _secs: float = 20.0
var _t: float = 0.0
var _fps: PackedFloat64Array = []


func _initialize() -> void:
	_counter = ErrorCounter.new()
	OS.add_logger(_counter)
	InputSetup.register_actions()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var scene := "res://main.tscn"
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--scene" and i + 1 < args.size():
			scene = args[i + 1]
		elif args[i] == "--seconds" and i + 1 < args.size():
			_secs = float(args[i + 1])
		elif args[i].begins_with("--press="):
			for a in args[i].trim_prefix("--press=").split(",", false):
				Input.action_press(StringName(a))
	root.add_child((load(scene) as PackedScene).instantiate())


func _process(delta: float) -> bool:
	_t += delta
	if _t > 2.0:
		_fps.append(1.0 / maxf(delta, 0.0001))
	if _t < _secs:
		return false
	var mean := 0.0
	var low := 1e9
	for f in _fps:
		mean += f
		low = minf(low, f)
	mean /= maxf(float(_fps.size()), 1.0)
	for line in _counter.first_errors:
		print("SMOKE ERROR ", line)
	print("SMOKE seconds=%.0f fps_mean=%.0f fps_min=%.0f errors=%d warnings=%d" % [_t, mean, low,
			_counter.errors, _counter.warnings])
	quit(1 if _counter.errors > 0 else 0)
	return true
