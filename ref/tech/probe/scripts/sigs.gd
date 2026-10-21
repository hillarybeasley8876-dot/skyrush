extends SceneTree
func _sig(c: String, m: String) -> void:
	for d in ClassDB.class_get_method_list(c, true):
		if d.name == m:
			var a := []
			for i in d.args.size():
				a.append("%s:%s" % [d.args[i].name, type_string(d.args[i].type) if d.args[i].class_name == "" else d.args[i].class_name])
			print(c, ".", m, "(", ", ".join(a), ") defaults=", d.default_args)
func _initialize() -> void:
	for m in ["create_texture", "get_texture_slice", "get_color_layer", "get_internal_size", "get_view_count", "has_texture", "get_texture", "get_depth_layer", "get_velocity_layer"]: _sig("RenderSceneBuffersRD", m)
	for m in ["compute_list_begin", "compute_list_dispatch", "compute_list_set_push_constant", "compute_list_add_barrier", "shader_compile_spirv_from_source", "shader_create_from_spirv", "compute_pipeline_create", "sampler_create", "texture_copy", "free_rid"]: _sig("RenderingDevice", m)
	for m in ["get_cache"]: _sig("UniformSetCacheRD", m)
	for m in ["_render_callback"]: _sig("CompositorEffect", m)
	for m in ["get_render_scene_buffers", "get_render_scene_data"]: _sig("RenderData", m)
	for m in ["viewport_get_measured_render_time_gpu", "viewport_set_measure_render_time", "get_rendering_info", "call_on_render_thread"]: _sig("RenderingServer", m)
	for m in ["bake"]: _sig("VoxelGI", m)
	quit()
