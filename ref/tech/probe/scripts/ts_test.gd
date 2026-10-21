extends SceneTree
var n := 0
func _initialize() -> void:
	var cam := Camera3D.new(); get_root().add_child(cam)
	var mi := MeshInstance3D.new(); mi.mesh = BoxMesh.new(); mi.position = Vector3(0, 0, -3); get_root().add_child(mi)
	RenderingServer.viewport_set_measure_render_time(get_root().get_viewport_rid(), true)
func _process(_d: float) -> bool:
	n += 1
	if n == 30:
		var rd := RenderingServer.get_rendering_device()
		var c := rd.get_captured_timestamps_count()
		print("TIMESTAMPS count=", c, " frame=", rd.get_captured_timestamps_frame())
		for i in mini(c, 12): print("  ", rd.get_captured_timestamp_name(i), " gpu_us=", rd.get_captured_timestamp_gpu_time(i) / 1000.0, " cpu_us=", rd.get_captured_timestamp_cpu_time(i))
		print("MEASURED gpu=", RenderingServer.viewport_get_measured_render_time_gpu(get_root().get_viewport_rid()), " cpu=", RenderingServer.viewport_get_measured_render_time_cpu(get_root().get_viewport_rid()))
		return true
	return false
