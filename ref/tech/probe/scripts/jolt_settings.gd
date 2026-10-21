extends SceneTree
func _initialize() -> void:
	for p in ProjectSettings.get_property_list():
		if p.name.begins_with("physics/jolt") or p.name.begins_with("physics/3d/") or p.name.begins_with("physics/common"):
			print(p.name, " = ", ProjectSettings.get_setting(p.name))
	quit()
