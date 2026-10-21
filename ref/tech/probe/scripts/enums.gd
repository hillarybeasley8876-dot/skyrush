extends SceneTree
func _initialize() -> void:
	for c in ["Viewport", "Environment", "RenderingServer", "BaseMaterial3D", "GPUParticles3D", "CompositorEffect", "RenderSceneBuffersRD"]:
		var out := []
		for k in ClassDB.class_get_integer_constant_list(c, true):
			if k.begins_with("SCALING_3D_MODE") or k.begins_with("MSAA_") or k.begins_with("SCREEN_SPACE_AA") or k.begins_with("TONE_MAPPER") or k.begins_with("ANISOTROPY") or k.begins_with("EFFECT_CALLBACK_TYPE") or k.begins_with("GLOW_BLEND") or k.begins_with("SDFGI_Y_SCALE") or k.begins_with("VIEWPORT_SCALING"):
				out.append("%s=%d" % [k, ClassDB.class_get_integer_constant(c, k)])
		if out.size(): print(c, ": ", ", ".join(out))
	var props := []
	for p in ClassDB.class_get_property_list("Viewport", true):
		if p.name.begins_with("scaling_3d") or p.name.contains("taa") or p.name.contains("msaa") or p.name.contains("aa") or p.name.contains("hdr") or p.name.contains("occlusion") or p.name.contains("mesh_lod"):
			props.append("%s(%s)" % [p.name, p.hint_string])
	print("Viewport props: ", props)
	var cprops := []
	for p in ClassDB.class_get_property_list("CompositorEffect", true): cprops.append(p.name)
	print("CompositorEffect props: ", cprops)
	quit()
