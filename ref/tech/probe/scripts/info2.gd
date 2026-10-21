extends SceneTree
var frames := 0
func _initialize() -> void:
	var ps3d = Engine.get_singleton("PhysicsServer3D")
	print("PHYSICS3D_SERVER_CLASS ", ps3d.get_class())
	for p in ProjectSettings.get_property_list():
		if p.name in ["physics/3d/physics_engine", "rendering/rendering_device/driver.macos", "rendering/environment/defaults/default_environment"]:
			print("HINT ", p.name, " -> ", p.hint_string)
	print("ClassDB Jolt-ish classes: ", Array(ClassDB.get_class_list()).filter(func(c): return "Jolt" in c))
	print("Has VehicleBody3D: ", ClassDB.class_exists("VehicleBody3D"), " CompositorEffect: ", ClassDB.class_exists("CompositorEffect"), " AudioStreamGenerator: ", ClassDB.class_exists("AudioStreamGenerator"))
	var tm = []
	for p in ClassDB.class_get_property_list("Environment"):
		if p.name == "tonemap_mode": tm.append(p.hint_string)
	print("TONEMAP_MODES ", tm)
	for p in ProjectSettings.get_property_list():
		if p.name == "rendering/scaling_3d/mode" or p.name == "rendering/anti_aliasing/quality/screen_space_aa": print("HINT ", p.name, " -> ", p.hint_string)
func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		var rs := RenderingServer
		print("VIDEO_ADAPTER ", rs.get_video_adapter_name(), " | vendor=", rs.get_video_adapter_vendor(), " | type=", rs.get_video_adapter_type(), " | api=", rs.get_video_adapter_api_version())
		print("RENDERING_METHOD ", rs.get_current_rendering_method(), " DRIVER ", rs.get_current_rendering_driver_name())
		var rd := rs.get_rendering_device()
		if rd: print("RD ", rd.get_device_name(), " | ", rd.get_device_vendor_name(), " | pipeline_cache=", rd.get_device_pipeline_cache_uuid())
		print("SCREEN ", DisplayServer.screen_get_size(), " scale=", DisplayServer.screen_get_scale(), " refresh=", DisplayServer.screen_get_refresh_rate(), " win=", DisplayServer.window_get_size())
		return true
	return false
