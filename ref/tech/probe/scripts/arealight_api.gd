extends SceneTree
func _initialize() -> void:
	print("AreaLight3D exists: ", ClassDB.class_exists("AreaLight3D"), " parent=", ClassDB.get_parent_class("AreaLight3D"))
	var props := []
	for p in ClassDB.class_get_property_list("AreaLight3D", true):
		if p.usage & PROPERTY_USAGE_EDITOR: props.append("%s(%s)" % [p.name, type_string(p.type)])
	print("AreaLight3D props: ", props)
	for p in ProjectSettings.get_property_list():
		var n: String = p.name
		if n.contains("hdr") or n.contains("area_light") or n.begins_with("rendering/lights_and_shadows/") and n.contains("area"):
			print("SETTING ", n, " = ", ProjectSettings.get_setting(n))
	for p in ClassDB.class_get_property_list("Window", true):
		if p.name.contains("hdr"): print("Window prop ", p.name)
	for m in ClassDB.class_get_method_list("DisplayServer", true):
		if m.name.contains("hdr"): print("DisplayServer.", m.name)
	quit()
