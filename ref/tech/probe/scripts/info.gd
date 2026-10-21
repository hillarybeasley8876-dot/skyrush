extends SceneTree
# Prints renderer / platform / default project settings of interest.
func _initialize() -> void:
	var rs := RenderingServer
	print("ENGINE ", Engine.get_version_info().string)
	print("OS ", OS.get_name(), " ", OS.get_version(), " model=", OS.get_model_name())
	print("CPU ", OS.get_processor_name(), " cores=", OS.get_processor_count())
	print("VIDEO_ADAPTER ", rs.get_video_adapter_name(), " | vendor=", rs.get_video_adapter_vendor(), " | type=", rs.get_video_adapter_type(), " | api=", rs.get_video_adapter_api_version())
	print("RENDERING_METHOD ", rs.get_current_rendering_method(), " DRIVER ", rs.get_current_rendering_driver_name())
	var rd := rs.get_rendering_device()
	if rd:
		print("RD device ", rd.get_device_name(), " vendor=", rd.get_device_vendor_name(), " api=", rd.get_device_api_name() if rd.has_method("get_device_api_name") else "?")
	for k in ["rendering/rendering_device/driver", "rendering/rendering_device/driver.macos", "rendering/renderer/rendering_method", "physics/3d/physics_engine", "physics/common/physics_ticks_per_second", "physics/common/max_physics_steps_per_frame", "physics/common/physics_interpolation", "rendering/anti_aliasing/quality/msaa_3d", "rendering/anti_aliasing/quality/use_taa", "rendering/scaling_3d/mode", "rendering/occlusion_culling/use_occlusion_culling", "rendering/lights_and_shadows/positional_shadow/atlas_size", "rendering/environment/volumetric_fog/volume_size", "rendering/environment/volumetric_fog/volume_depth", "rendering/limits/cluster_builder/max_clustered_elements", "rendering/textures/vram_compression/import_etc2_astc", "rendering/textures/vram_compression/import_s3tc_bptc", "audio/general/3d_panning_strength", "display/window/vsync/vsync_mode"]:
		print("SETTING ", k, " = ", ProjectSettings.get_setting(k, "<missing>"))
	quit()
