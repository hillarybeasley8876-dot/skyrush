extends Node3D
## Preset cost bench (tech dossier 3.1): the main window plus 7 extra 1920x1080 SubViewports that
## share the World3D, so the extra frame time divided by 8 is the cost of ONE more 1080p view.
## The presets are interleaved with the base (low) so a drifting GPU clock cancels out.
##
##   tools/godot.sh run res://world/env/lookdev_bench.tscn 90
##
## Pass = high <= 10 ms per 1080p view and (high - low) <= 3.0 ms (the tech dossier section 5 budget).

const VIEWS := 7
const ROUNDS := 5
const SETTLE_FRAMES := 20
const MEASURE_FRAMES := 30
const PRESETS: Array[StringName] = [&"medium", &"high", &"ultra"]
const BASE: StringName = &"low"

var _camera: Camera3D
var _viewports: Array[SubViewport] = []
var _samples: Dictionary = {}      # preset -> Array[float] of frame milliseconds
var _gpu_samples: Dictionary = {}   # preset -> Array[float] of GPU milliseconds per frame
var _vsync_was: int = DisplayServer.VSYNC_DISABLED


func _ready() -> void:
	_vsync_was = DisplayServer.window_get_vsync_mode()
	# The dossier measures with vsync off; with vsync on the measurement is the refresh rate.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for preset: StringName in PRESETS:
		_samples[preset] = []
		_gpu_samples[preset] = []
	_samples[BASE] = []
	_gpu_samples[BASE] = []
	add_child(load("res://world/env/lookdev.tscn").instantiate())
	_camera = Camera3D.new()
	_camera.fov = 70.0
	_camera.position = Vector3(2.4, 1.35, 8.0)
	add_child(_camera)
	_camera.look_at(Vector3(0.0, 2.2, -40.0))
	_camera.current = true
	var world := get_viewport().find_world_3d()
	for i in VIEWS:
		var vp := SubViewport.new()
		vp.size = Vector2i(1920, 1080)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.own_world_3d = false
		vp.world_3d = world
		add_child(vp)
		var cam := Camera3D.new()
		cam.fov = 70.0
		cam.position = _camera.position
		cam.rotation = _camera.rotation
		vp.add_child(cam)
		cam.current = true
		_viewports.append(vp)
	# The GPU time of every viewport is measured as well: the wall clock on a shared machine is
	# CPU-contended, so the two numbers have to be reported together.
	for vp: SubViewport in _viewports:
		RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_run.call_deferred()


func _run() -> void:
	print("BENCH views=%d rounds=%d resolution=1920x1080 vsync=off" % [VIEWS + 1, ROUNDS])
	for round in ROUNDS:
		# base, preset, base, preset ... so the GPU clock drift cancels out.
		for preset: StringName in PRESETS:
			await _measure_preset(BASE)
			await _measure_preset(preset)
		print("BENCH round=%d done" % round)
	_report()
	DisplayServer.window_set_vsync_mode(_vsync_was)
	get_tree().quit(0)


func _measure_preset(preset: StringName) -> void:
	Settings.set_quality(preset)
	await _settle()
	var result := await _measure()
	(_samples[preset] as Array).append(float(result["wall"]))
	(_gpu_samples[preset] as Array).append(float(result["gpu"]))
	print("BENCH preset=%s frame=%.2f ms gpu=%.2f ms" % [preset, float(result["wall"]), float(result["gpu"])])


## The GPU time of the main window plus the 7 sub-viewports, in milliseconds.
func _gpu_ms() -> float:
	var total := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	for vp: SubViewport in _viewports:
		total += RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid())
	return total


func _report() -> void:
	for preset: StringName in [BASE] + PRESETS:
		var arr: Array = _samples[preset]
		if arr.is_empty():
			continue
		var sorted: Array = arr.duplicate()
		sorted.sort()
		var median: float = sorted[sorted.size() / 2]
		var gpu: float = _median_of(_gpu_samples[preset])
		print("BENCH %s: min=%.2f median=%.2f max=%.2f ms/frame, gpu median=%.2f ms (8 views)" % [
			preset, sorted[0], median, sorted[sorted.size() - 1], gpu])
	var base := _median(BASE)
	var base_gpu := _median_of(_gpu_samples[BASE])
	for preset: StringName in PRESETS:
		var per_view := (_median(preset) - base) / float(VIEWS + 1)
		var per_view_gpu := (_median_of(_gpu_samples[preset]) - base_gpu) / float(VIEWS + 1)
		print("BENCH %s: %.2f ms per 1080p view over low (gpu %.2f ms)" % [preset, per_view, per_view_gpu])


func _median_of(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var sorted: Array = arr.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _median(preset: StringName) -> float:
	var arr: Array = _samples[preset]
	if arr.is_empty():
		return 0.0
	var sorted: Array = arr.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await get_tree().process_frame


func _measure() -> Dictionary:
	var start := Time.get_ticks_usec()
	var gpu_total := 0.0
	for i in MEASURE_FRAMES:
		await get_tree().process_frame
		gpu_total += _gpu_ms()
	var elapsed := (Time.get_ticks_usec() - start) / 1000.0
	return {"wall": elapsed / float(MEASURE_FRAMES), "gpu": gpu_total / float(MEASURE_FRAMES)}
