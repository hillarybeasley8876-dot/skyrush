extends SceneTree
## Performance probe (core-owned): `tools/godot.sh perf [--at=x,y,z,yaw] [--seconds=6] [game options]`.
## Boots res://main.tscn (pass --skip-menu), waits, then for each top-level child of Main (and of the
## world node) hides it for a few frames and reports how many draw calls / objects / primitives it
## costs (baseline minus hidden). Prints a table "PERF <node> draws=.. objs=.. prims=.." and the
## baseline fps. Windowed (needs a renderer). No class_name/autoload references (see CONTRACTS §3).

var _main: Node
var _frames: int = 0
var _phase: int = -1
var _targets: Array[Node3D] = []
var _base: Dictionary = {}
var _rows: Array[String] = []
var _fps: PackedFloat64Array = []
var _last_us: int = 0
var _warm_secs: float = 8.0
var _t: float = 0.0


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--warm="):
			_warm_secs = float(arg.trim_prefix("--warm="))
	_main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(_main)


func _info() -> Dictionary:
	return {
		"draws": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"objs": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"prims": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
	}


func _collect_targets() -> void:
	for child in _main.get_children():
		var n3 := child as Node3D
		if n3 != null:
			_targets.append(n3)
			if child.name.to_lower().contains("world"):
				for sub in child.get_children():
					if sub is Node3D:
						_targets.append(sub as Node3D)


func _process(delta: float) -> bool:
	_frames += 1
	_t += delta
	var now := Time.get_ticks_usec()
	if _last_us > 0 and _phase == -1 and _t > _warm_secs * 0.5:
		_fps.append(1e6 / float(maxi(now - _last_us, 1)))
	_last_us = now
	if _phase == -1:
		if _t >= _warm_secs:
			print("PERF warm done after %d frames (%.1f s)" % [_frames, _t])
			_base = _info()
			print("PERF baseline draws=%d objs=%d prims=%d" % [_base["draws"], _base["objs"], _base["prims"]])
			_collect_targets()
			_phase = 0
			_frames = 0
		return false
	if _phase >= _targets.size():
		_report()
		return true
	var target := _targets[_phase]
	if _frames == 1:
		target.visible = false
	elif _frames == 6:
		var hidden := _info()
		var row := "PERF %-40s draws=%5d objs=%6d prims=%9d" % [str(target.get_path()).trim_prefix("/root/"),
				int(_base["draws"]) - int(hidden["draws"]), int(_base["objs"]) - int(hidden["objs"]),
				int(_base["prims"]) - int(hidden["prims"])]
		_rows.append(row)
		print(row)
		target.visible = true
	elif _frames >= 8:
		_phase += 1
		_frames = 0
	return false


func _report() -> void:
	var mean := 0.0
	for f in _fps:
		mean += f
	mean /= maxf(float(_fps.size()), 1.0)
	print("PERF baseline fps=%.0f draws=%d objs=%d prims=%d (rows above)" % [mean, _base["draws"], _base["objs"], _base["prims"]])
	quit(0)
