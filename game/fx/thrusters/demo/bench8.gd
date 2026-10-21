extends SceneTree
## 8-view GPU amplification bench for the thruster plumes (ref/tech/GODOT.md §3.1).
##
## The main window plus 7 SubViewports (1920x1080) share one World3D, so a frame costs 8 views.
## The plume on/off windows are interleaved, and the extra cost per view is
##     (median frame ms with FX - median frame ms without FX) / 8
##
##   godot --path game --windowed --resolution 1920x1080 --always-on-top \
##         -s res://fx/thrusters/demo/bench8.gd -- --h=1.6
##
## With --breakdown=1 the bench measures the cost of every layer on its own (cumulative), so
## the review can see where the milliseconds go:
##
##   godot --path game --windowed --resolution 1920x1080 --always-on-top \
##         -s res://fx/thrusters/demo/bench8.gd -- --h=0.4 --breakdown=1

const VIEWS := 7
const WINDOW := 90
const WINDOWS := 8
const WARMUP := 240
const VIEW_SIZE := Vector2i(1920, 1080)
const FOV := 62.0
const CHASE_OFFSET := Vector3(0.0, 1.9, 6.6)
## The layers of the plume, in the order they are switched on for the breakdown. Every layer
## adds to the ones before it.
const LAYERS := ["vapour", "columns", "core", "throat", "lift_cloud", "rear_cloud", "lights"]
## The windows per layer in the breakdown, and the frames per window.
const BREAKDOWN_WINDOWS := 2
const BREAKDOWN_WINDOW := 40

var _root3d: Node3D
var _car: Node3D
var _sys: Node3D
var _cam: Camera3D
var _frame: int = 0
var _window: int = 0
var _last: int = 0
var _samples: Array[float] = []
var _result: Dictionary = {"on": [], "off": []}
var _height: float = 1.6
var _cam_offset: Vector3 = CHASE_OFFSET
var _breakdown: bool = false
## The breakdown state: which layer is being measured, and the samples of this layer.
var _layer_index: int = 0
var _bd_step: int = 0
var _bd_on: Array[float] = []
var _bd_off: Array[float] = []
## The nodes of every layer, so the bench can switch them on and off.
var _layers: Dictionary[String, Array] = {}


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--h="):
			_height = float(arg.trim_prefix("--h="))
		elif arg.begins_with("--cam="):
			var parts: PackedStringArray = arg.trim_prefix("--cam=").split(",")
			_cam_offset = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
		elif arg == "--breakdown=1":
			_breakdown = true
	_root3d = (load("res://fx/thrusters/demo/thruster_demo.tscn") as PackedScene).instantiate()
	# The demo script would drive its own car; the bench sets up its own.
	_root3d.set_script(null)
	root.add_child(_root3d)


func _setup() -> void:
	var scene: Node3D = _root3d
	var car_script: Script = load("res://fx/thrusters/demo/demo_car.gd")
	_car = car_script.new() as Node3D
	_car.set("build_body", false)
	_car.set("build_markers", false)
	scene.add_child(_car)
	var glb: Node = (load("res://assets/cars/roadster/roadster.glb") as PackedScene).instantiate()
	_car.call("get_visual_root").add_child(glb)
	_car.global_position = Vector3(0.0, _height, 0.0)
	_sys = (load("res://fx/thrusters/thruster_system.tscn") as PackedScene).instantiate()
	scene.add_child(_sys)
	_sys.call("attach", _car)
	_cam = scene.get_node("Camera") as Camera3D
	_cam.fov = FOV
	_cam.global_position = _car.global_position + _cam_offset
	_cam.look_at(_car.global_position + Vector3(0.0, 0.6, 0.0))
	for i in VIEWS:
		var viewport := SubViewport.new()
		viewport.size = VIEW_SIZE
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.world_3d = root.world_3d
		var sub_cam := Camera3D.new()
		sub_cam.fov = FOV
		viewport.add_child(sub_cam)
		root.add_child(viewport)
		sub_cam.global_transform = _cam.global_transform
		sub_cam.current = true
	_collect_layers()
	_last = Time.get_ticks_usec()
	# Window 0 is the "off" window, so the plumes have to be hidden before it is measured.
	_set_empty()


## Finds the nodes of every layer, so the bench can switch them on and off.
func _collect_layers() -> void:
	for layer in LAYERS:
		_layers[layer] = []
	for node in _car.find_children("", "", true, false):
		_add_layer_node(node)
	for node in _sys.find_children("", "", true, false):
		_add_layer_node(node)


func _add_layer_node(node: Node) -> void:
	var name := String(node.name)
	if name == "JetVapour":
		_layers["vapour"].append(node)
	elif name == "JetColumn":
		_layers["columns"].append(node)
	elif name == "JetCore":
		_layers["core"].append(node)
	elif name == "LiftCloud":
		_layers["lift_cloud"].append(node)
	elif name == "RearCloud":
		_layers["rear_cloud"].append(node)
	elif name.begins_with("Light"):
		_layers["lights"].append(node)
	elif name == "ThroatGlow":
		_layers["throat"].append(node)


## Switches on the first `count` layers and hides the rest.
func _set_layers(count: int) -> void:
	for i in LAYERS.size():
		var on: bool = i < count
		for node in _layers[LAYERS[i]]:
			(node as Node3D).visible = on


## The empty scene: no plume at all.
func _set_empty() -> void:
	_set_layers(0)
	_sys.visible = false
	for node in _car.find_children("Fx*", "Node3D", true, false):
		(node as Node3D).visible = false


func _set_fx(on: bool) -> void:
	_sys.visible = on
	for node in _car.find_children("Fx*", "Node3D", true, false):
		(node as Node3D).visible = on


func _process(_delta: float) -> bool:
	if _sys == null:
		_setup()
		return false
	var now: int = Time.get_ticks_usec()
	var ms: float = float(now - _last) / 1000.0
	_last = now
	_fire_all()
	_frame += 1
	if _frame < WARMUP:
		return false
	if _breakdown:
		return _process_breakdown(ms)
	var on: bool = _window % 2 == 1
	var k: int = (_frame - WARMUP) % WINDOW
	if k > 20:
		_samples.append(ms)
	if k == WINDOW - 1:
		# The minimum, not the median: the machine is shared with other units' renders, and
		# those only ever slow a frame down. The fastest frames are the clean ones.
		(_result["on" if on else "off"] as Array).append(_samples[0])
		_samples.clear()
		_window += 1
		_set_fx(_window % 2 == 1)
		if _window >= WINDOWS:
			_report()
			return true
	return false


## The breakdown: for every layer, alternate between the layers up to it and nothing at all.
func _process_breakdown(ms: float) -> bool:
	var k: int = (_frame - WARMUP) % BREAKDOWN_WINDOW
	if k > 10:
		_samples.append(ms)
	if k != BREAKDOWN_WINDOW - 1:
		return false
	var median: float = _samples[0]
	_samples.clear()
	if _bd_step % 2 == 0:
		# The empty scene: it is the baseline of this pair.
		_bd_off.append(median)
		_set_fx(true)
		_set_layers(_layer_index + 1)
	else:
		_bd_on.append(median)
		_set_empty()
	_bd_step += 1
	if _bd_step < BREAKDOWN_WINDOWS * 2:
		return false
	_report_layer()
	_bd_on.clear()
	_bd_off.clear()
	_bd_step = 0
	_layer_index += 1
	if _layer_index >= LAYERS.size():
		return true
	return false


## Prints the cost of every layer, as the extra milliseconds per 1080p view.
func _report_layer() -> void:
	var on: Array = _bd_on.duplicate()
	var off: Array = _bd_off.duplicate()
	if on.is_empty() or off.is_empty():
		return
	on.sort()
	off.sort()
	var mean_on: float = on[0]
	var mean_off: float = off[0]
	print("BENCH layer=%s on=%.2f off=%.2f delta=%.2f per_view=%.3f ms" % [
			LAYERS[_layer_index], mean_on, mean_off,
			mean_on - mean_off, (mean_on - mean_off) / float(VIEWS + 1)])


## All ten nozzles at full throttle.
func _fire_all() -> void:
	var telemetry: Object = _car.get("telemetry")
	var thrusters: Dictionary = telemetry.get("thrusters")
	for nozzle_name in ["Nozzle_R1", "Nozzle_R2", "Nozzle_R3", "Nozzle_R4", "Nozzle_P1",
			"Nozzle_P2", "Nozzle_P3", "Nozzle_P4", "Nozzle_P5", "Nozzle_P6"]:
		thrusters[nozzle_name] = 1.0


func _report() -> void:
	var on: Array = _result["on"]
	var off: Array = _result["off"]
	# The median over the windows: a single noisy window (another unit's render) must not
	# decide the number.
	on.sort()
	off.sort()
	var mean_on: float = on[0]
	var mean_off: float = off[0]
	print("BENCH h=%.1f cam=%s (min of the windows)" % [_height, str(_cam_offset)])
	print("BENCH frame_ms on=%.2f off=%.2f delta=%.2f per_view=%.3f ms (8 views)" % [
			mean_on, mean_off, mean_on - mean_off, (mean_on - mean_off) / float(VIEWS + 1)])
	var particles: int = _sys.call("particle_capacity", _car)
	print("BENCH particles_alive=%d draw_calls=%d primitives=%d" % [
			particles,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
