extends SceneTree
## Test host (core-owned): `tools/godot.sh test res://unit/tests/test_x.gd` runs this with
## --test=<path>. The test script is loaded at RUNTIME (after autoloads exist) and must
## `extends Node`: it is added under root, runs its checks (in _ready / _physics_process),
## prints PASS/FAIL lines and calls `get_tree().quit(<0 ok | 1 fail>)`. A SceneTree script cannot
## reference autoloads (Events, Game, ...) or class_name types that use them at compile time,
## which is why tests are Nodes. Timeout: --timeout=<s> (default 120) → exit 2.

const ErrorCounter := preload("res://tools/error_counter.gd")
const InputSetup := preload("res://core/input_setup.gd")

var _deadline: float = 120.0
var _t: float = 0.0
var _counter: ErrorCounter


func _initialize() -> void:
	_counter = ErrorCounter.new()
	OS.add_logger(_counter)
	InputSetup.register_actions()
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test="):
			path = arg.trim_prefix("--test=")
		elif arg.begins_with("--timeout="):
			_deadline = float(arg.trim_prefix("--timeout="))
	var script := load(path) as Script
	if script == null:
		push_error("test_host: cannot load test script " + path)
		quit(1)
		return
	var node := Node.new()
	node.set_script(script)
	if node.get_script() == null:
		push_error("test_host: %s must `extends Node` (got another base)" % path)
		quit(1)
		return
	node.name = "Test"
	root.add_child.call_deferred(node)


func _process(delta: float) -> bool:
	_t += delta
	if _t > _deadline:
		print("TEST TIMEOUT after %.0f s (engine errors so far: %d)" % [_t, _counter.errors])
		for line in _counter.first_errors:
			print("TEST ERROR ", line)
		quit(2)
		return true
	return false
